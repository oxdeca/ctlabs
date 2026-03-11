#!/usr/bin/env ruby

# -----------------------------------------------------------------------------
# File        : ctlabs/server.rb
# Description : ctlabs main script
# License     : MIT License
# -----------------------------------------------------------------------------

#require 'kramdown'
#require 'kramdown-parser-gfm'
require 'fileutils'
require 'webrick'
require 'sinatra'
require 'erb'
require 'net/http'
require 'shellwords'
require 'set'
require 'securerandom'

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), 'lib')
require 'lab'
require 'node'
require 'link'
require 'graph'
require 'lablog'

require_relative 'helpers/application_helper'

# sinatra settings
disable :logging
enable  :sessions
set     :session_secret,     SecureRandom.hex(64)
set     :bind,              '0.0.0.0'
set     :port,               4567
set     :public_folder,     '/srv/ctlabs-server/public'
set     :host_authorization, permitted_hosts: []
set     :markdown, input: 'GFM'
set     :server_settings,    SSLEnable: true,
                            SSLVerifyClient: OpenSSL::SSL::VERIFY_NONE,
                            SSLCertName:     [[ 'CN', WEBrick::Utils.getservername ]]

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

  # Parse info for the selected lab
  @lab_info = nil
  if @selected_lab && @labs.include?(@selected_lab)
    lab_file_path = File.join(LABS_DIR, @selected_lab)
    @lab_info = parse_lab_info(lab_file_path)
  end

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

# Helper to regenerate Graphs with AdHoc nodes injected in memory
def visualize_with_adhoc(lab_name)
  lab_file_path = File.join(LABS_DIR, lab_name)
  lab = Lab.new(cfg: lab_file_path, log: LabLog.null)
  safe_lab = lab_name.gsub(%r{[^a-zA-Z0-9_.\-/]}, '_').gsub('/', '_')
  
  adhoc_nodes_file = "#{LOCK_DIR}/adhoc_nodes_#{safe_lab}.json"
  if File.file?(adhoc_nodes_file)
    adhoc_nodes = JSON.parse(File.read(adhoc_nodes_file), symbolize_names: true)
    
    # Inject into raw @cfg so get_topology sees it
    cfg = lab.instance_variable_get(:@cfg)
    cfg['topology'][0]['nodes'] ||= {}
    
    adhoc_nodes.each do |an|
      cfg['topology'][0]['nodes'][an[:name].to_s] = an[:raw_cfg] || { 'type' => an[:type].to_s, 'kind' => an[:kind].to_s }
      
      existing = lab.nodes.find { |n| n.name == an[:name].to_s }
      if existing
        existing.instance_variable_set(:@type, an[:type].to_s)
      else
        node = Node.new({ 'name' => an[:name].to_s, 'defaults' => lab.defaults, 'log' => LabLog.null }.merge(an[:raw_cfg] || {}))
        lab.nodes << node
        lab.links << ["#{an[:switch]}:eth_adhoc", "#{an[:name]}:eth1"] if an[:switch] && !an[:switch].to_s.empty?
      end
    end
  end
  
  adhoc_dnat_file = "#{LOCK_DIR}/adhoc_dnat_#{safe_lab}.json"
  if File.file?(adhoc_dnat_file)
     JSON.parse(File.read(adhoc_dnat_file), symbolize_names: true).each do |rule|
        if n = lab.nodes.find { |node| node.name == rule[:node].to_s }
           n.instance_variable_set(:@dnat, []) if n.dnat.nil?
           n.dnat << [rule[:external_port].split(':').last, rule[:internal_port].split(':').last, rule[:proto]]
        end
     end
  end

  lab.visualize
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

    # Re-instantiate to natively redraw graphs with the new rule
    updated_lab = Lab.new(cfg: lab_path, log: LabLog.null)
    updated_lab.visualize 

    content_type :json
    { success: true, message: "AdHoc DNAT rule added" }.to_json
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
    
    # Re-instantiate from the updated YAML file to natively update inventory & graphs!
    updated_lab = Lab.new(cfg: lab_path, log: LabLog.null)
    updated_lab.visualize
    updated_lab.inventory

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

    if running_lab? && get_running_lab == lab_name
      # Re-instantiate from the updated YAML file to natively update inventory & graphs!
      updated_lab = Lab.new(cfg: lab_path, log: LabLog.null)
      updated_lab.visualize
      updated_lab.inventory
    end

    content_type :json
    { success: true, message: "Node configuration saved." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

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
        lab_instance.visualize
        lab_instance.inventory
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
  halt 403 unless log_file.start_with?("#{LOG_DIR}/ctlabs_") && log_file.end_with?('.log')
  halt 404 unless File.file?(log_file)

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
  halt 403 unless log_file.start_with?(LOG_DIR) && 
                  File.basename(log_file).match?(/\Actlabs_\d+_.+_\w+\.log\z/) &&
                  log_file.end_with?('.log')
  halt 404 unless File.file?(log_file)

  File.delete(log_file)
  redirect '/logs'
end

# Delete all log files
post '/logs/delete-all' do
  log_files = Dir.glob("#{LOG_DIR}/ctlabs_*.log")
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
