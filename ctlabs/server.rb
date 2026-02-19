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
  erb :config
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

post '/labs/*/dnat' do
  lab_name = params[:splat].first

  # --- Validation ---
  halt 400, "Invalid lab name" unless lab_name
  halt 400, "Lab must be a .yml file" unless lab_name.end_with?('.yml')
  halt 400, "Path traversal detected" if lab_name.include?('..') || lab_name.include?("\0")

  labs_list = all_labs
  halt 400, "Lab not found" unless labs_list.include?(lab_name)

  running = get_running_lab
  halt 400, "No lab is running" unless running
  halt 400, "AdHoc DNAT only allowed on the running lab" unless running == lab_name

  node     = params[:node]
  ext_port = params[:external_port]&.to_i
  int_port = params[:internal_port]&.to_i
  proto    = (params[:protocol] || 'tcp').downcase

  halt 400, "Missing node" unless node
  halt 400, "Invalid external port" unless ext_port >= 1 && ext_port <= 65535
  halt 400, "Invalid internal port" unless int_port >= 1 && int_port <= 65535
  halt 400, "Protocol must be tcp or udp" unless %w[tcp udp].include?(proto)

  begin
    lab_file_path  = File.join(LABS_DIR, lab_name)
    lab            = Lab.new(cfg: lab_file_path)
    rule           = lab.add_adhoc_dnat(node, ext_port, int_port, proto)

    # ✅ FIX: Append to lab's CURRENT operational log (visible in web UI)
    log_path = LabLog.latest_for_running_lab
    if log_path
      log = LabLog.new(path: log_path)
      log.info "AdHoc DNAT added: #{rule.inspect}"
      log.close
    end

    # Persist rule to ad-hoc DNAT file (for cleanup on lab stop)
    safe_lab   = lab_name.gsub(/\//, '_').gsub(/[^a-zA-Z0-9_.\-]/, '')
    adhoc_file = "#{LOCK_DIR}/adhoc_dnat_#{safe_lab}.json"
    
    # Load existing rules (if any)
    existing = []
    if File.file?(adhoc_file)
      begin
        existing = JSON.parse(File.read(adhoc_file), symbolize_names: true)
      rescue JSON::ParserError
        existing = []
      end
    end
    
    # Append new rule
    existing << rule
    
    # Save back
    File.write(adhoc_file, JSON.pretty_generate(existing))

    session[:adhoc_dnat_rules] ||= {}
    session[:adhoc_dnat_rules][lab_name] ||= []
    session[:adhoc_dnat_rules][lab_name] = existing

    content_type :json 
    { success: true, message: "AdHoc DNAT rule added", rule: rule }.to_json
  rescue => e
    content_type :json
    status 400
    { success: false, error: e.message }.to_json
  end
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

# server.rb — POST /labs/execute
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
    
    # Cleanup ad-hoc DNAT (controller-owned session state - OK here)
    if lab_name
      lab_name_safe = lab_name.gsub(%r{[^a-zA-Z0-9_.\-/]}, '_').gsub('/', '_')
      adhoc_file = "#{LOCK_DIR}/adhoc_dnat_#{lab_name_safe}.json"
      File.delete(adhoc_file) if File.file?(adhoc_file)
    end
  end

  lab_file_path = File.join(LABS_DIR, lab_name)
  
  log = LabLog.for_lab(lab_name: lab_name, action: action)
  
  Thread.new do
    begin
      lab_instance = Lab.new(cfg: lab_file_path, relative_path: lab_name, log: log)
      
      if action == 'up'
        lab_instance.visualize
        lab_instance.inventory
        lab_instance.up
        log.info "--- Lab #{lab_name} UP completed ---"

        # ✅ RUN PLAYBOOK ONCE with built-in concurrency protection
        # (playbook lock handled internally by Lab#run_playbook)
        begin
          lab_instance.run_playbook(nil, log.path)
          log.info "--- Ansible playbook completed ---"
        rescue => e
          log.info "⚠️  Playbook failed but lab is running: #{e.message}"
        end
      else
        lab_instance.down
        log.info "--- Lab #{lab_name} DOWN completed ---"
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
  <title>🔬 CTLABS</title>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://www.w3schools.com/w3css/4/w3.css">
  <link rel="stylesheet" href="https://www.w3schools.com/lib/w3-colors-2021.css">
  <link rel="stylesheet" href="/asciinema-player.css" type="text/css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/base16/dracula.min.css">
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/yaml.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/ini.min.js"></script>
  <script>hljs.highlightAll();</script>
  <script src="https://www.w3schools.com/lib/w3.js"></script>
  <style>
    #log-content span {
      font-weight: normal;
    }
    /* Optional: make bold ANSI codes actually bold */
    /* Would require parsing '1;' in ANSI codes */
    .svg-container {
      width: 100%;
      height: auto;
      position: relative;
      overflow: auto; /* Fallback scroll if needed */
      display: flex;
      justify-content: center;
      align-items: flex-start;
    }
  
    .responsive-embed {
      width: 100%;
      height: auto;
      min-height: 100px; /* prevent collapse */
      display: block;
      /* Preserve aspect ratio */
      max-width: 100%;
      max-height: 70vh; /* optional: cap height */
    }
  
    /* Optional: smooth scaling during zoom */
    .responsive-embed.zooming {
      transition: transform 0.2s ease;
    }
  </style>
  <body bgcolor="#1c1c1c">
    <div class="w3-top w3-bar w3-black">
      <a href="/"          class="w3-bar-item w3-button">🔬 CTLABS</a>
<!--      <a href="/labs"      class="w3-bar-item w3-button">🧪 Labs</a> -->
      <a href="/topo"      class="w3-bar-item w3-button">🗺️ Topology</a>
      <a href="/con"       class="w3-bar-item w3-button">🕸 Connections</a>
      <a href="/inventory" class="w3-bar-item w3-button">🗂️ Inventory</a>
      <a href="/config"    class="w3-bar-item w3-button">⚙️  Configuration</a>
      <a href="/logs"      class="w3-bar-item w3-button">🧾 Logs</a>
      <a href="/flashcards" class="w3-bar-item w3-button">🎴 Flashcards</a>
      <a href="/demo"      class="w3-bar-item w3-button">📹 Walkthrough</a>
<!--      <a href="/upload" class="w3-bar-item w3-button">📤 Upload</a> -->
    </div>
    <div id="ctlabs"><br></div>
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