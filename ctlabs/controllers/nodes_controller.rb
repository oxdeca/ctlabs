# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/nodes_controller.rb
# Description : Controller for Node management
# License     : MIT License
# -----------------------------------------------------------------------------

class NodesController < BaseController
  # --- Fetch Node Details ---
  get '/labs/*/node/:node_name' do
    lab_name = params[:splat].first
    node_name = params[:node_name]
    lab_path = Lab.get_file_path(lab_name)

    node_cfg = nil
    if File.file?(lab_path)
      data = YAML.load_file(lab_path)
      vm = data['topology']&.first || {}
      node_cfg, plane_name = Lab.find_node_in_raw_yaml(vm, node_name)
      node_cfg['plane'] = plane_name if node_cfg && plane_name
    end

    node_cfg ||= { 'type' => 'host', 'profile' => 'linux', 'gw' => '', 'nics' => {} }

    yaml_str = node_cfg.to_yaml
    yaml_str = yaml_str.sub(/\A---\r?\n/, '')

    # --- FETCH CLOUD VM CONFIG ---
    cloud_vm_yaml = ""
    begin
      full_yaml = YAML.load_file(lab_path) || {}
      vm_topology = full_yaml['topology']&.first || {}
      ctrl_node, _ = Lab.find_node_in_raw_yaml(vm_topology, 'ansible')
      ctrl_node ||= Lab.find_node_in_raw_yaml(vm_topology, 'controller').first
      
      work_dir = ctrl_node&.dig('terraform', 'work_dir')
      if work_dir && !work_dir.strip.empty?
        config_path = "/root/ctlabs-terraform/#{work_dir}/config.yml"
        
        if File.exist?(config_path)
          lines = File.readlines(config_path)
          capturing = false
          captured_lines = []

          lines.each do |line|
            if !capturing
              if line.match?(/^\s*-\s*name\s*:\s*#{Regexp.escape(node_name)}\b/)
                capturing = true
                captured_lines << line
              end
            else
              if line.match?(/^\s*-\s*name\s*:/) || line.match?(/^[a-zA-Z0-9_-]+\s*:/)
                break
              else
                captured_lines << line
              end
            end
          end

          if captured_lines.any?
            first_indent = captured_lines.first[/\A\s*/].length
            cloud_vm_yaml = captured_lines.map { |l| l.sub(/\A\s{0,#{first_indent}}/, '') }.join.rstrip
          end
        end
      end
    rescue => e
      cloud_vm_yaml = "# ⚠️ ERROR READING config.yml ⚠️\n# #{e.message}"
    end

    content_type :json
    { yaml: yaml_str, json: node_cfg, cloud_vm_yaml: cloud_vm_yaml }.to_json
  end

  # --- Add New Node to Base Config ---
  post '/labs/*/node/new' do
    lab_name = params[:splat].first
    labs_dir = LabRepository.labs_dir
    lab_path = File.join(labs_dir, lab_name)

    begin
      yaml = YAML.load_file(lab_path) || {}
      node_name = params[:node_name].strip
      raise "Node name is required." if node_name.empty?

      yaml['topology'] ||= [{}]
      vm = yaml['topology'][0] ||= {}

      existing_node, _ = Lab.find_node_in_raw_yaml(vm, node_name)
      raise "Node '#{node_name}' already exists!" if existing_node

      new_node = Node.parse_form_data(params)
      Node.validate_profile!(new_node, yaml)
      Node.sync_to_terraform!(node_name, new_node, yaml, params[:cloud_vm_yaml])
      target_plane = new_node['plane'] || 'data'

      vm['planes'][target_plane] ||= {}
      vm['planes'][target_plane]['nodes'] ||= {}
      vm['planes'][target_plane]['nodes'][node_name] = new_node

      # --- AUTO-WIRE: link every interface that has a target switch ---
      nic_switches = Node.parse_nic_switches(params)
      primary_nic  = Lab.primary_nic_for(new_node)
      nic_switches[primary_nic] ||= params[:switch].strip if params[:switch] && !params[:switch].strip.empty?

      vm['links'] ||= []
      all_nics = (new_node['nics'] || {}).keys.map(&:to_s)
      ([primary_nic] + all_nics).uniq.each do |nic|
        sw = nic_switches[nic].to_s.strip
        next if sw.empty?
        next if vm['links'].any? { |l| l.is_a?(Array) && l.include?("#{node_name}:#{nic}") }

        port = Lab.next_free_switch_port(vm, sw)
        vm['links'] << ["#{sw}:eth#{port}", "#{node_name}:#{nic}"]
        sw_node, _ = Lab.find_node_in_raw_yaml(vm, sw)
        sw_node['ports'] = port if sw_node && port > (sw_node['ports'] || 4)
      end

      LabRepository.write_formatted_yaml(lab_path, yaml)
      { success: true, message: "Node '#{node_name}' added to base configuration." }.to_json
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # --- Add AdHoc Node to Running Lab ---
  post '/labs/*/node' do
    lab_name = params[:splat].first
    halt 400, "AdHoc Nodes only allowed on the running lab" unless Lab.current_name == lab_name
    node_name = params[:node_name]

    begin
      lab_path = Lab.get_file_path(lab_name)
      data = YAML.load_file(lab_path)

      node_cfg = Node.parse_form_data(params)
      Node.validate_profile!(node_cfg, data)

      nic_switches = Node.parse_nic_switches(params)
      primary_nic  = Lab.primary_nic_for(node_cfg)
      nic_switches[primary_nic] ||= params[:switch].strip if params[:switch] && !params[:switch].strip.empty?

      lab = Lab.new(cfg: lab_path, relative_path: lab_name)
      cfg_out, data_links = lab.add_adhoc_node(node_name, node_cfg, params[:switch], session[:vault_token], session[:vault_addr], nic_switches)

      vm = data['topology'][0]
      target_plane = cfg_out['plane'] || 'data'

      vm['planes'][target_plane] ||= {}
      vm['planes'][target_plane]['nodes'] ||= {}
      vm['planes'][target_plane]['nodes'][node_name] = cfg_out

      vm['links'] ||= []
      Array(data_links).compact.each do |data_link|
        vm['links'] << data_link
        sw_name = data_link[0].split(':eth').first
        sw_port = data_link[0].split(':eth').last.to_i

        sw_node, _ = Lab.find_node_in_raw_yaml(vm, sw_name)
        sw_node['ports'] = sw_port if sw_node && sw_port > (sw_node['ports'] || 4)
      end

      LabRepository.write_formatted_yaml(lab_path, data)
      content_type :json
      { success: true, message: "AdHoc Node '#{node_name}' started" }.to_json
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # --- Edit Node Configuration ---
  post '/labs/*/node_edit/:node_name' do
    lab_name = params[:splat].first
    node_name = params[:node_name]
    lab_path = Lab.get_file_path(lab_name)

    begin
      full_yaml = YAML.load_file(lab_path)
      vm = full_yaml['topology'][0]
      base_data, old_plane = Lab.find_node_in_raw_yaml(vm, node_name)
      base_data ||= {}

      if params[:format] == 'form'
        new_cfg = Node.parse_form_data(params, base_data)

        if new_cfg['type'] == 'tunnel' && ['openvpn', 'wireguard', 'ipsec'].include?(new_cfg['provider'].to_s.downcase)
          if params[:peers] && !params[:peers].to_s.strip.empty?
            begin
              new_cfg['peers'] = JSON.parse(params[:peers])
              new_cfg['nics'] = {}
              new_cfg.delete('profile')
              new_cfg.delete('gw')
              new_cfg.delete('image')
            rescue => e
              puts "Error parsing peers JSON: #{e.message}"
            end
          end
        else
          new_cfg.delete('peers')
        end
      else
        new_cfg = YAML.safe_load(params[:yaml_data])
      end

      Node.validate_profile!(new_cfg, full_yaml)
      Node.sync_to_terraform!(node_name, new_cfg, full_yaml, params[:cloud_vm_yaml])

      new_plane = new_cfg['plane'] || old_plane || 'data'

      if old_plane && old_plane != new_plane && vm['planes'][old_plane] && vm['planes'][old_plane]['nodes']
        vm['planes'][old_plane]['nodes'].delete(node_name)
      end
      vm['planes'][new_plane] ||= {}
      vm['planes'][new_plane]['nodes'] ||= {}
      vm['planes'][new_plane]['nodes'][node_name] = new_cfg

      # --- SYNC NIC -> SWITCH LINKS ---
      # Only when the form actually supplied the wiring map, so API / raw-YAML
      # edits never silently drop existing links.
      links_added   = []
      links_removed = []
      if params.key?(:nic_switches)
        nic_switches = Node.parse_nic_switches(params)
        primary_nic  = Lab.primary_nic_for(new_cfg)
        nic_switches[primary_nic] ||= params[:switch].strip if params[:switch] && !params[:switch].strip.empty?

        vm['links'] ||= []
        all_nics = (new_cfg['nics'] || {}).keys.map(&:to_s)

        ([primary_nic] + all_nics + nic_switches.keys).uniq.each do |nic|
          sw = nic_switches[nic].to_s.strip
          next if sw.empty?

          self_ep = "#{node_name}:#{nic}"
          existing = vm['links'].find { |l| l.is_a?(Array) && l.include?(self_ep) }
          if existing
            peer = (existing - [self_ep]).first
            # Already wired to the desired peer — leave it in place.
            next if peer.to_s.start_with?("#{sw}:")
            # Peer changed: drop the old link and recreate it below.
            vm['links'].delete(existing)
            links_removed << [self_ep, peer]
          end

          port = Lab.next_free_switch_port(vm, sw)
          new_link = ["#{sw}:eth#{port}", "#{node_name}:#{nic}"]
          vm['links'] << new_link
          sw_node, _ = Lab.find_node_in_raw_yaml(vm, sw)
          sw_node['ports'] = port if sw_node && port > (sw_node['ports'] || 4)
          links_added << new_link
        end

        vm['links'].reject! do |l|
          next false unless l.is_a?(Array)
          ep_self = l.find { |ep| ep.to_s.start_with?("#{node_name}:") }
          next false unless ep_self

          nic = ep_self.split(':', 2).last
          next false if nic == 'eth0'
          if nic_switches[nic].to_s.strip.empty?
            links_removed << [ep_self, (l - [ep_self]).first]
            true
          else
            false
          end
        end
      end

      LabRepository.write_formatted_yaml(lab_path, full_yaml)

      if Lab.running? && Lab.current_name == lab_name
        begin
          lab = Lab.new(cfg: lab_path, log: LabLog.null)
          target_node = lab.find_node(node_name)

          if target_node && !target_node.remote?
            old_nics = base_data['nics'] || {}
            new_nics = new_cfg['nics'] || {}

            # Create/remove interfaces first (hotplug_link creates the veth pair
            # and applies the node's IP), then reconcile IPs on surviving NICs.
            links_removed.each { |ep, other| lab.hotunplug_link(ep, other) if other }
            links_added.each   { |ep1, ep2| lab.hotplug_link(ep1, ep2) }

            new_nics.each do |nic_name, ip|
              next if links_added.any? { |_e1, e2| e2 == "#{node_name}:#{nic_name}" }
              if old_nics[nic_name] != ip
                target_node.hotplug_ip(nic_name, ip)
              end
            end
          end
        rescue => e
          puts "[HotPlug Error] #{e.message}"
        end
      end

      content_type :json
      { success: true, message: "Node configuration saved." }.to_json
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # --- Delete Node ---
  post '/labs/*/node/:node_name/delete' do
    lab_name = params[:splat].first
    node_name = params[:node_name]
    lab_path = Lab.get_file_path(lab_name)

    begin
      if Lab.running? && Lab.current_name == lab_name
        lab = Lab.new(cfg: lab_path, log: LabLog.null)
        target_node = lab.find_node(node_name)
        target_node.stop if target_node
      end

      yaml = YAML.load_file(lab_path)
      vm = yaml['topology'][0]

      vm['planes'].each do |_, p_data|
        p_data['nodes'].delete(node_name) if p_data && p_data['nodes']
      end

      vm['links']&.reject! do |l|
        l.is_a?(Array) && (l[0].start_with?("#{node_name}:") || l[1].start_with?("#{node_name}:"))
      end

      Node.remove_from_terraform!(node_name, yaml)
      LabRepository.write_formatted_yaml(lab_path, yaml)

      content_type :json
      { success: true, message: "Node deleted and orphaned links removed." }.to_json
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # --- Ping Node ---
  get '/labs/*/node/:node_name/ping' do
    lab_name = params[:splat].first
    node_name = params[:node_name]
    lab_path = Lab.get_file_path(lab_name)

    begin
      lab = Lab.new(cfg: lab_path, log: LabLog.null)
      target_node = lab.find_node(node_name)
      
      if target_node
        is_alive = target_node.ping
      else
        # If not fully initialized as a Node object, use the raw config
        data = YAML.load_file(lab_path)
        node_cfg, _ = Lab.find_node_in_raw_yaml(data['topology'][0], node_name)
        # Temporary node object for pinging
        temp_node = Node.new(node_cfg.merge('name' => node_name))
        is_alive = temp_node.ping
      end

      content_type :json
      { success: true, alive: is_alive }.to_json
    rescue => e
      content_type :json
      { success: true, alive: false, error: e.message }.to_json
    end
  end
end
