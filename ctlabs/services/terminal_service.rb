# -----------------------------------------------------------------------------
# File        : ctlabs/services/terminal_service.rb
# Description : Service for Web Terminal management and WebSocket logic
# License     : MIT License
# -----------------------------------------------------------------------------

require 'pty'
require 'json'
require 'timeout'
require 'securerandom'
require 'base64'
require 'open3'
require 'shellwords'
require 'fileutils'

require_relative 'recording_service'

class TerminalService
  DISCONNECT_GRACE_PERIOD = 45 # seconds
  MAX_REPLAY_BUFFER = 128 * 1024 # 128 KB
  @@pty_sessions = {}
  @@pty_mutex = Mutex.new

  @@sessions = {}
  @@mutex = Mutex.new
  @@session_ttl = 24 * 60 * 60

  @@staged_env = {}
  @@env_mutex = Mutex.new

  def self.register_session(node_name, session_info)
    @@mutex.synchronize do
      @@sessions[node_name] ||= []
      @@sessions[node_name] << session_info
    end
  end

  def self.unregister_session(node_name, session_info)
    @@mutex.synchronize do
      next unless @@sessions[node_name]
      @@sessions[node_name].delete(session_info)
    end
  end

  def self.session_count(node_name)
    cleanup_stale(node_name)
    @@mutex.synchronize { (@@sessions[node_name] || []).size }
  end

  def self.register_if_available(node_name)
    cleanup_stale(node_name)
    @@mutex.synchronize do
      @@sessions[node_name] ||= []
      if @@sessions[node_name].size >= 3
        [false, nil]
      else
        info = { id: SecureRandom.uuid, node: node_name, created_at: Time.now }
        @@sessions[node_name] << info
        [true, info]
      end
    end
  end

  def self.terminate_oldest(node_name)
    session = nil
    @@mutex.synchronize do
      return false unless @@sessions[node_name] && !@@sessions[node_name].empty?
      session = @@sessions[node_name].shift
    end
    begin
      session[:close_proc].call if session[:close_proc]
    rescue => e
      puts "[Terminal Termination Error] #{e.message}"
    end
    true
  end

  def self.cleanup_stale(node_name = nil)
    now = Time.now
    @@mutex.synchronize do
      if node_name
        arr = @@sessions[node_name]
        return unless arr
        arr.reject! { |s| s[:created_at] && (now - s[:created_at]) > @@session_ttl }
      else
        @@sessions.each_key do |key|
          @@sessions[key].reject! { |s| s[:created_at] && (now - s[:created_at]) > @@session_ttl }
        end
      end
    end
    cleanup_stale_pty_sessions
  end

  def self.cleanup_stale_pty_sessions
    cutoff = Time.now - (DISCONNECT_GRACE_PERIOD + 10)
    stale_ids = []
    @@pty_mutex.synchronize do
      @@pty_sessions.each do |sid, s|
        if s[:detached_at] && s[:detached_at] < cutoff
          stale_ids << sid
        end
      end
    end
    stale_ids.each { |sid| cleanup_pty_session(sid) }
  end

  def self.cleanup_pty_session(session_id)
    sess = nil
    @@pty_mutex.synchronize do
      sess = @@pty_sessions.delete(session_id)
    end
    return unless sess
    return if sess[:closed]
    sess[:closed] = true

    # Cancel detach timer
    sess[:detach_timer]&.kill rescue nil

    # Finalize recording if open
    if sess[:rec_io] && !sess[:rec_io].closed?
      sess[:rec_io].flush rescue nil
      sess[:rec_io].close rescue nil
      sess[:rec_io] = nil
    end

    # Clean up staged environment files if any
    cleanup_env_files(sess[:env_token]) if sess[:env_token]

    # Unregister from session limiter
    unregister_session(sess[:node_name], sess[:session_info]) if sess[:session_info]

    # Kill pty read thread unless current thread is the pty read thread
    if sess[:pty_thread] && sess[:pty_thread] != Thread.current
      sess[:pty_thread].kill rescue nil
    end

    # Close pty handles
    sess[:pty_write]&.close rescue nil
    sess[:pty_read]&.close rescue nil

    # Terminate container exec process group
    pid = sess[:pty_pid]
    if pid
      begin
        Process.kill('TERM', -pid) rescue nil
        sleep 0.05
        Process.kill('KILL', -pid) rescue nil
      rescue Errno::ESRCH
      end
      begin
        Timeout.timeout(1) do
          loop do
            wpid, _ = Process.waitpid2(pid, Process::WNOHANG)
            break if wpid
            sleep 0.02
          end
        end
      rescue Timeout::Error, Errno::ECHILD
      end
    end

    # Close driver and IO
    sess[:driver]&.close rescue nil
    if sess[:io] && sess[:ssl_mutex]
      sess[:ssl_mutex].synchronize { sess[:io].close rescue nil } rescue nil
    end
  end

  def self.is_controller?(node_name)
    return true if node_name == 'ansible' || node_name == 'ctl-ctrl'
    if defined?(Controller)
      cname = Controller::NAME rescue 'ctl-ctrl'
      return true if node_name == cname
    end
    if Lab.running?
      runtime_path = Lab.get_file_path(Lab.current_name)
      if File.file?(runtime_path)
        begin
          lab = Lab.new(cfg: runtime_path, log: LabLog.null)
          node = lab.find_node(node_name)
          return node.type == 'controller' if node
        rescue => e
          puts "[Terminal Controller Check Error] #{e.message}"
        end
      end
    end
    false
  end

  def self.stage_env_files(node_name, files)
    raise ArgumentError, 'Files must be an array' unless files.is_a?(Array)
    raise ArgumentError, 'Too many files (max 10 allowed)' if files.size > 10

    validated = []
    summary = []

    files.each do |f|
      next unless f.is_a?(Hash)
      var_name = f['env_var'].to_s.strip.upcase
      raise ArgumentError, "Invalid environment variable name: #{var_name}" unless var_name =~ /\A[A-Z_][A-Z0-9_]*\z/

      raw_fname = f['filename'].to_s.strip
      fname = File.basename(raw_fname).gsub(/[^a-zA-Z0-9_.-]/, '_')
      fname = "#{var_name.downcase}.dat" if fname.empty? || fname == '.' || fname == '..'

      b64 = f['content_base64'].to_s
      b64 = b64.sub(/\Adata:[^;]+;base64,/, '')

      content = begin
        Base64.decode64(b64)
      rescue => e
        raise ArgumentError, "Invalid base64 encoding for #{var_name}: #{e.message}"
      end

      if content.bytesize > 5 * 1024 * 1024
        raise ArgumentError, "File for #{var_name} exceeds 5MB size limit"
      end

      validated << { env_var: var_name, filename: fname, content: content }
      summary << { env_var: var_name, filename: fname, size: content.bytesize }
    end

    return [nil, []] if validated.empty?

    token = SecureRandom.hex(16)
    @@env_mutex.synchronize do
      cutoff = Time.now - 900
      @@staged_env.reject! { |_, v| v[:created_at] && v[:created_at] < cutoff }
      @@staged_env[token] = {
        node_name: node_name,
        created_at: Time.now,
        files: validated
      }
    end

    [token, summary]
  end

  def self.apply_staged_env_files(engine, exec_name, node_user, env_token)
    staged = nil
    @@env_mutex.synchronize do
      staged = @@staged_env[env_token]
    end
    return {} unless staged && staged[:files] && !staged[:files].empty?

    base_dir = resolve_home_dir(engine, exec_name, node_user || 'root') || (node_user ? "/home/#{node_user}" : "/root")
    target_dir = "#{base_dir}/.ctlabs_env/#{env_token}"

    system("#{engine} exec #{exec_name} mkdir -p -m 700 #{target_dir} >/dev/null 2>&1")

    env_map = {}
    staged[:files].each do |f|
      target_path = "#{target_dir}/#{f[:filename]}"
      begin
        Open3.popen3("#{engine} exec -i #{exec_name} sh -c \"cat > #{target_path} && chmod 600 #{target_path}\"") do |stdin, stdout, stderr, wait_thr|
          stdin.write(f[:content])
          stdin.close
          wait_thr.value
        end
        env_map[f[:env_var]] = target_path
      rescue => e
        puts "[Terminal Env File Write Error] #{f[:filename]}: #{e.message}"
      end
    end

    if node_user && !node_user.empty?
      system("#{engine} exec #{exec_name} chown -R #{node_user}:#{node_user} #{target_dir} >/dev/null 2>&1")
    end

    @@env_mutex.synchronize do
      if @@staged_env[env_token]
        @@staged_env[env_token][:engine] = engine
        @@staged_env[env_token][:exec_name] = exec_name
        @@staged_env[env_token][:target_dir] = target_dir
      end
    end

    env_map
  end

  def self.cleanup_env_files(env_token)
    return if env_token.to_s.empty?
    staged = nil
    @@env_mutex.synchronize do
      staged = @@staged_env.delete(env_token)
    end
    return unless staged

    if staged[:engine] && staged[:exec_name] && staged[:target_dir]
      system("#{staged[:engine]} exec #{staged[:exec_name]} rm -rf #{staged[:target_dir]} >/dev/null 2>&1")
    end
  end

  # Login names come from lab/profile YAML, so they are interpolated into a
  # shell command below. Only accept a plain POSIX user name; anything else
  # (or a nil/blank profile user) means "no opinion" and we fall back to root.
  def self.sanitize_login_user(user)
    u = user.to_s.strip
    return nil unless u =~ %r{\A[a-zA-Z0-9_][a-zA-Z0-9_.-]*\z}
    u
  end

  # Home directory of a user inside a running container, cached per
  # container+user. Returns nil if it cannot be determined, in which case we
  # simply omit -w: the shell then starts in / but HOME is still correct, which
  # is far better than guessing a path that may not exist.
  def self.resolve_home_dir(engine, container, user)
    return nil if user.to_s.empty?
    @home_dir_cache ||= {}
    key = "#{container}:#{user}"
    return @home_dir_cache[key] if @home_dir_cache.key?(key)

    home = begin
      out = `#{engine} exec #{container} sh -c 'getent passwd #{user} | cut -d: -f6' 2>/dev/null`.to_s
      out.lines.first.to_s.strip
    rescue
      ''
    end
    home = nil unless home.start_with?('/') && !home.include?(' ')
    @home_dir_cache[key] = home
    home
  end

  # True if `path` is a directory inside the container. Checked before passing -w
  # to `docker exec`, which fails outright if the working directory is missing -
  # so this keeps the terminal usable on labs whose controller does not mount
  # the repo.
  def self.container_dir_exists?(engine, container, path)
    return false if path.to_s.empty?
    system("#{engine} exec #{container} test -d #{path} >/dev/null 2>&1")
  end

  def self.resolve_terminal_command(node_name, session, env_token: nil)
    if node_name == 'ctlabs_host'
      cmd = ['env', 'TERM=linux']
      cmd.push("VAULT_TOKEN=#{session[:vault_token]}") if session[:vault_token]
      cmd.push("VAULT_ADDR=#{session[:vault_addr]}") if session[:vault_addr]
      cmd.push('bash')
      return cmd
    end

    custom_term = nil
    node_type = nil
    tf_cfg = nil
    node_user = nil
    # The lab's controller node is a logical name (e.g. "ansible"); when the
    # lab is attached to the persistent controller there is no such container,
    # so exec must be routed to the real one (ctl-ctrl). For every other node
    # this stays equal to node_name.
    exec_name = node_name

    if Lab.running?
      runtime_path = Lab.get_file_path(Lab.current_name)
      if File.file?(runtime_path)
        begin
          lab = Lab.new(cfg: runtime_path, log: LabLog.null)
          if node = lab.find_node(node_name)
            node_type = node.type
            custom_term = node.term
            profile_user = sanitize_login_user(node.user)
            exec_name = lab.controller_exec_name if node_type == 'controller'

            # `user:` in the profile is ANSIBLE's login (it becomes to root for
            # tasks), not the shell a human wants. Only the controller is logged
            # in as that user; every other node gets root, which is what these
            # terminals used before the non-root migration.
            node_user = node_type == 'controller' ? profile_user : nil

            # Fallback for remote nodes with no explicit term:. Here the profile
            # user IS a real login credential - there is no become on a remote
            # device - so keep using it rather than forcing root.
            if (!custom_term || custom_term.empty?) && node.remote?
              ip_target = node.gw || node.ipv4 || (node.nics && node.nics.values.first)
              custom_term = "ssh://#{profile_user || 'root'}@#{ip_target.split('/').first}" if ip_target
            end
            
            tf_cfg = node.terraform if node.terraform
          end
        rescue => e
          puts "[Terminal Lookup Error] #{e.message}"
        end
      end
    end

    # If we still don't have tf_cfg and we're execing into the controller plane (ctl-ctrl),
    # pull terraform config from the Controller's effective topology/overlay.
    if !tf_cfg && defined?(Controller)
      cname = Controller::NAME rescue 'ctl-ctrl'
      if exec_name == cname
        begin
          ctf = Controller.controller_terraform
          tf_cfg = ctf if ctf.is_a?(Hash) && !ctf.empty?
        rescue
        end
      end
    end

    if custom_term && custom_term.start_with?('ssh://')
      require 'uri'
      uri = URI.parse(custom_term)
      user = uri.user || 'root'
      host = uri.host
      
      cmd = ['ssh', '-o', 'StrictHostKeyChecking=no', '-o', 'SetEnv="TERM=xterm-256color"']
      if Lab.running?
        safe_name = Lab.current_name.gsub('/', '_')
        priv_key_path = "/var/run/ctlabs/keys/#{safe_name}_id_ed25519"
        cmd.push('-i', priv_key_path) if File.exist?(priv_key_path)
      end
      cmd.push("#{user}@#{host}")
    else
      engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'

      # The controller logs in as its profile user (see above); every other node
      # runs with no -u, i.e. root, which is what an operator expects on a data
      # node. Home dir is resolved only when we are overriding the user.
      cmd = [engine, 'exec', '-it']
      cmd.push('-u', node_user) if node_user

      # The controller opens in the mounted repo workspace (the same path the
      # playbook runs from). Every other node runs as root and opens in root's
      # home (/root) rather than the container's default WORKDIR (/); if that
      # directory is absent we fall back to the default cwd (no -w).
      work_dir = nil
      if node_type == 'controller'
        workspace = Automation::ANSIBLE_DIR_CTL
        work_dir  = workspace if container_dir_exists?(engine, exec_name, workspace)
      end
      work_dir ||= resolve_home_dir(engine, exec_name, node_user || 'root')
      work_dir = nil if work_dir && !container_dir_exists?(engine, exec_name, work_dir)
      cmd.push('-w', work_dir) if work_dir
      cmd.push('-e', 'TERM=xterm-256color')

      # Inject GCP creds when opening a terminal in a controller container: the
      # lab's in-lab controller node (ansible/controller), or the persistent
      # control-plane controller (ctl-ctrl) whose terraform config lives in the
      # Controller overlay. The scope selects which terraform_profiles.yml the
      # named `terraform.profile` is resolved against (automation/lab vs ctl).
      is_ctl_controller = defined?(Controller) && exec_name == (Controller::NAME rescue 'ctl-ctrl')
      is_controller_container = (node_type == 'controller') || is_ctl_controller

      if session[:vault_token] && session[:vault_addr] && is_controller_container && tf_cfg
        begin
          gcp_env = GcpAuth.env_vars(tf_cfg, { addr: session[:vault_addr], token: session[:vault_token] },
                                     scope: is_ctl_controller ? 'ctl' : 'lab')
          gcp_env.each { |key, value| cmd.push('-e', "#{key}=#{value}") }
        rescue => e
          puts "[Terminal GCP Auto-Fetch Error] #{e.message}"
        end
      end

      # Inject user-provided environment files on controller containers
      if is_controller_container && env_token && !env_token.to_s.empty?
        begin
          staged_vars = apply_staged_env_files(engine, exec_name, node_user, env_token)
          staged_vars.each { |key, value| cmd.push('-e', "#{key}=#{value}") }
        rescue => e
          puts "[Terminal Env Files Error] #{e.message}"
        end
      end

      cmd.push(exec_name, 'bash')
    end
    cmd
  end

  def self.handle_websocket(driver, cmd, io, ssl_mutex, node_name = 'unknown', initial_cols: nil, initial_rows: nil, env_token: nil, session_id: nil)
    session_id = session_id.to_s.strip
    session_id = session_id.gsub(/[^a-zA-Z0-9_\-]/, '')[0..63] unless session_id.empty?
    session_id = SecureRandom.uuid if session_id.nil? || session_id.empty?

    existing_sess = nil
    @@pty_mutex.synchronize do
      s = @@pty_sessions[session_id]
      if s && !s[:closed] && s[:node_name] == node_name && s[:pty_pid]
        begin
          Process.kill(0, s[:pty_pid])
          existing_sess = s
        rescue Errno::ESRCH
          @@pty_sessions.delete(session_id)
        end
      end
    end

    if existing_sess
      # =========================================================================
      # RESUMED SESSION: Reconnect to active running PTY
      # =========================================================================
      sess = existing_sess

      # Cancel detach timer
      sess[:detach_timer]&.kill rescue nil
      sess[:detach_timer] = nil
      sess[:detached_at] = nil

      # Close old IO if still around and different
      old_io = sess[:io]
      old_ssl = sess[:ssl_mutex]
      if old_io && old_io != io && old_ssl
        old_ssl.synchronize { old_io.close rescue nil } rescue nil
      end

      # Swap in new connection handles
      sess[:driver] = driver
      sess[:io] = io
      sess[:ssl_mutex] = ssl_mutex

      # Update terminal size if provided
      cols = (initial_cols || sess[:cur_cols] || 120).to_i
      rows = (initial_rows || sess[:cur_rows] || 40).to_i
      sess[:cur_cols] = cols if cols.positive?
      sess[:cur_rows] = rows if rows.positive?
      if sess[:pty_write]
        winsize = [sess[:cur_rows], sess[:cur_cols], 0, 0].pack('SSSS')
        sess[:pty_write].ioctl(0x5414, winsize) rescue nil
      end

      driver.on(:open) do |_|
        sess[:output_mutex].synchronize do
          buf = sess[:output_buffer]
          if buf && !buf.empty?
            driver.text(buf) rescue nil
          end
          if sess[:rec_id]
            driver.text("\x00" + JSON.generate({ type: 'record', state: 'started', id: sess[:rec_id], node: node_name })) rescue nil
          end
        end
      end

      attach_driver_handlers(driver, io, ssl_mutex, sess)
      driver.start
      start_socket_reader(io, ssl_mutex, driver)
      return
    end

    # =========================================================================
    # NEW SESSION: Allocate session and spawn PTY
    # =========================================================================
    sess = {
      session_id: session_id,
      node_name: node_name,
      pty_read: nil,
      pty_write: nil,
      pty_pid: nil,
      pty_thread: nil,
      session_info: nil,
      output_buffer: ''.force_encoding('UTF-8'),
      output_mutex: Mutex.new,
      driver: driver,
      io: io,
      ssl_mutex: ssl_mutex,
      env_token: env_token,
      rec_io: nil,
      rec_id: nil,
      rec_started: nil,
      rec_mutex: Mutex.new,
      cur_cols: (initial_cols || 120).to_i,
      cur_rows: (initial_rows || 40).to_i,
      detach_timer: nil,
      detached_at: nil,
      closed: false
    }

    sess[:rec_event] = lambda do |kind, data|
      begin
        sess[:rec_mutex].synchronize do
          if sess[:rec_io] && !sess[:rec_io].closed?
            t = Process.clock_gettime(Process::CLOCK_MONOTONIC) - sess[:rec_started].to_f
            sess[:rec_io].write(JSON.generate([t.round(6), kind, data]) + "\n")
            sess[:rec_io].flush
          end
        end
      rescue StandardError => e
        puts "[Recording Write Error] #{e.class}: #{e.message}"
      end
    end

    sess[:rec_start] = lambda do |cols, rows|
      sess[:rec_mutex].synchronize do
        next if sess[:rec_io]
        id, io_handle = RecordingService.open(node: node_name, cols: cols, rows: rows)
        sess[:rec_io]      = io_handle
        sess[:rec_id]      = id
        sess[:rec_started] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      sess[:rec_id]
    end

    sess[:rec_stop] = lambda do
      id       = nil
      duration = 0.0
      sess[:rec_mutex].synchronize do
        id = sess[:rec_id]
        if sess[:rec_io]
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - sess[:rec_started].to_f
          sess[:rec_io].flush rescue nil
          sess[:rec_io].close rescue nil
        end
        sess[:rec_io]      = nil
        sess[:rec_id]      = nil
        sess[:rec_started] = nil
      end
      [id, duration]
    end

    driver.on(:open) do |_|
      begin
        available, info = register_if_available(node_name)
        unless available
          cleanup_env_files(env_token) if env_token
          driver.text("\r\n\x1b[31m[Session Limit Reached: Max 3 terminal sessions per node]\x1b[0m\r\n") rescue nil
          driver.close
          return
        end

        sess[:session_info] = info
        info[:close_proc] = proc { cleanup_pty_session(session_id) }

        pty_read, pty_write, pty_pid = PTY.spawn(*cmd)
        sess[:pty_read]  = pty_read
        sess[:pty_write] = pty_write
        sess[:pty_pid]   = pty_pid

        if initial_cols && initial_rows && pty_write
          winsize = [initial_rows.to_i, initial_cols.to_i, 0, 0].pack('SSSS')
          pty_write.ioctl(0x5414, winsize) rescue nil
        end

        @@pty_mutex.synchronize do
          @@pty_sessions[session_id] = sess
        end

        sess[:pty_thread] = Thread.new do
          utf8_buf = ''.force_encoding('BINARY')
          loop do
            begin
              chunk = pty_read.readpartial(8192)
              utf8_buf << chunk.force_encoding('BINARY')

              utf8 = utf8_buf.dup.force_encoding('UTF-8')
              if utf8.valid_encoding?
                sess[:rec_event].call('o', utf8)
                sess[:output_mutex].synchronize do
                  sess[:output_buffer] << utf8
                  if sess[:output_buffer].bytesize > MAX_REPLAY_BUFFER
                    sess[:output_buffer] = sess[:output_buffer].byteslice(-MAX_REPLAY_BUFFER..-1).scrub('')
                  end
                  sess[:driver]&.text(utf8) rescue nil
                end
                utf8_buf.clear
              else
                scrubbed = utf8.scrub('?')
                if scrubbed != utf8
                  sess[:rec_event].call('o', scrubbed)
                  sess[:output_mutex].synchronize do
                    sess[:output_buffer] << scrubbed
                    if sess[:output_buffer].bytesize > MAX_REPLAY_BUFFER
                      sess[:output_buffer] = sess[:output_buffer].byteslice(-MAX_REPLAY_BUFFER..-1).scrub('')
                    end
                    sess[:driver]&.text(scrubbed) rescue nil
                  end
                  utf8_buf.clear
                end
              end
            rescue IO::WaitReadable
              IO.select([pty_read], nil, nil, 0.1) rescue sleep(0.01)
              retry
            rescue EOFError, Errno::EIO, Errno::ECONNRESET, IOError
              remainder = utf8_buf.force_encoding('UTF-8')
              if remainder.bytesize > 0
                s_rem = remainder.scrub('?')
                sess[:rec_event].call('o', s_rem)
                sess[:output_mutex].synchronize do
                  sess[:output_buffer] << s_rem
                  sess[:driver]&.text(s_rem) rescue nil
                end
              end
              exit_msg = "\r\n\x1b[31m[Session closed by container]\x1b[0m\r\n"
              sess[:rec_event].call('o', exit_msg)
              sess[:output_mutex].synchronize do
                sess[:output_buffer] << exit_msg
                sess[:driver]&.text(exit_msg) rescue nil
              end
              cleanup_pty_session(session_id)
              break
            rescue StandardError => e
              puts "[PTY Error] #{e.message}"
              cleanup_pty_session(session_id)
              break
            end
          end
        end
      rescue => e
        cleanup_env_files(env_token) if env_token
        unregister_session(node_name, sess[:session_info]) if sess[:session_info]
        driver.text("\r\n\x1b[31m[Error spawning terminal: #{e.message}]\x1b[0m\r\n") rescue nil
        driver.close rescue nil
      end
    end

    attach_driver_handlers(driver, io, ssl_mutex, sess)
    driver.start
    start_socket_reader(io, ssl_mutex, driver)
  end

  def self.attach_driver_handlers(driver, io, ssl_mutex, sess)
    node_name = sess[:node_name]
    session_id = sess[:session_id]

    driver.on(:message) do |event|
      payload = begin
        JSON.parse(event.data)
      rescue JSON::ParserError
        sess[:pty_write]&.write(event.data)
        next
      end
      next unless payload.is_a?(Hash)

      case payload['type']
      when 'input'
        sess[:pty_write]&.write(payload['data'])

      when 'resize'
        cols = payload['cols'].to_i
        rows = payload['rows'].to_i
        if sess[:pty_write]
          winsize = [rows, cols, 0, 0].pack('SSSS')
          sess[:pty_write].ioctl(0x5414, winsize) rescue nil
        end
        sess[:cur_cols] = cols if cols.positive?
        sess[:cur_rows] = rows if rows.positive?
        sess[:rec_event]&.call('r', "#{sess[:cur_cols]}x#{sess[:cur_rows]}")

      when 'record_start'
        begin
          cols = payload['cols'].to_i.positive? ? payload['cols'].to_i : sess[:cur_cols]
          rows = payload['rows'].to_i.positive? ? payload['rows'].to_i : sess[:cur_rows]
          id   = sess[:rec_start]&.call(cols, rows)
          if id
            rec_text = "\r\n\x1b[31m● REC\x1b[0m #{id}\r\n"
            sess[:rec_event]&.call('o', rec_text)
            sess[:output_mutex].synchronize do
              sess[:output_buffer] << rec_text
              driver.text(rec_text) rescue nil
            end
            driver.text("\x00" + JSON.generate({ type: 'record', state: 'started', id: id, node: node_name })) rescue nil
          else
            active = sess[:rec_mutex].synchronize { sess[:rec_id] }
            driver.text("\x00" + JSON.generate({ type: 'record', state: 'started', id: active, node: node_name })) rescue nil
          end
        rescue StandardError => e
          puts "[Recording Start Error] #{e.class}: #{e.message}"
          driver.text("\x00" + JSON.generate({ type: 'record', state: 'error', message: e.message })) rescue nil
        end

      when 'record_stop'
        id, duration = sess[:rec_stop] ? sess[:rec_stop].call : [nil, 0.0]
        if id
          msg = "\r\n\x1b[32m■ Saved\x1b[0m #{id} (#{format('%.1fs', duration)}) — open Walkthrough to replay\r\n"
          sess[:rec_event]&.call('o', msg)
          sess[:output_mutex].synchronize do
            sess[:output_buffer] << msg
            driver.text(msg) rescue nil
          end
          driver.text("\x00" + JSON.generate({ type: 'record', state: 'stopped', id: id, duration: duration.round(3) })) rescue nil
        else
          driver.text("\x00" + JSON.generate({ type: 'record', state: 'stopped', id: nil })) rescue nil
        end
      end
    end

    driver.on(:close) do |_|
      if sess[:driver] == driver && !sess[:closed]
        sess[:driver] = nil
        sess[:io] = nil
        sess[:detached_at] = Time.now
        sess[:detach_timer] = Thread.new do
          sleep DISCONNECT_GRACE_PERIOD
          cleanup_pty_session(session_id)
        end
      end
      ssl_mutex.synchronize { io.close rescue nil } rescue nil
    end
  end

  def self.start_socket_reader(io, ssl_mutex, driver)
    Thread.new do
      loop do
        begin
          data = nil
          ssl_mutex.synchronize do
            data = io.read_nonblock(8192)
          end
          
          if data == :wait_readable || data == :wait_writable
            IO.select([io], nil, nil, 0.1) rescue sleep(0.01)
            next
          elsif data.nil?
            break
          end
          driver.parse(data) if data && !data.empty?
        rescue IO::WaitReadable
          IO.select([io], nil, nil, 0.1) rescue sleep(0.01)
          retry
        rescue IO::WaitWritable
          sleep(0.01)
          retry
        rescue EOFError, Errno::ECONNRESET, IOError, OpenSSL::SSL::SSLError
          break
        rescue StandardError => e
          puts "[Terminal Debug] Loop broken by StandardError: #{e.class} - #{e.message}"
          break
        end
      end
      driver.close rescue nil
    end
  end

  # ---------------------------------------------------------------------------
  # General File Upload & Download Support
  # ---------------------------------------------------------------------------

  def self.resolve_node_target(node_name)
    if node_name == 'ctlabs_host'
      return {
        type: :host,
        default_dir: '/root'
      }
    end

    custom_term = nil
    node_type = nil
    node_user = nil
    exec_name = node_name

    if Lab.running?
      runtime_path = Lab.get_file_path(Lab.current_name)
      if File.file?(runtime_path)
        begin
          lab = Lab.new(cfg: runtime_path, log: LabLog.null)
          if node = lab.find_node(node_name)
            node_type = node.type
            custom_term = node.term
            profile_user = sanitize_login_user(node.user)
            exec_name = lab.controller_exec_name if node_type == 'controller'
            node_user = node_type == 'controller' ? profile_user : nil

            if (!custom_term || custom_term.empty?) && node.remote?
              ip_target = node.gw || node.ipv4 || (node.nics && node.nics.values.first)
              custom_term = "ssh://#{profile_user || 'root'}@#{ip_target.split('/').first}" if ip_target
            end
          end
        rescue => e
          puts "[Terminal Target Lookup Error] #{e.message}"
        end
      end
    end

    if defined?(Controller)
      cname = Controller::NAME rescue 'ctl-ctrl'
      if exec_name == cname || node_name == cname || node_name == 'ctl-ctrl'
        exec_name = cname
        node_type = 'controller'
      end
    end

    if custom_term && custom_term.start_with?('ssh://')
      require 'uri'
      uri = URI.parse(custom_term)
      user = uri.user || 'root'
      host = uri.host
      priv_key_path = nil
      if Lab.running?
        safe_name = Lab.current_name.gsub('/', '_')
        key_path = "/var/run/ctlabs/keys/#{safe_name}_id_ed25519"
        priv_key_path = key_path if File.exist?(key_path)
      end
      return {
        type: :ssh,
        user: user,
        host: host,
        key: priv_key_path,
        default_dir: "/home/#{user}"
      }
    end

    engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
    default_dir = nil
    if node_type == 'controller'
      workspace = Automation::ANSIBLE_DIR_CTL
      default_dir = workspace if container_dir_exists?(engine, exec_name, workspace)
    end
    default_dir ||= resolve_home_dir(engine, exec_name, node_user || 'root') || (node_user ? "/home/#{node_user}" : "/root")

    {
      type: :container,
      engine: engine,
      container: exec_name,
      user: node_user,
      default_dir: default_dir
    }
  end

  def self.sanitize_relative_path(path)
    return '' if path.to_s.strip.empty?
    str = path.to_s.sub(/^[a-zA-Z]:/, '')
    stack = []
    str.tr('\\', '/').split('/').each do |p|
      next if p.empty? || p == '.'
      if p == '..'
        stack.pop
      else
        clean = p.gsub(/[^a-zA-Z0-9_.-]/, '_')
        stack.push(clean) unless clean.empty? || clean == '.' || clean == '..'
      end
    end
    stack.join('/')
  end

  def self.resolve_target_path(target, input_path, default_filename: nil)
    raw = input_path.to_s.strip
    raw = target[:default_dir] if raw.empty?

    home_dir = if target[:type] == :container
      resolve_home_dir(target[:engine], target[:container], target[:user] || 'root') || (target[:user] ? "/home/#{target[:user]}" : "/root")
    elsif target[:type] == :ssh
      "/home/#{target[:user]}"
    else
      ENV['HOME'] || '/root'
    end

    if raw == '~'
      raw = home_dir
    elsif raw.start_with?('~/')
      raw = File.join(home_dir, raw[2..-1])
    elsif !raw.start_with?('/')
      raw = File.join(target[:default_dir] || home_dir, raw)
    end

    clean_path = File.expand_path(raw, '/')

    if default_filename
      clean_rel = sanitize_relative_path(default_filename)
      clean_rel = 'file.dat' if clean_rel.empty?
      if raw.end_with?('/') || clean_rel.include?('/') || is_target_directory?(target, clean_path)
        clean_path = File.join(clean_path, clean_rel)
      end
    end

    clean_path
  end

  def self.is_target_directory?(target, path)
    return false if path.to_s.empty?
    case target[:type]
    when :container
      system("#{target[:engine]} exec #{target[:container]} test -d #{Shellwords.escape(path)} >/dev/null 2>&1")
    when :host
      File.directory?(path)
    when :ssh
      cmd = ["ssh", "-o", "StrictHostKeyChecking=no"]
      cmd.push("-i", target[:key]) if target[:key]
      cmd.push("#{target[:user]}@#{target[:host]}", "test -d #{Shellwords.escape(path)}")
      system(*cmd)
    else
      false
    end
  end

  def self.upload_file(node_name, tempfile_or_io, original_filename, dest_dir: nil, custom_filename: nil)
    target = resolve_node_target(node_name)
    raise ArgumentError, "Node '#{node_name}' cannot be resolved" unless target

    raw_name = (custom_filename && !custom_filename.strip.empty?) ? custom_filename.strip : original_filename.to_s.strip
    clean_rel = sanitize_relative_path(raw_name)
    clean_rel = "uploaded_file.dat" if clean_rel.empty?

    target_path = resolve_target_path(target, dest_dir, default_filename: clean_rel)
    parent_dir = File.dirname(target_path)
    base_name = File.basename(target_path)
    fname = base_name

    case target[:type]
    when :container
      engine = target[:engine]
      container = target[:container]
      escaped_parent = Shellwords.escape(parent_dir)
      escaped_path = Shellwords.escape(target_path)

      system("#{engine} exec #{container} mkdir -p #{escaped_parent} >/dev/null 2>&1")

      cmd = "#{engine} exec -i #{container} sh -c \"cat > #{escaped_path}\""
      Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        if tempfile_or_io.respond_to?(:read)
          IO.copy_stream(tempfile_or_io, stdin)
        else
          File.open(tempfile_or_io.to_s, 'rb') { |f| IO.copy_stream(f, stdin) }
        end
        stdin.close
        status = wait_thr.value
        raise "Container upload failed: #{stderr.read}" unless status.success?
      end

      # Smart permissions for SSH keys and scripts
      if parent_dir.end_with?('/.ssh')
        system("#{engine} exec #{container} chmod 700 #{escaped_parent} >/dev/null 2>&1")
        if target[:user] && !target[:user].empty?
          system("#{engine} exec #{container} chown #{target[:user]}:#{target[:user]} #{escaped_parent} >/dev/null 2>&1")
        end
      end

      if target[:user] && !target[:user].empty?
        system("#{engine} exec #{container} chown #{target[:user]}:#{target[:user]} #{escaped_path} >/dev/null 2>&1")
      end

      is_private_key = (base_name =~ /^id_[a-z0-9_]+$/i) || base_name.end_with?('.pem', '.key')
      mode = if is_private_key || (parent_dir.end_with?('/.ssh') && !base_name.end_with?('.pub'))
        '0600'
      elsif base_name.end_with?('.pub')
        '0644'
      elsif base_name.end_with?('.sh', '.py', '.rb', '.bash')
        '0755'
      end
      if mode
        system("#{engine} exec #{container} chmod #{mode} #{escaped_path} >/dev/null 2>&1")
      end

      size_out, _ = Open3.capture2("#{engine} exec #{container} sh -c \"wc -c < #{escaped_path}\" 2>/dev/null")
      file_size = size_out.to_s.strip.to_i

      { ok: true, filename: base_name, relative_path: clean_rel, path: target_path, size: file_size }

    when :host
      FileUtils.mkdir_p(parent_dir)
      if tempfile_or_io.respond_to?(:read)
        File.open(target_path, 'wb') { |f| IO.copy_stream(tempfile_or_io, f) }
      else
        FileUtils.cp(tempfile_or_io.to_s, target_path)
      end

      if parent_dir.end_with?('/.ssh')
        File.chmod(0700, parent_dir) rescue nil
      end
      is_private_key = (base_name =~ /^id_[a-z0-9_]+$/i) || base_name.end_with?('.pem', '.key')
      mode = if is_private_key || (parent_dir.end_with?('/.ssh') && !base_name.end_with?('.pub'))
        0600
      elsif base_name.end_with?('.pub')
        0644
      elsif base_name.end_with?('.sh', '.py', '.rb', '.bash')
        0755
      end
      File.chmod(mode, target_path) if mode rescue nil

      { ok: true, filename: base_name, relative_path: clean_rel, path: target_path, size: File.size(target_path) }

    when :ssh
      require 'tempfile'
      local_src = if tempfile_or_io.is_a?(String) && File.exist?(tempfile_or_io)
        tempfile_or_io
      else
        tf = Tempfile.new('ctlabs_upload')
        tf.binmode
        IO.copy_stream(tempfile_or_io, tf)
        tf.close
        tf.path
      end

      ssh_cmd = ["ssh", "-o", "StrictHostKeyChecking=no"]
      ssh_cmd.push("-i", target[:key]) if target[:key]
      ssh_cmd.push("#{target[:user]}@#{target[:host]}", "mkdir -p #{Shellwords.escape(parent_dir)}")
      system(*ssh_cmd)

      if parent_dir.end_with?('/.ssh')
        chmod_dir_cmd = ["ssh", "-o", "StrictHostKeyChecking=no"]
        chmod_dir_cmd.push("-i", target[:key]) if target[:key]
        chmod_dir_cmd.push("#{target[:user]}@#{target[:host]}", "chmod 700 #{Shellwords.escape(parent_dir)}")
        system(*chmod_dir_cmd)
      end

      scp_cmd = ["scp", "-o", "StrictHostKeyChecking=no"]
      scp_cmd.push("-i", target[:key]) if target[:key]
      scp_cmd.push(local_src, "#{target[:user]}@#{target[:host]}:#{target_path}")
      success = system(*scp_cmd)
      raise "SCP transfer failed" unless success

      is_private_key = (base_name =~ /^id_[a-z0-9_]+$/i) || base_name.end_with?('.pem', '.key')
      mode = if is_private_key || (parent_dir.end_with?('/.ssh') && !base_name.end_with?('.pub'))
        '0600'
      elsif base_name.end_with?('.pub')
        '0644'
      elsif base_name.end_with?('.sh', '.py', '.rb', '.bash')
        '0755'
      end
      if mode
        chmod_file_cmd = ["ssh", "-o", "StrictHostKeyChecking=no"]
        chmod_file_cmd.push("-i", target[:key]) if target[:key]
        chmod_file_cmd.push("#{target[:user]}@#{target[:host]}", "chmod #{mode} #{Shellwords.escape(target_path)}")
        system(*chmod_file_cmd)
      end

      { ok: true, filename: base_name, relative_path: clean_rel, path: target_path, size: File.size(local_src) }
    end
  end

  def self.create_directory(node_name, relative_dir, dest_dir: nil)
    target = resolve_node_target(node_name)
    raise ArgumentError, "Node '#{node_name}' cannot be resolved" unless target

    clean_rel = sanitize_relative_path(relative_dir)
    return { ok: true } if clean_rel.empty?

    base_dir = resolve_target_path(target, dest_dir)
    target_path = File.join(base_dir, clean_rel)
    escaped_path = Shellwords.escape(target_path)

    case target[:type]
    when :container
      engine = target[:engine]
      container = target[:container]
      system("#{engine} exec #{container} mkdir -p #{escaped_path} >/dev/null 2>&1")
      if target[:user] && !target[:user].empty?
        system("#{engine} exec #{container} chown -R #{target[:user]}:#{target[:user]} #{escaped_path} >/dev/null 2>&1")
      end
    when :host
      FileUtils.mkdir_p(target_path)
    when :ssh
      ssh_cmd = ["ssh", "-o", "StrictHostKeyChecking=no"]
      ssh_cmd.push("-i", target[:key]) if target[:key]
      ssh_cmd.push("#{target[:user]}@#{target[:host]}", "mkdir -p #{escaped_path}")
      system(*ssh_cmd)
    end

    { ok: true, path: target_path }
  end

  def self.upload_files(node_name, files_with_paths, dest_dir: nil, empty_dirs: [])
    target = resolve_node_target(node_name)
    raise ArgumentError, "Node '#{node_name}' cannot be resolved" unless target

    base_dir = resolve_target_path(target, dest_dir)

    Array(empty_dirs).each do |edir|
      create_directory(node_name, edir, dest_dir: base_dir) rescue nil
    end

    uploaded = []
    errors = []
    total_bytes = 0

    files_with_paths.each do |item|
      tempfile = item[:tempfile] || item[:io]
      rel_path = item[:path] || item[:filename]
      next unless tempfile && rel_path

      begin
        res = upload_file(node_name, tempfile, rel_path, dest_dir: "#{base_dir}/")
        if res[:ok]
          uploaded << res
          total_bytes += (res[:size] || 0)
        else
          errors << { filename: rel_path, error: res[:error] || 'Upload failed' }
        end
      rescue => e
        errors << { filename: rel_path, error: e.message }
      end
    end

    {
      ok: errors.empty?,
      count: uploaded.size,
      total_size: total_bytes,
      files: uploaded,
      errors: errors
    }
  end

  def self.list_node_files(node_name, remote_dir = nil)
    target = resolve_node_target(node_name)
    return { ok: false, error: "Node not found" } unless target

    resolved_dir = resolve_target_path(target, remote_dir || target[:default_dir] || '~')
    escaped = Shellwords.escape(resolved_dir)

    list_script = "for f in #{escaped}/* #{escaped}/.*; do " \
                  "[ \"$f\" = \"#{escaped}/*\" ] && continue; " \
                  "[ \"$f\" = \"#{escaped}/.\" ] && continue; " \
                  "[ \"$f\" = \"#{escaped}/..\" ] && continue; " \
                  "if [ -f \"$f\" ]; then echo \"FILE:$(wc -c < \"$f\" 2>/dev/null):$(basename \"$f\")\"; " \
                  "elif [ -d \"$f\" ]; then echo \"DIR:0:$(basename \"$f\")\"; fi; " \
                  "done 2>/dev/null"

    raw_output = case target[:type]
    when :container
      out, _ = Open3.capture2("#{target[:engine]} exec #{target[:container]} sh -c #{Shellwords.escape(list_script)}")
      out
    when :host
      out, _ = Open3.capture2("sh", "-c", list_script)
      out
    when :ssh
      ssh_cmd = ["ssh", "-o", "StrictHostKeyChecking=no"]
      ssh_cmd.push("-i", target[:key]) if target[:key]
      ssh_cmd.push("#{target[:user]}@#{target[:host]}", list_script)
      out, _ = Open3.capture2(*ssh_cmd)
      out
    end

    items = []
    raw_output.to_s.each_line do |line|
      line = line.strip
      parts = line.split(':', 3)
      next unless parts.length == 3
      type = parts[0] == 'FILE' ? :file : :dir
      size = parts[1].to_i
      name = parts[2]
      next if name.empty?
      items << {
        name: name,
        type: type,
        size: type == :file ? size : nil,
        path: File.join(resolved_dir, name)
      }
    end

    # Sort directories first, then files alphabetically
    items.sort_by! { |item| [item[:type] == :dir ? 0 : 1, item[:name].downcase] }

    { ok: true, dir: resolved_dir, items: items }
  end

  def self.check_node_file(node_name, remote_path)
    target = resolve_node_target(node_name)
    return { ok: false, exists: false, error: "Node not found" } unless target

    resolved_path = resolve_target_path(target, remote_path)
    bname = File.basename(resolved_path)

    case target[:type]
    when :container
      engine = target[:engine]
      container = target[:container]
      escaped = Shellwords.escape(resolved_path)
      cmd = "#{engine} exec #{container} sh -c 'if [ -f #{escaped} ]; then echo \"FILE:$(wc -c < #{escaped} 2>/dev/null)\"; elif [ -d #{escaped} ]; then echo DIR; else echo NOT_FOUND; fi' 2>/dev/null"
      out, _ = Open3.capture2(cmd)
      line = out.to_s.strip

      if line.start_with?('FILE:')
        size = line.sub('FILE:', '').strip.to_i
        { ok: true, exists: true, type: :file, size: size, path: resolved_path, name: bname }
      elsif line == 'DIR'
        { ok: true, exists: true, type: :dir, size: nil, path: resolved_path, name: bname }
      else
        { ok: true, exists: false, path: resolved_path, name: bname }
      end

    when :host
      if File.file?(resolved_path)
        { ok: true, exists: true, type: :file, size: File.size(resolved_path), path: resolved_path, name: bname }
      elsif File.directory?(resolved_path)
        { ok: true, exists: true, type: :dir, size: nil, path: resolved_path, name: bname }
      else
        { ok: true, exists: false, path: resolved_path, name: bname }
      end

    when :ssh
      ssh_cmd = ["ssh", "-o", "StrictHostKeyChecking=no"]
      ssh_cmd.push("-i", target[:key]) if target[:key]
      escaped = Shellwords.escape(resolved_path)
      check_script = "if [ -f #{escaped} ]; then echo FILE:$(wc -c < #{escaped} 2>/dev/null); elif [ -d #{escaped} ]; then echo DIR; else echo NOT_FOUND; fi"
      ssh_cmd.push("#{target[:user]}@#{target[:host]}", check_script)
      out, _ = Open3.capture2(*ssh_cmd)
      line = out.to_s.strip

      if line.start_with?('FILE:')
        size = line.sub('FILE:', '').strip.to_i
        { ok: true, exists: true, type: :file, size: size, path: resolved_path, name: bname }
      elsif line == 'DIR'
        { ok: true, exists: true, type: :dir, size: nil, path: resolved_path, name: bname }
      else
        { ok: true, exists: false, path: resolved_path, name: bname }
      end
    end
  end

  def self.stream_file(node_name, remote_path, is_dir: false, &block)
    target = resolve_node_target(node_name)
    raise ArgumentError, "Node '#{node_name}' cannot be resolved" unless target

    resolved_path = resolve_target_path(target, remote_path)

    case target[:type]
    when :container
      engine = target[:engine]
      container = target[:container]

      if is_dir
        parent = File.dirname(resolved_path)
        bname = File.basename(resolved_path)
        cmd = "#{engine} exec #{container} tar -czf - -C #{Shellwords.escape(parent)} #{Shellwords.escape(bname)}"
      else
        cmd = "#{engine} exec #{container} cat #{Shellwords.escape(resolved_path)}"
      end

      Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        while (chunk = stdout.read(65536))
          block.call(chunk)
        end
        wait_thr.value
      end

    when :host
      if is_dir
        parent = File.dirname(resolved_path)
        bname = File.basename(resolved_path)
        cmd = "tar -czf - -C #{Shellwords.escape(parent)} #{Shellwords.escape(bname)}"
        Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          while (chunk = stdout.read(65536))
            block.call(chunk)
          end
          wait_thr.value
        end
      else
        File.open(resolved_path, 'rb') do |f|
          while (chunk = f.read(65536))
            block.call(chunk)
          end
        end
      end

    when :ssh
      ssh_cmd = ["ssh", "-o", "StrictHostKeyChecking=no"]
      ssh_cmd.push("-i", target[:key]) if target[:key]
      if is_dir
        parent = File.dirname(resolved_path)
        bname = File.basename(resolved_path)
        ssh_cmd.push("#{target[:user]}@#{target[:host]}", "tar -czf - -C #{Shellwords.escape(parent)} #{Shellwords.escape(bname)}")
      else
        ssh_cmd.push("#{target[:user]}@#{target[:host]}", "cat #{Shellwords.escape(resolved_path)}")
      end
      Open3.popen3(*ssh_cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        while (chunk = stdout.read(65536))
          block.call(chunk)
        end
        wait_thr.value
      end
    end
  end

  at_exit do
    sids = @@pty_mutex.synchronize { @@pty_sessions.keys } rescue []
    sids.each { |sid| cleanup_pty_session(sid) rescue nil }
  end
end
