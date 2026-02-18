# -----------------------------------------------------------------------------
# File        : ctlabs/helpers/application_helper.rb
# Description : app helper
# License     : MIT License
# -----------------------------------------------------------------------------

# Copy ALL helpers from server.rb's `helpers do ... end` block here
module ApplicationHelper
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

  def parse_lab_info(yaml_file_path, adhoc_rules_by_lab = {})
    require 'yaml'
    require 'set'
  
    lab             = Lab.new(cfg: yaml_file_path, log: LabLog.null)
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