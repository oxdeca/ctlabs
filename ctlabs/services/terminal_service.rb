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

require_relative 'recording_service'

class TerminalService
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

  def self.handle_websocket(driver, cmd, io, ssl_mutex, node_name = 'unknown', initial_cols: nil, initial_rows: nil, env_token: nil)
    pty_read     = nil
    pty_write    = nil
    pty_pid      = nil
    pty_thread   = nil
    session_info = nil
    closed       = false

    # --- Recording (asciicast v2) -------------------------------------------
    # A recording is opt-in per browser tab. The PTY thread records output as
    # it is forwarded, the message handler records resizes, and the file is
    # finalized on stop or when the socket closes. Input is deliberately NOT
    # recorded: the PTY echoes what the user types anyway, and skipping input
    # keeps echo-off secrets (passwords) out of the cast.
    rec_io      = nil
    rec_id      = nil
    rec_started = nil
    rec_mutex   = Mutex.new
    cur_cols    = (initial_cols || 120).to_i
    cur_rows    = (initial_rows || 40).to_i

    rec_event = lambda do |kind, data|
      begin
        rec_mutex.synchronize do
          if rec_io && !rec_io.closed?
            t = Process.clock_gettime(Process::CLOCK_MONOTONIC) - rec_started.to_f
            rec_io.write(JSON.generate([t.round(6), kind, data]) + "\n")
            rec_io.flush
          end
        end
      rescue StandardError => e
        puts "[Recording Write Error] #{e.class}: #{e.message}"
      end
    end

    rec_start = lambda do |cols, rows|
      rec_mutex.synchronize do
        next if rec_io
        id, io = RecordingService.open(node: node_name, cols: cols, rows: rows)
        rec_io      = io
        rec_id      = id
        rec_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      rec_id
    end

    rec_stop = lambda do
      id       = nil
      duration = 0.0
      rec_mutex.synchronize do
        id = rec_id
        if rec_io
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - rec_started.to_f
          rec_io.flush rescue nil
          rec_io.close rescue nil
        end
        rec_io      = nil
        rec_id      = nil
        rec_started = nil
      end
      [id, duration]
    end

    # Control frames are prefixed with NUL so they can share the terminal's
    # websocket without ever being mistaken for terminal output. The client
    # strips the prefix and handles the JSON; anything that fails to parse is
    # written to the terminal as normal data.
    rec_control = lambda do |payload|
      driver.text("\x00" + JSON.generate(payload)) rescue nil
    end

    # Write to both the recording and the screen (used for our own notices).
    emit = lambda do |text|
      rec_event.call('o', text)
      driver.text(text) rescue nil
    end

    driver.on(:open) do |_|
      begin
        available, info = register_if_available(node_name)
        unless available
          cleanup_env_files(env_token) if env_token
          driver.text("\r\n\x1b[31m[Session Limit Reached: Max 3 terminal sessions per node]\x1b[0m\r\n")
          driver.close
          return
        end
        session_info = info
        session_info[:close_proc] = proc { driver.close rescue nil }

        pty_read, pty_write, pty_pid = PTY.spawn(*cmd)
        
        if initial_cols && initial_rows && pty_write
          winsize = [initial_rows.to_i, initial_cols.to_i, 0, 0].pack('SSSS')
          pty_write.ioctl(0x5414, winsize) rescue nil
        end

        pty_thread = Thread.new do
          utf8_buf = ''.force_encoding('BINARY')
          loop do
            begin
              chunk = pty_read.readpartial(8192)
              utf8_buf << chunk.force_encoding('BINARY')

              # Convert buffered bytes to UTF-8. readpartial can split
              # multi-byte sequences across chunks, so only emit when we
              # have complete UTF-8; otherwise keep buffering.
              utf8 = utf8_buf.dup.force_encoding('UTF-8')
              if utf8.valid_encoding?
                rec_event.call('o', utf8)
                driver.text(utf8)
                utf8_buf.clear
              else
                # Genuinely invalid bytes -> scrub and emit; otherwise
                # an incomplete multibyte sequence is still pending.
                scrubbed = utf8.scrub('?')
                if scrubbed != utf8
                  rec_event.call('o', scrubbed)
                  driver.text(scrubbed)
                  utf8_buf.clear
                end
              end
            rescue IO::WaitReadable
              IO.select([pty_read], nil, nil, 0.1) rescue sleep(0.01)
              retry
            rescue EOFError, Errno::EIO, Errno::ECONNRESET, IOError
              remainder = utf8_buf.force_encoding('UTF-8')
              if remainder.bytesize > 0
                rec_event.call('o', remainder.scrub('?'))
                driver.text(remainder.scrub('?'))
              end
              emit.call("\r\n\x1b[31m[Session closed by container]\x1b[0m\r\n")
              break
            rescue StandardError => e
              puts "[PTY Error] #{e.message}"
              break
            end
          end
          driver.close rescue nil
        end
      rescue => e
        cleanup_env_files(env_token) if env_token
        unregister_session(node_name, session_info) if session_info
        driver.text("\r\n\x1b[31m[Error spawning terminal: #{e.message}]\x1b[0m\r\n") rescue nil
        driver.close rescue nil
      end
    end

    driver.on(:message) do |event|
      payload = begin
        JSON.parse(event.data)
      rescue JSON::ParserError
        pty_write&.write(event.data)
        next
      end
      next unless payload.is_a?(Hash)

      case payload['type']
      when 'input'
        pty_write&.write(payload['data'])

      when 'resize'
        cols = payload['cols'].to_i
        rows = payload['rows'].to_i
        if pty_write
          winsize = [rows, cols, 0, 0].pack('SSSS')
          pty_write.ioctl(0x5414, winsize) rescue nil
        end
        cur_cols = cols if cols.positive?
        cur_rows = rows if rows.positive?
        rec_event.call('r', "#{cur_cols}x#{cur_rows}")

      when 'record_start'
        begin
          cols = payload['cols'].to_i.positive? ? payload['cols'].to_i : cur_cols
          rows = payload['rows'].to_i.positive? ? payload['rows'].to_i : cur_rows
          id   = rec_start.call(cols, rows)
          if id
            emit.call("\r\n\x1b[31m● REC\x1b[0m #{id}\r\n")
            rec_control.call({ type: 'record', state: 'started', id: id, node: node_name })
          else
            # Already recording (e.g. a second click raced the first): report
            # the active id so the button converges on the real state.
            active = rec_mutex.synchronize { rec_id }
            rec_control.call({ type: 'record', state: 'started', id: active, node: node_name })
          end
        rescue StandardError => e
          puts "[Recording Start Error] #{e.class}: #{e.message}"
          rec_control.call({ type: 'record', state: 'error', message: e.message })
        end

      when 'record_stop'
        id, duration = rec_stop.call
        if id
          emit.call("\r\n\x1b[32m■ Saved\x1b[0m #{id} (#{format('%.1fs', duration)}) — open Walkthrough to replay\r\n")
          rec_control.call({ type: 'record', state: 'stopped', id: id, duration: duration.round(3) })
        else
          rec_control.call({ type: 'record', state: 'stopped', id: nil })
        end
      end
    end

    driver.on(:close) do |_|
      next if closed
      closed = true
      begin
        cleanup_env_files(env_token) if env_token
        # Finalize any in-flight recording before the PTY is torn down so the
        # cast is complete and closed even if the tab is simply closed.
        rec_stop.call
        unregister_session(node_name, session_info) if session_info && session_info[:id]
        pty_thread&.kill
        pty_write&.close rescue nil
        pty_read&.close  rescue nil
        if pty_pid
          begin
            Process.kill('TERM', -pty_pid) rescue nil
            sleep 0.1
            Process.kill('KILL', -pty_pid) rescue nil
          rescue Errno::ESRCH
          end
          begin
            Timeout.timeout(2) do
              loop do
                pid, _ = Process.waitpid2(pty_pid, Process::WNOHANG)
                break if pid
                sleep 0.05
              end
            end
          rescue Timeout::Error, Errno::ECHILD
          end
        end
      rescue => e
        puts "[Terminal Close Error] #{e.message}"
      ensure
        ssl_mutex.synchronize { io.close } rescue nil
      end
    end

    driver.start

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
end
