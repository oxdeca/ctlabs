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


#
# HELPERS
#
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
    Lab.running?
  end
  
  def get_running_lab
    Lab.current_name
  end
#  
#  def set_running_lab(lab_name)
#    File.write(LOCK_FILE, lab_name)
#  end
#  
#  def clear_running_lab
#    File.delete(LOCK_FILE) if File.file?(LOCK_FILE)
#  end

  def parse_lab_info(yaml_file_path, adhoc_rules_by_lab = {})
    require 'yaml'
    require 'set'
  
    lab             = Lab.new(cfg: yaml_file_path)
    info            = {}
    info[:lab_name] = File.basename(yaml_file_path, '.yml')
    info[:desc]     = lab.desc || ''
  
    images = []
    lab.defaults.each do |tk, tv|
      tv.each do |kk, kv|
        images << {type: tk, kind: kk, image: kv['image']}
      end
    end
    info[:images] = images
  
    nodes = []
    lab.nodes.each do |node|
      if node.type != "gateway"
        #p lab.defaults[node.type][node.kind || 'linux']['image'] || 'N/A',
        node_info = {
          name: node.name,
          type: node.type   || 'N/A',
          kind: node.kind   || 'N/A',
          image: lab.defaults[node.type][node.kind || 'linux']['image'] || 'N/A',
          cpus: 'N/A',
          memory: 'N/A',
        }
        nodes << node_info
      end
    end

    info[:nodes] = nodes
  
    ansible_info = {}
    ctrl = lab.find_node("ansible")
    #p ctrl
    if ! ctrl.play.nil?
      ansible_info[:playbook]    = ctrl.play['book']
      ansible_info[:environment] = ctrl.play['env'] || []
      ansible_info[:tags]        = ctrl.play['tags']
      ansible_info[:roles]       = ctrl.play['tags']
    end
    #p "here"
    #p ansible_info
    info[:ansible] = ansible_info

    vip  = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).rstrip
    exposed_ports = []
    lab.nodes.each do |node|
      if (defined? node.dnat) && ! node.dnat.nil? && (node.type.include?('host') || node.type.include?('controller'))
        node.dnat.each do |p|
          rip = ""
          if node.type == 'controller'
            rip = node.nics['eth0'].split('/').first
          else
            rip = node.nics['eth1'].split('/').first
          end
          node_info = {
            node: node.name,
            type: node.type,
            proto: p[2] || 'tcp',
            external_port: "#{vip}:#{p[0]}",
            internal_port: "#{rip}:#{p[1]}",
          }
          exposed_ports << node_info
        end
      end
    end

    adhoc_rules = []
    # Always try to load from disk if lab is running
    if running_lab? && yaml_file_path.sub(LABS_DIR + '/', '') == get_running_lab
      lab_name_safe = get_running_lab.gsub(/\//, '_').gsub(/[^a-zA-Z0-9_.\-]/, '')
      adhoc_file = "#{LOCK_DIR}/adhoc_dnat_#{lab_name_safe}.json"
      if File.file?(adhoc_file)
        begin
          adhoc_rules = JSON.parse(File.read(adhoc_file), :symbolize_names => true)
        rescue JSON::ParserError
          adhoc_rules = []
        end
      end
    end
    
    #if session && session[:adhoc_dnat_rules]
    #  current_lab_name = yaml_file_path.sub(LABS_DIR + '/', '')
    #  adhoc_rules = session[:adhoc_dnat_rules][current_lab_name] || []
    #end
    # Mark them as adhoc and merge
    adhoc_rules.each do |dr|
      exposed_ports << dr.merge(adhoc: true)
    end

    info[:exposed_ports] = exposed_ports
  
    #puts "DEBUG: Generated lab info hash: #{info.inspect}"
    return info
  rescue => e
    #puts "DEBUG: Error processing lab info for #{yaml_file_path}: #{e.message}"
    #puts e.backtrace.join("\n") # Print the backtrace for more detail
    { error: "Error processing lab info: #{e.message}" }
  end

  #
  #
  #
  def render_lab_info_card(info_hash)
    # This is a simplified example using ERB directly within Ruby code.
    # A more robust approach might involve separate .erb partials.
    template = %q(
<% if info_hash[:error] %>
  <div class="w3-panel w3-red">
    <h4>Error Loading Lab Info</h4>
    <p><%= info_hash[:error] %></p>
  </div>
<% else %>
  <div class="w3-panel w3-card w3-flat-midnight-blue">
    <h4>Info: <code><%= info_hash[:lab_name] %></code></h4>
    <div><%= info_hash[:desc] %></div>

    <!-- Two-column layout -->
    <div class="w3-row-padding w3-margin-top">
      <!-- LEFT COLUMN: Nodes + Ansible -->
      <div class="w3-col s12 m6 l6">
        <!-- Nodes Card -->
        <div class="w3-card w3-white w3-margin-bottom">
          <div class="w3-container w3-green">
            <h5>Nodes</h5>
          </div>
          <div class="w3-container w3-padding w3-flat-wet-asphalt">
            <table class="w3-table w3-bordered w3-striped">
              <thead>
                <tr><th>Name</th><th>Type</th><th>Kind</th><th>Image</th><th>CPUs</th><th>Mem</th></tr>
              </thead>
              <tbody>
                <% info_hash[:nodes].each do |node| %>
                  <tr>
                    <td><code><%= node[:name] %></code></td>
                    <td><%= node[:type] %></td>
                    <td><%= node[:kind] %></td>
                    <td><%= node[:image] %></td>
                    <td><%= node[:cpus] %></td>
                    <td><%= node[:memory] %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Ansible Card -->
        <div class="w3-card w3-white">
          <div class="w3-container w3-purple">
            <h5>Ansible</h5>
          </div>
          <div class="w3-container w3-padding">
            <table class="w3-table w3-bordered w3-striped">
              <tr>
                <th>Playbook:</th>
                <td><%= info_hash[:ansible][:playbook] %></td>
              </tr>
              <tr>
                <th>Environment:</th>
                <td>
                  <% info_hash[:ansible][:environment].each do |e| %>
                    <%= e %><br>
                  <% end %>
                </td>
              </tr>
              <tr>
                <th>Tags:</th>
                <td>
                  <% info_hash[:ansible][:tags].each do |t| %>
                    <%= t %><br>
                  <% end %>
                </td>
              </tr>
            </table>
          </div>
        </div>
      </div>

      <!-- RIGHT COLUMN: Images + Exposed Ports -->
      <div class="w3-col s12 m6 l6">
        <!-- Images Card -->
        <div class="w3-card w3-white w3-margin-bottom">
          <div class="w3-container w3-blue">
            <h5>Images</h5>
          </div>
          <div class="w3-container w3-padding">
            <% if info_hash[:images].empty? %>
              <p>No images defined</p>
            <% else %>
              <table class="w3-table w3-bordered w3-striped">
                <thead>
                  <tr><th>Type</th><th>Kind</th><th>Image</th></tr>
                </thead>
                <tbody>
                  <% info_hash[:images].each do |img| %>
                    <tr>
                      <td><%= img[:type] %></td>
                      <td><%= img[:kind] %></td>
                      <td><%= img[:image] %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>

        <!-- Exposed Ports Card -->
        <div class="w3-card w3-white">
          <div class="w3-container w3-deep-orange">
            <h5>Exposed Ports (DNAT)</h5>
          </div>
          <div class="w3-container w3-padding">
            <% if info_hash[:exposed_ports].empty? %>
              <p>None Defined</p>
            <% else %>
              <table id="dnat_table" class="w3-table w3-bordered w3-striped">
                <thead>
                  <tr><th>Node</th><th>Type</th><th>Protocol</th><th>Rule</th></tr>
                </thead>
                <tbody>
                  <% info_hash[:exposed_ports].each do |port| %>
                    <tr style="<%= 'background-color:#f0f8ff;' if port[:adhoc] %>">
                      <td><%= port[:node] %></td>
                      <td><%= port[:type] %></td>
                      <td><%= port[:proto] %></td>
                      <td>
                        <%= port[:external_port] %> ➡ <%= port[:internal_port] %>
                        <% if port[:adhoc] %>
                          <span style="color:#ff6f00; font-size:0.8em; margin-left:6px;">(adhoc)</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
          <div id="me" class="w3-container w3-padding">
            <!-- AdHoc DNAT Form -->
            <% if @selected_lab && running_lab? && @selected_lab == get_running_lab %>
              <h6>Add AdHoc DNAT Rule</h6>
              <form id="adhoc-dnat-form" method="POST" action="/labs/<%= URI.encode_www_form_component(@selected_lab) %>/dnat" class="w3-row-padding">
                <!-- hidden input for lab name is not needed since it's in URL -->
                <input type="hidden" name="lab_name" value="<%= @selected_lab %>"> <!-- optional, for validation -->
                <div class="w3-col s12 m4 l4 w3-margin-bottom">
                  <select name="node" class="w3-select w3-border" required>
                    <option value="">-- Select Node --</option>
                    <% info_hash[:nodes].each do |n| %>
                      <% if n[:type] == 'host' || n[:type] == 'controller' %>
                        <option value="<%= n[:name] %>"><%= n[:name] %> (<%= n[:type] %>)</option>
                      <% end %>
                    <% end %>
                  </select>
                </div>
                <div class="w3-col s6 m2 l2 w3-margin-bottom">
                  <input type="number" name="external_port" placeholder="Ext Port" min="1" max="65535" class="w3-input w3-border" required>
                </div>
                <div class="w3-col s6 m2 l2 w3-margin-bottom">
                  <input type="number" name="internal_port" placeholder="Int Port" min="1" max="65535" class="w3-input w3-border" required>
                </div>
                <div class="w3-col s6 m2 l1 w3-margin-bottom">
                  <select name="protocol" class="w3-select w3-border">
                    <option value="tcp">TCP</option>
                    <option value="udp">UDP</option>
                  </select>
                </div>
                <div class="w3-col s6 m2 l1 w3-margin-bottom">
                  <button type="submit" class="w3-button w3-blue w3-round">➕ Add</button>
                </div>
              </form>
              <div id="adhoc-dnat-result" class="w3-panel" style="display:none;"></div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
  </div>
<% end %>
  
  <% if @selected_lab && running_lab? && @selected_lab == get_running_lab %>
  <script>
  document.getElementById('adhoc-dnat-form')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const formData = new FormData(e.target);
    const labName = formData.get('lab_name');
    const url = `/labs/${encodeURIComponent(labName)}/dnat`;
  
    // Send as application/x-www-form-urlencoded
    const params = new URLSearchParams(formData).toString();
  
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params
    });
  
    const resultDiv = document.getElementById('adhoc-dnat-result');
    const dnatTableBody = document.querySelector('#dnat_table tbody');

    if (res.ok) {
      const data = await res.json(); // ← still return JSON *response*, but send form data
      resultDiv.className = 'w3-panel w3-green';
      resultDiv.textContent = '✅ ' + data.message;
      
      // If rule data is returned, add it to the table
      if (data.rule && dnatTableBody) {
        const row = document.createElement('tr');
        
        // Optional: add a subtle style to indicate it's adhoc 
        row.style.backgroundColor = '#f0f8ff'; // light blue tint
        // Or add a class: row.classList.add('adhoc-rule');
  
        row.innerHTML = `
          <td>${data.rule.node}</td>
          <td>${data.rule.type}</td>
          <td>${data.rule.proto}</td>
          <td>
            ${data.rule.external_port} ➡ ${data.rule.internal_port}
            <span style="color:#ff6f00; font-size:0.8em; margin-left:6px;">(adhoc)</span>
          </td>
        `;
        dnatTableBody.appendChild(row);
      }
    } else {
      const err = await res.json().catch(() => ({error: 'Unknown error'}));
      resultDiv.className = 'w3-panel w3-red';
      resultDiv.textContent = '❌ ' + (err.error || 'Failed');
    }
    resultDiv.style.display = 'block';
  });
  </script>
<% end %>)
  
    # Use ERB to render the template with the provided hash
    erb_template = ERB.new(template)
    # Bind the local variable 'info_hash' within the ERB context
    # We need to pass the info_hash into the binding somehow.
    # A common way is to use instance variables or a more complex binding setup.
    # For simplicity here, let's assume the template is self-contained regarding variables.
    # A better way might be to pass it as a local variable using :locals
    # But ERB.new doesn't directly support :locals like Sinatra's erb() does.
    # We can use a binding trick or use a method like Sinatra's internal rendering.
    # Let's use the instance variable approach by setting it temporarily.
    old_info_hash = instance_variable_get("@info_hash")
    instance_variable_set("@info_hash", info_hash)
    result = erb_template.result(binding)
    # Restore the old value if it existed
    if old_info_hash
      instance_variable_set("@info_hash", old_info_hash)
    else
      remove_instance_variable("@info_hash") if instance_variable_defined?("@info_hash")
    end
    result
  end
end


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

# In server.rb, inside ROUTES section

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

    # Optional: log it
    timestamp      = Time.now  #.strftime('%Y-%m-%d %H:%M:%S')
    safe_lab       = lab_name.gsub(/\//, '_').gsub(/[^a-zA-Z0-9_.\-]/, '')

    log_entry      = "[#{timestamp.strftime('%Y-%m-%d %H:%M:%S')}] AdHoc DNAT #{lab_name}: #{rule}\n"
    adhoc_file     = "#{LOCK_DIR}/adhoc_dnat_#{safe_lab}.json"
    adhoc_log_file = "#{LOG_DIR}/ctlabs_#{timestamp.to_i}_#{safe_lab}_adhoc.log"
    File.open(adhoc_log_file, 'a') { |f| f.write(log_entry) }

    # Load existing rules (if any)
    existing = []
    if File.file?(adhoc_file)
      begin
        existing = JSON.parse(File.read(adhoc_file), :symbolize_names => true)
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

    # Return success as plain text or redirect — but since we're using AJAX, return JSON *response*
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
  else # action == 'down'
    unless Lab.running?
      halt 400, "No lab is currently running."
    end
    lab_name = Lab.current_name
    labs_list = all_labs
    halt 500, "Running lab not found in lab list: #{lab_name}" unless labs_list.include?(lab_name)

    # Clean up ad-hoc DNAT session data
    if session[:adhoc_dnat_rules] && session[:adhoc_dnat_rules].key?(lab_name)
      session[:adhoc_dnat_rules].delete(lab_name)
    end

    # Clean up ad-hoc DNAT file
    if lab_name
      lab_name_safe = lab_name.gsub(/\//, '_').gsub(/[^a-zA-Z0-9_.\-]/, '')
      adhoc_file = "#{LOCK_DIR}/adhoc_dnat_#{lab_name_safe}.json"
      File.delete(adhoc_file) if File.file?(adhoc_file)
    end
  end

  lab_file_path = File.join(LABS_DIR, lab_name)
  timestamp     = Time.now.to_i
  safe_lab      = lab_name.gsub(/\//, '_').gsub(/[^a-zA-Z0-9_.\-]/, '')
  log_file_path = "#{LOG_DIR}/ctlabs_#{timestamp}_#{safe_lab}_#{action}.log"

  # Write initial line to log file
  File.open(log_file_path, 'w') do |f|
    f.puts "Starting '#{action}' for lab: #{lab_name} (File: #{lab_file_path})"
  end

  # --- Background Thread ---
  Thread.new do
    begin
      File.open(log_file_path, 'a') do |log_file_handle|
        log = LabLog.new(out: log_file_handle, level: 'info')
        log.info "--- Background Thread Started ---"

        # 🔑 Pass relative_path = lab_name (e.g., "net/net01.yml")
        lab_instance = Lab.new(
          cfg: lab_file_path,
          relative_path: lab_name,
          log: log
        )

        if action == 'up'
          lab_instance.visualize
          lab_instance.inventory
          lab_instance.up
          log.info "--- Lab #{lab_name} UP Operation Completed ---"
          lab_instance.run_playbook(true, log_file_path)
          log.info "--- Lab #{lab_name} Ansible Operation Completed ---"
        elsif action == 'down'
          lab_instance.down
          log.info "--- Lab #{lab_name} DOWN Operation Completed ---"
        end

        log.info "--- Background Thread Finished ---"
      end

    rescue => e
      # Log error even if main block fails
      File.open(log_file_path, 'a') do |f|
        error_msg = "Error in background thread executing '#{action}' for lab '#{lab_name}': #{e.message}\n#{e.backtrace.join("\n")}"
        f.puts error_msg

        # Clean up lock on up-failure
        if action == 'up' && Lab.running? && Lab.current_name == lab_name
          Lab.release_lock!
          f.puts "--- Cleared lock for failed 'up' operation for #{lab_name} ---"
        end
      end
    end
  end

  redirect "/logs?file=#{URI.encode_www_form_component(log_file_path)}&lab=#{lab_name}&action=#{action}"
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
<!--      <a href="/labs"      class="w3-bar-item w3-button">🧪 Labs</a> -->
      <a href="/topo"      class="w3-bar-item w3-button">🗺️ Topology</a>
      <a href="/con"       class="w3-bar-item w3-button">🕸 Connections</a>
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
  </body>
</html>
)

__END__


@@home
<%= HEADER %>
    <div id="con" class="w3-panel w3-green">
      <h2>🕸 Connections [Data Network] </h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <span>Zoom: <strong><span id="zoom-value-con">100</span>%</strong></span></br>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="con-embed">
      </div>
      <div class="svg-container">
        <embed id="con-embed" src="con.svg" class="w3-round responsive-embed" alt="🕸 Connections" type="image/svg+xml" width="100%">
      </div>
    </div>
    <div id="topo" class="w3-panel w3-green">
      <h2>🗺️ Topology [Data Network]</h2>
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
      <h2>🕸 Connections [Data Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="con-embed">
        <span>Zoom: <strong><span id="zoom-value-con">100</span>%</strong></span>
      </div>
      <div class="svg-container">
        <embed id="con-embed" src="con.svg" class="w3-round responsive-embed" alt="🕸 Connections" type="image/svg+xml" width="100%">
      </div>
    </div>
    <div id="mgmt_con" class="w3-panel w3-green">
      <h2>🕸 Connections [Management Network] </h2>
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
      <h2>🗺️ Topology [Data Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="topo-embed">
        <span>Zoom: <strong><span id="zoom-value-topo">100</span>%</strong></span>
      </div>
      <div class="svg-container">
        <embed id="topo-embed" src="topo.svg" class="w3-round responsive-embed" alt="🗺 Topology" type="image/svg+xml" width="100%">
      </div>
    </div>
    <div id="mgmt_topo" class="w3-panel w3-green">
      <h2>🗺️ Topology [Management Network]</h2>
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
    <!-- Constrain total height to viewport, similar to live_log -->
    <div class="w3-container" style="height: calc(100vh - 120px); display: flex; flex-direction: column; overflow: hidden;"> <!-- Adjust calc value if needed -->
      <!-- Main card/container for the demo player -->
      <div class="w3-card-4 w3-2021-inkwell" style="flex: 1; display: flex; flex-direction: column; min-height: 0; overflow: hidden; padding: 8px;"> <!-- Added padding -->
        <!-- Container specifically for the Asciinema player -->
        <div id="demo-container" style="flex: 1; display: flex; align-items: stretch; justify-content: center; overflow: hidden;"> <!-- New container div -->
          <div id="demo" style="flex: 1; height: 100%; width: 100%;"> <!-- Target div for Asciinema, fills its container -->
            <!-- Asciinema player will be injected here -->
          </div>
        </div>
      </div>
    </div>

    <script src="/asciinema-player.min.js"></script>
    <script>
      // Wait for the DOM to be fully loaded before initializing the player
      document.addEventListener('DOMContentLoaded', function() {
        // Get the target div
        const demoDiv = document.getElementById('demo');

        // Create the player, targeting the 'demo' div
        // Pass configuration options to influence sizing
        AsciinemaPlayer.create('/demo.cast', demoDiv, {
          // --- Player Sizing Options ---
          cols: null, // Let the player determine based on container/recording width
          rows: null, // Let the player determine based on container/recording height
          // fit: "width", // Alternative: fit only width, height adapts
          // fit: "height", // Alternative: fit only height, width adapts (might distort)
          fit: "both", // Default behavior might be similar, but explicit 'both' can sometimes help
          // autoFit: true, // Check Asciinema docs - this might be the key option if supported
          // --- Other Common Options ---
          // autoplay: true, // Start playing automatically
          // loop: false,    // Loop the playback
          // startAt: 0,     // Start time in seconds
          // poster: "npt:0", // Poster frame (e.g., at start)
          // fontSize: "small", // Font size ("small", "normal", "big")
          // theme: "dracula", // Color theme
          // terminalFontFamily: "Monaco, Courier New", // Custom font
          // terminalLineHeight: 1.3, // Line height multiplier
          // terminalPadding: "4px", // Padding around terminal content
        });
      });
    </script>
<%= FOOTER %>

@@demo_old
<%= HEADER %>
    <div class="w3-panel w3-green">
      <h2>📹 Walkthrough </h2>
    </div>
    <div id="demo" class="w3-container w3-card-4 w3-2021-inkwell" style="max-width: 100%; max-height: 95%; overflow: auto;">
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
<div class="w3-container w3-card-4 w3-padding w3-2021-inkwell">
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

<!-- Lab Info Card Section -->
<div id="lab-info-section" class="w3-container w3-2021-inkwell w3-round">
  <% if @lab_info %>
    <%= render_lab_info_card(@lab_info) %> <!-- Use the helper -->
  <% else %>
    <div id="lab-info-placeholder" class="w3-panel w3-light-grey">
      <p>Select a lab to view its details.</p>
    </div>
  <% end %>
</div>

<br>
<script>
  document.addEventListener('DOMContentLoaded', () => {
    const lastLog = localStorage.getItem('ctlabs_last_log');
    const selectElement = document.getElementById('lab-selector');
    const infoSection = document.getElementById('lab-info-section');

    if (lastLog && selectElement) {
      try {
        const { lab } = JSON.parse(lastLog);
        if (Array.from(selectElement.options).some(opt => opt.value === lab)) {
          selectElement.value = lab;
          // Trigger change event to update info card if needed
          // This might be redundant if the server already rendered the info,
          // but ensures client-side update if selection changes externally.
          selectElement.dispatchEvent(new Event('change'));
        }
      } catch (e) {
        console.warn('Failed to parse last log:', e);
      }
    }
    selectElement.addEventListener('change', function() {
      const selectedLab = this.value;
      if (selectedLab) {
        // Show a loading message or spinner
        infoSection.innerHTML = '<div class="w3-panel w3-flat-midnight-blue"><p>Loading lab info...</p></div>';
    
        // Fetch the new lab info card HTML via AJAX
        fetch(`/labs/${encodeURIComponent(selectedLab)}/info_card`) // New route
          .then(response => {
              if (!response.ok) {
                  throw new Error(`HTTP error! status: ${response.status}`);
              }
              return response.text(); // Get the HTML string
          })
          .then(htmlFragment => {
              // Directly inject the rendered HTML
              infoSection.innerHTML = htmlFragment;
          })
          .catch(error => {
              console.error('Error fetching lab info card:', error);
              infoSection.innerHTML = '<div class="w3-panel w3-red"><h4>Error</h4><p>Could not load lab info.</p></div>';
          });
      }
    })
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
<div class="w3-container" style="height: calc(100vh - 130px); display: flex; flex-direction: column;">
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
<div class="w3-container w3-2021-inkwell">
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

<div class="w3-container w3-2021-inkwell">


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
    <ul class="w3-ul w3-card-4 w3-hoverable w3-2021-inkwell">
      <% @log_files.each do |log| %>
        <%
          basename    = File.basename(log, '.log')
          parts       = basename.split('_')
          timestamp   = parts[1].to_i rescue 0
          lab_name    = parts[2..-2].join('_').gsub(/\.yml$/, '.yml') rescue 'Unknown Lab'
          action_part = parts.last
          action      = case action_part
            when 'up' then 'Start'
            when 'down' then 'Stop'
            when 'adhoc' then 'AdHoc'
            else 'Unknown'
          end
          #action      = parts.last == 'up' ? 'Start' : 'Stop'
          time_str  = Time.at(timestamp).strftime('%Y-%m-%d %H:%M:%S') rescue 'Unknown time'
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
  <!-- Delete All Button -->
  <% if @log_files.any? %>
    <form method="post" action="/logs/delete-all" style="margin-bottom: 15px;" 
          onsubmit="return confirm('Delete ALL logs? This cannot be undone.')">
      <button type="submit" class="w3-button w3-red w3-tiny w3-round w3-right">
        🗑️ Delete All Logs
      </button>
    </form>
  <% end %>

  <br>
</div>
<%= FOOTER %>
