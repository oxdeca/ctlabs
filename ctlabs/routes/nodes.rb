# -----------------------------------------------------------------------------
# File        : ctlabs/routes/nodes.rb
# License     : MIT License
# -----------------------------------------------------------------------------

require 'socket'
require 'timeout'

# ===================================================
# ROUTES
# ===================================================

get '/labs/*/node/:node_name' do
  lab_name = params[:splat].first
  node_name = params[:node_name]
  lab_path = get_lab_file_path(lab_name)

  node_cfg = nil
  if File.file?(lab_path)
    data = YAML.load_file(lab_path)
    vm = data['topology']&.first || {}
    node_cfg, plane_name = find_node_in_raw_yaml(vm, node_name)
    node_cfg['plane'] = plane_name if node_cfg && plane_name
  end

  node_cfg ||= { 'type' => 'host', 'profile' => 'linux', 'gw' => '', 'nics' => {} }

  yaml_str = node_cfg.to_yaml
  yaml_str = yaml_str.gsub(/^(\s*)- -\s*(.+?)\n\1  -\s*(.+?)\n\1  -\s*(.+?)\n/) { "#{$1}- [#{$2}, #{$3}, #{$4}]\n" }
  yaml_str = yaml_str.gsub(/^(\s*)- -\s*(.+?)\n\1  -\s*(.+?)\n/) { "#{$1}- [#{$2}, #{$3}]\n" }

  # --- FETCH CLOUD VM CONFIG ---
  cloud_vm_yaml = ""
  begin
    full_yaml = YAML.load_file(lab_path) || {}
    vm_topology = full_yaml['topology']&.first || {}
    ctrl_node, _ = find_node_in_raw_yaml(vm_topology, 'ansible')
    ctrl_node ||= find_node_in_raw_yaml(vm_topology, 'controller').first
    
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

post '/labs/*/node/new' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path) || {}
    node_name = params[:node_name].strip
    raise "Node name is required." if node_name.empty?

    yaml['topology'] ||= [{}]
    vm = yaml['topology'][0] ||= {}

    existing_node, _ = find_node_in_raw_yaml(vm, node_name)
    raise "Node '#{node_name}' already exists!" if existing_node

    new_node = parse_node_form_data(params)
    validate_node_profile!(new_node, yaml)
    sync_node_to_terraform_config!(node_name, new_node, yaml, params[:cloud_vm_yaml])
    target_plane = new_node['plane'] || 'data'

    if vm['planes']
      vm['planes'][target_plane] ||= {}
      vm['planes'][target_plane]['nodes'] ||= {}
      vm['planes'][target_plane]['nodes'][node_name] = new_node
    else
      vm['nodes'] ||= {}
      vm['nodes'][node_name] = new_node
    end

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

  begin
    lab_path = get_lab_file_path(lab_name)
    data = YAML.load_file(lab_path)

    node_cfg = parse_node_form_data(params)
    validate_node_profile!(node_cfg, data)

    lab = Lab.new(cfg: lab_path, relative_path: lab_name)
    cfg_out, data_link = lab.add_adhoc_node(node_name, node_cfg, params[:switch], session[:vault_token], session[:vault_addr])

    vm = data['topology'][0]
    target_plane = cfg_out['plane'] || 'data'

    if vm['planes']
      vm['planes'][target_plane] ||= {}
      vm['planes'][target_plane]['nodes'] ||= {}
      vm['planes'][target_plane]['nodes'][node_name] = cfg_out
    else
      vm['nodes'] ||= {}
      vm['nodes'][node_name] = cfg_out
    end

    vm['links'] ||= []
    if data_link
      vm['links'] << data_link
      sw_name = params[:switch].strip
      sw_port = data_link[0].split(':eth').last.to_i

      sw_node, _ = find_node_in_raw_yaml(vm, sw_name)
      sw_node['ports'] = sw_port if sw_node && sw_port > (sw_node['ports'] || 4)
    end

    write_formatted_yaml(lab_path, data)
    content_type :json
    { success: true, message: "AdHoc Node '#{node_name}' started" }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

post '/labs/*/node_edit/:node_name' do
  lab_name = params[:splat].first
  node_name = params[:node_name]
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path)
    vm = full_yaml['topology'][0]
    base_data, old_plane = find_node_in_raw_yaml(vm, node_name)
    base_data ||= {}

    if params[:format] == 'form'
      new_cfg = parse_node_form_data(params, base_data)

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

    validate_node_profile!(new_cfg, full_yaml)
    sync_node_to_terraform_config!(node_name, new_cfg, full_yaml, params[:cloud_vm_yaml])

    new_plane = new_cfg['plane'] || old_plane || 'data'

    if vm['planes']
      if old_plane && old_plane != new_plane && vm['planes'][old_plane] && vm['planes'][old_plane]['nodes']
        vm['planes'][old_plane]['nodes'].delete(node_name)
      end
      vm['planes'][new_plane] ||= {}
      vm['planes'][new_plane]['nodes'] ||= {}
      vm['planes'][new_plane]['nodes'][node_name] = new_cfg
    else
      vm['nodes'][node_name] = new_cfg
    end

    write_formatted_yaml(lab_path, full_yaml)

    if Lab.running? && Lab.current_name == lab_name
      begin
        lab = Lab.new(cfg: lab_path, log: LabLog.null)
        target_node = lab.find_node(node_name)

        if target_node && !target_node.remote?
          old_nics = base_data['nics'] || {}
          new_nics = new_cfg['nics'] || {}

          new_nics.each do |nic_name, ip|
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

post '/labs/*/node/:node_name/delete' do
  lab_name = params[:splat].first
  node_name = params[:node_name]
  lab_path = get_lab_file_path(lab_name)

  begin
    if Lab.running? && Lab.current_name == lab_name
      lab = Lab.new(cfg: lab_path, log: LabLog.null)
      target_node = lab.find_node(node_name)
      target_node.stop if target_node
    end

    yaml = YAML.load_file(lab_path)
    vm = yaml['topology'][0]

    if vm['nodes']
      vm['nodes'].delete(node_name)
    elsif vm['planes']
      vm['planes'].each do |_, p_data|
        p_data['nodes'].delete(node_name) if p_data && p_data['nodes']
      end
    end

    vm['links']&.reject! do |l|
      l.is_a?(Array) && (l[0].start_with?("#{node_name}:") || l[1].start_with?("#{node_name}:"))
    end

    remove_node_from_terraform_config!(node_name, yaml)

    write_formatted_yaml(lab_path, yaml)
    { success: true, message: "Node deleted and orphaned links removed." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

get '/labs/*/node/:node_name/ping' do
  lab_name = params[:splat].first
  node_name = params[:node_name]
  lab_path = get_lab_file_path(lab_name)

  begin
    data = YAML.load_file(lab_path)
    node_cfg, _ = find_node_in_raw_yaml(data['topology'][0], node_name)

    if node_cfg['type'] == 'tunnel' && ['openvpn', 'wireguard', 'ipsec'].include?(node_cfg['provider'].to_s.downcase)
      content_type :json
      return { success: true, alive: true }.to_json
    end

    nics = node_cfg['nics'] || {}
    string_nics = nics.transform_keys(&:to_s) rescue nics

    raw_ip = string_nics['eth0'] || node_cfg['gw'] || string_nics['eth1'] || string_nics['tun0']
    target_ip = raw_ip.to_s.split('/').first.to_s.strip

    if target_ip.empty?
      content_type :json
      return { success: true, alive: false }.to_json
    end

    is_alive = false
    begin
      Timeout.timeout(1.0) do
        Socket.tcp(target_ip, 22, connect_timeout: 1.0) { |sock| is_alive = true }
      end
    rescue StandardError
      is_alive = false
    end

    content_type :json
    { success: true, alive: is_alive }.to_json
  rescue => e
    content_type :json
    { success: true, alive: false, error: e.message }.to_json
  end
end
