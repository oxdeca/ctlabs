# -----------------------------------------------------------------------------
# File        : ctlabs/helpers/application_helper.rb
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
    require 'socket' # <-- Required for the TCP Ping

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

    # Let the Node class figure out who is running!
    Node.bulk_update_status(lab.nodes) if is_running

    # Nodes (With Diffing)
    nodes = []
    if lab.nodes
      lab.nodes.each do |node|
        if node.type != "gateway"
          image_ref = 'N/A'
          if lab.defaults && lab.defaults[node.type] && lab.defaults[node.type][node.kind || 'linux']
            image_ref = lab.defaults[node.type][node.kind || 'linux']['image'] || 'N/A'
          end
          
          is_adhoc = !base_nodes_list.include?(node.name)

          node_info = {
            name: node.name,
            type: node.type   || 'N/A',
            kind: node.kind   || 'N/A',
            image: image_ref,
            cpus: 'N/A',
            memory: 'N/A',
            adhoc: is_adhoc,
            running: node.is_running # <-- Just read the property!
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
        ansible_info[:playbook]    = ctrl.play['book']  || 'N/A'
        ansible_info[:environment] = ctrl.play['env']   || []
        ansible_info[:tags]        = ctrl.play['tags']  || []
        ansible_info[:roles]       = ctrl.play['roles'] || ctrl.play['tags'] || []
      else
        ansible_info[:playbook]    = ctrl.play.to_s
      end
    end
    info[:ansible] = ansible_info

    # Terraform
    terraform_info = { workspace: 'default', work_dir: 'N/A', vars: [] }
    ctrl = lab.find_node("ansible")
    
    if ctrl && ctrl.respond_to?(:terraform) && !ctrl.terraform.nil?
      terraform_info[:workspace] = ctrl.terraform['workspace'] || 'default'
      terraform_info[:work_dir]  = ctrl.terraform['work_dir']  || 'N/A'
      terraform_info[:vars]      = ctrl.terraform['vars']      || []
    end
    info[:terraform] = terraform_info


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
end
