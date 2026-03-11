# -----------------------------------------------------------------------------
# File        : ctlabs/helpers/application_helper.rb
# Description : app helper
# License     : MIT License
# -----------------------------------------------------------------------------

module ApplicationHelper
  def ansi_to_html(text)
    color_map = {
      '30' => '#000',   '31' => '#a00',   '32' => '#0a0',   '33' => '#aa0',
      '34' => '#00a',   '35' => '#a0a',   '36' => '#0aa',   '37' => '#aaa',
      '90' => '#555',   '91' => '#f55',   '92' => '#5f5',   '93' => '#ff5',
      '94' => '#55f',   '95' => '#f5f',   '96' => '#5ff',   '97' => '#fff',
    }

    html = ''
    current_color = nil

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
        html += ERB::Util.h(part)
      end
    end

    html += '</span>' if current_color
    html 
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

    lab_name = yaml_file_path.sub(LABS_DIR + '/', '')
    runtime_path = "#{LOCK_DIR}/#{lab_name.gsub('/', '_')}.yml"
    is_running = running_lab? && get_running_lab == lab_name
    
    actual_path = (is_running && File.file?(runtime_path)) ? runtime_path : yaml_file_path

    # Load runtime lab and base lab to compute the diff!
    lab = Lab.new(cfg: actual_path, log: LabLog.null)
    base_lab = is_running ? Lab.new(cfg: yaml_file_path, log: LabLog.null) : lab

    # Map base nodes and base DNATs for comparison
    base_nodes_list = base_lab.nodes.map(&:name)
    base_dnats = {}
    base_lab.nodes.each { |n| base_dnats[n.name] = n.dnat || [] }

    info = { lab_name: File.basename(yaml_file_path, '.yml'), lab_path: lab_name, desc: lab.desc || '' }

    # Images Map
    images = []
    images_map = {}
    if lab.defaults
      lab.defaults.each do |tk, tv|
        if tv.is_a?(Hash)
          images_map[tk] = tv.keys
          tv.each do |kk, kv|
            images << {type: tk, kind: kk, image: (kv && kv['image']) ? kv['image'] : 'N/A'}
          end
        else
          images_map[tk] = []
        end
      end
    end
    info[:images] = images
    info[:images_map] = images_map

    # Nodes (With Diffing)
    nodes = []
    if lab.nodes
      lab.nodes.each do |node|
        if node.type != "gateway"
          image_ref = 'N/A'
          if lab.defaults && lab.defaults[node.type] && lab.defaults[node.type][node.kind || 'linux']
            image_ref = lab.defaults[node.type][node.kind || 'linux']['image'] || 'N/A'
          end
          
          # If it's not in the base YAML, it was added AdHoc!
          is_adhoc = !base_nodes_list.include?(node.name)

          # Real-time Podman / Docker Health Check
          cmd = "/usr/bin/podman inspect -f '{{.State.Running}}' #{node.name} 2>&1"
          raw_output = `#{cmd}`.strip
          
          # Fallback to docker if podman is missing entirely
          if raw_output.include?("No such file") || raw_output.empty?
            raw_output = `docker inspect -f '{{.State.Running}}' #{node.name} 2>/dev/null`.strip
          end

          # Bulletproof boolean check (ignores hidden characters/quotes)
          container_running = raw_output.to_s.downcase.include?('true')

          node_info = {
            name: node.name,
            type: node.type   || 'N/A',
            kind: node.kind   || 'N/A',
            image: image_ref,
            cpus: 'N/A',
            memory: 'N/A',
            adhoc: is_adhoc,
            running: container_running
          }
          nodes << node_info
        end
      end
    end

    info[:nodes] = nodes
    info[:switches] = lab.nodes.select { |n| n.type == 'switch' }.map(&:name)

    # Ansible
    ansible_info = { playbook: 'N/A', environment: [], tags: [], roles: [] }
    ctrl = lab.find_node("ansible")
    if ctrl && !ctrl.play.nil?
      if ctrl.play.is_a?(Hash)
        ansible_info[:playbook]    = ctrl.play['book'] || 'N/A'
        ansible_info[:environment] = ctrl.play['env'] || []
        ansible_info[:tags]        = ctrl.play['tags'] || []
        ansible_info[:roles]       = ctrl.play['roles'] || ctrl.play['tags'] || []
      else
        ansible_info[:playbook]    = ctrl.play.to_s
      end
    end
    info[:ansible] = ansible_info

    # DNAT (With Diffing)
    vip  = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).rstrip
    exposed_ports = []
    if lab.nodes
      lab.nodes.each do |node|
        if (defined? node.dnat) && ! node.dnat.nil? && (node.type.include?('host') || node.type.include?('controller'))
          node.dnat.each do |p|
            
            # Check if this exact rule exists in the base YAML
            base_rule_exists = base_dnats[node.name] && base_dnats[node.name].any? { |bp| p[0].to_s == bp[0].to_s && p[1].to_s == bp[1].to_s && (p[2] || 'tcp').to_s == (bp[2] || 'tcp').to_s }
            is_adhoc_dnat = !base_rule_exists

            rip = ""
            if node.type == 'controller'
              rip = node.nics['eth0'].split('/').first if node.nics && node.nics['eth0']
            else
              rip = node.nics['eth1'].split('/').first if node.nics && node.nics['eth1']
            end
            
            node_info = {
              node: node.name,
              type: node.type,
              proto: p[2] || 'tcp',
              external_port: "#{vip}:#{p[0]}",
              internal_port: "#{rip || 'N/A'}:#{p[1]}",
              adhoc: is_adhoc_dnat
            }
            exposed_ports << node_info
          end
        end
      end
    end

    info[:exposed_ports] = exposed_ports
    return info
  rescue => e
    { error: "Error processing lab info: #{e.message}" }
  end

  def render_lab_info_card(info_hash)
    template = %q(
<% if info_hash[:error] %>
  <div class="w3-panel w3-red w3-round-large">
    <h4><i class="fas fa-exclamation-triangle"></i> Error Loading Lab Info</h4>
    <p><%= info_hash[:error] %></p>
  </div>
<% else %>
  <div class="w3-panel w3-round-large" style="background-color: #1e293b; padding: 20px;">
    <div style="border-bottom: 1px solid #334155; padding-bottom: 15px; margin-bottom: 20px;">
      <h3 style="margin:0; font-weight: 600; color: #38bdf8;">
        <i class="fas fa-flask"></i> <%= info_hash[:lab_name] %>
      </h3>
      <span style="color: #94a3b8; font-size: 0.95em;"><%= info_hash[:desc] %></span>
    </div>

    <div class="w3-row-padding" style="margin: 0 -16px;">
      <div class="w3-col s12 m6 l6">

        <div class="w3-card w3-round-large w3-margin-bottom" style="background-color: #0f172a; overflow:hidden;">
          <div class="w3-padding" style="background-color: #334155; color: #fff; font-weight: 500; display:flex; justify-content:space-between; align-items:center;">
            <span><i class="fas fa-server"></i> Active Nodes</span>
          </div>
          <div class="w3-padding">
            <table class="w3-table w3-striped w3-small" id="nodes_table">
              <thead>
                <tr style="color: #94a3b8;">
                  <th style="width: 30px; text-align: center;"><i class="fas fa-heartbeat"></i></th>
                  <th>Name</th>
                  <th>Type</th>
                  <th>Kind</th>
                  <th>Image</th>
                  <th style="text-align:right;">Actions</th>
                </tr>
              </thead>
              <tbody>
                <% (info_hash[:nodes] || []).each do |node| %>
                  <tr style="<%= 'background-color:rgba(59, 130, 246, 0.1);' if node[:adhoc] %>">
                    
                    <td style="text-align: center; vertical-align: middle;">
                      <% if node[:running] %>
                        <span title="Running" style="color: #10b981; text-shadow: 0 0 8px rgba(16, 185, 129, 0.8);">
                          <i class="fas fa-circle" style="font-size: 0.8em;"></i>
                        </span>
                      <% else %>
                        <span title="Stopped / Missing" style="color: #ef4444; opacity: 0.7;">
                          <i class="fas fa-circle" style="font-size: 0.8em;"></i>
                        </span>
                      <% end %>
                    </td>

                    <td>
                      <strong style="color: #38bdf8;"><%= node[:name] %></strong>
                      <% if node[:adhoc] %>
                        <span style="color:#f59e0b; font-size:0.75em; margin-left:4px; font-weight: bold;">(adhoc)</span>
                      <% end %>
                    </td>
                    <td><span class="w3-badge w3-tiny w3-round" style="background-color: #475569;"><%= node[:type] %></span></td>
                    <td><%= node[:kind] %></td>
                    <td style="color: #cbd5e1;"><%= node[:image] %></td>
                    <td style="text-align:right;">
                      <button type="button" onclick="window.editNodeConfig('<%= info_hash[:lab_path] %>', '<%= node[:name] %>')" class="w3-button w3-tiny w3-round w3-blue" style="padding: 2px 8px;">
                        <i class="fas fa-edit"></i> Edit
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div class="w3-padding" style="border-top: 1px solid #334155; background-color: rgba(0,0,0,0.2); text-align: center;">
            <% if get_running_lab == info_hash[:lab_path] %>
              <button onclick="window.openAddNodeModal('<%= info_hash[:lab_path] %>')" class="w3-button w3-blue w3-small w3-round">
                <i class="fas fa-plus"></i> Add AdHoc Node
              </button>
            <% end %>
          </div>
        </div>

        <div id="add-node-modal" class="w3-modal" style="z-index: 9999;">
          <div class="w3-modal-content w3-round-large w3-card-4" style="background-color: #1e293b; color: #f8fafc; max-width: 500px;">
            <header class="w3-container w3-padding" style="border-bottom: 1px solid #334155; background-color: #0f172a; border-radius: 12px 12px 0 0;">
              <span onclick="document.getElementById('add-node-modal').style.display='none'" class="w3-button w3-display-topright w3-hover-red w3-round" style="color: #cbd5e1;">&times;</span>
              <h4 style="margin: 0;"><i class="fas fa-plus-circle"></i> Add AdHoc Node</h4>
            </header>
            
            <form id="adhoc-node-form" onsubmit="window.submitAdhocNode(event)">
              <div class="w3-container w3-padding">
                <input type="hidden" name="lab_name" id="add-node-lab-name">
                
                <div class="w3-margin-bottom">
                  <label style="font-size: 0.85em; color: #94a3b8;">Node Name</label>
                  <input type="text" name="node_name" placeholder="e.g. h3" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;" required>
                </div>

                <div class="w3-row-padding" style="margin: 0 -8px;">
                  <div class="w3-col m6 w3-margin-bottom">
                    <label style="font-size: 0.85em; color: #94a3b8;">Type</label>
                    <select name="type" class="w3-select w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;" onchange="window.updateKindOptions(this.value)" required>
                      <option value="" disabled selected>-- Select Type --</option>
                      <% (info_hash[:images_map] || {}).keys.each do |t| %>
                        <option value="<%= t %>"><%= t %></option>
                      <% end %>
                    </select>
                  </div>
                  <div class="w3-col m6 w3-margin-bottom">
                    <label style="font-size: 0.85em; color: #94a3b8;">Kind</label>
                    <select name="kind" id="add-node-kind" class="w3-select w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;" required>
                      <option value="" disabled selected>-- Select Kind --</option>
                    </select>
                  </div>
                </div>

                <div class="w3-margin-bottom">
                  <label style="font-size: 0.85em; color: #94a3b8;">Connect to Switch (Data Network)</label>
                  <select name="switch" class="w3-select w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
                    <option value="" selected>-- None (Mgmt Only) --</option>
                    <% (info_hash[:switches] || []).each do |sw| %>
                      <option value="<%= sw %>"><%= sw %></option>
                    <% end %>
                  </select>
                </div>

                <div class="w3-row-padding" style="margin: 0 -8px;">
                  <div class="w3-col m6 w3-margin-bottom">
                    <label style="font-size: 0.85em; color: #94a3b8;">Data IP Address (Optional)</label>
                    <input type="text" name="ip" placeholder="e.g. 192.168.10.20/24" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
                  </div>
                  <div class="w3-col m6 w3-margin-bottom">
                    <label style="font-size: 0.85em; color: #94a3b8;">Default Gateway (Optional)</label>
                    <input type="text" name="gw" placeholder="e.g. 192.168.10.1" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
                  </div>
                </div>

                <div id="adhoc-node-result" class="w3-panel w3-round" style="display:none; font-size: 0.9em; padding: 8px; margin-bottom: 0;"></div>
              </div>
              <footer class="w3-container w3-padding" style="border-top: 1px solid #334155; background-color: #0f172a; border-radius: 0 0 12px 12px; text-align: right;">
                <button type="button" onclick="document.getElementById('add-node-modal').style.display='none'" class="w3-button w3-round w3-small" style="background-color: #475569;">Cancel</button>
                <button type="submit" class="w3-button w3-blue w3-round w3-small"><i class="fas fa-play"></i> Start Node</button>
              </footer>
            </form>
          </div>
        </div>

        <div id="node-editor-modal" class="w3-modal" style="z-index: 9999;">
          <div class="w3-modal-content w3-round-large w3-card-4" style="background-color: #1e293b; color: #f8fafc; max-width: 600px;">
            <header class="w3-container w3-padding" style="border-bottom: 1px solid #334155; background-color: #0f172a; border-radius: 12px 12px 0 0;">
              <span onclick="document.getElementById('node-editor-modal').style.display='none'" class="w3-button w3-display-topright w3-hover-red w3-round" style="color: #cbd5e1;">&times;</span>
              <h4 style="margin: 0;"><i class="fas fa-edit"></i> Configure Node: <span id="editor-node-name" style="color: #38bdf8;"></span></h4>
            </header>

            <div class="w3-container w3-padding">
              <div class="w3-panel w3-pale-yellow w3-leftbar w3-border-yellow w3-small w3-text-black" style="padding: 8px;">
                <i class="fas fa-info-circle"></i> Edits are saved as an <strong>ad-hoc override</strong>. They will <u>not</u> modify the original YAML file. Shut down the lab to clear changes.
              </div>

              <div class="w3-bar w3-margin-bottom" style="border-bottom: 1px solid #475569;">
                <button type="button" class="w3-bar-item w3-button editor-tablink w3-text-blue" onclick="window.openEditorTab(event, 'FormEdit')" id="defaultTab"><b>Basic Form</b></button>
                <button type="button" class="w3-bar-item w3-button editor-tablink" onclick="window.openEditorTab(event, 'YamlEdit')"><b>Raw YAML</b></button>
              </div>

              <div id="FormEdit" class="editor-tab">
                <div class="w3-row-padding" style="margin: 0 -8px;">
                  <div class="w3-col m6 w3-margin-bottom">
                    <label style="font-size: 0.85em; color: #94a3b8;">Type</label>
                    <select id="edit-type" class="w3-select w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
                      <option value="host">host</option>
                      <option value="router">router</option>
                      <option value="switch">switch</option>
                      <option value="controller">controller</option>
                      <option value="gateway">gateway</option>
                    </select>
                  </div>
                  <div class="w3-col m6 w3-margin-bottom">
                    <label style="font-size: 0.85em; color: #94a3b8;">Kind</label>
                    <input type="text" id="edit-kind" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
                  </div>
                  <div class="w3-col m12 w3-margin-bottom">
                    <label style="font-size: 0.85em; color: #94a3b8;">Gateway (gw)</label>
                    <input type="text" id="edit-gw" class="w3-input w3-small w3-round" placeholder="e.g. 192.168.10.1" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
                  </div>
                  <div class="w3-col m12 w3-margin-bottom">
                    <label style="font-size: 0.85em; color: #94a3b8;">Network Interfaces (nics)</label>
                    <textarea id="edit-nics" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: 'Courier New', Courier, monospace !important; resize: vertical;" rows="3" placeholder="eth1=192.168.10.11/24\neth2=10.0.0.1/24"></textarea>
                  </div>
                  <div class="w3-col m12 w3-margin-bottom">
                    <label style="font-size: 0.85em; color: #94a3b8;"><i class="fas fa-info-circle"></i> Node Info (Description)</label>
                    <input type="text" id="edit-info" class="w3-input w3-small w3-round" placeholder="e.g., Primary Database Server" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
                  </div>
                  <div class="w3-col m12 w3-margin-bottom">
                    <label style="font-size: 0.85em; color: #94a3b8;"><i class="fas fa-terminal"></i> Terminal / SSH Link</label>
                    <input type="text" id="edit-term" class="w3-input w3-small w3-round" placeholder="e.g., ssh://root@192.168.10.5 or https://tty.local" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
                  </div>
                  <div class="w3-col m12 w3-margin-bottom">
                    <label style="font-size: 0.85em; color: #94a3b8;"><i class="fas fa-link"></i> Custom URLs</label>
                    <p style="font-size: 0.75em; color: #64748b; margin: 0 0 4px 0;">Format: <code>Title|https://link.com</code> (One per line)</p>
                    <textarea id="edit-urls" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: 'Courier New', Courier, monospace !important; resize: vertical;" rows="3" placeholder="Flashcards|https://quizlet.com/...&#10;Walkthrough|https://docs.local/..."></textarea>
                  </div>
                </div> </div> <div id="YamlEdit" class="editor-tab" style="display:none">
                <textarea id="node-yaml-editor" class="w3-input w3-round w3-small" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: 'Courier New', Courier, monospace !important; height: 250px; resize: vertical; white-space: pre;"></textarea>
              </div>

              <div id="node-editor-result" class="w3-panel w3-round" style="display:none; font-size: 0.9em; padding: 8px; margin-top: 10px;"></div>
            </div> <footer class="w3-container w3-padding" style="border-top: 1px solid #334155; background-color: #0f172a; border-radius: 0 0 12px 12px; text-align: right;">
              <button type="button" onclick="document.getElementById('node-editor-modal').style.display='none'" class="w3-button w3-round w3-small" style="background-color: #475569;">Cancel</button>
              <button type="button" onclick="window.saveNodeConfig()" class="w3-button w3-green w3-round w3-small"><i class="fas fa-save"></i> Save Override</button>
            </footer>
          </div>
        </div>

        <div class="w3-card w3-round-large w3-margin-bottom" style="background-color: #0f172a; overflow:hidden;">
          <div class="w3-padding" style="background-color: #334155; color: #fff; font-weight: 500; display:flex; justify-content:space-between; align-items:center;">
            <span><i class="fas fa-code-branch"></i> Ansible Playbook Configuration</span>
            <div>
              <% if get_running_lab == info_hash[:lab_path] %>
                <button type="button" onclick="window.openAnsibleEditor('<%= info_hash[:lab_path] %>')" class="w3-button w3-tiny w3-round w3-blue" style="padding: 2px 8px; margin-right: 4px;">
                  <i class="fas fa-edit"></i> Edit
                </button>
                
                <% if info_hash[:ansible][:playbook] != 'N/A' %>
                  <% pb_running = Lab.playbook_running?(info_hash[:lab_path]) %>
                  <button type="button" onclick="window.runAnsiblePlaybook(event, '<%= info_hash[:lab_path] %>')" class="w3-button w3-tiny w3-round <%= pb_running ? 'w3-grey' : 'w3-green' %>" style="padding: 2px 8px;" <%= pb_running ? 'disabled' : '' %>>
                    <i class="fas <%= pb_running ? 'fa-spinner fa-spin' : 'fa-play' %>"></i> <%= pb_running ? 'Running...' : 'Run Playbook' %>
                  </button>
                <% end %>
              <% end %>
            </div>
          </div>
          <div class="w3-padding w3-small">
            <table class="w3-table">
              <tr>
                <td style="color: #94a3b8; width: 120px;">Playbook:</td>
                <td><code style="background-color: #1e293b; padding: 2px 6px;"><%= info_hash[:ansible][:playbook] %></code></td>
              </tr>
              <tr>
                <td style="color: #94a3b8;">Environment:</td>
                <td>
                  <% (info_hash[:ansible][:environment] || []).each do |e| %>
                    <div style="margin-bottom: 2px;"><code style="background-color: #1e293b; padding: 2px 6px; color: #a78bfa;"><%= e %></code></div>
                  <% end %>
                </td>
              </tr>
              <tr>
                <td style="color: #94a3b8;">Tags:</td>
                <td>
                  <% (info_hash[:ansible][:tags] || []).each do |t| %>
                    <span class="w3-badge w3-tiny w3-round" style="background-color: #10b981; margin-right: 4px;"><%= t %></span>
                  <% end %>
                </td>
              </tr>
            </table>
          </div>
        </div>

        <div id="ansible-editor-modal" class="w3-modal" style="z-index: 9999;">
          <div class="w3-modal-content w3-round-large w3-card-4" style="background-color: #1e293b; color: #f8fafc; max-width: 500px;">
            <header class="w3-container w3-padding" style="border-bottom: 1px solid #334155; background-color: #0f172a; border-radius: 12px 12px 0 0;">
              <span onclick="document.getElementById('ansible-editor-modal').style.display='none'" class="w3-button w3-display-topright w3-hover-red w3-round" style="color: #cbd5e1;">&times;</span>
              <h4 style="margin: 0;"><i class="fas fa-magic"></i> Configure Ansible Playbook</h4>
            </header>

            <div class="w3-container w3-padding">
              <div class="w3-panel w3-pale-yellow w3-leftbar w3-border-yellow w3-small w3-text-black" style="padding: 8px;">
                <i class="fas fa-info-circle"></i> Edits are saved as an <strong>ad-hoc override</strong> for the current run.
              </div>

              <div class="w3-margin-bottom">
                <label style="font-size: 0.85em; color: #94a3b8;">Playbook File</label>
                <input type="text" id="edit-ansible-book" class="w3-input w3-small w3-round" placeholder="e.g. main.yml" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
              </div>

              <div class="w3-margin-bottom">
                <label style="font-size: 0.85em; color: #94a3b8;">Tags (Comma separated)</label>
                <input type="text" id="edit-ansible-tags" class="w3-input w3-small w3-round" placeholder="e.g. setup, web, db" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
              </div>

              <div class="w3-margin-bottom">
                <label style="font-size: 0.85em; color: #94a3b8;">Environment Variables (One per line)</label>
                <textarea id="edit-ansible-env" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: 'Courier New', Courier, monospace !important; resize: vertical;" rows="3" placeholder="APP_ENV=production&#10;DEBUG=true"></textarea>
              </div>

              <div id="ansible-editor-result" class="w3-panel w3-round" style="display:none; font-size: 0.9em; padding: 8px; margin-top: 10px;"></div>
            </div>

            <footer class="w3-container w3-padding" style="border-top: 1px solid #334155; background-color: #0f172a; border-radius: 0 0 12px 12px; text-align: right;">
              <button type="button" onclick="document.getElementById('ansible-editor-modal').style.display='none'" class="w3-button w3-round w3-small" style="background-color: #475569;">Cancel</button>
              <button type="button" onclick="window.saveAnsibleConfig()" class="w3-button w3-green w3-round w3-small"><i class="fas fa-save"></i> Save</button>
            </footer>
          </div>
        </div>

      </div>

      <div class="w3-col s12 m6 l6">

        <div class="w3-card w3-round-large w3-margin-bottom" style="background-color: #0f172a; overflow:hidden;">
          <div class="w3-padding" style="background-color: #334155; color: #fff; font-weight: 500;">
            <i class="fas fa-box-open"></i> Defined Images
          </div>
          <div class="w3-padding">
            <% if (info_hash[:images] || []).empty? %>
              <p style="color: #94a3b8; font-style: italic;">No images defined</p>
            <% else %>
              <table class="w3-table w3-striped w3-small">
                <thead>
                  <tr style="color: #94a3b8;"><th>Type</th><th>Kind</th><th>Image Reference</th></tr>
                </thead>
                <tbody>
                  <% (info_hash[:images] || []).each do |img| %>
                    <tr>
                      <td><%= img[:type] %></td>
                      <td><%= img[:kind] %></td>
                      <td style="color: #cbd5e1;"><%= img[:image] %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>

        <div class="w3-card w3-round-large" style="background-color: #0f172a; overflow:hidden;">
          <div class="w3-padding" style="background-color: #b91c1c; color: #fff; font-weight: 500;">
            <i class="fas fa-network-wired"></i> Exposed Ports (DNAT)
          </div>
          <div class="w3-padding">
            <% if (info_hash[:exposed_ports] || []).empty? %>
              <p style="color: #94a3b8; font-style: italic;">No ports exposed</p>
            <% else %>
              <table id="dnat_table" class="w3-table w3-striped w3-small">
                <thead>
                  <tr style="color: #94a3b8;"><th>Node</th><th>Proto</th><th>Forwarding Rule</th></tr>
                </thead>
                <tbody>
                  <% (info_hash[:exposed_ports] || []).each do |port| %>
                    <tr style="<%= 'background-color:rgba(59, 130, 246, 0.1);' if port[:adhoc] %>">
                      <td><strong><%= port[:node] %></strong></td>
                      <td><span class="w3-badge w3-tiny" style="background: #475569;"><%= port[:proto].upcase %></span></td>
                      <td>
                        <code style="color: #10b981;"><%= port[:external_port] %></code>
                        <i class="fas fa-arrow-right" style="color: #64748b; font-size: 0.8em; margin: 0 4px;"></i>
                        <code style="color: #38bdf8;"><%= port[:internal_port] %></code>
                        <% if port[:adhoc] %>
                          <span style="color:#f59e0b; font-size:0.75em; margin-left:4px; font-weight: bold;">(adhoc)</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>

          <div id="me" class="w3-padding" style="border-top: 1px solid #334155; background-color: rgba(0,0,0,0.2);">
            <% if get_running_lab == info_hash[:lab_path] %>
              <h6 style="color: #94a3b8; font-weight: 600; margin-top: 0;"><i class="fas fa-plus"></i> Add AdHoc DNAT Rule</h6>
              <form id="adhoc-dnat-form" onsubmit="window.submitAdhocDnat(event)" class="w3-row-padding" style="margin:0 -8px;">
                <input type="hidden" name="lab_name" value="<%= info_hash[:lab_path] %>">
                <div class="w3-col s12 m4 l4 w3-margin-bottom" style="padding:0 4px;">
                  <select name="node" class="w3-select w3-small" required>
                    <option value="" disabled selected>-- Node --</option>
                    <% (info_hash[:nodes] || []).each do |n| %>
                      <% if n[:type] == 'host' || n[:type] == 'controller' %>
                        <option value="<%= n[:name] %>"><%= n[:name] %> (<%= n[:type] %>)</option>
                      <% end %>
                    <% end %>
                  </select>
                </div>
                <div class="w3-col s6 m2 l2 w3-margin-bottom" style="padding:0 4px;">
                  <input type="number" name="external_port" placeholder="Ext Port" min="1" max="65535" class="w3-input w3-small" required>
                </div>
                <div class="w3-col s6 m2 l2 w3-margin-bottom" style="padding:0 4px;">
                  <input type="number" name="internal_port" placeholder="Int Port" min="1" max="65535" class="w3-input w3-small" required>
                </div>
                <div class="w3-col s6 m2 l2 w3-margin-bottom" style="padding:0 4px;">
                  <select name="protocol" class="w3-select w3-small">
                    <option value="tcp">TCP</option>
                    <option value="udp">UDP</option>
                  </select>
                </div>
                <div class="w3-col s6 m2 l2 w3-margin-bottom" style="padding:0 4px;">
                  <button type="submit" class="w3-button w3-blue w3-small w3-block"><i class="fas fa-plus"></i> Add</button>
                </div>
              </form>
              <div id="adhoc-dnat-result" class="w3-panel w3-round" style="display:none; font-size: 0.9em; padding: 8px;"></div>
            <% end %>
          </div>
        </div>

      </div>
    </div>
  </div>

  <script>
    window.labImagesMap = <%= info_hash[:images_map].to_json %>;

    if (!window.ctlabsListenersAttached) {
      window.ctlabsListenersAttached = true;
      
      window.submitAdhocDnat = async function(e) {
        e.preventDefault();
        const form = e.target;
        const formData = new FormData(form);
        const labName = formData.get('lab_name');
        const safeLab = labName.split('/').map(encodeURIComponent).join('/');
        const url = `/labs/${safeLab}/dnat`;

        const res = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams(formData).toString()
        });

        const resultDiv = document.getElementById('adhoc-dnat-result');

        if (res.ok) {
          const data = await res.json();
          resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.textContent = '✅ ' + data.message;
          setTimeout(() => location.reload(), 1200);
        } else {
          const err = await res.json().catch(() => ({error: 'Unknown error'}));
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.textContent = '❌ ' + (err.error || 'Failed');
        }
      };
      
      window.submitAdhocNode = async function(e) {
        e.preventDefault();
        const form = e.target;
        const formData = new FormData(form);
        const labName = formData.get('lab_name');
        const safeLab = labName.split('/').map(encodeURIComponent).join('/');
        const url = `/labs/${safeLab}/node`;

        const resultDiv = document.getElementById('adhoc-node-result');
        const btn = form.querySelector('button[type="submit"]');
        let originalBtnHTML = '';
        if (btn) {
           originalBtnHTML = btn.innerHTML;
           btn.disabled = true;
           btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Starting...';
        }

        try {
          const res = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams(formData).toString()
          });

          const data = await res.json();
          if (res.ok) {
            resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
            resultDiv.textContent = '✅ ' + data.message + ' (Reloading...)';
            setTimeout(() => location.reload(), 1200);
          } else {
            throw new Error(data.error || 'Failed to start node');
          }
        } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.textContent = '❌ ' + err.message;
          if (btn) {
             btn.disabled = false;
             btn.innerHTML = originalBtnHTML;
          }
        }
      };

      window.runAnsiblePlaybook = async function(event, labName) {
        const btn = event.currentTarget;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Starting...';
        btn.classList.replace('w3-green', 'w3-grey');

        const safeLab = labName.split('/').map(encodeURIComponent).join('/');
        const url = `/labs/${safeLab}/playbook`;

        try {
          const res = await fetch(url, { method: 'POST' });
          const data = await res.json();
          if (res.ok) {
            window.location.href = '/logs/current';
          } else {
            alert("Error: " + (data.error || 'Failed to start playbook'));
            btn.disabled = false;
            btn.innerHTML = '<i class="fas fa-play"></i> Run Playbook';
            btn.classList.replace('w3-grey', 'w3-green');
          }
        } catch (err) {
          alert("Error: " + err.message);
          btn.disabled = false;
          btn.innerHTML = '<i class="fas fa-play"></i> Run Playbook';
          btn.classList.replace('w3-grey', 'w3-green');
        }
      };

      window.openAnsibleEditor = async function(labName) {
        window.currentEditLab = labName;
        document.getElementById('ansible-editor-result').style.display = 'none';

        try {
          const safeLab = labName.split('/').map(encodeURIComponent).join('/');
          // Fetch the ansible node directly to get its current play config
          const res = await fetch(`/labs/${safeLab}/node/ansible`);
          if (!res.ok) throw new Error("Could not fetch ansible node configuration");
          const data = await res.json();

          let play = data.json.play || {};
          
          if (typeof play === 'string') {
            document.getElementById('edit-ansible-book').value = play;
            document.getElementById('edit-ansible-tags').value = '';
            document.getElementById('edit-ansible-env').value = '';
          } else {
            document.getElementById('edit-ansible-book').value = play.book || '';
            document.getElementById('edit-ansible-tags').value = (play.tags || []).join(', ');
            document.getElementById('edit-ansible-env').value = (play.env || []).join('\n');
          }

          document.getElementById('ansible-editor-modal').style.display = 'block';
        } catch (err) {
          alert("Error: " + err.message);
        }
      };

      window.saveAnsibleConfig = async function() {
        const resultDiv = document.getElementById('ansible-editor-result');
        const formData = new URLSearchParams();

        formData.append('book', document.getElementById('edit-ansible-book').value);
        formData.append('tags', document.getElementById('edit-ansible-tags').value);
        formData.append('env', document.getElementById('edit-ansible-env').value);

        const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');

        try {
          const res = await fetch(`/labs/${safeLab}/ansible/edit`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: formData.toString()
          });

          const data = await res.json();
          if (res.ok) {
            resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
            resultDiv.textContent = '✅ ' + data.message + ' (Reloading...)';
            setTimeout(() => location.reload(), 1200);
          } else {
            throw new Error(data.error || 'Failed to save configuration');
          }
        } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.textContent = '❌ ' + err.message;
        }
      };

      window.openAddNodeModal = function(labPath) {
        document.getElementById('add-node-lab-name').value = labPath;
        document.getElementById('adhoc-node-form').reset();
        document.getElementById('add-node-kind').innerHTML = '<option value="" disabled selected>-- Select Kind --</option>';
        document.getElementById('adhoc-node-result').style.display = 'none';
        document.getElementById('add-node-modal').style.display = 'block';
      };

      window.updateKindOptions = function(type) {
        const kindSelect = document.getElementById('add-node-kind');
        kindSelect.innerHTML = '<option value="" disabled selected>-- Select Kind --</option>';
        const kinds = window.labImagesMap[type] || [];
        kinds.forEach(k => {
          kindSelect.innerHTML += `<option value="${k}">${k}</option>`;
        });
      };

      window.currentEditNode = '';
      window.currentEditLab = '';

      window.openEditorTab = function(evt, tabName) {
        var i, x, tablinks;
        x = document.getElementsByClassName("editor-tab");
        for (i = 0; i < x.length; i++) {
          x[i].style.display = "none";
        }
        tablinks = document.getElementsByClassName("editor-tablink");
        for (i = 0; i < tablinks.length; i++) {
          tablinks[i].className = tablinks[i].className.replace(" w3-text-blue", "");
        }
        document.getElementById(tabName).style.display = "block";
        evt.currentTarget.className += " w3-text-blue";
      };

      window.editNodeConfig = async function(labName, nodeName) {
        window.currentEditLab = labName;
        window.currentEditNode = nodeName;
        document.getElementById('editor-node-name').textContent = nodeName;
        document.getElementById('node-editor-result').style.display = 'none';

        try {
          const safeLab = labName.split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`/labs/${safeLab}/node/${encodeURIComponent(nodeName)}`);
          if (!res.ok) throw new Error("HTTP Status " + res.status);
          const data = await res.json();

          document.getElementById('node-yaml-editor').value = data.yaml;

          if(data.json) {
             document.getElementById('edit-type').value = data.json.type || 'host';
             document.getElementById('edit-kind').value = data.json.kind || '';
             document.getElementById('edit-gw').value = data.json.gw || '';
             
             // NEW: Load Info field
             document.getElementById('edit-info').value = data.json.info || '';
             document.getElementById('edit-term').value = data.json.term || '';

             // Load NICs
             let nicsStr = '';
             if (data.json.nics) {
                for (const [key, value] of Object.entries(data.json.nics)) {
                   nicsStr += `${key}=${value}\n`;
                }
             }
             document.getElementById('edit-nics').value = nicsStr.trim();

             // NEW: Load URLs Hash and convert to multi-line string format
             let urlStr = '';
             if (data.json.urls && typeof data.json.urls === 'object') {
                for (const [title, link] of Object.entries(data.json.urls)) {
                   urlStr += `${title}|${link}\n`;
                }
             }
             document.getElementById('edit-urls').value = urlStr.trim();
          }

          document.getElementById('defaultTab').click();
          document.getElementById('node-editor-modal').style.display = 'block';
        } catch (err) {
          alert("Failed to load node configuration. " + err.message);
        }
      };

      window.saveNodeConfig = async function() {
        const resultDiv = document.getElementById('node-editor-result');
        const formData = new URLSearchParams();

        const isYaml = document.getElementById('YamlEdit').style.display === 'block';

        if (isYaml) {
           formData.append('format', 'yaml');
           formData.append('yaml_data', document.getElementById('node-yaml-editor').value);
        } else {
           formData.append('format', 'form');
           formData.append('type', document.getElementById('edit-type').value);
           formData.append('kind', document.getElementById('edit-kind').value);
           formData.append('gw', document.getElementById('edit-gw').value);
           formData.append('nics', document.getElementById('edit-nics').value);
           
           // NEW: Append the info and urls data from our new HTML fields!
           formData.append('info', document.getElementById('edit-info').value);
           formData.append('urls_text', document.getElementById('edit-urls').value);
           formData.append('term', document.getElementById('edit-term').value);
        }

        const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');

        try {
          const res = await fetch(`/labs/${safeLab}/node/${encodeURIComponent(window.currentEditNode)}/edit`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: formData.toString()
          });

          const data = await res.json();
          if (res.ok) {
            resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
            resultDiv.textContent = '✅ ' + data.message + ' (Reloading view...)';
            setTimeout(() => location.reload(), 1200);
          } else {
            throw new Error(data.error || 'Failed to save configuration');
          }
        } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.textContent = '❌ ' + err.message;
        }
      };
    }
  </script>
<% end %>
)

    erb_template = ERB.new(template)
    old_info_hash = instance_variable_get("@info_hash")
    instance_variable_set("@info_hash", info_hash)
    result = erb_template.result(binding)
    if old_info_hash
      instance_variable_set("@info_hash", old_info_hash)
    else
      remove_instance_variable("@info_hash") if instance_variable_defined?("@info_hash")
    end
    result
  end
end
