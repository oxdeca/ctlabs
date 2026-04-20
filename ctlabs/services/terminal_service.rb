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
  @@sessions = Hash.new { |h, k| h[k] = [] }
  @@mutex = Mutex.new

  def self.register_session(node_name, session_info)
    @@mutex.synchronize { @@sessions[node_name] << session_info }
  end

  def self.unregister_session(node_name, session_info)
    @@mutex.synchronize { @@sessions[node_name].delete(session_info) }
  end

  def self.session_count(node_name)
    @@mutex.synchronize { @@sessions[node_name].size }
  end

  def self.terminate_oldest(node_name)
    session = nil
    @@mutex.synchronize { session = @@sessions[node_name].shift }
    if session
      begin
        session[:close_proc].call if session[:close_proc]
      rescue => e
        puts "[Terminal Termination Error] #{e.message}"
      end
      true
    else
      false
    end
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
    tf_vault_project = nil
    tf_vault_roleset = nil

    if Lab.running?
      runtime_path = Lab.get_file_path(Lab.current_name)
      if File.file?(runtime_path)
        begin
          lab = Lab.new(cfg: runtime_path, log: LabLog.null)
          if node = lab.find_node(node_name)
            node_type = node.type
            custom_term = node.term
            
            if (!custom_term || custom_term.empty?) && node.remote?
              ip_target = node.gw || node.ipv4 || (node.nics && node.nics.values.first)
              custom_term = "ssh://root@#{ip_target.split('/').first}" if ip_target
            end
            
            if node.terraform && node.terraform['vault']
              tf_vault_project = node.terraform['vault']['project']
              tf_vault_roleset = node.terraform['vault']['roleset']
            end
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
      cmd = [engine, 'exec', '-it', '-w', '/root', '-e', 'TERM=xterm-256color']

      if session[:vault_token] && session[:vault_addr] && node_type == 'controller'
        v_project = tf_vault_project.to_s.strip
        v_roleset = tf_vault_roleset.to_s.strip
        v_roleset = 'terraform-runner' if v_roleset.empty?

        if !v_project.empty?
          begin
            gcp_token = VaultAuth.get_gcp_token(session[:vault_addr], session[:vault_token], v_project, v_roleset)
            if gcp_token
              cmd.push('-e', "GOOGLE_OAUTH_ACCESS_TOKEN=#{gcp_token}")
              cmd.push('-e', "CLOUDSDK_AUTH_ACCESS_TOKEN=#{gcp_token}")
            end
          rescue => e
            puts "[Terminal GCP Auto-Fetch Error] #{e.message}"
          end
        end
      end
      cmd.push(node_name, 'bash')
    end
    cmd
  end

  def self.handle_websocket(driver, cmd, io, ssl_mutex, node_name = 'unknown', initial_cols: nil, initial_rows: nil)
    pty_read   = nil
    pty_write  = nil
    pty_pid    = nil
    pty_thread = nil
    session_info = nil

    driver.on(:open) do |_|
      if session_count(node_name) >= 3
        driver.text("\r\n\x1b[31m[Session Limit Reached: Max 3 terminal sessions per node]\x1b[0m\r\n")
        driver.close
        return
      end

      begin
        pty_read, pty_write, pty_pid = PTY.spawn(*cmd)
        
        # Apply initial terminal size if provided
        if initial_cols && initial_rows && pty_write
          winsize = [initial_rows.to_i, initial_cols.to_i, 0, 0].pack('SSSS')
          pty_write.ioctl(0x5414, winsize) rescue nil
        end
        
        session_info = {
          id: SecureRandom.uuid,
          node: node_name,
          close_proc: proc { driver.close rescue nil }
        }
        register_session(node_name, session_info)

        pty_thread = Thread.new do
          loop do
            begin
              data = pty_read.readpartial(8192)
              driver.text(data.force_encoding('UTF-8').scrub) 
            rescue IO::WaitReadable
              IO.select([pty_read], nil, nil, 0.1) rescue sleep(0.01)
              retry
            rescue EOFError, Errno::EIO, Errno::ECONNRESET, IOError
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
      unregister_session(node_name, session_info) if session_info
      pty_thread&.kill
      pty_write&.close
      pty_read&.close
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
      ssl_mutex.synchronize { io.close } rescue nil
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
            begin
              IO.select([io], nil, nil, 0.1)
            rescue
              sleep(0.01)
            end
            next
          elsif data.nil?
            break
          end
          driver.parse(data) if data && !data.empty?
        rescue IO::WaitReadable
          begin
            IO.select([io], nil, nil, 0.1)
          rescue
            sleep(0.01)
          end
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
