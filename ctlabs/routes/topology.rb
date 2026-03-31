# -----------------------------------------------------------------------------
# File        : ctlabs/routes/topology.rb
# License     : MIT License
# -----------------------------------------------------------------------------

require 'socket'
require 'timeout'

# ===================================================
# HELPER: Find node in raw YAML (supports v1 and v2)
# ===================================================
def find_node_in_raw_yaml(vm_cfg, node_name)
  if vm_cfg['nodes'] && vm_cfg['nodes'][node_name]
    return vm_cfg['nodes'][node_name], nil
  elsif vm_cfg['planes']
    vm_cfg['planes'].each do |p_name, p_data|
      if p_data && p_data['nodes'] && p_data['nodes'][node_name]
        return p_data['nodes'][node_name], p_name
      end
    end
  end
  [nil, nil]
end

# ===================================================
# HELPER: Parse Form Data (DRY Helper)
# ===================================================
def parse_node_form_data(params, base_data = {})
  new_cfg = base_data.dup
  new_cfg['type'] = params[:type] unless params[:type].to_s.empty?
  params[:plane].to_s.empty? ? new_cfg.delete('plane') : new_cfg['plane'] = params[:plane]
  params[:profile].to_s.empty? ? new_cfg.delete('profile') : new_cfg['profile'] = params[:profile]
  params[:provider].to_s.empty? ? new_cfg.delete('provider') : new_cfg['provider'] = params[:provider]
  params[:gw].to_s.empty? ? new_cfg.delete('gw') : new_cfg['gw'] = params[:gw]
  params[:info].to_s.empty? ? new_cfg.delete('info') : new_cfg['info'] = params[:info]
  params[:term].to_s.empty? ? new_cfg.delete('term') : new_cfg['term'] = params[:term]

  if params[:nics] && !params[:nics].strip.empty?
    new_cfg['nics'] = params[:nics].split("\n").map { |l| l.split('=').map(&:strip) }.to_h.reject { |k,v| k.nil? || v.nil? }
  else
    new_cfg.delete('nics')
  end

  if params[:urls_text] && !params[:urls_text].strip.empty?
    urls_hash = {}
    params[:urls_text].split("\n").each do |line|
      title, link = line.split('|', 2)
      urls_hash[title.strip] = link.strip if title && !title.strip.empty? && link && !link.strip.empty?
    end
    new_cfg['urls'] = urls_hash unless urls_hash.empty?
  else
    new_cfg.delete('urls')
  end

  ['vols', 'env', 'devs'].each do |field|
    if params[field] && !params[field].strip.empty?
      new_cfg[field] = params[field].split("\n").map(&:strip).reject(&:empty?)
    else
      new_cfg.delete(field)
    end
  end

  # --- PARSE TERRAFORM CONFIG ---
  if params[:terraform] && !params[:terraform].strip.empty?
    require 'json'
    begin
      new_cfg['terraform'] = JSON.parse(params[:terraform])
    rescue JSON::ParserError
      # Silently ignore bad JSON payloads
    end
  else
    new_cfg.delete('terraform')
  end

  new_cfg
end


# ===================================================
# HELPER: Auto-Assign Management IP
# ===================================================
def auto_assign_mgmt_ip!(node_cfg, full_yaml)
  target_nic = (node_cfg['provider'] && node_cfg['provider'] != 'local') ? 'tun0' : 'eth0'
  node_cfg['nics'] ||= {}

  if node_cfg['nics'][target_nic].to_s.empty?
    mgmt_net_str = full_yaml.dig('topology', 0, 'planes', 'mgmt', 'net') || full_yaml.dig('topology', 0, 'mgmt', 'net') || "192.168.99.0/24"
    used_ips = []

    vm = full_yaml['topology'][0]
    nodes_to_scan = vm['planes'] ? vm['planes'].values.map { |p| p['nodes'] } : [vm['nodes']]

    nodes_to_scan.compact.each do |node_group|
      node_group.each do |_, n|
        n['nics']&.values&.each { |ip| used_ips << ip.split('/')[0] if ip }
        used_ips << n['ipv4'].split('/')[0] if n['ipv4'] && !n['ipv4'].to_s.empty?
      end
    end

    require 'ipaddr'
    begin
      subnet = IPAddr.new(mgmt_net_str)
      ip_range = subnet.to_range.to_a
      start_idx = [20, ip_range.size - 2].min
      next_ip = ip_range[start_idx..-2].find { |ip| !used_ips.include?(ip.to_s) }

      if next_ip
        node_cfg['nics'][target_nic] = "#{next_ip}/#{subnet.prefix}"
      end
    rescue => e
      puts "[IP Calc Error] Could not auto-calculate IP: #{e.message}"
    end
  end
end

# ===================================================
# HELPER: Schema Validation (Block undefined profiles)
# ===================================================
def validate_node_profile!(node_cfg, full_yaml)
  type = node_cfg['type'] || 'host'
  profile = node_cfg['profile'] || node_cfg['kind']

  # Only validate if a profile is explicitly requested
  return if profile.nil? || profile.to_s.strip.empty?

  # 1. Check local lab overrides first
  profile_key = full_yaml.key?('profiles') ? 'profiles' : 'defaults'
  return if full_yaml.dig(profile_key, type, profile)

  # 2. Check the global profiles dictionary
  if File.exist?(::GLOBAL_PROFILES)
    global_yaml = YAML.load_file(::GLOBAL_PROFILES) || {}
    global_key = global_yaml.key?('profiles') ? 'profiles' : 'defaults'
    
    return if global_yaml.dig(global_key, type, profile)
  end

  # 3. If it's in neither place, block it!
  raise "Schema Error: Profile '#{profile}' is not defined for type '#{type}'. Please create it in the global config/profiles.yml file or override it in this lab."
end

# ===================================================
# HELPER: Sync Node to Terraform config.yml (Text-Based)
# ===================================================
def sync_node_to_terraform_config!(node_name, node_cfg, full_lab_yaml, cloud_vm_yaml_payload)
  return unless node_cfg['provider'].to_s.downcase == 'gcp'
  return if cloud_vm_yaml_payload.nil? || cloud_vm_yaml_payload.strip.empty?

  vm_topology = full_lab_yaml['topology']&.first || {}
  ctrl_node, _ = find_node_in_raw_yaml(vm_topology, 'ansible')
  ctrl_node ||= find_node_in_raw_yaml(vm_topology, 'controller').first
  
  work_dir = ctrl_node&.dig('terraform', 'work_dir')
  return if work_dir.nil? || work_dir.strip.empty?

  config_path = "/root/ctlabs-terraform/#{work_dir}/config.yml"
  
  unless File.exist?(config_path)
    puts "[Warning] config.yml not found at #{config_path}. Cannot save Cloud VM snippet."
    return
  end

  # --- INDENTATION NORMALIZER ---
  # We figure out how many spaces the user put in front of "- name:", 
  # strip them, and strictly enforce exactly 2 spaces so it aligns perfectly under "vms:"
  lines = cloud_vm_yaml_payload.rstrip.lines
  first_line_indent = lines.first[/\A\s*/].length
  
  payload = lines.map do |line|
    unindented = line.sub(/\A\s{0,#{first_line_indent}}/, '')
    "  #{unindented}"
  end.join + "\n"
  # ------------------------------

  content = File.read(config_path)

  regex = /^(\s*)-\s*name\s*:\s*#{Regexp.escape(node_name)}\b.*?(?=(^\s*-\s*name\s*:|^\S|\z))/m

  if content.match?(regex)
    content.sub!(regex, payload)
  else
    if content.match?(/^vms:\s*$/)
      content.sub!(/^vms:\s*$/, "vms:\n" + payload)
    else
      content += "\n\nvms:\n" + payload
    end
  end

  File.write(config_path, content)
  puts "[SUCCESS] Updated #{node_name} in #{config_path}"
end


# ===================================================
# HELPER: Remove Node from Terraform config.yml
# ===================================================
def remove_node_from_terraform_config!(node_name, full_lab_yaml)
  vm_topology = full_lab_yaml['topology']&.first || {}
  ctrl_node, _ = find_node_in_raw_yaml(vm_topology, 'ansible')
  ctrl_node ||= find_node_in_raw_yaml(vm_topology, 'controller').first
  
  work_dir = ctrl_node&.dig('terraform', 'work_dir')
  return if work_dir.nil? || work_dir.strip.empty?

  config_path = "/root/ctlabs-terraform/#{work_dir}/config.yml"
  #config_path = File.expand_path(File.join("..", "ctlabs-terraform", work_dir, "config.yml"))
  return unless File.exist?(config_path)

  tf_config = YAML.load_file(config_path) || {}
  if tf_config['vms']
    tf_config['vms'].reject! { |v| v['name'] == node_name }
    File.write(config_path, tf_config.to_yaml)
  end
end

# ===================================================
# NODES
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
        # BULLETPROOF LINE-BY-LINE PARSER
        lines = File.readlines(config_path)
        capturing = false
        captured_lines = []

        lines.each do |line|
          if !capturing
            # Start capturing when we find our exact VM block
            if line.match?(/^\s*-\s*name\s*:\s*#{Regexp.escape(node_name)}\b/)
              capturing = true
              captured_lines << line
            end
          else
            # Stop capturing if we hit the next VM block OR a root-level YAML key
            if line.match?(/^\s*-\s*name\s*:/) || line.match?(/^[a-zA-Z0-9_-]+\s*:/)
              break
            else
              captured_lines << line
            end
          end
        end

        if captured_lines.any?
          # Cleanly un-indent the block so it aligns perfectly in the CodeMirror editor
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

    # Let the Lab Engine handle the IP calculation and wiring perfectly!
    lab = Lab.new(cfg: lab_path, relative_path: lab_name)
    cfg_out, data_link = lab.add_adhoc_node(node_name, node_cfg, params[:switch])

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

      # --- NEW: VPN Peer Handling ---
      if new_cfg['type'] == 'tunnel' && ['openvpn', 'wireguard', 'ipsec'].include?(new_cfg['provider'].to_s.downcase)
        if params[:peers] && !params[:peers].to_s.strip.empty?
          begin
            new_cfg['peers'] = JSON.parse(params[:peers])
            new_cfg['nics'] = {}  # Set explicitly to empty hash, prevents 'nil' errors!
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
      # ------------------------------

    else
      new_cfg = YAML.safe_load(params[:yaml_data])
    end

    validate_node_profile!(new_cfg, full_yaml)
    
    # --- DIAGNOSTIC TRACE ---
    puts "\n" + "="*50
    puts "[DIAGNOSTIC] Node Edit Save triggered for: #{node_name}"
    puts "[DIAGNOSTIC] 1. Provider is: '#{new_cfg['provider']}'"
    puts "[DIAGNOSTIC] 2. Payload received? : #{!params[:cloud_vm_yaml].nil? && !params[:cloud_vm_yaml].strip.empty?}"
    
    vm_topology_diag = full_yaml['topology']&.first || {}
    ctrl_node_diag, _ = find_node_in_raw_yaml(vm_topology_diag, 'ansible')
    ctrl_node_diag ||= find_node_in_raw_yaml(vm_topology_diag, 'controller').first
    
    work_dir_diag = ctrl_node_diag&.dig('terraform', 'work_dir')
    puts "[DIAGNOSTIC] 3. Controller Node Found? : #{!ctrl_node_diag.nil?}"
    puts "[DIAGNOSTIC] 4. Work Dir extracted: '#{work_dir_diag}'"
    
    if work_dir_diag
      config_path_diag = "/root/ctlabs-terraform/#{work_dir_diag}/config.yml"
      #config_path_diag = File.expand_path(File.join("..", "ctlabs-terraform", work_dir_diag, "config.yml"))
      puts "[DIAGNOSTIC] 5. Target config file exists? : #{File.exist?(config_path_diag)} (Path: #{config_path_diag})"
    end
    puts "="*50 + "\n"

    # Now actually run the sync
    sync_node_to_terraform_config!(node_name, new_cfg, full_yaml, params[:cloud_vm_yaml])
    # ------------------------

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

    # --- HOT-PLUG DIFFING ENGINE ---
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

    # 1. Abstract VPN Tunnels are conceptually "alive" (no SSH needed)
    if node_cfg['type'] == 'tunnel' && ['openvpn', 'wireguard', 'ipsec'].include?(node_cfg['provider'].to_s.downcase)
      content_type :json
      return { success: true, alive: true }.to_json
    end

    # 2. Extract IP safely using the new schema priorities
    nics = node_cfg['nics'] || {}
    string_nics = nics.transform_keys(&:to_s) rescue nics

    raw_ip = string_nics['eth0'] || node_cfg['gw'] || string_nics['eth1'] || string_nics['tun0']
    target_ip = raw_ip.to_s.split('/').first.to_s.strip

    # FIX: Return HTTP 200 instead of 400 when there is no IP yet.
    # This tells the JS cleanly that the node is offline, stopping the spinner!
    if target_ip.empty?
      content_type :json
      return { success: true, alive: false }.to_json
    end

    # 3. Perform the native Ruby health check with a strict timeout wrapper
    is_alive = false
    begin
      require 'socket'
      require 'timeout'
      
      Timeout.timeout(1.0) do
        Socket.tcp(target_ip, 22, connect_timeout: 1.0) { |sock| is_alive = true }
      end
    rescue StandardError
      is_alive = false
    end

    content_type :json
    { success: true, alive: is_alive }.to_json
  rescue => e
    # Return 200 even on total failure so the UI spinner stops
    content_type :json
    { success: true, alive: false, error: e.message }.to_json
  end
end

post '/labs/*/link/save' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    yaml['topology'][0]['links'] ||= []

    ep1 = "#{params[:node_a]}:#{params[:int_a]}"
    ep2 = "#{params[:node_b]}:#{params[:int_b]}"
    new_link = [ep1, ep2]

    if params[:old_ep1] && params[:old_ep2] && !params[:old_ep1].empty?
      if Lab.running? && Lab.current_name == lab_name
        Lab.new(cfg: lab_path, log: LabLog.null).hotunplug_link(params[:old_ep1], params[:old_ep2])
      end

      idx = yaml['topology'][0]['links'].find_index { |l| l.is_a?(Array) && l.include?(params[:old_ep1]) && l.include?(params[:old_ep2]) }
      idx ? (yaml['topology'][0]['links'][idx] = new_link) : (yaml['topology'][0]['links'] << new_link)
    else
      yaml['topology'][0]['links'] << new_link
    end

    write_formatted_yaml(lab_path, yaml)

    if Lab.running? && Lab.current_name == lab_name
      Lab.new(cfg: lab_path, log: LabLog.null).hotplug_link(ep1, ep2)
    end

    { success: true, message: "Link saved and connected successfully." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

post '/labs/*/link/delete' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    yaml['topology'][0]['links']&.reject! { |l| l.is_a?(Array) && l.include?(params[:ep1]) && l.include?(params[:ep2]) }
    write_formatted_yaml(lab_path, yaml)

    if Lab.running? && Lab.current_name == lab_name
      Lab.new(cfg: lab_path, log: LabLog.null).hotunplug_link(params[:ep1], params[:ep2])
    end

    { success: true, message: "Link deleted and disconnected." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

post '/labs/*/dnat' do
  lab_name = params[:splat].first
  halt 400, "AdHoc DNAT only allowed on the running lab" unless get_running_lab == lab_name

  begin
    lab_path = get_lab_file_path(lab_name)
    lab = Lab.new(cfg: lab_path)
    rule = lab.add_adhoc_dnat(params[:node], params[:external_port].to_i, params[:internal_port].to_i, (params[:protocol] || 'tcp').downcase)

    data = YAML.load_file(lab_path)
    node_cfg, _ = find_node_in_raw_yaml(data['topology'][0], params[:node])

    if node_cfg
      node_cfg['dnat'] ||= []
      node_cfg['dnat'] << [params[:external_port].to_i, params[:internal_port].to_i, (params[:protocol] || 'tcp').downcase]
      write_formatted_yaml(lab_path, data)
    end

    content_type :json
    { success: true, message: "AdHoc DNAT rule added" }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

post '/labs/*/dnat/delete' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    node = params[:node]
    node_cfg, _ = find_node_in_raw_yaml(yaml['topology'][0], node)
    dnat_rules = node_cfg['dnat'] rescue nil

    if dnat_rules
      dnat_rules.reject! { |r| r[0].to_s == params[:ext].to_s && r[1].to_s == params[:int].to_s && (r[2] || 'tcp').to_s == params[:proto].to_s }
      node_cfg.delete('dnat') if dnat_rules.empty?
      write_formatted_yaml(lab_path, yaml)
    end
    { success: true, message: "DNAT rule deleted." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

get '/labs/*/raw' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  
  if File.exist?(lab_path)
    content_type 'text/plain'
    File.read(lab_path)
  else
    status 404
    "File not found"
  end
end

post '/labs/*/raw' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  
  begin
    yaml_content = params[:yaml_content]
    
    # Optional: Safely parse it first to ensure the user didn't write broken YAML
    YAML.safe_load(yaml_content)
    
    File.write(lab_path, yaml_content)
    content_type :json
    { success: true }.to_json
  rescue => e
    status 400
    content_type :json
    { success: false, error: "Invalid YAML: #{e.message}" }.to_json
  end
end

get '/labs/*/cloud_config' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  
  begin
    full_yaml = YAML.load_file(lab_path) || {}
    vm_topology = full_yaml['topology']&.first || {}
    ctrl_node, _ = find_node_in_raw_yaml(vm_topology, 'ansible')
    ctrl_node ||= find_node_in_raw_yaml(vm_topology, 'controller').first

    work_dir = ctrl_node&.dig('terraform', 'work_dir')
    raise "No Terraform working directory configured for this lab." if work_dir.nil? || work_dir.strip.empty?

    config_path = "/root/ctlabs-terraform/#{work_dir}/config.yml"
    #config_path = File.expand_path(File.join("..", "ctlabs-terraform", work_dir, "config.yml"))
    raise "config.yml not found at: #{config_path}" unless File.exist?(config_path)

    content_type :json
    { success: true, content: File.read(config_path) }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

post '/labs/*/cloud_config' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  
  begin
    full_yaml = YAML.load_file(lab_path) || {}
    vm_topology = full_yaml['topology']&.first || {}
    ctrl_node, _ = find_node_in_raw_yaml(vm_topology, 'ansible')
    ctrl_node ||= find_node_in_raw_yaml(vm_topology, 'controller').first

    work_dir = ctrl_node&.dig('terraform', 'work_dir')
    raise "No Terraform working directory configured for this lab." if work_dir.nil? || work_dir.strip.empty?

    config_path = "/root/ctlabs-terraform/#{work_dir}/config.yml"
    #config_path = File.expand_path(File.join("..", "ctlabs-terraform", work_dir, "config.yml"))
    
    # Validate it's proper YAML before blindly overwriting
    yaml_content = params[:content]
    YAML.safe_load(yaml_content)
    
    File.write(config_path, yaml_content)
    
    content_type :json
    { success: true }.to_json
  rescue => e
    status 400
    { success: false, error: "Invalid YAML: #{e.message}" }.to_json
  end
end
