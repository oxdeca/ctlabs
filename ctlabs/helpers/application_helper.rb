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
    refresh_lab_visuals(lab_name)
    runtime_path = "#{LOCK_DIR}/#{lab_name.gsub('/', '_')}.yml"
    is_running = running_lab? && get_running_lab == lab_name

    actual_path = (is_running && File.file?(runtime_path)) ? runtime_path : yaml_file_path

    # Load runtime lab and base lab to compute the diff
    lab = Lab.new(cfg: actual_path, log: LabLog.null)
    base_lab = is_running ? Lab.new(cfg: yaml_file_path, log: LabLog.null) : lab

    # Map base nodes and base DNATs for comparison
    base_nodes_list = base_lab.nodes.map(&:name)
    base_dnats = {}
    base_lab.nodes.each { |n| base_dnats[n.name] = n.dnat || [] }

    info = { lab_name: File.basename(yaml_file_path, '.yml'), lab_path: lab_name, desc: lab.desc || '' }

    # --- BULLETPROOF LINKS PARSER ---
    raw_links = []
    if base_lab.topology.is_a?(Array) && base_lab.topology.first.is_a?(Hash)
      raw_links = base_lab.topology.first['links'] || []
    elsif base_lab.topology.is_a?(Hash)
      raw_links = base_lab.topology['links'] || []
    end

    info[:links] = raw_links.map do |l|
      if l.is_a?(Array) && l.size == 2
         n_a, i_a = l[0].split(':', 2)
         n_b, i_b = l[1].split(':', 2)
         { node_a: n_a, int_a: i_a, node_b: n_b, int_b: i_b, ep1: l[0], ep2: l[1] }
      else
         nil
      end
    end.compact
    # --------------------------------

    # Images Map
    images = []
    images_map = {}
    if lab.defaults
      lab.defaults.each do |tk, tv|
        if tv.is_a?(Hash)
          images_map[tk] = tv.keys
          tv.each do |kk, kv|
            if kv
              # Grab any keys that aren't the standard three
              core_keys = ['image', 'caps', 'env']
              extras = kv.reject { |k, _| core_keys.include?(k) }
              extras_yaml = extras.empty? ? "" : extras.to_yaml.sub("---\n", "").strip

              images << {
                type: tk, 
                kind: kk, 
                image: kv['image'] || 'N/A',
                caps: kv['caps'] || [],
                env: kv['env'] || [],
                extras: extras_yaml
              }
            end
          end
        else
          images_map[tk] = []
        end
      end
    end
    info[:images] = images
    info[:images_map] = images_map

    # --- BULK HEALTH CHECK (Lightning Fast) ---
    # Fetch all running container names exactly ONCE, and ONLY if the lab is active!
    active_containers = []
    
    if is_running
      podman_running = `podman ps --format '{{.Names}}' 2>/dev/null`.split("\n").map(&:strip)
      docker_running = `docker ps --format '{{.Names}}' 2>/dev/null`.split("\n").map(&:strip)
      active_containers = (podman_running + docker_running).uniq
    end
    # ------------------------------------------

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

          # Real-time Health Check (In-Memory Array Lookup)
          container_running = active_containers.include?(node.name)

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
    info[:gateways] = lab.nodes.map { |n| n.gw }.compact.reject { |g| g.to_s.strip.empty? }.uniq

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
              adhoc: is_adhoc_dnat,
              raw_ext: p[0],   # NEW
              raw_int: p[1]    # NEW
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

  # Helper to automatically regenerate Topology Maps and Inventories ONLY if needed
  def refresh_lab_visuals(lab_name, force: false)
    begin
      lock_dir = defined?(LOCK_DIR) ? LOCK_DIR : '/var/run/ctlabs'
      runtime_path = File.join(lock_dir, "#{lab_name.gsub('/', '_')}.yml")
      base_path = File.join(LABS_DIR, lab_name)
      
      # Intelligently decide whether to map the active runtime or the offline base YAML
      is_running = Lab.running? && Lab.current_name == lab_name
      actual_path = (is_running && File.file?(runtime_path)) ? runtime_path : base_path

      # SMART CACHE CHECK
      pubdir = '/srv/ctlabs-server/public'
      topo_file = File.join(pubdir, 'topo.png')
      tracker_file = File.join(pubdir, '.topo_tracker')
      
      needs_rebuild = force
      
      if !needs_rebuild
        # 1. Did we choose a different lab from the dropdown?
        last_drawn_lab = File.exist?(tracker_file) ? File.read(tracker_file).strip : ""
        if last_drawn_lab != lab_name
          needs_rebuild = true
          
        # 2. Was the YAML edited (via UI or CLI) since we last drew the map?
        elsif File.exist?(topo_file) && File.exist?(actual_path)
          needs_rebuild = true if File.mtime(actual_path) > File.mtime(topo_file)
          
        # 3. Are the images missing entirely?
        else
          needs_rebuild = true
        end
      end

      # Skip heavy processing if nothing changed!
      return unless needs_rebuild

      # Generate visuals
      lab = Lab.new(cfg: actual_path, log: LabLog.null)
      lab.visualize
      lab.inventory
      
      # Update the tracker file with the currently drawn lab
      File.write(tracker_file, lab_name)
      
    rescue => e
      puts "[Warning] Failed to generate visuals for #{lab_name}: #{e.message}"
    end
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
    <div id="lab-running-state" data-is-running="<%= get_running_lab == info_hash[:lab_path] %>" style="display:none;"></div>
    <div id="lab-dynamic-data" data-images-map="<%= ERB::Util.html_escape(info_hash[:images_map].to_json) %>" style="display:none;"></div>

    <div style="border-bottom: 1px solid #334155; padding-bottom: 15px; margin-bottom: 20px;">
      <h3 style="margin:0; font-weight: 600; color: #38bdf8;"><i class="fas fa-flask"></i> <%= info_hash[:lab_name] %></h3>
      <span style="color: #94a3b8; font-size: 0.95em;"><%= info_hash[:desc] %></span>
    </div>

    <div class="w3-row-padding" style="margin: 0 -16px;">
      <div class="w3-col s12 m6 l6">
        
        <div class="w3-card w3-round-large w3-margin-bottom" style="background-color: #0f172a; overflow:hidden;">
          <div class="w3-padding" style="background-color: #334155; color: #fff; font-weight: 500; display:flex; justify-content:space-between; align-items:center;">
            <span><i class="fas fa-server"></i> Active Nodes</span>
            <button type="button" onclick="window.openAddNodeModal('<%= info_hash[:lab_path] %>')" class="w3-button w3-tiny w3-round w3-blue" style="padding: 2px 8px;">
              <i class="fas fa-plus"></i> Add Node
            </button>
          </div>
          <div class="w3-padding">
            <table class="w3-table w3-striped w3-small" id="nodes_table">
              <thead><tr style="color: #94a3b8;"><th style="width: 30px; text-align: center;"><i class="fas fa-heartbeat"></i></th><th>Name</th><th>Type</th><th>Kind</th><th>Image</th><th style="text-align:right;">Actions</th></tr></thead>
              <tbody>
                <% (info_hash[:nodes] || []).each do |node| %>
                  <tr style="<%= 'background-color:rgba(59, 130, 246, 0.1);' if node[:adhoc] %>">
                    <td style="text-align: center; vertical-align: middle;">
                      <i class="fas fa-circle" style="font-size: 0.8em; color: <%= node[:running] ? '#10b981' : '#ef4444' %>;"></i>
                    </td>
                    <td>
                      <strong style="color: #38bdf8;"><%= node[:name] %></strong>
                      <% if node[:adhoc] %><span style="color:#f59e0b; font-size:0.75em; margin-left:4px; font-weight: bold;">(adhoc)</span><% end %>
                    </td>
                    <td><span class="w3-badge w3-tiny w3-round" style="background-color: #475569;"><%= node[:type] %></span></td>
                    <td><%= node[:kind] %></td>
                    <td style="color: #cbd5e1;"><%= node[:image] %></td>
                    <td style="text-align:right; white-space: nowrap;">
                      <button type="button" onclick="const w=900, h=600, t=(window.top.outerHeight/2)+window.top.screenY-(h/2), l=(window.top.outerWidth/2)+window.top.screenX-(w/2); window.open('/terminal/<%= node[:name] %>', 'term_<%= node[:name] %>', 'width='+w+',height='+h+',top='+t+',left='+l+',resizable=yes,scrollbars=yes,toolbar=no,location=no');" class="w3-button w3-tiny w3-transparent w3-text-green w3-hover-text-light-green" title="Open Web Terminal now" style="padding: 2px 6px;"><i class="fas fa-terminal fa-lg"></i></button>

                      <button type="button" onclick="window.editNodeConfig('<%= info_hash[:lab_path] %>', '<%= node[:name] %>')" class="w3-button w3-tiny w3-transparent w3-text-blue w3-hover-text-light-blue" title="Edit Node" style="padding: 2px 6px;"><i class="fas fa-edit fa-lg"></i></button>
                      <button type="button" onclick="window.deleteItem('<%= info_hash[:lab_path] %>', 'node/<%= node[:name] %>')" class="w3-button w3-tiny w3-transparent w3-text-red w3-hover-text-light-coral" title="Delete Node" style="padding: 2px 6px;"><i class="fas fa-trash fa-lg"></i></button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <div class="w3-card w3-round-large w3-margin-bottom" style="background-color: #0f172a; overflow:hidden;">
          <div class="w3-padding" style="background-color: #334155; color: #fff; font-weight: 500; display:flex; justify-content:space-between; align-items:center;">
            <span><i class="fas fa-sliders-h w3-text-blue"></i> Image Profiles</span>
            <button type="button" onclick="window.openImageEditor('<%= info_hash[:lab_path] %>')" class="w3-button w3-tiny w3-round w3-blue" style="padding: 2px 8px;"><i class="fas fa-plus"></i> Add</button>
          </div>
          <div class="w3-padding">
            <% if (info_hash[:images] || []).empty? %>
              <p style="color: #94a3b8; font-style: italic;">No image profiles defined</p>
            <% else %>
              <table class="w3-table w3-striped w3-small">
                <thead><tr style="color: #94a3b8;"><th>Type</th><th>Kind</th><th>Mapped Image</th><th></th></tr></thead>
                <tbody>
                  <% (info_hash[:images] || []).each do |img| %>
                    <tr>
                      <td><span class="w3-badge w3-tiny w3-round" style="background-color: #475569;"><%= img[:type] %></span></td>
                      <td><%= img[:kind] %></td>
                      <td style="color: #cbd5e1;"><%= img[:image] %></td>
                      <td style="text-align:right; white-space: nowrap;">
                        <button type="button" onclick="window.editImageConfig('<%= img[:type] %>', '<%= img[:kind] %>', '<%= ERB::Util.url_encode(img[:image]) %>', '<%= ERB::Util.url_encode(img[:caps].join(', ')) %>', '<%= ERB::Util.url_encode(img[:env].join("\n")) %>', '<%= ERB::Util.url_encode(img[:extras]) %>')" class="w3-button w3-tiny w3-transparent w3-text-blue w3-hover-text-light-blue" title="Edit Image Profile" style="padding: 2px 6px;"><i class="fas fa-edit fa-lg"></i></button>
                        <button type="button" onclick="window.deleteItem('<%= info_hash[:lab_path] %>', 'image/<%= img[:type] %>/<%= img[:kind] %>')" class="w3-button w3-tiny w3-transparent w3-text-red w3-hover-text-light-coral" title="Delete Image Profile" style="padding: 2px 6px;"><i class="fas fa-trash fa-lg"></i></button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>

        <div class="w3-card w3-round-large w3-margin-bottom" style="background-color: #0f172a; overflow:hidden;">
          <div class="w3-padding" style="background-color: #334155; color: #fff; font-weight: 500; display:flex; justify-content:space-between; align-items:center;">
            <span><i class="fas fa-box w3-text-orange"></i> Images</span>
            <button type="button" onclick="window.openAddLocalImageModal()" class="w3-button w3-tiny w3-round w3-blue" style="padding: 2px 8px;"><i class="fas fa-plus"></i> Add</button>
          </div>
          <div style="padding: 0;">
            <% 
              global_images = []
              Dir.glob(File.join("..", "images", "**", "Dockerfile")).each do |df|
                rel_path = df.sub(/\A.*?\.\.\/images\//, '').sub(/\/Dockerfile\z/, '')
                global_images << rel_path
              end
              global_images.sort!
            %>
            
            <% if global_images.empty? %>
              <div class="w3-padding">
                <p style="color: #94a3b8; font-style: italic;">No local images detected in ../images.</p>
              </div>
            <% else %>
              <div style="max-height: 350px; overflow-y: auto;" class="docker-scroll">
                <table class="w3-table w3-striped w3-small" style="margin: 0;">
                  <thead style="position: sticky; top: 0; z-index: 1;">
                    <tr style="color: #94a3b8; background-color: #1e293b;">
                      <th style="border-bottom: 1px solid #475569 !important;">Name</th>
                      <th style="border-bottom: 1px solid #475569 !important;">Category</th>
                      <th style="border-bottom: 1px solid #475569 !important;">OS</th>
                      <th style="border-bottom: 1px solid #475569 !important; text-align:right;">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <% global_images.each do |img_path| %>
                      <% parts = img_path.split('/') %>
                      <% category = parts[0] %>
                      <% os = parts.length > 2 ? parts[1] : '-' %>
                      <tr>
                        <td><strong style="color: #38bdf8;"><%= img_path %></strong></td>
                        <td><span class="w3-badge w3-tiny w3-round" style="background-color: #475569;"><%= category %></span></td>
                        <td><%= os == '-' ? '-' : "<span class='w3-badge w3-tiny w3-round' style='background-color: #64748b;'>#{os}</span>" %></td>
                        <td style="text-align:right; white-space: nowrap;">
                          <button type="button" onclick="window.quickBuildImage('<%= ERB::Util.url_encode(img_path) %>')" class="w3-button w3-tiny w3-transparent w3-text-orange w3-hover-text-yellow" title="Quick Build" style="padding: 2px 6px;"><i class="fas fa-hammer fa-lg"></i></button>
                          <button type="button" onclick="window.openBuildModal('<%= ERB::Util.url_encode(img_path) %>')" class="w3-button w3-tiny w3-transparent w3-text-blue w3-hover-text-light-blue" title="Edit Dockerfile" style="padding: 2px 6px;"><i class="fas fa-edit fa-lg"></i></button>
                          <button type="button" onclick="window.deleteLocalImage('<%= ERB::Util.url_encode(img_path) %>')" class="w3-button w3-tiny w3-transparent w3-text-red w3-hover-text-light-coral" title="Delete Image Structure" style="padding: 2px 6px;"><i class="fas fa-trash fa-lg"></i></button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>

      </div>
      <div class="w3-col s12 m6 l6">
        
        <div class="w3-card w3-round-large w3-margin-bottom" style="background-color: #0f172a; overflow:hidden;">
          <div class="w3-padding" style="background-color: #334155; color: #fff; font-weight: 500; display:flex; justify-content:space-between; align-items:center;">
            <span><i class="fas fa-code-branch"></i> Ansible Playbook</span>
            <div>
              <button type="button" onclick="window.openAnsibleEditor('<%= info_hash[:lab_path] %>')" class="w3-button w3-tiny w3-round w3-blue" style="padding: 2px 8px; margin-right: 4px;"><i class="fas fa-edit"></i> Edit</button>
              <% if get_running_lab == info_hash[:lab_path] && info_hash[:ansible][:playbook] != 'N/A' %>
                <% pb_running = Lab.playbook_running?(info_hash[:lab_path]) %>
                <button type="button" onclick="window.runAnsiblePlaybook(event, '<%= info_hash[:lab_path] %>')" class="w3-button w3-tiny w3-round <%= pb_running ? 'w3-grey' : 'w3-green' %>" style="padding: 2px 8px;" <%= pb_running ? 'disabled' : '' %>>
                  <i class="fas <%= pb_running ? 'fa-spinner fa-spin' : 'fa-play' %>"></i> <%= pb_running ? 'Running...' : 'Run Playbook' %>
                </button>
              <% end %>
            </div>
          </div>
          <div class="w3-padding w3-small">
            <table class="w3-table">
              <tr><td style="color: #94a3b8; width: 120px;">Playbook:</td><td><code style="background-color: #1e293b; padding: 2px 6px;"><%= info_hash[:ansible][:playbook] %></code></td></tr>
              <tr><td style="color: #94a3b8;">Environment:</td><td><% (info_hash[:ansible][:environment] || []).each do |e| %><div style="margin-bottom: 2px;"><code style="background-color: #1e293b; padding: 2px 6px; color: #a78bfa;"><%= e %></code></div><% end %></td></tr>
              <tr><td style="color: #94a3b8;">Tags:</td><td><% (info_hash[:ansible][:tags] || []).each do |t| %><span class="w3-badge w3-tiny w3-round" style="background-color: #10b981; margin-right: 4px;"><%= t %></span><% end %></td></tr>
            </table>
          </div>
        </div>

        <div class="w3-card w3-round-large w3-margin-bottom" style="background-color: #0f172a; overflow:hidden;">
          <div class="w3-padding" style="background-color: #334155; color: #fff; font-weight: 500;"><i class="fas fa-network-wired w3-text-red"></i> Exposed Ports (DNAT)</div>
          <div class="w3-padding">
            <% if (info_hash[:exposed_ports] || []).empty? %>
              <p style="color: #94a3b8; font-style: italic;">No ports exposed</p>
            <% else %>
              <table id="dnat_table" class="w3-table w3-striped w3-small">
                <thead><tr style="color: #94a3b8;"><th>Node</th><th>Proto</th><th>Forwarding Rule</th><th></th></tr></thead>
                <tbody>
                  <% (info_hash[:exposed_ports] || []).each do |port| %>
                    <tr style="<%= 'background-color:rgba(59, 130, 246, 0.1);' if port[:adhoc] %>">
                      <td><strong><%= port[:node] %></strong></td>
                      <td><span class="w3-badge w3-tiny" style="background: #475569;"><%= port[:proto].upcase %></span></td>
                      <td><code style="color: #10b981;"><%= port[:external_port] %></code> <i class="fas fa-arrow-right" style="color: #64748b; font-size: 0.8em; margin: 0 4px;"></i> <code style="color: #38bdf8;"><%= port[:internal_port] %></code><% if port[:adhoc] %> <span style="color:#f59e0b; font-size:0.75em; font-weight: bold;">(adhoc)</span><% end %></td>
                      <td style="text-align:right; white-space: nowrap;"><button type="button" onclick="window.deleteDnat('<%= info_hash[:lab_path] %>', '<%= port[:node] %>', '<%= port[:raw_ext] %>', '<%= port[:raw_int] %>', '<%= port[:proto] %>')" class="w3-button w3-tiny w3-transparent w3-text-red w3-hover-text-light-coral" style="padding: 2px 6px;"><i class="fas fa-trash fa-lg"></i></button></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
          <% if get_running_lab == info_hash[:lab_path] %>
            <div class="w3-padding" style="border-top: 1px solid #334155; background-color: rgba(0,0,0,0.2);">
              <h6 style="color: #94a3b8; font-weight: 600; margin-top: 0;"><i class="fas fa-plus"></i> Add AdHoc DNAT Rule</h6>
              <form id="adhoc-dnat-form" onsubmit="window.submitAdhocDnat(event)" class="w3-row-padding" style="margin:0 -8px;">
                <input type="hidden" name="lab_name" value="<%= info_hash[:lab_path] %>">
                <div class="w3-col s12 m4 l4 w3-margin-bottom" style="padding:0 4px;"><select name="node" class="w3-select w3-small" required><option value="" disabled selected>-- Node --</option><% (info_hash[:nodes] || []).each do |n| %><% if n[:type] == 'host' || n[:type] == 'controller' %><option value="<%= n[:name] %>"><%= n[:name] %> (<%= n[:type] %>)</option><% end %><% end %></select></div>
                <div class="w3-col s6 m2 l2 w3-margin-bottom" style="padding:0 4px;"><input type="number" name="external_port" placeholder="Ext" min="1" max="65535" class="w3-input w3-small" required></div>
                <div class="w3-col s6 m2 l2 w3-margin-bottom" style="padding:0 4px;"><input type="number" name="internal_port" placeholder="Int" min="1" max="65535" class="w3-input w3-small" required></div>
                <div class="w3-col s6 m2 l2 w3-margin-bottom" style="padding:0 4px;"><select name="protocol" class="w3-select w3-small"><option value="tcp">TCP</option><option value="udp">UDP</option></select></div>
                <div class="w3-col s6 m2 l2 w3-margin-bottom" style="padding:0 4px;"><button type="submit" class="w3-button w3-blue w3-small w3-block"><i class="fas fa-plus"></i> Add</button></div>
              </form>
              <div id="adhoc-dnat-result" class="w3-panel w3-round" style="display:none; font-size: 0.9em; padding: 8px;"></div>
            </div>
          <% end %>
        </div>

        <div class="w3-card w3-round-large w3-margin-bottom" style="background-color: #0f172a; overflow:hidden;">
          <div class="w3-padding" style="background-color: #334155; color: #fff; font-weight: 500; display:flex; justify-content:space-between; align-items:center;">
            <span><i class="fas fa-project-diagram w3-text-green"></i> Network Links</span>
            <button type="button" onclick="window.openLinkEditor('<%= info_hash[:lab_path] %>')" class="w3-button w3-tiny w3-round w3-blue" style="padding: 2px 8px;"><i class="fas fa-plus"></i> Add Link</button>
          </div>
          <div class="w3-padding">
            <% if (info_hash[:links] || []).empty? %>
              <p style="color: #94a3b8; font-style: italic;">No links defined</p>
            <% else %>
              <table class="w3-table w3-striped w3-small">
                <thead><tr style="color: #94a3b8;"><th>Endpoint A</th><th>Endpoint B</th><th style="text-align:right;">Actions</th></tr></thead>
                <tbody>
                  <% info_hash[:links].each do |l| %>
                    <tr>
                      <td><strong style="color: #38bdf8;"><%= l[:node_a] %></strong> <span style="color: #64748b;">[<%= l[:int_a] %>]</span></td>
                      <td><strong style="color: #38bdf8;"><%= l[:node_b] %></strong> <span style="color: #64748b;">[<%= l[:int_b] %>]</span></td>
                      <td style="text-align:right; white-space: nowrap;">
                        <button type="button" onclick="window.editLinkConfig('<%= info_hash[:lab_path] %>', '<%= l[:node_a] %>', '<%= l[:int_a] %>', '<%= l[:node_b] %>', '<%= l[:int_b] %>', '<%= l[:ep1] %>', '<%= l[:ep2] %>')" class="w3-button w3-tiny w3-transparent w3-text-blue w3-hover-text-light-blue" title="Edit Link" style="padding: 2px 6px;"><i class="fas fa-edit fa-lg"></i></button>
                        <button type="button" onclick="window.deleteLink('<%= info_hash[:lab_path] %>', '<%= l[:ep1] %>', '<%= l[:ep2] %>')" class="w3-button w3-tiny w3-transparent w3-text-red w3-hover-text-light-coral" title="Delete Link" style="padding: 2px 6px;"><i class="fas fa-trash fa-lg"></i></button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>
      </div>
    </div>
  </div>

  <div id="add-node-modal" class="w3-modal" style="z-index: 9999;">
    <div class="w3-modal-content w3-round-large w3-card-4" style="background-color: #1e293b; color: #f8fafc; max-width: 600px;">
      <header class="w3-container w3-padding" style="border-bottom: 1px solid #334155; background-color: #0f172a; border-radius: 12px 12px 0 0;">
        <span onclick="document.getElementById('add-node-modal').style.display='none'" class="w3-button w3-display-topright w3-hover-red w3-round" style="color: #cbd5e1;">&times;</span>
        <h4 style="margin: 0;"><i class="fas fa-plus-circle"></i> Add Node</h4>
      </header>
      <form id="add-node-form" onsubmit="window.submitCombinedNode(event)">
        <div class="w3-container w3-padding" style="max-height: 70vh; overflow-y: auto;">
          <input type="hidden" name="lab_name" id="add-node-lab-name">
          <div class="w3-panel w3-pale-yellow w3-leftbar w3-border-yellow w3-small w3-text-black" style="padding: 8px; margin-top: 0;">
            <i class="fas fa-info-circle"></i> If the lab is running, the node will automatically boot. If stopped, it will be saved to the YAML.
          </div>

          <div class="w3-row-padding" style="margin: 0 -8px;">
            <div class="w3-col m12 w3-margin-bottom">
              <label style="font-size: 0.85em; color: #94a3b8;">Node Name</label>
              <input type="text" name="node_name" placeholder="e.g. h3" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;" required>
            </div>
            <div class="w3-col m6 w3-margin-bottom">
              <label style="font-size: 0.85em; color: #94a3b8;">Type</label>
              <select name="type" class="w3-select w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;" onchange="window.updateKindOptions(this.value, 'add-node-kind')" required>
                <option value="" disabled selected>-- Select Type --</option>
                <% (info_hash[:images_map] || {}).keys.each do |t| %><option value="<%= t %>"><%= t %></option><% end %>
              </select>
            </div>
            <div class="w3-col m6 w3-margin-bottom">
              <label style="font-size: 0.85em; color: #94a3b8;">Kind</label>
              <select name="kind" id="add-node-kind" class="w3-select w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;" required>
                <option value="" disabled selected>-- Select Kind --</option>
              </select>
            </div>
            <div class="w3-col m12 w3-margin-bottom">
              <label style="font-size: 0.85em; color: #94a3b8;">Connect to Switch (eth1)</label>
              <select name="switch" class="w3-select w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
                <option value="" selected>-- None (Mgmt Only) --</option>
                <% (info_hash[:switches] || []).each do |sw| %><option value="<%= sw %>"><%= sw %></option><% end %>
              </select>
            </div>
            <div class="w3-col m6 w3-margin-bottom">
              <label style="font-size: 0.85em; color: #94a3b8;">Data IP Address (eth1)</label>
              <input type="text" name="ip" placeholder="e.g. 192.168.10.20/24" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
            </div>
            <div class="w3-col m6 w3-margin-bottom">
              <label style="font-size: 0.85em; color: #94a3b8;">Gateway (Select or Type Override)</label>
              <input type="text" name="gw" list="gw-options" placeholder="e.g. 192.168.10.1" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
              <datalist id="gw-options">
                <% (info_hash[:gateways] || []).each do |g| %><option value="<%= g %>"><% end %>
              </datalist>
            </div>
            <div class="w3-col m12 w3-margin-bottom">
              <label style="font-size: 0.85em; color: #94a3b8;">Additional NICs (key=val)</label>
              <textarea name="nics" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: monospace; resize: vertical;" rows="2" placeholder="eth2=10.0.0.1/24"></textarea>
            </div>
            <div class="w3-col m12 w3-margin-bottom">
              <label style="font-size: 0.85em; color: #94a3b8;"><i class="fas fa-info-circle"></i> Node Info (Description)</label>
              <input type="text" name="info" class="w3-input w3-small w3-round" placeholder="e.g., Primary Database Server" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
            </div>
            <div class="w3-col m12 w3-margin-bottom">
              <label style="font-size: 0.85em; color: #94a3b8;"><i class="fas fa-terminal"></i> Terminal / SSH Link</label>
              <input type="text" name="term" class="w3-input w3-small w3-round" placeholder="e.g., ssh://root@192.168.10.5" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
            </div>
            <div class="w3-col m12 w3-margin-bottom">
              <label style="font-size: 0.85em; color: #94a3b8;"><i class="fas fa-link"></i> Custom URLs (Title|https://link.com)</label>
              <textarea name="urls_text" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: monospace; resize: vertical;" rows="2" placeholder="Walkthrough|https://docs.local/..."></textarea>
            </div>
          </div>
          <div id="add-node-result" class="w3-panel w3-round" style="display:none; font-size: 0.9em; padding: 8px; margin-bottom: 0;"></div>
        </div>
        <footer class="w3-container w3-padding" style="border-top: 1px solid #334155; background-color: #0f172a; border-radius: 0 0 12px 12px; text-align: right;">
          <button type="button" onclick="document.getElementById('add-node-modal').style.display='none'" class="w3-button w3-round w3-small" style="background-color: #475569;">Cancel</button>
          <button type="submit" class="w3-button w3-blue w3-round w3-small"><i class="fas fa-save"></i> Save Node</button>
        </footer>
      </form>
    </div>
  </div>

  <div id="node-editor-modal" class="w3-modal" style="z-index: 9999;">
    <div class="w3-modal-content w3-round-large w3-card-4" style="background-color: #1e293b; color: #f8fafc; max-width: 600px;">
      <header class="w3-container w3-padding" style="border-bottom: 1px solid #334155; background-color: #0f172a; border-radius: 12px 12px 0 0;"><span onclick="document.getElementById('node-editor-modal').style.display='none'" class="w3-button w3-display-topright w3-hover-red w3-round" style="color: #cbd5e1;">&times;</span><h4 style="margin: 0;"><i class="fas fa-edit"></i> Configure Node: <span id="editor-node-name" style="color: #38bdf8;"></span></h4></header>
      <div class="w3-container w3-padding">
        <div class="w3-panel w3-pale-yellow w3-leftbar w3-border-yellow w3-small w3-text-black" style="padding: 8px;"><i class="fas fa-info-circle"></i> If the lab is running, edits apply as an <strong>override</strong>. If stopped, they save permanently to the <strong>base YAML</strong>.</div>
        <div class="w3-bar w3-margin-bottom" style="border-bottom: 1px solid #475569;"><button type="button" class="w3-bar-item w3-button editor-tablink w3-text-blue" onclick="window.openEditorTab(event, 'FormEdit')" id="defaultTab"><b>Basic Form</b></button><button type="button" class="w3-bar-item w3-button editor-tablink" onclick="window.openEditorTab(event, 'YamlEdit')"><b>Raw YAML</b></button></div>
        <div id="FormEdit" class="editor-tab">
          <div class="w3-row-padding" style="margin: 0 -8px;">
            <div class="w3-col m6 w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Type</label><select id="edit-type" class="w3-select w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"><option value="host">host</option><option value="router">router</option><option value="switch">switch</option><option value="controller">controller</option><option value="gateway">gateway</option></select></div>
            <div class="w3-col m6 w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Kind</label><input type="text" id="edit-kind" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
            <div class="w3-col m12 w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Gateway (gw)</label><input type="text" id="edit-gw" class="w3-input w3-small w3-round" placeholder="e.g. 192.168.10.1" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
            <div class="w3-col m12 w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Network Interfaces (nics)</label><textarea id="edit-nics" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: monospace; resize: vertical;" rows="3" placeholder="eth1=192.168.10.11/24\neth2=10.0.0.1/24"></textarea></div>
            <div class="w3-col m12 w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;"><i class="fas fa-info-circle"></i> Node Info (Description)</label><input type="text" id="edit-info" class="w3-input w3-small w3-round" placeholder="e.g., Primary Database Server" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
            <div class="w3-col m12 w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;"><i class="fas fa-terminal"></i> Terminal / SSH Link</label><input type="text" id="edit-term" class="w3-input w3-small w3-round" placeholder="e.g., ssh://root@192.168.10.5" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
            <div class="w3-col m12 w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;"><i class="fas fa-link"></i> Custom URLs (Title|https://link.com)</label><textarea id="edit-urls" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: monospace; resize: vertical;" rows="3" placeholder="Flashcards|https://quizlet.com/...&#10;Walkthrough|https://docs.local/..."></textarea></div>
          </div>
        </div>
        <div id="YamlEdit" class="editor-tab" style="display:none"><textarea id="node-yaml-editor" class="w3-input w3-round w3-small" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: monospace; height: 250px; resize: vertical; white-space: pre;"></textarea></div>
        <div id="node-editor-result" class="w3-panel w3-round" style="display:none; font-size: 0.9em; padding: 8px; margin-top: 10px;"></div>
      </div>
      <footer class="w3-container w3-padding" style="border-top: 1px solid #334155; background-color: #0f172a; border-radius: 0 0 12px 12px; text-align: right;"><button type="button" onclick="document.getElementById('node-editor-modal').style.display='none'" class="w3-button w3-round w3-small" style="background-color: #475569;">Cancel</button><button type="button" onclick="window.saveNodeConfig()" class="w3-button w3-green w3-round w3-small"><i class="fas fa-save"></i> Save Override</button></footer>
    </div>
  </div>

  <div id="add-local-image-modal" class="w3-modal" style="z-index: 9999;">
    <div class="w3-modal-content w3-round-large w3-card-4" style="background-color: #1e293b; color: #f8fafc; max-width: 400px;">
      <header class="w3-container w3-padding" style="border-bottom: 1px solid #334155; background-color: #0f172a; border-radius: 12px 12px 0 0;">
        <span onclick="document.getElementById('add-local-image-modal').style.display='none'" class="w3-button w3-display-topright w3-hover-red w3-round" style="color: #cbd5e1;">&times;</span>
        <h4 style="margin: 0;"><i class="fas fa-folder-plus"></i> Add New Image</h4>
      </header>
      <form onsubmit="window.submitNewLocalImage(event)">
        <div class="w3-container w3-padding">
          <div class="w3-panel w3-pale-yellow w3-leftbar w3-border-yellow w3-small w3-text-black" style="padding: 8px;">
            <i class="fas fa-info-circle"></i> This will create the folder structure and a blank Dockerfile.
          </div>
          <label style="font-size: 0.85em; color: #94a3b8;">Image Path (e.g. centos/c9/test or kali/tool)</label>
          <input type="text" name="image_path" class="w3-input w3-small w3-round w3-margin-bottom" placeholder="category/os/kind" required style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;">
        </div>
        <footer class="w3-container w3-padding" style="border-top: 1px solid #334155; background-color: #0f172a; border-radius: 0 0 12px 12px; text-align: right;">
          <button type="button" onclick="document.getElementById('add-local-image-modal').style.display='none'" class="w3-button w3-round w3-small" style="background-color: #475569;">Cancel</button>
          <button type="submit" class="w3-button w3-blue w3-round w3-small"><i class="fas fa-plus"></i> Create Folder</button>
        </footer>
      </form>
    </div>
  </div>

  <div id="image-editor-modal" class="w3-modal" style="z-index: 9999;">
    <div class="w3-modal-content w3-round-large w3-card-4" style="background-color: #1e293b; color: #f8fafc; max-width: 400px;">
      <header class="w3-container w3-padding" style="border-bottom: 1px solid #334155; background-color: #0f172a; border-radius: 12px 12px 0 0;"><span onclick="document.getElementById('image-editor-modal').style.display='none'" class="w3-button w3-display-topright w3-hover-red w3-round" style="color: #cbd5e1;">&times;</span><h4 style="margin: 0;"><i class="fas fa-box-open"></i> Add/Edit Image</h4></header>
      <div class="w3-container w3-padding">
        <div class="w3-margin-bottom">
          <label style="font-size: 0.85em; color: #94a3b8;">Node Type & Kind</label>
          <div class="w3-row-padding" style="margin: 0 -8px;">
            <div class="w3-col s6" style="padding: 0 8px;"><input type="text" id="edit-img-type" class="w3-input w3-small w3-round" placeholder="host, router..." style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
            <div class="w3-col s6" style="padding: 0 8px;"><input type="text" id="edit-img-kind" class="w3-input w3-small w3-round" placeholder="linux" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
          </div>
        </div>
        <div class="w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Image Reference</label><input type="text" id="edit-img-ref" class="w3-input w3-small w3-round" placeholder="ctlabs/c9/base" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
        <div class="w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Capabilities (caps) - Comma separated</label><input type="text" id="edit-img-caps" class="w3-input w3-small w3-round" placeholder="SYS_PTRACE, IPC_LOCK" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
        <div class="w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Environment Variables (env) - One per line</label><textarea id="edit-img-env" class="w3-input w3-small w3-round" rows="2" placeholder="VAR=value" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: monospace;"></textarea></div>
        <div class="w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Extra Attributes (YAML formatting)</label><textarea id="edit-img-extras" class="w3-input w3-small w3-round" rows="3" placeholder="ports: 18&#10;privileged: true" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: monospace;"></textarea></div>
        <div id="image-editor-result" class="w3-panel w3-round" style="display:none; font-size: 0.9em; padding: 8px;"></div>
      </div>
      <footer class="w3-container w3-padding" style="border-top: 1px solid #334155; background-color: #0f172a; border-radius: 0 0 12px 12px; text-align: right;"><button type="button" onclick="document.getElementById('image-editor-modal').style.display='none'" class="w3-button w3-round w3-small" style="background-color: #475569;">Cancel</button><button type="button" onclick="window.saveImageConfig()" class="w3-button w3-green w3-round w3-small"><i class="fas fa-save"></i> Save</button></footer>
    </div>
  </div>

  <div id="build-image-modal" class="w3-modal" style="z-index: 9999;">
    <style>
      /* Force Monospace */
      .code-font { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace !important; }

      /* Sleek Scrollbars */
      .docker-scroll::-webkit-scrollbar { width: 10px; height: 10px; }
      .docker-scroll::-webkit-scrollbar-track { background: #0f172a; border-radius: 4px; }
      .docker-scroll::-webkit-scrollbar-thumb { background: #334155; border-radius: 4px; border: 2px solid #0f172a; }
      .docker-scroll::-webkit-scrollbar-thumb:hover { background: #38bdf8; }

      .editor-container { position: relative; height: 450px; background: #0f172a; border: 1px solid #475569; border-radius: 4px; }
      
      /* Both layers share exact same padding and fonts */
      .editor-layer { 
        position: absolute; top: 0; left: 0; width: 100%; height: 100%; 
        padding: 12px; margin: 0; border: none; 
        font-size: 13px; line-height: 1.5; 
        white-space: pre !important; 
        box-sizing: border-box; tab-size: 4; 
      }
      
      /* BACK LAYER: Give it auto scrolling so the dimensions match, but hide its ugly scrollbar */
      #raw-highlight-pre { z-index: 1; overflow: auto !important; color: #e2e8f0; -ms-overflow-style: none; scrollbar-width: none; }
      #raw-highlight-pre::-webkit-scrollbar { display: none; }
      #raw-highlight { background: transparent !important; padding: 0 !important; margin: 0 !important; }
      
      /* FRONT LAYER: Transparent text, visible scrollbar */
      #build-dockerfile { 
        z-index: 2; color: transparent !important; background: transparent !important; 
        caret-color: #38bdf8; outline: none; resize: none; overflow: auto !important; 
      }
      #build-dockerfile::selection { background: rgba(56, 189, 248, 0.3) !important; color: transparent !important; }
    </style>

    <div class="w3-modal-content w3-round-large w3-card-4" style="background-color: #1e293b; color: #f8fafc; max-width: 850px;">
      <header class="w3-container w3-padding" style="border-bottom: 1px solid #334155; background-color: #0f172a; border-radius: 12px 12px 0 0;">
        <span onclick="document.getElementById('build-image-modal').style.display='none'" class="w3-button w3-display-topright w3-hover-red w3-round" style="color: #cbd5e1;">&times;</span>
        <h4 style="margin: 0;"><i class="fas fa-file-code w3-text-orange"></i> Edit Dockerfile: <span id="build-img-name" style="color: #38bdf8;"></span></h4>
      </header>

      <div class="w3-container w3-padding">
        <input type="hidden" id="build-img-ref">

        <div class="editor-container w3-margin-top">
          <pre id="raw-highlight-pre" class="editor-layer"><code id="raw-highlight" class="language-dockerfile code-font"></code></pre>
          <textarea id="build-dockerfile" class="editor-layer docker-scroll code-font" spellcheck="false" oninput="window.updateDockerHighlight();" onscroll="window.syncDockerScroll(this);"></textarea>
        </div>

        <div id="build-image-result" class="w3-panel w3-round" style="display:none; font-size: 0.9em; padding: 8px; margin-top: 15px;"></div>
      </div>

      <footer class="w3-container w3-padding" style="border-top: 1px solid #334155; background-color: #0f172a; border-radius: 0 0 12px 12px; display: flex; justify-content: space-between; align-items: center; margin-top: 10px;">
        <button type="button" onclick="document.getElementById('build-image-modal').style.display='none'" class="w3-button w3-round w3-small" style="background-color: #475569;">Cancel</button>
        <div>
          <button type="button" onclick="window.saveDockerfileOnly()" class="w3-button w3-blue w3-round w3-small" style="margin-right: 8px;"><i class="fas fa-save"></i> Save File</button>
          <button type="button" onclick="window.triggerImageBuild(event)" class="w3-button w3-orange w3-round w3-small"><i class="fas fa-hammer"></i> Build Image</button>
        </div>
      </footer>
    </div>
  </div>

  <div id="ansible-editor-modal" class="w3-modal" style="z-index: 9999;">
    <div class="w3-modal-content w3-round-large w3-card-4" style="background-color: #1e293b; color: #f8fafc; max-width: 500px;">
      <header class="w3-container w3-padding" style="border-bottom: 1px solid #334155; background-color: #0f172a; border-radius: 12px 12px 0 0;"><span onclick="document.getElementById('ansible-editor-modal').style.display='none'" class="w3-button w3-display-topright w3-hover-red w3-round" style="color: #cbd5e1;">&times;</span><h4 style="margin: 0;"><i class="fas fa-magic"></i> Configure Ansible Playbook</h4></header>
      <div class="w3-container w3-padding">
        <div class="w3-panel w3-pale-yellow w3-leftbar w3-border-yellow w3-small w3-text-black" style="padding: 8px;"><i class="fas fa-info-circle"></i> Edits are saved as an <strong>ad-hoc override</strong> for the current run.</div>
        <div class="w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Playbook File</label><input type="text" id="edit-ansible-book" class="w3-input w3-small w3-round" placeholder="e.g. main.yml" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
        <div class="w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Tags (Comma separated)</label><input type="text" id="edit-ansible-tags" class="w3-input w3-small w3-round" placeholder="e.g. setup, web, db" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
        <div class="w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Environment Variables (One per line)</label><textarea id="edit-ansible-env" class="w3-input w3-small w3-round" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569; font-family: monospace; resize: vertical;" rows="3" placeholder="APP_ENV=production&#10;DEBUG=true"></textarea></div>
        <div id="ansible-editor-result" class="w3-panel w3-round" style="display:none; font-size: 0.9em; padding: 8px; margin-top: 10px;"></div>
      </div>
      <footer class="w3-container w3-padding" style="border-top: 1px solid #334155; background-color: #0f172a; border-radius: 0 0 12px 12px; text-align: right;"><button type="button" onclick="document.getElementById('ansible-editor-modal').style.display='none'" class="w3-button w3-round w3-small" style="background-color: #475569;">Cancel</button><button type="button" onclick="window.saveAnsibleConfig()" class="w3-button w3-green w3-round w3-small"><i class="fas fa-save"></i> Save</button></footer>
    </div>
  </div>

  <div id="link-editor-modal" class="w3-modal" style="z-index: 9999;">
    <div class="w3-modal-content w3-round-large w3-card-4" style="background-color: #1e293b; color: #f8fafc; max-width: 500px;">
      <header class="w3-container w3-padding" style="border-bottom: 1px solid #334155; background-color: #0f172a; border-radius: 12px 12px 0 0;"><span onclick="document.getElementById('link-editor-modal').style.display='none'" class="w3-button w3-display-topright w3-hover-red w3-round">&times;</span><h4 style="margin: 0;"><i class="fas fa-project-diagram"></i> Configure Network Link</h4></header>
      <div class="w3-container w3-padding">
        <input type="hidden" id="edit-link-old-ep1"><input type="hidden" id="edit-link-old-ep2">
        <div class="w3-row-padding" style="margin: 0 -8px;">
          <div class="w3-col m6 w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Node A</label><input type="text" id="edit-link-node-a" class="w3-input w3-small w3-round" placeholder="e.g. h1" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
          <div class="w3-col m6 w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Interface A</label><input type="text" id="edit-link-int-a" class="w3-input w3-small w3-round" placeholder="e.g. eth1" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
        </div>
        <div class="w3-row-padding" style="margin: 0 -8px;">
          <div class="w3-col m6 w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Node B</label><input type="text" id="edit-link-node-b" class="w3-input w3-small w3-round" placeholder="e.g. sw1" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
          <div class="w3-col m6 w3-margin-bottom"><label style="font-size: 0.85em; color: #94a3b8;">Interface B</label><input type="text" id="edit-link-int-b" class="w3-input w3-small w3-round" placeholder="e.g. eth1" style="background-color: #0f172a; color: #e2e8f0; border: 1px solid #475569;"></div>
        </div>
      </div>
      <footer class="w3-container w3-padding" style="border-top: 1px solid #334155; background-color: #0f172a; border-radius: 0 0 12px 12px; text-align: right;"><button type="button" onclick="document.getElementById('link-editor-modal').style.display='none'" class="w3-button w3-round w3-small" style="background-color: #475569;">Cancel</button><button type="button" onclick="window.saveLinkConfig()" class="w3-button w3-green w3-round w3-small"><i class="fas fa-save"></i> Save</button></footer>
    </div>
  </div>
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
