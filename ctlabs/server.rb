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


# sinatra settings
enable :sessions
set    :session_secret, ENV['SESSION_SECRET'] || ["e7c22b994c59d9cf2b48e549b1e24666636045930d3da7c1acb299d1c3b7f931f94aae41edda2c2b207a36e10f8bcb8d45223e54878f5b316e7ce3b6bc019629"].pack("H*")
set    :bind,              '0.0.0.0'
set    :port,               4567
set    :public_folder,     '/srv/ctlabs-server/public'
set    :host_authorization, permitted_hosts: []
set    :markdown, input: 'GFM'
set    :server_settings,    SSLEnable: true,
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
Dir.mkdir(LOG_DIR, 0755)    unless Dir.exists?(LOG_DIR)
Dir.mkdir(LOCK_DIR, 0755)   unless Dir.exists?(LOCK_DIR)
Dir.mkdir(UPLOAD_DIR, 0755) unless Dir.exist?(UPLOAD_DIR)

# add basic authentication
use Rack::Auth::Basic, 'Restricted Area' do |user, pass|
  salt = "GGV78Ib5vVRkTc"
  user == 'ctlabs' && pass.crypt("$6$#{salt}$") == "$6$GGV78Ib5vVRkTc$cRAo9wl36SQPkh/UFzgEIOO1rBuju7/h5Lu8fJMDUNDG0HUcL3AhBNEqcYT1UUZkmBHa9.8r/5eh5qXwA8zcr."
end

helpers do
  def ansi_to_html(text)
    color_map = {
      '30' => '#000',   # black
      '31' => '#a00',   # red
      '32' => '#0a0',   # green
      '33' => '#aa0',   # yellow
      '34' => '#00a',   # blue
      '35' => '#a0a',   # magenta
      '36' => '#0aa',   # cyan
      '37' => '#aaa',   # white
      '90' => '#555',   # bright black
      '91' => '#f55',   # bright red
      '92' => '#5f5',   # bright green
      '93' => '#ff5',   # bright yellow
      '94' => '#55f',   # bright blue
      '95' => '#f5f',   # bright magenta
      '96' => '#5ff',   # bright cyan
      '97' => '#fff',   # bright white
    }

    html = ''
    current_color = nil

    # Split by ANSI escape sequences
    parts = text.split(/(\e\[[\d;]*m)/)
    parts.each do |part|
      if part.start_with?("\e[")
        code = part[2..-2] || ''
        if code == '0' || code.empty?
          if current_color
            html += '</span>'
            current_color = nil
          end
        else
          color_codes = code.split(';').grep(/\A\d+\z/)
          fg = color_codes.find { |c| c.start_with?('3') || c.start_with?('9') }
          if fg && color_map[fg]
            if current_color
              html += '</span>'
            end
            html += "<span style='color:#{color_map[fg]}'>"
            current_color = fg
          end
        end
      else
        # Escape HTML special chars
        html += ERB::Util.h(part)
      end
    end

    html += '</span>' if current_color
    html  # ← just return plain string, NO .html_safe
  end

  def all_labs
    Dir.glob(File.join(LABS_DIR, "**", "*.yml"))
       .map { |f| f.sub(LABS_DIR + '/', '') }
       .sort
  end

  def running_lab?
    File.file?(LOCK_FILE)
  end
  
  def get_running_lab
    File.read(LOCK_FILE).strip if running_lab?
  rescue
    nil
  end
  
  def set_running_lab(lab_name)
    File.write(LOCK_FILE, lab_name)
  end
  
  def clear_running_lab
    File.delete(LOCK_FILE) if File.file?(LOCK_FILE)
  end
end

# ------------------------------------------------------------------------------
# ROUTES
# ------------------------------------------------------------------------------
get "/" do
  #ERB.new(home).result(binding)
  erb :home
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
  @selected_lab = session[:selected_lab] || (@labs.first if @labs.any?)
  erb :labs
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

post '/labs/execute' do
  action = params[:action]
  halt 400, "Invalid action" unless %w[up down].include?(action)

  if action == 'down'
    # Get the running lab
    running_lab = get_running_lab
    halt 400, "No lab is currently running." unless running_lab

    lab_name = running_lab
    labs_list = all_labs
    halt 500, "Running lab not found in lab list: #{lab_name}" unless labs_list.include?(lab_name)

    # ✅ CLEAR THE LOCK NOW — assume user wants to stop
    clear_running_lab

  else # action == 'up'
    lab_name = params[:lab_name]
    labs_list = all_labs
    halt 400, "Invalid lab" unless lab_name && labs_list.include?(lab_name)

    if running_lab?
      current = get_running_lab
      halt 400, "A lab is already running: #{current}. Stop it first."
    end

    set_running_lab(lab_name)
  end

  # Proceed with execution
  lab_path = File.join(LABS_DIR, lab_name)
  timestamp = Time.now.to_i
  safe_lab = lab_name.gsub(/\//, '_').gsub(/[^a-zA-Z0-9_.\-]/, '')
  log_file = "#{LOG_DIR}/ctlabs_#{timestamp}_#{safe_lab}_#{action}.log"

  cmd_flag = (action == 'up') ? '-up' : '-d'
  cmd = "cd #{SCRIPT_DIR} && nohup #{CTLABS_SCRIPT} -c #{lab_path.shellescape} #{cmd_flag} > #{log_file.shellescape} 2>&1 </dev/null &"

  # Run the command
  success = system(cmd)

  # Optional: if system() fails, re-set the lock for 'up', or warn for 'down'
  if !success && action == 'up'
    clear_running_lab  # undo lock if start failed
    halt 500, "Failed to start lab process"
  end

  redirect "/logs?file=#{URI.encode_www_form_component(log_file)}&lab=#{lab_name}&action=#{action}"
end

get '/logs' do
  if params[:file]
    # View specific log
    @log_file = URI.decode_www_form_component(params[:file])
    # Security: only allow logs from our dir
    halt 403 unless @log_file.start_with?(LOG_DIR) && @log_file.end_with?('.log')
    halt 404 unless File.file?(@log_file)

    # Extract lab name and action from filename
    basename = File.basename(@log_file, '.log')
    parts = basename.split('_')
    @lab_name = parts[2..-2].join('_').gsub(/\.yml$/, '.yml') rescue 'Unknown'
    @action = parts.last == 'up' ? 'up' : 'down'

    erb :live_log
  else
    # Show log index
    @log_files   = Dir.glob("#{LOG_DIR}/ctlabs_*.log") .sort_by { |f| File.mtime(f) } .reverse  # newest first
    @running_lab = get_running_lab if running_lab?

    erb :logs_index
  end
end

get '/logs/current' do
  if running_lab?
    latest = Dir.glob("#{LOG_DIR}/ctlabs_*_#{running_lab.gsub(/\//, '_')}*.log")
                 .sort_by { |f| File.mtime(f) }
                 .last
    if latest
      redirect "/logs?file=#{URI.encode_www_form_component(latest)}"
    end
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
      <a href="/labs"      class="w3-bar-item w3-button">🧪 Labs</a>
      <a href="/con"       class="w3-bar-item w3-button">🖧  Connections</a>
      <a href="/topo"      class="w3-bar-item w3-button">🏠 Topology</a>
      <a href="/inventory" class="w3-bar-item w3-button">🗂️ Inventory</a>
      <a href="/config"    class="w3-bar-item w3-button">⚙️  Configuration</a>
      <a href="/logs"      class="w3-bar-item w3-button">🧾 Logs</a>
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
    <br><br>
  </body>
</html>
)

__END__


@@home
<%= HEADER %>
    <div id="con" class="w3-panel w3-green">
      <h2>🖧  Connections [Data Network] </h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <span>Zoom: <strong><span id="zoom-value-con">100</span>%</strong></span></br>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="con-embed">
      </div>
      <div class="svg-container">
        <embed id="con-embed" src="con.svg" class="w3-round responsive-embed" alt="🖧  Connections" type="image/svg+xml" width="100%">
      </div>
    </div>
    <div id="topo" class="w3-panel w3-green">
      <h2>🏠 Topology [Data Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <span> Zoom: <strong><span id="zoom-value-topo">100</span>%</strong></span></br>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="topo-embed">
      </div>
      <div class="svg-container">
        <embed id="topo-embed" src="topo.svg" class="w3-round responsive-embed" alt="Management" type="image/svg+xml" width="100%">
      </div>
    </div>
<%= SCRIPT %>
<%= FOOTER %>

@@con
<%= HEADER %>
    <div id="con" class="w3-panel w3-green">
      <h2>🖧  Connections [Data Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="con-embed">
        <span>Zoom: <strong><span id="zoom-value-con">100</span>%</strong></span>
      </div>
      <div class="svg-container">
        <embed id="con-embed" src="con.svg" class="w3-round responsive-embed" alt="Connections" type="image/svg+xml" width="100%">
      </div>
    </div>
    <div id="mgmt_con" class="w3-panel w3-green">
      <h2>🖧  Connections [Management Network] </h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="mgmt-con-embed">
        <span>Zoom: <strong><span id="zoom-value-mgmt-con">100</span>%</strong></span>
      </div>
      <div class="svg-container">
        <embed id="mgmt-con-embed" src="mgmt_con.svg" class="w3-round responsive-embed" alt="Management" type="image/svg+xml" width="100%">
      </div>
    </div>
<%= SCRIPT %>
<%= FOOTER %>

@@topo
<%= HEADER %>
    <div id="topo" class="w3-panel w3-green">
      <h2>🏠 Topology [Data Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="topo-embed">
        <span>Zoom: <strong><span id="zoom-value-topo">100</span>%</strong></span>
      </div>
      <div class="svg-container">
        <embed id="topo-embed" src="topo.svg" class="w3-round responsive-embed" alt="🏠 Topology" type="image/svg+xml" width="100%">
      </div>
    </div>
    <div id="mgmt_topo" class="w3-panel w3-green">
      <h2>🏠 Topology [Management Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="mgmt-topo-embed">
        <span>Zoom: <strong><span id="zoom-value-mgmt-topo">100</span>%</strong></span>
      </div>
      <div class="svg-container">
        <embed id="mgmt-topo-embed" src="mgmt_topo.svg" class="w3-round responsive-embed" alt="Management" type="image/svg+xml" width="100%">
      </div>
    </div>
<%= SCRIPT %>
<%= FOOTER %>

@@upload
<%= HEADER %>
    <div id="upload" class="w3-panel w3-green">
      <h2> Upload </h2>
    </div>
    <div class="w3-container w3-teal">
    <form action="/upload" method="post" enctype="multipart/form-data">
      <label class="w3-text-teal"><b>Select a file:</b></label>
      <input class="w3-input w3-border"  type="file"   name="file" id="file"/>
      <input class="w3-btn w3-blue-grey" type="submit" value="Send File"/>
    </form>
    </div>
    <br/><br/>
    <div class="w3-container">
      <ul class="w3-ul w3-border w3-hoverable">
        <li class="w3-teal"><h3>Uploaded Files:</h3></li>
      <% Dir.entries(UPLOAD_DIR, encoding: "ascii" ).each do |f| %>
        <%  if f =~ /[a-zA-Z0-9].*/ %>
          <li><%= f %><br/></li>
        <% end %>
      <% end %>
      </ul>
    </divc>
<%= FOOTER %>

@@inventory
<%= HEADER %>
    <div id="inventory" class="w3-panel w3-green">
      <h2>🗂️ Inventory [Management Network]</h2>
    </div>
    <div class="w3-container">
      <div class="w3-container w3-card-4 w3-2021-inkwell" style="max-width: 100%; max-height: 100%; overflow: auto;">
        <pre><code class="language-ini"><%= File.file?(INVENTORY) ? ERB::Util.h(File.read(INVENTORY)) : "Error: No Inventory found!" %></code></pre>
      </div>
    </div>
<%= FOOTER %>

@@config
<%= HEADER %>
    <div id="config" class="w3-panel w3-green">
      <h2>⚙️  Lab Configuration </h2>
    </div>
    <div class="w3-container">
      <div class="w3-container w3-card-4 w3-2021-inkwell" style="max-width: 100%; max-height: 100%; overflow: auto;">
        <pre><code class="language-yaml"><%= File.file?(CONFIG) ? ERB::Util.h(File.read(CONFIG)) : "Error: No Configuration found!" %></code></pre>
      </div>
    </div>
<%= FOOTER %>

@@demo
<%= HEADER %>
    <div class="w3-panel w3-green">
      <h2>📹 Walkthrough </h2>
    </div>
    <div id="demo" class="w3-container w3-card-4" style="max-width: 100%; max-height: 100%; overflow: auto;">
      <div class="w3-round">
      <script src="/asciinema-player.min.js"></script>
      <script>
        AsciinemaPlayer.create('/demo.cast', document.getElementById('demo'));
      </script>
      </div>
    </div>
<%= FOOTER %>

@@markdown
<%= HEADER %>
    <div id="config" class="w3-panel w3-green">
      <h2> Markdown </h2>
    </div>
    <div class="w3-container w3-margin">
      <div class="w3-card-4 w3-bar w3-round-large">
        <header class="w3-container w3-bar w3-dark-grey w3-padding">
          <span class="w3-badge w3-red w3-circle w3-small w3-text-red">&nbsp;</span>
          <span class="w3-text-dark-grey">&nbsp;</span>
          <span class="w3-badge w3-yellow w3-circle w3-small w3-text-yellow">&nbsp;</span>
          <span class="w3-text-dark-grey">&nbsp;</span>
          <span class="w3-badge w3-green w3-circle w3-small w3-text-green">&nbsp;</span>
        </header>
        <div class="w3-container w3-bar w3-2021-inkwell" style="max-width: 100%; max-height: 100%; overflow: auto;">
        <%= Kramdown::Document.new(File.read("/srv/ctlabs-server/public/ex.md"), input: 'GFM').to_html %>
        </div>
      </div>
    </div>
<%= FOOTER %>

@@labs
<%= HEADER %>
<% last_log = nil
   if request.xhr?
     # Can't access localStorage from server
   else %>
  <!-- Check localStorage via JS -->
  <div id="resume-log" style="display:none;" class="w3-panel w3-blue">
    <span id="resume-content"></span>
  </div>
  <script>
    const lastLog = localStorage.getItem('ctlabs_last_log');
    if (lastLog) {
      try {
        const { lab, action } = JSON.parse(lastLog);
        const url = `/logs?file=${encodeURIComponent(JSON.parse(lastLog).file)}&lab=${encodeURIComponent(lab)}&action=${action}`;
        document.getElementById('resume-content').innerHTML =
          `💡 <a href="${url}">Resume last log</a> for <code>${lab}</code>`;
        document.getElementById('resume-log').style.display = 'block';
      } catch(e) { /* ignore */ }
    }
  </script>
<% end %>
<div class="w3-panel w3-green">
  <h2>🧪 Manage Labs</h2>
</div>

<% running = running_lab? %>
<div class="w3-container w3-card-4 w3-padding">
  <form method="post" action="/labs/execute">
    <label><b>Select Lab:</b></label>
    <select name="lab_name" id="lab-selector" class="w3-select w3-margin-bottom" required <%= 'disabled' if running %>>
      <% @labs.each do |lab| %>
        <option value="<%= lab %>" <%= 'selected' if lab == @selected_lab %>><%= lab %></option>
      <% end %>
    </select>
    <br/>
    <button type="submit" name="action" value="up" class="w3-button w3-green w3-round" <%= 'disabled' if running %>> ▶ Start Lab </button>
    <button type="submit" name="action" value="down" class="w3-button w3-red w3-round"> ⏹ Stop Lab </button>
  </form>

  <% if running %>
    <div class="w3-panel w3-orange w3-margin-top" style="padding:8px;">
      <strong>⚠️ A lab is already running:</strong> 
      <code><%= get_running_lab || 'unknown' %></code>
      <br>Please stop it before starting another.
    </div>
  <% end %>
</div>

<br>
<script>
  document.addEventListener('DOMContentLoaded', () => {
    const lastLog = localStorage.getItem('ctlabs_last_log');
    const select = document.getElementById('lab-selector');

    if (lastLog && select) {
      try {
        const { lab } = JSON.parse(lastLog);
        // Only auto-select if the lab still exists in the list
        if (Array.from(select.options).some(opt => opt.value === lab)) {
          select.value = lab;
          // Optional: highlight that it was auto-filled
          // select.style.borderColor = '#4CAF50';
        }
      } catch (e) {
        console.warn('Failed to parse last log:', e);
      }
    }
  });
</script>
<%= FOOTER %>

@@lab_action_result
<%= HEADER %>
<div class="w3-panel <%= @success ? 'w3-green' : 'w3-red' %>">
  <h2><%= @success ? 'Success' : 'Error' %></h2>
</div>
<div class="w3-container w3-card-4 w3-2021-inkwell" style="max-width:100%; overflow:auto;">
  <pre><%= @output.gsub(/</, '&lt;').gsub(/>/, '&gt;') %></pre>
</div>
<br>
<%= FOOTER %>

@@live_log
<%= HEADER %>
<div class="w3-panel w3-<%= @action == 'up' ? 'green' : 'red' %>">
  <h2>
    <%= @action == 'up' ? '🚀 Starting' : '⏹ Stopping' %> Lab: 
    <code><%= @lab_name %></code>
  </h2>
</div>

<!-- Constrain total height to viewport -->
<div class="w3-container" style="height: calc(100vh - 120px); display: flex; flex-direction: column;">
  <div class="w3-container w3-card-4 w3-2021-inkwell" style="flex: 1; display: flex; flex-direction: column; min-height: 0;">
    <br>
    <pre id="log-content" style="flex: 1; resize: vertical; overflow: auto; min-height: 150px; background: #1e1e1e; color: #f0f0f0; padding: 1em; white-space: pre-wrap; font-family: monospace; margin: 0; border: none;"></pre>
    <div id="scroll-status" style="font-size: 0.8em; color: #aaa; margin-top: 4px; height: 16px;"></div>
  </div>
</div>

<script>
  // === Save log context to localStorage ===
  const logFile = <%= @log_file.to_json %>;
  const labName = <%= @lab_name.to_json %>;
  const action  = <%= @action.to_json %>;
  const logContent = document.getElementById('log-content');

  localStorage.setItem('ctlabs_last_log', JSON.stringify({
    file: logFile,
    lab: labName,
    action: action,
    timestamp: Date.now()
  }));

  // === Auto-scroll with pause/resume ===
  let isAutoScroll = true;

  logContent.addEventListener('scroll', () => {
    const atBottom = logContent.scrollHeight - logContent.scrollTop <= logContent.clientHeight + 5;
    isAutoScroll = atBottom;
    document.getElementById('scroll-status').textContent = 
      isAutoScroll ? '' : '⏸ Paused (scroll to bottom to resume)';
  });

  function fetchLog() {
    if (!isAutoScroll) return;
    fetch(`/logs/content?file=${encodeURIComponent(logFile)}`)
      .then(response => response.text())
      .then(html => {
        logContent.innerHTML = html;
        if (isAutoScroll) {
          logContent.scrollTop = logContent.scrollHeight;
        }
      })
      .catch(err => console.error("Log fetch failed:", err));
  }

  fetchLog();
  const logInterval = setInterval(fetchLog, 500);
  window.addEventListener('beforeunload', () => clearInterval(logInterval));
</script>
<%= FOOTER %>

@@logs_home
<%= HEADER %>
<div class="w3-panel w3-green">
  <h2>🧾 Lab Logs</h2>
</div>
<div class="w3-container">
  <p id="status">Checking for active log session...</p>
</div>

<script>
  document.addEventListener('DOMContentLoaded', () => {
    const lastLog = localStorage.getItem('ctlabs_last_log');
    const statusEl = document.getElementById('status');

    if (lastLog) {
      try {
        const { file, lab, action } = JSON.parse(lastLog);
        // Optional: expire old logs (>1 hour)
        if (Date.now() - (new Date(lastLog.timestamp)).getTime() > 3600000) {
          localStorage.removeItem('ctlabs_last_log');
          statusEl.textContent = "No recent active log session.";
          return;
        }

        const url = `/logs?file=${encodeURIComponent(file)}&lab=${encodeURIComponent(lab)}&action=${encodeURIComponent(action)}`;
        
        // Auto-redirect after a brief delay (for UX feedback)
        statusEl.innerHTML = `
          <strong>Resuming active log...</strong><br>
          Lab: <code>${lab}</code> (${action === 'up' ? 'Starting' : 'Stopping'})
        `;
        
        setTimeout(() => {
          window.location.href = url;
        }, 800); // 0.8 second delay so user sees message

      } catch (e) {
        console.warn('Failed to resume log:', e);
        localStorage.removeItem('ctlabs_last_log');
        statusEl.textContent = "No valid log session found.";
      }
    } else {
      statusEl.textContent = "No active log session.";
    }
  });
</script>
<%= FOOTER %>

@@logs_index
<%= HEADER %>
<div class="w3-panel w3-green">
  <h2>🧾 Lab Logs</h2>
</div>

<div class="w3-container">

  <% if @running_lab %>
    <div class="w3-panel w3-green">
      <strong>Currently running:</strong> <code><%= @running_lab %></code>
      <a href="#" onclick="window.location.href = findLatestLog(); return false;"
         class="w3-button w3-small w3-white w3-margin-left">
        ▶ View Live Log
      </a>
    </div>
    <script>
      const logs = <%= JSON.generate(@log_files.map { |f| { file: f, mtime: File.mtime(f).to_i } }) %>;
      const runningLab = <%= JSON.generate(@running_lab) %>;
      
      function findLatestLog() {
        if (!runningLab) return '/logs';
        const filtered = logs.filter(l => l.file.includes(runningLab.replace(/\//g, '_')));
        if (filtered.length > 0) {
          filtered.sort((a, b) => b.mtime - a.mtime);
          return '/logs?file=' + encodeURIComponent(filtered[0].file);
        }
        return '/logs';
      }
    </script>
  <% end %>

  <h3>Recent Logs</h3>
  <% if @log_files.empty? %>
    <p>No logs found.</p>
  <% else %>
    <ul class="w3-ul w3-card-4">
      <% @log_files.each do |log| %>
        <%
          basename = File.basename(log, '.log')
          parts = basename.split('_')
          timestamp = parts[1].to_i rescue 0
          lab_name = parts[2..-2].join('_').gsub(/\.yml$/, '.yml') rescue 'Unknown Lab'
          action = parts.last == 'up' ? 'Start' : 'Stop'
          time_str = Time.at(timestamp).strftime('%Y-%m-%d %H:%M:%S') rescue 'Unknown time'
        %>
        <li>
          <strong><%= lab_name %></strong> 
          (<%= action %>) — <%= time_str %><br>
          <a href="/logs?file=<%= URI.encode_www_form_component(log) %>" class="w3-button w3-tiny w3-blue w3-round">View</a>
        </li>
      <% end %>
    </ul>
  <% end %>

  <br>
</div>
<%= FOOTER %>

@@logs_index
<%= HEADER %>
<div class="w3-panel w3-blue">
  <h2>Lab Logs</h2>
</div>

<div class="w3-container">

  <!-- Delete All Button -->
  <% if @log_files.any? %>
    <form method="post" action="/logs/delete-all" style="margin-bottom: 15px;" 
          onsubmit="return confirm('Delete ALL logs? This cannot be undone.')">
      <button type="submit" class="w3-button w3-red w3-tiny w3-round">
        🗑️ Delete All Logs
      </button>
    </form>
  <% end %>

  <% if @running_lab %>
    <div class="w3-panel w3-green">
      <strong>Currently running:</strong> <code><%= @running_lab %></code>
      <a href="#" onclick="window.location.href = findLatestLog(); return false;"
         class="w3-button w3-small w3-white w3-margin-left">
        ▶ View Live Log
      </a>
    </div>
    <script>
      const logs = <%= JSON.generate(@log_files.map { |f| { file: f, mtime: File.mtime(f).to_i } }) %>;
      const runningLab = <%= JSON.generate(@running_lab) %>;
      
      function findLatestLog() {
        if (!runningLab) return '/logs';
        const filtered = logs.filter(l => l.file.includes(runningLab.replace(/\//g, '_')));
        if (filtered.length > 0) {
          filtered.sort((a, b) => b.mtime - a.mtime);
          return '/logs?file=' + encodeURIComponent(filtered[0].file);
        }
        return '/logs';
      }
    </script>
  <% end %>

  <h3>Recent Logs</h3>
  <% if @log_files.empty? %>
    <p>No logs found.</p>
  <% else %>
    <ul class="w3-ul w3-card-4">
      <% @log_files.each do |log| %>
        <%
          basename = File.basename(log, '.log')
          parts = basename.split('_')
          timestamp = parts[1].to_i rescue 0
          lab_name = parts[2..-2].join('_').gsub(/\.yml$/, '.yml') rescue 'Unknown Lab'
          action = parts.last == 'up' ? 'Start' : 'Stop'
          time_str = Time.at(timestamp).strftime('%Y-%m-%d %H:%M:%S') rescue 'Unknown time'
        %>
        <li style="display: flex; justify-content: space-between; align-items: center;">
          <div>
            <strong><%= lab_name %></strong> 
            (<%= action %>) — <%= time_str %>
          </div>
          <div>
            <a href="/logs?file=<%= URI.encode_www_form_component(log) %>" 
               class="w3-button w3-tiny w3-blue w3-round">View</a>
            <form method="post" action="/logs/delete" style="display: inline;"
                  onsubmit="return confirm('Delete this log?')">
              <input type="hidden" name="file" value="<%= URI.encode_www_form_component(log) %>">
              <button type="submit" class="w3-button w3-tiny w3-red w3-round">🗑️</button>
            </form>
          </div>
        </li>
      <% end %>
    </ul>
  <% end %>

  <br>
</div>
<%= FOOTER %>
