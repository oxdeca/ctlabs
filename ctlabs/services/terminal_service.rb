# -----------------------------------------------------------------------------
# File        : ctlabs/services/terminal_service.rb
# Description : Service for Web Terminal management and WebSocket logic
# License     : MIT License
# -----------------------------------------------------------------------------

require 'pty'
require 'json'
require 'timeout'
require 'securerandom'

class TerminalService
  @@sessions = {}
  @@mutex = Mutex.new
  @@session_ttl = 24 * 60 * 60

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

  def self.resolve_terminal_command(node_name, session)
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

    if Lab.running?
      runtime_path = Lab.get_file_path(Lab.current_name)
      if File.file?(runtime_path)
        begin
          lab = Lab.new(cfg: runtime_path, log: LabLog.null)
          if node = lab.find_node(node_name)
            node_type = node.type
            custom_term = node.term
            profile_user = sanitize_login_user(node.user)

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
      # playbook runs from), not $HOME. Other nodes keep root's default cwd.
      work_dir = nil
      if node_type == 'controller'
        workspace = Automation::ANSIBLE_DIR_CTL
        work_dir  = workspace if container_dir_exists?(engine, node_name, workspace)
      end
      work_dir ||= resolve_home_dir(engine, node_name, node_user) if node_user
      cmd.push('-w', work_dir) if work_dir
      cmd.push('-e', 'TERM=xterm-256color')

      if session[:vault_token] && session[:vault_addr] && node_type == 'controller'
        begin
          gcp_env = GcpAuth.env_vars(tf_cfg, { addr: session[:vault_addr], token: session[:vault_token] })
          gcp_env.each { |key, value| cmd.push('-e', "#{key}=#{value}") }
        rescue => e
          puts "[Terminal GCP Auto-Fetch Error] #{e.message}"
        end
      end
      cmd.push(node_name, 'bash')
    end
    cmd
  end

  def self.handle_websocket(driver, cmd, io, ssl_mutex, node_name = 'unknown', initial_cols: nil, initial_rows: nil)
    pty_read     = nil
    pty_write    = nil
    pty_pid      = nil
    pty_thread   = nil
    session_info = nil
    closed       = false

    driver.on(:open) do |_|
      begin
        available, info = register_if_available(node_name)
        unless available
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
                driver.text(utf8)
                utf8_buf.clear
              else
                # Genuinely invalid bytes -> scrub and emit; otherwise
                # an incomplete multibyte sequence is still pending.
                scrubbed = utf8.scrub('?')
                if scrubbed != utf8
                  driver.text(scrubbed)
                  utf8_buf.clear
                end
              end
            rescue IO::WaitReadable
              IO.select([pty_read], nil, nil, 0.1) rescue sleep(0.01)
              retry
            rescue EOFError, Errno::EIO, Errno::ECONNRESET, IOError
              remainder = utf8_buf.force_encoding('UTF-8')
              driver.text(remainder.scrub('?')) if remainder.bytesize > 0
              driver.text("\r\n\x1b[31m[Session closed by container]\x1b[0m\r\n") rescue nil
              break
            rescue StandardError => e
              puts "[PTY Error] #{e.message}"
              break
            end
          end
          driver.close rescue nil
        end
      rescue => e
        unregister_session(node_name, session_info) if session_info
        driver.text("\r\n\x1b[31m[Error spawning terminal: #{e.message}]\x1b[0m\r\n") rescue nil
        driver.close rescue nil
      end
    end

    driver.on(:message) do |event|
      if pty_write
        begin
          payload = JSON.parse(event.data)
          if payload['type'] == 'input'
            pty_write.write(payload['data'])
          elsif payload['type'] == 'resize'
            winsize = [payload['rows'].to_i, payload['cols'].to_i, 0, 0].pack('SSSS')
            pty_write.ioctl(0x5414, winsize) rescue nil
          end
        rescue JSON::ParserError
          pty_write.write(event.data)
        end
      end
    end

    driver.on(:close) do |_|
      next if closed
      closed = true
      begin
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
