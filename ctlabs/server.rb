#!/usr/bin/env ruby

# -----------------------------------------------------------------------------
# File        : ctlabs/server.rb
# Description : ctlabs main script
# License     : MIT License
# -----------------------------------------------------------------------------

#require 'kramdown'
#require 'kramdown-parser-gfm'
require 'fileutils'
#require 'webrick'
require 'openssl'
require 'sinatra'
require 'erb'
require 'net/http'
require 'shellwords'
require 'set'
require 'securerandom'
require 'websocket/driver'
require 'pty'
require 'json'

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), 'lib')
require 'lab'
require 'node'
require 'link'
require 'graph'
require 'lablog'

require_relative 'helpers/application_helper'

class WSSocketWrapper
  attr_reader :env
  def initialize(env, io, mutex)
    @env = env
    @io = io
    @mutex = mutex
  end
  def url
    scheme = @env['rack.url_scheme'] == 'https' ? 'wss' : 'ws'
    "#{scheme}://#{@env['HTTP_HOST']}#{@env['REQUEST_URI']}"
  end
  def write(data)
    # Safely lock the SSL socket before writing!
    @mutex.synchronize { @io.write(data) } rescue nil
  end
end

# sinatra settings
disable :logging
enable  :sessions
set     :server,            'webrick'
set     :session_secret,     SecureRandom.hex(64)
set     :bind,              '0.0.0.0'
set     :port,               4567
set     :public_folder,     '/srv/ctlabs-server/public'
set     :host_authorization, permitted_hosts: []
set     :markdown,           input: 'GFM'

disable :run

#set     :server_settings,    SSLEnable: true,
#                             SSLVerifyClient: OpenSSL::SSL::VERIFY_NONE,
#                             SSLCertName:     [[ 'CN', WEBrick::Utils.getservername ]]
#set     :server_settings,    SSLEnable: true,
#                             SSLVerifyClient: OpenSSL::SSL::VERIFY_NONE,
#                             SSLCertificate: CERT_PATH,
#                             SSLPrivateKey: KEY_PATH


CONFIG        = '/srv/ctlabs-server/public/config.yml'
INVENTORY     = '/srv/ctlabs-server/public/inventory.ini'
UPLOAD_DIR    = '/srv/ctlabs-server/uploads'
SCRIPT_DIR    = File.dirname(File.expand_path(__FILE__))
LABS_DIR      = "#{SCRIPT_DIR}/../labs"
CTLABS_SCRIPT = './ctlabs.rb'
LOCK_DIR      = '/var/run/ctlabs'
LOCK_FILE     = "#{LOCK_DIR}/running_lab"
LOG_DIR       = '/var/log/ctlabs'
Dir.mkdir(LOG_DIR,    0755) unless Dir.exists?(LOG_DIR)
Dir.mkdir(LOCK_DIR,   0755) unless Dir.exists?(LOCK_DIR)
Dir.mkdir(UPLOAD_DIR, 0755) unless Dir.exist?(UPLOAD_DIR)


# add basic authentication
use Rack::Auth::Basic, 'Restricted Area' do |user, pass|
  salt = "GGV78Ib5vVRkTc"
  user == 'ctlabs' && pass.crypt("$6$#{salt}$") == "$6$GGV78Ib5vVRkTc$cRAo9wl36SQPkh/UFzgEIOO1rBuju7/h5Lu8fJMDUNDG0HUcL3AhBNEqcYT1UUZkmBHa9.8r/5eh5qXwA8zcr."
end

helpers ApplicationHelper

# ------------------------------------------------------------------------------
# ROUTES
# ------------------------------------------------------------------------------
get "/" do
  #ERB.new(home).result(binding)
  #erb :home
  redirect('/labs')
end

get '/upload' do
  erb :upload
end

get '/con' do
  erb :con
end

get '/topo' do
  erb :topo
end

get '/inventory' do
  erb :inventory
end

get '/config' do
  @running_lab = Lab.running? ? Lab.current_name : nil
  
  if @running_lab
    runtime_path = "#{LOCK_DIR}/#{@running_lab.gsub('/', '_')}.yml"
    @active_yaml = File.file?(runtime_path) ? File.read(runtime_path) : nil
  end
  erb :config
end

# Web Terminal Endpoint
get '/terminal/:node_name' do
  if request.env['HTTP_UPGRADE']&.downcase == 'websocket'
    
    request.env['rack.hijack'].call
    io = request.env['rack.hijack_io']

    ssl_mutex = Mutex.new
    wrapper = WSSocketWrapper.new(request.env, io, ssl_mutex)
    driver = WebSocket::Driver.rack(wrapper)
    
    node_name = params[:node_name]
    engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
    cmd = [engine, 'exec', '-it', '-e', 'TERM=xterm-256color', node_name, 'bash']

    pty_read = nil
    pty_write = nil
    pty_pid = nil
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

#
# IMAGES
#
# Fetch a Dockerfile
get '/images/dockerfile' do
  content_type :json
  image = params[:image].split(':').first # Drop the tag
  # e.g., 'ctlabs/c8/base' -> ['c8', 'base'] -> 'c8/base'
  search_path = image.split('/').last(2).join('/')
  
  # Search the images directory
  dockerfile_path = Dir.glob(File.join("..", "images", "**", search_path, "Dockerfile")).first

  if dockerfile_path && File.exist?(dockerfile_path)
    { dockerfile: File.read(dockerfile_path) }.to_json
  else
    status 404
    { error: "Dockerfile not found for #{image}" }.to_json
  end
end

# Save Dockerfile WITHOUT triggering build
post '/images/save' do
  content_type :json
  image = params[:image].split(':').first
  search_path = image.split('/').last(2).join('/')
  dockerfile_path = Dir.glob(File.join("..", "images", "**", search_path, "Dockerfile")).first

  if dockerfile_path
    File.write(dockerfile_path, params[:dockerfile])
    { message: "Dockerfile saved" }.to_json
  else
    status 404
    { error: "Dockerfile path not found" }.to_json
  end
end

# Save and trigger build
post '/images/build' do
  content_type :json
  require 'fileutils'

  image = params[:image].split(':').first
  search_path = image.split('/').last(2).join('/')
  dockerfile_path = Dir.glob(File.join("..", "images", "**", search_path, "Dockerfile")).first

  if dockerfile_path
    # ONLY overwrite the file if the UI actually sent text (so Quick Build works safely!)
    if params[:dockerfile] && !params[:dockerfile].to_s.strip.empty?
      File.write(dockerfile_path, params[:dockerfile])
    end
    build_script = File.join(File.dirname(dockerfile_path), 'build.sh')
    
    if File.exist?(build_script)
      log_dir = defined?(LOG_DIR) ? LOG_DIR : '/var/log/ctlabs'
      FileUtils.mkdir_p(log_dir)
      
      safe_img_name = image.gsub('/', '_').gsub(/[^0-9a-zA-Z_]/, '')
      log_file_name = "build_#{safe_img_name}_#{Time.now.to_i}.log"
      
      # The absolute path for the spawn command
      log_file = File.join(log_dir, log_file_name)
      FileUtils.touch(log_file)
      
      # Trigger in background
      spawn("cd #{File.dirname(build_script)} && bash build.sh > #{log_file} 2>&1")
      
      # FIX: Pass the absolute path (log_file) back to the frontend so the log viewer can find it!
      { message: "Build triggered", log_path: log_file }.to_json
    else
      status 400
      { error: "build.sh not found in directory" }.to_json
    end
  else
    status 404
    { error: "Dockerfile path not found" }.to_json
  end
end

# Create a new Image Directory Structure
post '/images/create' do
  content_type :json
  require 'fileutils'
  
  # Clean input to prevent path traversal
  path = params[:image_path].to_s.gsub(/[^a-zA-Z0-9_\-\/]/, '')
  full_dir = File.join("..", "images", path)
  
  if File.directory?(full_dir)
    status 400
    return { error: "Directory already exists" }.to_json
  end

  # Build the skeleton
  FileUtils.mkdir_p(full_dir)
  File.write(File.join(full_dir, "Dockerfile"), "FROM ubuntu:latest\n# Add your instructions here\n")
  
  build_sh = File.join(full_dir, "build.sh")
  File.write(build_sh, "#!/bin/bash\n# Replace with podman/docker build command\necho 'Build script for #{path}'\n")
  FileUtils.chmod(0755, build_sh) # Make executable

  { message: "Created successfully" }.to_json
end

# Delete an Image Directory Structure
post '/images/delete' do
  content_type :json
  require 'fileutils'
  
  # Clean input
  image = params[:image].to_s.gsub(/[^a-zA-Z0-9_\-\/]/, '')
  full_dir = File.join("..", "images", image)

  # Security check to ensure it stays inside the images folder
  if File.directory?(full_dir) && full_dir.include?("../images/")
    FileUtils.rm_rf(full_dir)
    { message: "Deleted successfully" }.to_json
  else
    status 404
    { error: "Image directory not found" }.to_json
  end
end


#
# LABS
#

# Download the active runtime YAML configuration
get '/labs/download' do
  lab_name = params[:lab]
  
  # Try to grab the active runtime file first
  runtime_path = File.join(LOCK_DIR, "#{lab_name.gsub('/', '_')}.yml")
  
  # Fallback to the base lab file if it's not currently running
  file_path = File.file?(runtime_path) ? runtime_path : File.join(LABS_DIR, lab_name)

  if File.file?(file_path)
    # Send the file as a downloadable attachment
    send_file file_path, :filename => "custom_#{File.basename(lab_name)}", :type => 'application/x-yaml'
  else
    halt 404, "Configuration file not found."
  end
end

get '/demo' do
  erb :demo
end

get '/flashcards' do
  @read_only = Lab.running?
  erb :flashcards
end

# Save flashcards (Blocked if Lab is Running)
post '/flashcards/data' do
  content_type :json
  
  # Security: Block saves if Lab is running
  if Lab.running?
     status 403
     return { success: false, error: 'Read-Only Mode: Cannot save while Lab is running.' }.to_json
  end
  
  begin
    data        = JSON.parse(request.body.read)
    public_file = '/srv/ctlabs-server/public/flashcards.json'
    
    if !data['set'] || !data['set']['cards'] || data['set']['cards'].empty?
      status 400
      { success: false, error: 'Cannot save empty flashcard set' }.to_json
    else
      File.write(public_file, JSON.pretty_generate(data))
      { success: true }.to_json
    end
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

get '/markdown' do
  erb :markdown
end

post '/upload' do
  uploaded_file = params[:file]
  return halt erb(:upload), BADREQ unless uploaded_file

  filename = uploaded_file[:tempfile].path

  puts "File received: #{filename}\nContents: #{File.read(filename).unpack("H*")}"
  if File.zero?(filename)
    puts "Error: The file is empty"
    return halt erb(:upload), BADREQ
  end

  FileUtils.cp(filename, UPLOAD_DIR + '/' + uploaded_file[:filename] )
  #File.rename(filename, UPLOAD_DIR + '/' + uploaded_file[:filename] )
  #File.unlink(filename)

  redirect '/upload'
end

get '/labs' do
  @labs = all_labs
  @selected_lab = get_running_lab || session[:selected_lab] || (@labs.first if @labs.any?)
  session[:adhoc_dnat_rules] ||= {}

  # (DELETED THE @lab_info = parse_lab_info(...) BLOCK ENTIRELY)

  # In /labs route
  running = get_running_lab
  if running && @selected_lab == running
    # Load from disk and update session for consistency
    lab_name_safe = running.gsub(/\//, '_').gsub(/[^a-zA-Z0-9_.\-]/, '')
    adhoc_file = "#{LOCK_DIR}/adhoc_dnat_#{lab_name_safe}.json"
    if File.file?(adhoc_file)
      session[:adhoc_dnat_rules] ||= {}
      session[:adhoc_dnat_rules][running] = JSON.parse(File.read(adhoc_file), :symbolize_names => true)
    end
  end

  erb :labs
end

# Helper to resolve lab file path
def get_lab_file_path(lab_name)
  runtime_path = "#{LOCK_DIR}/#{lab_name.gsub('/', '_')}.yml"
  (Lab.running? && Lab.current_name == lab_name && File.file?(runtime_path)) ? runtime_path : File.join(LABS_DIR, lab_name)
end

# Helper to format nested YAML arrays strictly inline (cleaner readability)
def write_formatted_yaml(path, data)
  yaml_str = data.to_yaml
  
  # Clean up psych array formatting for nested 2-element or 3-element arrays
  yaml_str.gsub!(/^(\s*)-\s*-\s*(.+?)\n\1\s{2}-\s*(.+?)\n(?:\1\s{2}-\s*(.+?)\n)?/) do |match|
    indent = $1
    v1, v2, v3 = $2.strip, $3.strip, $4&.strip

    # Remove surrounding quotes if psych added them
    v1 = v1[1..-2] if v1.start_with?('"') && v1.end_with?('"') || v1.start_with?("'") && v1.end_with?("'")
    v2 = v2[1..-2] if v2.start_with?('"') && v2.end_with?('"') || v2.start_with?("'") && v2.end_with?("'")
    v3 = v3[1..-2] if v3 && (v3.start_with?('"') && v3.end_with?('"') || v3.start_with?("'") && v3.end_with?("'"))

    # Re-quote if it looks like an interface string
    v1 = "\"#{v1}\"" if v1.match?(/[a-zA-Z]+.*:/)
    v2 = "\"#{v2}\"" if v2.match?(/[a-zA-Z]+.*:/)
    
    if v3
      v3 = "\"#{v3}\"" if v3.match?(/[a-zA-Z]+.*:/)
      "#{indent}- [ #{v1}, #{v2}, #{v3} ]\n"
    else
      "#{indent}- [ #{v1}, #{v2} ]\n"
    end
  end
  
  # Remove empty 'nics: {}' if it was stripped down to nothing
  yaml_str.gsub!(/\n\s*nics:\s*\{\}/, '')

  File.write(path, yaml_str)
end

# ---------------------------------------------------
# DNAT
# ---------------------------------------------------
post '/labs/*/dnat' do
  lab_name = params[:splat].first
  halt 400, "AdHoc DNAT only allowed on the running lab" unless get_running_lab == lab_name

  begin
    lab_path = get_lab_file_path(lab_name)
    lab = Lab.new(cfg: lab_path)
    rule = lab.add_adhoc_dnat(params[:node], params[:external_port].to_i, params[:internal_port].to_i, (params[:protocol] || 'tcp').downcase)

    # Append to runtime YAML
    data = YAML.load_file(lab_path)
    data['topology'][0]['nodes'][params[:node]]['dnat'] ||= []
    data['topology'][0]['nodes'][params[:node]]['dnat'] << [params[:external_port].to_i, params[:internal_port].to_i, (params[:protocol] || 'tcp').downcase]
    
    # Save beautifully formatted YAML
    write_formatted_yaml(lab_path, data)

    content_type :json
    { success: true, message: "AdHoc DNAT rule added" }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# Delete a DNAT Rule
post '/labs/*/dnat/delete' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    node = params[:node]
    dnat_rules = yaml['topology'][0]['nodes'][node]['dnat'] rescue nil
    
    if dnat_rules
      dnat_rules.reject! do |r| 
        r[0].to_s == params[:ext].to_s && r[1].to_s == params[:int].to_s && (r[2] || 'tcp').to_s == params[:proto].to_s
      end
      yaml['topology'][0]['nodes'][node].delete('dnat') if dnat_rules.empty?
      write_formatted_yaml(lab_path, yaml)
    end
    { success: true, message: "DNAT rule deleted." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# ---------------------------------------------------
# NODES
# ---------------------------------------------------

# Add a New Node to the Base YAML
post '/labs/*/node/new' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path) || {}
    node_name = params[:node_name].strip
    
    raise "Node name is required." if node_name.empty?
    
    # Bulletproof YAML path generation
    yaml['topology'] ||= [{}]
    yaml['topology'][0] ||= {}
    yaml['topology'][0]['nodes'] ||= {}
    
    raise "Node '#{node_name}' already exists!" if yaml['topology'][0]['nodes'].key?(node_name)

    yaml['topology'][0]['nodes'][node_name] = {
      'type' => params[:type],
      'kind' => params[:kind]
    }
    write_formatted_yaml(lab_path, yaml)
    { success: true, message: "Node '#{node_name}' added to base configuration." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

post '/labs/*/node' do
  lab_name = params[:splat].first
  halt 400, "AdHoc Nodes only allowed on the running lab" unless get_running_lab == lab_name
  node_name = params[:node_name]

  node_cfg = { 'type' => params[:type] || 'host', 'kind' => params[:kind] || 'linux' }
  node_cfg['gw'] = params[:gw].strip if params[:gw] && !params[:gw].strip.empty?
  node_cfg['nics'] = { 'eth1' => params[:ip].strip } if params[:ip] && !params[:ip].strip.empty?

  begin
    lab_path = get_lab_file_path(lab_name)
    lab = Lab.new(cfg: lab_path)
    
    # Start node and get config/links
    cfg_out, data_link = lab.add_adhoc_node(node_name, node_cfg, params[:switch])

    # Append to runtime YAML
    data = YAML.load_file(lab_path)
    data['topology'][0]['nodes'][node_name] = cfg_out
    
    data['topology'][0]['links'] ||= []
    if data_link
      data['topology'][0]['links'] << data_link
      
      # Auto-expand switch port capacity if necessary
      sw_name = params[:switch].strip
      sw_port = data_link[0].split(':eth').last.to_i
      sw_node = data['topology'][0]['nodes'][sw_name]
      if sw_node
        current_ports = sw_node['ports'] || 4 
        if sw_port > current_ports
          sw_node['ports'] = sw_port
        end
      end
    end
    
    write_formatted_yaml(lab_path, data)
    
    content_type :json
    { success: true, message: "AdHoc Node '#{node_name}' started" }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

get '/labs/*/node/:node_name' do
  lab_name = params[:splat].first
  node_name = params[:node_name]
  lab_path = get_lab_file_path(lab_name)

  node_cfg = nil
  if File.file?(lab_path)
    data = YAML.load_file(lab_path)
    node_cfg = data['topology'][0]['nodes'][node_name] if data['topology'] && data['topology'][0]
  end

  node_cfg ||= { 'type' => 'host', 'kind' => 'linux', 'gw' => '', 'nics' => { 'eth1' => '' } }
  
  yaml_str = node_cfg.to_yaml
  yaml_str = yaml_str.gsub(/^(\s*)- -\s*(.+?)\n\1  -\s*(.+?)\n\1  -\s*(.+?)\n/) { "#{$1}- [#{$2}, #{$3}, #{$4}]\n" }
  yaml_str = yaml_str.gsub(/^(\s*)- -\s*(.+?)\n\1  -\s*(.+?)\n/) { "#{$1}- [#{$2}, #{$3}]\n" }

  content_type :json
  { yaml: yaml_str, json: node_cfg }.to_json
end

post '/labs/*/node/:node_name/edit' do
  lab_name = params[:splat].first
  node_name = params[:node_name]
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path)
    base_data = full_yaml['topology'][0]['nodes'][node_name] || {}

    if params[:format] == 'form'
      new_cfg = base_data.dup
      new_cfg['type'] = params[:type] unless params[:type].to_s.empty?
      params[:kind].to_s.empty? ? new_cfg.delete('kind') : new_cfg['kind'] = params[:kind]
      params[:gw].to_s.empty? ? new_cfg.delete('gw') : new_cfg['gw'] = params[:gw]
      
      # NEW: Process the Info field
      params[:info].to_s.empty? ? new_cfg.delete('info') : new_cfg['info'] = params[:info]
      params[:term].to_s.empty? ? new_cfg.delete('term') : new_cfg['term'] = params[:term]

      if params[:nics] && !params[:nics].strip.empty?
        new_cfg['nics'] = params[:nics].split("\n").map { |l| l.split('=').map(&:strip) }.to_h.reject { |k,v| k.nil? || v.nil? }
      else
        new_cfg.delete('nics')
      end

      # NEW: Process the Custom URLs Textarea
      if params[:urls_text] && !params[:urls_text].strip.empty?
        urls_hash = {}
        params[:urls_text].split("\n").each do |line|
          title, link = line.split('|', 2)
          # Only add if both a title and a link exist on the line
          if title && !title.strip.empty? && link && !link.strip.empty?
            urls_hash[title.strip] = link.strip 
          end
        end
        new_cfg['urls'] = urls_hash unless urls_hash.empty?
      else
        new_cfg.delete('urls')
      end

    else
      new_cfg = YAML.safe_load(params[:yaml_data])
    end

    full_yaml['topology'][0]['nodes'][node_name] = new_cfg
    write_formatted_yaml(lab_path, full_yaml)

    content_type :json
    { success: true, message: "Node configuration saved." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# Delete a Node, Stop the Container, and Clean up Dangling Links
post '/labs/*/node/:node_name/delete' do
  lab_name = params[:splat].first
  node_name = params[:node_name]
  lab_path = get_lab_file_path(lab_name)
  
  begin
    # 1. Stop the live container if the lab is running
    if Lab.running? && Lab.current_name == lab_name
      lab = Lab.new(cfg: lab_path, log: LabLog.null)
      target_node = lab.find_node(node_name)
      target_node.stop if target_node
    end

    # 2. Remove the node from the YAML
    yaml = YAML.load_file(lab_path)
    yaml['topology'][0]['nodes'].delete(node_name)

    # 3. SCRUB ORPHANED LINKS: Remove any links connected to this node!
    yaml['topology'][0]['links']&.reject! do |l|
      l.is_a?(Array) && (l[0].start_with?("#{node_name}:") || l[1].start_with?("#{node_name}:"))
    end

    # 4. Save the file (This updates the timestamp, which triggers the visual Smart Cache on reload!)
    write_formatted_yaml(lab_path, yaml)
    
    { success: true, message: "Node deleted and orphaned links removed." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# ---------------------------------------------------
# LINKS
# ---------------------------------------------------
# Add or Edit a Network Link
post '/labs/*/link/save' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    yaml['topology'][0]['links'] ||= []

    ep1 = "#{params[:node_a]}:#{params[:int_a]}"
    ep2 = "#{params[:node_b]}:#{params[:int_b]}"
    
    # Native Format: ["h1:eth1", "sw1:eth1"]
    new_link = [ep1, ep2]

    if params[:old_ep1] && params[:old_ep2] && !params[:old_ep1].empty?
      # Update Existing Link
      idx = yaml['topology'][0]['links'].find_index do |l|
        l.is_a?(Array) && l.include?(params[:old_ep1]) && l.include?(params[:old_ep2])
      end
      idx ? (yaml['topology'][0]['links'][idx] = new_link) : (yaml['topology'][0]['links'] << new_link)
    else
      # Add New Link
      yaml['topology'][0]['links'] << new_link
    end

    write_formatted_yaml(lab_path, yaml)
    { success: true, message: "Link saved successfully." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# Delete a Network Link
post '/labs/*/link/delete' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    yaml['topology'][0]['links']&.reject! do |l|
      l.is_a?(Array) && l.include?(params[:ep1]) && l.include?(params[:ep2])
    end
    write_formatted_yaml(lab_path, yaml)
    { success: true, message: "Link deleted." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# ---------------------------------------------------
# ANSIBLE
# ---------------------------------------------------
# Edit Ansible Playbook Configuration
post '/labs/*/ansible/edit' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path)
    
    # Locate the ansible controller node
    ansible_node_name = full_yaml['topology'][0]['nodes'].keys.find { |k| k == 'ansible' || full_yaml['topology'][0]['nodes'][k]['type'] == 'controller' }
    raise "No ansible controller node found in topology" unless ansible_node_name
    
    base_data = full_yaml['topology'][0]['nodes'][ansible_node_name] || {}
    
    # Initialize or reset the play configuration
    play_cfg = base_data['play'] || {}
    play_cfg = {} if play_cfg.is_a?(String) # Convert raw strings to hashes
    
    # 1. Update Playbook
    params[:book].to_s.strip.empty? ? play_cfg.delete('book') : play_cfg['book'] = params[:book].strip
    
    # 2. Update Environment Variables
    if params[:env] && !params[:env].strip.empty?
      play_cfg['env'] = params[:env].split("\n").map(&:strip).reject(&:empty?)
    else
      play_cfg.delete('env')
    end
    
    # 3. Update Tags
    if params[:tags] && !params[:tags].strip.empty?
      play_cfg['tags'] = params[:tags].split(",").map(&:strip).reject(&:empty?)
    else
      play_cfg.delete('tags')
    end

    # Save it back
    base_data['play'] = play_cfg
    full_yaml['topology'][0]['nodes'][ansible_node_name] = base_data
    write_formatted_yaml(lab_path, full_yaml)

    content_type :json
    { success: true, message: "Ansible configuration updated." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

post '/labs/*/playbook' do
  lab_name = params[:splat].first
  halt 400, { error: "No lab is running" }.to_json unless get_running_lab == lab_name
  halt 400, { error: "Playbook running!" }.to_json if Lab.playbook_running?(lab_name)

  log_path = LabLog.latest_for_running_lab
  Thread.new do
    begin
      lab_instance = Lab.new(cfg: get_lab_file_path(lab_name), relative_path: lab_name)
      File.open(log_path, 'a') { |f| f.puts "\n--- Manual Ansible playbook run triggered ---\n" }
      lab_instance.run_playbook(nil, log_path)
    rescue => e
      File.open(log_path, 'a') { |f| f.puts "\n⚠️ Playbook failed: #{e.message}\n" }
    end
  end
  content_type :json
  { success: true }.to_json
end

# ---------------------------------------------------
# IMAGES
# ---------------------------------------------------
# Add or Edit a Defined Image
post '/labs/*/image/edit' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path) || {}
    full_yaml['defaults'] ||= {}
    
    type = params[:type].to_s.strip
    kind = params[:kind].to_s.strip
    
    raise "Type and Kind are required." if type.empty? || kind.empty?

    full_yaml['defaults'][type] ||= {}
    img_cfg = full_yaml['defaults'][type][kind] || {}
    
    img_cfg['image'] = params[:image].strip unless params[:image].to_s.strip.empty?

    # Parse capabilities
    params[:caps].to_s.strip.empty? ? img_cfg.delete('caps') : img_cfg['caps'] = params[:caps].split(',').map(&:strip)
    
    # Parse environment variables
    if params[:env] && !params[:env].strip.empty?
      img_cfg['env'] = params[:env].split("\n").map(&:strip).reject(&:empty?)
    else
      img_cfg.delete('env')
    end

    # Process Extra Arbitrary Attributes (ports, privileged, etc.)
    # 1. Clean out old extra keys first
    core_keys = ['image', 'caps', 'env']
    img_cfg.keys.each { |k| img_cfg.delete(k) unless core_keys.include?(k) }
    
    # 2. Safely merge the new ones
    if params[:extra_attrs] && !params[:extra_attrs].strip.empty?
      parsed_extras = YAML.safe_load(params[:extra_attrs])
      img_cfg.merge!(parsed_extras) if parsed_extras.is_a?(Hash)
    end

    full_yaml['defaults'][type][kind] = img_cfg
    write_formatted_yaml(lab_path, full_yaml)

    content_type :json
    { success: true, message: "Image configuration saved." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# Delete an Image
post '/labs/*/image/:type/:kind/delete' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    yaml['defaults'][params[:type]].delete(params[:kind]) rescue nil
    yaml['defaults'].delete(params[:type]) if yaml['defaults'][params[:type]]&.empty?
    write_formatted_yaml(lab_path, yaml)
    { success: true, message: "Image deleted." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# ---------------------------------------------------
# LABS
# ---------------------------------------------------

# Create a Brand New Lab YAML with the Default Base Environment
post '/labs/new' do
  lab_name = params[:lab_name].to_s.strip.gsub(/[^a-zA-Z0-9_\-\/]/, '') # sanitize
  desc = params[:desc].to_s.strip
  
  lab_name += '.yml' unless lab_name.end_with?('.yml')
  lab_path = File.join(LABS_DIR, lab_name)

  if File.exist?(lab_path)
    halt 400, "A lab with that filename already exists!"
  end

  FileUtils.mkdir_p(File.dirname(lab_path))
  
  # Base name without the .yml extension
  base_name = File.basename(lab_name, '.yml')

  # Use a Heredoc to perfectly preserve spacing, alignment, and arrays!
  default_yaml = <<~YAML
    # -----------------------------------------------------------------------------
    # File        : ctlabs/labs/#{lab_name}
    # Description : #{desc}
    # -----------------------------------------------------------------------------

    name: #{base_name}
    desc: #{desc}

    defaults:
      controller:
        linux:
          image: ctlabs/c9/ctrl
      switch:
        mgmt:
          image: ctlabs/c9/ctrl
          ports: 16
        linux:
          image: ctlabs/c9/base
          ports: 6
      host:
        linux:
          image: ctlabs/c9/base
        db2:
          image: ctlabs/misc/db2
          caps: [SYS_NICE,IPC_LOCK,IPC_OWNER]
        cbeaver:
          image: ctlabs/misc/cbeaver
        d12:
          image: ctlabs/d12/base
        kali:
          image: ctlabs/kali/base
        parrot:
          image: ctlabs/parrot/base
        slapd:
          image: ctlabs/d12/base
          caps: [SYS_PTRACE]
      router:
        frr:
          image: ctlabs/c9/frr
          caps : [SYS_NICE,NET_BIND_SERVICE]
        mgmt:
          image: ctlabs/c9/frr
          caps : [SYS_NICE,NET_BIND_SERVICE]

    topology:
      - name: #{base_name}-vm1
        dns : [192.168.10.11, 192.168.10.12, 8.8.8.8]
        mgmt:
          vrfid : 99
          dns   : [1.1.1.1, 8.8.8.8]
          net   : 192.168.99.0/24
          gw    : 192.168.99.1
        nodes:
          ansible :
            type : controller
            gw   : 192.168.99.1
            nics :
              eth0: 192.168.99.3/24
            vols : ['/root/ctlabs-ansible/:/root/ctlabs-ansible/:Z,rw', '/srv/jupyter/ansible/:/srv/jupyter/work/:Z,rw']
            play: 
              book: ctlabs.yml
              tags: [up, setup, ca, bind, jupyter, smbadc, slapd, sssd]
            dnat :
              - [9988, 8888]
          sw0:
            type  : switch
            kind  : mgmt
            ipv4  : 192.168.99.11/24
            gw    : 192.168.99.1
          ro0:
            type : router
            kind : mgmt
            gw   : 192.168.15.1
            nics :
              eth0: 192.168.99.1/24
              eth1: 192.168.15.2/29
          natgw:
            type : gateway
            ipv4 : 192.168.15.1/29
            snat : true
            dnat : ro1:eth1
          sw1:
            type : switch
          sw2:
            type : switch
          sw3:
            type : switch
          ro1:
            type : router
            kind : frr
            gw   : 192.168.15.1
            nics :
              eth1: 192.168.15.3/29
              eth2: 192.168.10.1/24
              eth3: 192.168.20.1/24
              eth4: 192.168.30.1/24
        links: []
  YAML

  File.write(lab_path, default_yaml)
  redirect '/labs' # Refresh the page to show the new lab in the dropdown
end

# Save Current Lab (Base or Runtime) as a New File
post '/labs/*/save_as' do
  lab_name = params[:splat].first
  new_lab_name = params[:new_lab_name].to_s.strip.gsub(/[^a-zA-Z0-9_\-\/]/, '')
  new_desc = params[:new_desc].to_s.strip
  
  halt 400, { success: false, error: "New lab name is required" }.to_json if new_lab_name.empty?
  
  new_lab_name += '.yml' unless new_lab_name.end_with?('.yml')
  new_lab_path = File.join(LABS_DIR, new_lab_name)
  
  if File.exist?(new_lab_path)
    halt 400, { success: false, error: "A lab with that filename already exists!" }.to_json
  end
  
  begin
    # get_lab_file_path automatically grabs the runtime lock file if the lab is currently running!
    source_path = get_lab_file_path(lab_name)
    yaml = YAML.load_file(source_path) || {}
    
    # Update the internal metadata for the new lab
    base_name = File.basename(new_lab_name, '.yml')
    yaml['name'] = base_name
    yaml['desc'] = new_desc unless new_desc.empty?
    
    # Ensure the target directory exists (e.g. custom/my_new_lab.yml)
    FileUtils.mkdir_p(File.dirname(new_lab_path))
    
    write_formatted_yaml(new_lab_path, yaml)
    
    { success: true, message: "Lab saved as #{new_lab_name}", new_lab: new_lab_name }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

post '/labs/execute' do
  action = params[:action]
  halt 400, "Invalid action" unless %w[up down].include?(action)

  if action == 'up'
    lab_name = params[:lab_name]
    labs_list = all_labs
    halt 400, "Invalid lab" unless lab_name && labs_list.include?(lab_name)
    if Lab.running?
      halt 400, "A lab is already running: #{Lab.current_name}. Stop it first."
    end
  else # down
    unless Lab.running?
      halt 400, "No lab is currently running."
    end
    lab_name = Lab.current_name
    labs_list = all_labs
    halt 500, "Running lab not found" unless labs_list.include?(lab_name)
  end

  source_path = File.join(LABS_DIR, lab_name)
  runtime_path = "#{LOCK_DIR}/#{lab_name.gsub('/', '_')}.yml"
  log = LabLog.for_lab(lab_name: lab_name, action: action)

  Thread.new do
    begin
      if action == 'up'
        FileUtils.cp(source_path, runtime_path)
        lab_instance = Lab.new(cfg: runtime_path, relative_path: lab_name, log: log)
        lab_instance.up
        log.info "--- Lab #{lab_name} UP completed ---"

        # ✅ RUN PLAYBOOK ONCE with built-in concurrency protection
        begin
          lab_instance.run_playbook(nil, log.path)
          log.info "--- Ansible playbook completed ---"
        rescue => e
          log.info "⚠️  Playbook failed but lab is running: #{e.message}"
        end
      else
        lab_instance = Lab.new(cfg: runtime_path, relative_path: lab_name, log: log)
        lab_instance.down
        log.info "--- Lab #{lab_name} DOWN completed ---"
        FileUtils.rm_f(runtime_path)
      end
      
      log.info "--- Operation finished ---"
      log.close
      
    rescue => e
      log.info "ERROR: #{e.message}"
      log.info e.backtrace.join("\n")
      log.close
    end
  end
  
  redirect "/logs?file=#{URI.encode_www_form_component(log.path)}"
end

post '/labs/action' do
  @labs = all_labs
  lab_name = params[:lab_name]
  action   = params[:action]

  unless lab_name && @labs.include?(lab_name)
    halt 400, "Invalid lab"
  end

  session[:selected_lab] = lab_name

  lab_path = File.join(LABS_DIR, lab_name)
  cmd = case action
        when 'start'
          "cd #{SCRIPT_DIR} && #{CTLABS_SCRIPT} -c #{lab_path.shellescape} -up"
        when 'stop'
          "cd #{SCRIPT_DIR} && #{CTLABS_SCRIPT} -c #{lab_path.shellescape} -d"
        else
          halt 400, "Unknown action"
        end

  @output = `#{cmd} 2>&1`
  @success = $?.success?
  @selected_lab = lab_name

  erb :lab_action_result
end

# Add this route *before* the main routes, and importantly, BEFORE the '/labs/*/info' route
get '/labs/*/info_card' do # <-- NEW: Wildcard for info_card
  content_type 'text/html' # Return HTML fragment

  # params[:splat] is an Array containing the matched '*' part(s).
  # For the URL /labs/lpic2/lpic210.yml/info_card, params[:splat] will be ["lpic2/lpic210.yml"]
  lab_name_parts = params[:splat]

  # Extract the lab name string from the first element of the splat array
  lab_name = lab_name_parts.first if lab_name_parts && lab_name_parts.length > 0

  # --- Validation (same as before) ---
  # Ensure lab_name exists, ends with .yml, and doesn't contain dangerous patterns
  if !lab_name || !lab_name.end_with?('.yml') || lab_name.include?('..') || lab_name.include?("\0")
    halt 404, "Invalid lab name."
  end

  labs_list = all_labs
  unless labs_list.include?(lab_name)
    halt 404, "Lab '#{lab_name}' not found."
  end

  # --- Processing (same as before) ---
  lab_file_path = File.join(LABS_DIR, lab_name)
  lab_info = parse_lab_info(lab_file_path)

  # --- Response (same as before) ---
  # Use the helper method to render the card HTML
  render_lab_info_card(lab_info)
end

# Add this route *before* the main routes, or wherever appropriate
# This route catches /labs/ANYTHING/info
get '/labs/*/info' do
  content_type :json

  # params[:splat] is an Array containing the matched '*' part(s).
  # For the URL /labs/k3s/k3s01.yml/info, params[:splat] will be ["k3s/k3s01.yml"]
  lab_name_parts = params[:splat]

  # Extract the lab name string from the first element of the splat array
  lab_name = lab_name_parts.first if lab_name_parts && lab_name_parts.length > 0

  # --- Validation ---
  # Ensure lab_name exists, ends with .yml, and doesn't contain dangerous patterns
  if !lab_name || !lab_name.end_with?('.yml') || lab_name.include?('..') || lab_name.include?("\0")
    # Return a JSON error object with a 404 status
    halt 404, { error: "Invalid lab name." }.to_json
  end

  # Check if the requested lab name exists in the list of known labs
  labs_list = all_labs
  unless labs_list.include?(lab_name)
    # Return a JSON error object with a 404 status
    halt 404, { error: "Lab '#{lab_name}' not found." }.to_json
  end

  lab_file_path = File.join(LABS_DIR, lab_name)
  lab = Lab.new(cfg: lab_file_path)
  #puts "nodes"
  #lab.nodes.each do |node|
  #  p "Node: #{node}"
  #end
  #p lab.nodes

  # --- Processing ---
  # Construct the full path to the lab file
  lab_file_path = File.join(LABS_DIR, lab_name)

  # Call the helper function to parse the lab's YAML file
  lab_info = parse_lab_info(lab_file_path)

  # --- Response ---
  # Send the parsed information back as a JSON string
  lab_info.to_json
end

get '/logs' do
  if params[:file]
    # View specific log
    @log_file = URI.decode_www_form_component(params[:file])
    halt 403 unless @log_file.start_with?(LabLog::LOG_DIR) && @log_file.end_with?('.log')
    halt 404 unless File.file?(@log_file)
    
    # Extract from filename (minimal parsing for display only)
    basename = File.basename(@log_file, '.log')
    parts = basename.split('_')
    @lab_name = parts[2..-2].join('_').gsub(/\.yml$/, '.yml') rescue 'Unknown'
    @action = parts.last == 'up' ? 'up' : 'down'
    
    erb :live_log
  else
    # Show log index
    @running_lab = Lab.running? ? Lab.current_name : nil
    
    # ✅ DELEGATE TO LABLOG
    @log_files = if @running_lab
      LabLog.all_for_lab(@running_lab)
    else
      LabLog.all_logs
    end
    
    erb :logs_index
  end
end

get '/logs/current' do
  if Lab.running?
    log_path = LabLog.latest_for_running_lab  # ✅ No pattern matching!
    redirect "/logs?file=#{URI.encode_www_form_component(log_path)}" if log_path
  end
  redirect '/logs'
end

get '/logs/content' do
  content_type 'text/html; charset=utf-8'
  log_file = URI.decode_www_form_component(params[:file])
  
  # Forgiving path check
  log_dir = defined?(LOG_DIR) ? LOG_DIR : '/var/log/ctlabs'
  basename = File.basename(log_file)
  is_valid_prefix = basename.start_with?('ctlabs_') || basename.start_with?('build_')
  
  # If it fails the security check, print it to the UI!
  unless log_file.start_with?(log_dir) && is_valid_prefix && log_file.end_with?('.log')
    status 403
    return "<span style='color:#ef4444;'>❌ Error 403: Log viewer blocked access to: #{log_file}.</span>"
  end

  # If the file hasn't been written to disk yet, print it to the UI!
  unless File.file?(log_file)
    status 404
    return "<span style='color:#ef4444;'>❌ Error 404: The log file does not exist. (Did the build script fail to execute?)</span>"
  end

  raw_text = File.read(log_file)
  ansi_to_html(raw_text)
end

get '/logs/system' do
  system_log = '/var/log/ctlabs.log'
  if File.file?(system_log)
    @log_file = system_log
    @lab_name = 'System Log (CLI operations)'
    @action = 'system'
    erb :live_log
  else
    halt 404, "System log not found"
  end
end

# Delete a single log file
post '/logs/delete' do
  log_file = URI.decode_www_form_component(params[:file])
  # Security: only allow logs from our directory with correct pattern
  # Security: allow standard lab logs AND image build logs
  basename = File.basename(log_file)
  is_valid_pattern = basename.match?(/\Actlabs_\d+_.+_\w+\.log\z/) || basename.match?(/\Abuild_.+_\d+\.log\z/)

  halt 403 unless log_file.start_with?(LOG_DIR) && File.basename(log_file).match?(/\Actlabs_\d+_.+_\w+\.log\z/) && log_file.end_with?('.log')
  halt 404 unless File.file?(log_file)

  File.delete(log_file)
  redirect '/logs'
end

# Delete all log files
post '/logs/delete-all' do
  log_files = Dir.glob("#{LOG_DIR}/ctlabs_*.log") + Dir.glob("#{LOG_DIR}/build_*.log")
  log_files.each { |f| File.delete(f) if File.file?(f) }
  redirect '/logs'
end

# ------------------------------------------------------------------------------
# Templates
# ------------------------------------------------------------------------------
BADREQ = %q(
<div class="w3-panel w3-red">
  <h3>Bad Request</h3>
  <p>Something went wrong! [Hint: Did you choose a file?]</p>
</div>
)

HEADER = %q(
<!DOCTYPE html>
<html lang="en">
<head>
  <title>🔬 CTLABS</title>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://www.w3schools.com/w3css/4/w3.css">
  <link rel="stylesheet" href="https://www.w3schools.com/lib/w3-colors-2021.css">
  <link rel="stylesheet" href="/asciinema-player.css" type="text/css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/base16/dracula.min.css">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/yaml.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/ini.min.js"></script>
  <script>hljs.highlightAll();</script>
  <script src="https://www.w3schools.com/lib/w3.js"></script>

  <style>
    /* Global Modern Typography */
    body, h1, h2, h3, h4, h5, h6, button, input, select, textarea {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif !important;
    }
    
    /* Sleek Slate Dark Theme */
    body { background-color: #0f172a; color: #e2e8f0; }
    
    /* Frosted Glass Navbar */
    .w3-top .w3-bar { 
      background-color: rgba(15, 23, 42, 0.85) !important; 
      backdrop-filter: blur(12px); 
      border-bottom: 1px solid #1e293b; 
      box-shadow: none;
    }
    .w3-bar-item.w3-button:hover { background-color: rgba(255,255,255,0.1) !important; border-radius: 6px; }

    /* Modernized Cards and Panels */
    .w3-card-4, .w3-panel, .w3-2021-inkwell { 
      background-color: #1e293b !important; 
      color: #f8fafc !important; 
      border-radius: 12px; 
      border: 1px solid #334155; 
      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.3), 0 2px 4px -1px rgba(0, 0, 0, 0.2) !important; 
    }
    
    /* Page Titles */
    .w3-panel.w3-green {
      background: linear-gradient(135deg, #059669 0%, #10b981 100%) !important;
      color: white !important;
      border: none;
    }

    /* Buttons */
    .w3-button { border-radius: 6px; transition: all 0.2s ease-in-out; font-weight: 500; }
    .w3-button.w3-green { background-color: #10b981 !important; }
    .w3-button.w3-green:hover { background-color: #059669 !important; transform: translateY(-1px); }
    .w3-button.w3-blue { background-color: #3b82f6 !important; }
    .w3-button.w3-blue:hover { background-color: #2563eb !important; transform: translateY(-1px); }
    .w3-button.w3-red { background-color: #ef4444 !important; }
    .w3-button.w3-red:hover { background-color: #dc2626 !important; transform: translateY(-1px); }

    /* Inputs & Selects */
    .w3-select, .w3-input { 
      border-radius: 6px; 
      background-color: #0f172a !important; 
      color: #e2e8f0 !important; 
      border: 1px solid #475569 !important;
    }
    .w3-select:focus, .w3-input:focus { border-color: #3b82f6 !important; outline: none; }

    /* Tables */
    .w3-table td, .w3-table th { border-bottom: 1px solid #334155 !important; }
    .w3-striped tbody tr:nth-child(even) { background-color: rgba(255,255,255,0.03) !important; }
    
    #log-content span { font-weight: normal; }
    .svg-container { width: 100%; height: auto; position: relative; overflow: auto; display: flex; justify-content: center; align-items: flex-start; }
    .responsive-embed { width: 100%; height: auto; min-height: 100px; display: block; max-width: 100%; max-height: 70vh; }
    .responsive-embed.zooming { transition: transform 0.2s ease; }
    
    /* Code Blocks */
    pre, code { border-radius: 8px; }
  </style>
</head>
<body>
  <div class="w3-top w3-bar w3-padding-small">
    <a href="/"          class="w3-bar-item w3-button w3-margin-right"><b>🔬 CTLABS</b></a>
    <a href="/topo"      class="w3-bar-item w3-button"><i class="fas fa-sitemap w3-margin-right"></i>Topology</a>
    <a href="/con"       class="w3-bar-item w3-button"><i class="fas fa-network-wired w3-margin-right"></i>Connections</a>
    <a href="/inventory" class="w3-bar-item w3-button"><i class="fas fa-list w3-margin-right"></i>Inventory</a>
    <a href="/config"    class="w3-bar-item w3-button"><i class="fas fa-cogs w3-margin-right"></i>Configuration</a>
    <a href="/logs"      class="w3-bar-item w3-button"><i class="fas fa-terminal w3-margin-right"></i>Logs</a>
    <a href="/flashcards" class="w3-bar-item w3-button"><i class="fas fa-layer-group w3-margin-right"></i>Flashcards</a>
    <a href="/demo"      class="w3-bar-item w3-button"><i class="fas fa-video w3-margin-right"></i>Walkthrough</a>
  </div>
  <div id="ctlabs" style="height: 70px;"></div>
)

SCRIPT = %q(
<script>
function updateSVGScale(embedId, percent) {
  const embed = document.getElementById(embedId);
  if (!embed) return;

  const scale = percent / 100;
  // Apply scale without affecting layout flow
  embed.style.transform = `scale(${scale})`;
  embed.style.transformOrigin = 'top left';
  embed.classList.add('zooming');

  // Update label
  const labelId = `zoom-value-${embedId.replace('-embed', '')}`;
  const label = document.getElementById(labelId);
  if (label) label.textContent = percent;
}

// Initialize sliders
document.addEventListener('DOMContentLoaded', function () {
  const sliders = document.querySelectorAll('.zoom-slider');
  sliders.forEach(slider => {
    slider.addEventListener('input', function () {
      const embedId = this.getAttribute('data-embed-id');
      const percent = this.value;
      updateSVGScale(embedId, percent);
    });
  });

  // Optional: set initial base width for accurate scaling
  document.querySelectorAll('.responsive-embed').forEach(embed => {
    // Force load if not already
    if (!embed.getAttribute('src')) return;
  });
});
function fitToContainer(embed) {
  const container = embed.parentElement;
  const svgDoc = embed.getSVGDocument?.();
  if (!svgDoc) return;

  const svg = svgDoc.documentElement;
  const vb = svg.viewBox.baseVal;
  if (vb && vb.width > 0) {
    const containerWidth = container.clientWidth;
    const scale = Math.min(1, containerWidth / vb.width);
    embed.style.transform = `scale(${scale})`;
    embed.dataset.initialScale = scale;
  }
}

// Call after embed loads
document.querySelectorAll('.responsive-embed').forEach(embed => {
  embed.onload = () => fitToContainer(embed);
});
</script>
)

FOOTER = %q(
  </body>
</html>
)


# ------------------------------------------------------------------------------
# SECURE PUMA BOOTLOADER (Must remain at the bottom of the file!)
# ------------------------------------------------------------------------------
if __FILE__ == $0
  require 'fileutils'
  require 'openssl'
  require 'webrick'
  require 'puma'
  require 'puma/configuration'
  require 'puma/launcher'

  CERT_DIR = '/srv/ctlabs-server/ssl'
  FileUtils.mkdir_p(CERT_DIR)
  CERT_PATH = File.join(CERT_DIR, 'cert.pem')
  KEY_PATH  = File.join(CERT_DIR, 'key.pem')

  # Auto-generate SSL Certs if they don't exist
  unless File.exist?(CERT_PATH) && File.exist?(KEY_PATH)
    puts "Generating secure self-signed SSL certificates for Puma..."
    key             = OpenSSL::PKey::RSA.new(4096)
    cert            = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = 1
    cn_name         = WEBrick::Utils.getservername rescue 'localhost'
    cert.subject    = OpenSSL::X509::Name.parse("/CN=#{cn_name}")
    cert.issuer     = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after  = cert.not_before + (365 * 24 * 60 * 60)
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    
    File.write(KEY_PATH, key.to_pem)
    File.write(CERT_PATH, cert.to_pem)
  end

  puts "🚀 Starting CTLABS Secure Terminal Engine on https://0.0.0.0:4567"

  conf = Puma::Configuration.new do |c|
    c.bind "ssl://0.0.0.0:4567?key=#{KEY_PATH}&cert=#{CERT_PATH}&verify_mode=none"
    c.app Sinatra::Application
  end

  Puma::Launcher.new(conf).run
end
