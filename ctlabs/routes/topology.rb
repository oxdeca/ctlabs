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

  node_cfg ||= { 'type' => 'host', 'kind' => 'linux', 'gw' => '', 'nics' => { 'eth1' => '' } }
  
  yaml_str = node_cfg.to_yaml
  yaml_str = yaml_str.gsub(/^(\s*)- -\s*(.+?)\n\1  -\s*(.+?)\n\1  -\s*(.+?)\n/) { "#{$1}- [#{$2}, #{$3}, #{$4}]\n" }
  yaml_str = yaml_str.gsub(/^(\s*)- -\s*(.+?)\n\1  -\s*(.+?)\n/) { "#{$1}- [#{$2}, #{$3}]\n" }

  content_type :json
  { yaml: yaml_str, json: node_cfg }.to_json
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

    new_node            = { 'type' => params[:type] }
    new_node['plane']   = params[:plane] unless params[:plane].to_s.empty?
    new_node['profile'] = params[:profile] unless params[:profile].to_s.empty?

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

  node_cfg = { 'type' => params[:type] || 'host', 'profile' => params[:profile] || 'linux' }
  node_cfg['plane']    = params[:plane] unless params[:plane].to_s.empty?
  node_cfg['gw']       = params[:gw].strip if params[:gw] && !params[:gw].strip.empty?
  node_cfg['nics']     = { 'eth1' => params[:ip].strip } if params[:ip] && !params[:ip].strip.empty?
  node_cfg['provider'] = params[:provider] unless params[:provider].to_s.empty?

  begin
    lab_path = get_lab_file_path(lab_name)
    lab = Lab.new(cfg: lab_path)
    cfg_out, data_link = lab.add_adhoc_node(node_name, node_cfg, params[:switch])

    data = YAML.load_file(lab_path)
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
    else
      new_cfg = YAML.safe_load(params[:yaml_data])
    end

    new_plane = new_cfg['plane'] || old_plane || 'data'

    if vm['planes']
      # Remove from old plane if it moved
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

          # Handle IP Changes & New NICs
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
    # -------------------------------

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

    write_formatted_yaml(lab_path, yaml)
    { success: true, message: "Node deleted and orphaned links removed." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end


#
# ASYNC LIVENESS CHECK
#
get '/labs/*/node/:node_name/ping' do
  lab_name = params[:splat].first
  node_name = params[:node_name]
  lab_path = get_lab_file_path(lab_name)

  begin
    data = YAML.load_file(lab_path)
    node_cfg, _ = find_node_in_raw_yaml(data['topology'][0], node_name)
    
    # Extract Public Mgmt IP from the 'gw' field
    target_ip = node_cfg['gw'].to_s.split('/').first

    if target_ip.nil? || target_ip.strip.empty?
      halt 400, { success: false, error: "No IP defined in gw field" }.to_json
    end

    is_alive = false
    begin
      # Native TCP connection with a strict 1-second timeout to port 22
      Socket.tcp(target_ip, 22, connect_timeout: 1) { |sock| is_alive = true }
    rescue StandardError
      is_alive = false
    end

    content_type :json
    { success: true, alive: is_alive }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# ===================================================
# LINKS
# ===================================================
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


# ===================================================
# DNAT
# ===================================================
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

