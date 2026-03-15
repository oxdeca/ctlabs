# -----------------------------------------------------------------------------
# File        : ctlabs/routes/terminal.rb
# License     : MIT License
# -----------------------------------------------------------------------------

# Web Terminal Endpoint
get '/terminal/:node_name' do
  if request.env['HTTP_UPGRADE']&.downcase == 'websocket'
    
    request.env['rack.hijack'].call
    io = request.env['rack.hijack_io']

    ssl_mutex = Mutex.new
    wrapper = WSSocketWrapper.new(request.env, io, ssl_mutex)
    driver = WebSocket::Driver.rack(wrapper)
    
    node_name = params[:node_name]
    
    if node_name == 'ctlabs_host'
      cmd = ['bash']
    else
      # 1. Smart Lookup: Check the active lab YAML for custom terminal configurations
      custom_term = nil
      if Lab.running?
        runtime_path = File.join(LOCK_DIR, "#{Lab.current_name.gsub('/', '_')}.yml")
        if File.file?(runtime_path)
          begin
            yaml = YAML.load_file(runtime_path)
            node_cfg = yaml.dig('topology', 0, 'nodes', node_name)
            
            if node_cfg
              custom_term = node_cfg['term']
              # Fallback for external nodes that might just have an ipv4 defined
              if (!custom_term || custom_term.empty?) && node_cfg['type'] == 'external' && node_cfg['ipv4']
                custom_term = "ssh://root@#{node_cfg['ipv4'].split('/').first}"
              end
            end
          rescue
            # Safely ignore YAML parsing errors and fallback to Docker
          end
        end
      end

      # 2. Command Router: Launch SSH or Docker based on the lookup
      if custom_term && custom_term.start_with?('ssh://')
        require 'uri'
        uri = URI.parse(custom_term)
        user = uri.user || 'root'
        host = uri.host
        cmd = ['ssh', '-o', 'StrictHostKeyChecking=no', "#{user}@#{host}"]
      else
        engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
        cmd = [engine, 'exec', '-it', '-e', 'TERM=xterm-256color', node_name, 'bash']
      end
    end
    
    pty_read   = nil
    pty_write  = nil
    pty_pid    = nil
    pty_thread = nil

    # 1. Connection Established
    driver.on(:open) do |event|
      begin
        # PTY.spawn returns [read_io, write_io, pid]
        pty_read, pty_write, pty_pid = PTY.spawn(*cmd)
        
        # WE DO NOT CLOSE pty_write HERE! That is our keyboard input!

        # PTY Read Loop
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

#    # 2. Keystrokes (Browser -> Container)
#    driver.on(:message) do |event|
#      # Write directly to the PTY write channel!
#      pty_write.write(event.data) if pty_write
#    end

    # 2. Keystrokes & Resize Events (Browser -> Container)
    driver.on(:message) do |event|
      if pty_write
        begin
          payload = JSON.parse(event.data)
          
          if payload['type'] == 'input'
            pty_write.write(payload['data'])
            
          elsif payload['type'] == 'resize'
            # Pack the rows and cols into a C-style struct (4 unsigned shorts)
            winsize = [payload['rows'].to_i, payload['cols'].to_i, 0, 0].pack('SSSS')
            # 0x5414 is the hex code for TIOCSWINSZ (Set Window Size) on Linux
            pty_write.ioctl(0x5414, winsize) rescue nil
          end
          
        rescue JSON::ParserError
          # Fallback just in case raw text gets sent
          pty_write.write(event.data)
        end
      end
    end

    # 3. Cleanup on Disconnect
    driver.on(:close) do |event|
      pty_thread&.kill
      pty_read&.close
      pty_write&.close
      Process.kill('TERM', pty_pid) rescue nil if pty_pid
      ssl_mutex.synchronize { io.close } rescue nil
    end

    # 4. START HANDSHAKE
    driver.start

    # 5. Thread-Safe Socket Read Loop (Browser -> Parser)
    Thread.new do
      loop do
        begin
          data = nil
          ssl_mutex.synchronize do
            data = io.read_nonblock(8192)
          end
          
          if data == :wait_readable || data == :wait_writable
            sleep(0.01)
            next
          end
          
          driver.parse(data) if data && !data.empty?

        rescue IO::WaitReadable
          sleep(0.01)
          retry
        rescue EOFError, Errno::ECONNRESET, IOError, OpenSSL::SSL::SSLError
          break
        rescue StandardError => e
          puts "[Socket Read Error] #{e.class}: #{e.message}"
          break
        end
      end
      driver.close rescue nil
    end

    return [-1, {}, []]
  else
    # Standard HTML Page
    @node_name = params[:node_name]
    erb :terminal, layout: false
  end
end