# -----------------------------------------------------------------------------
# File        : ctlabs/helpers/lab_helper.rb
# License     : MIT License
# -----------------------------------------------------------------------------

module LabHelper

  # ---------------------------------------------------------------------------
  # Helper: Find node in raw YAML (supports v1 and v2)
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Helper: Parse Form Data (DRY Helper)
  # ---------------------------------------------------------------------------
  def parse_node_form_data(params, base_data = {})
    new_cfg         = base_data.dup

    new_cfg['type'] = params[:type] unless params[:type].to_s.empty?
    params[:plane].to_s.empty?    ? new_cfg.delete('plane')    : new_cfg['plane']    = params[:plane]
    params[:profile].to_s.empty?  ? new_cfg.delete('profile')  : new_cfg['profile']  = params[:profile]
    params[:provider].to_s.empty? ? new_cfg.delete('provider') : new_cfg['provider'] = params[:provider]
    params[:gw].to_s.empty?       ? new_cfg.delete('gw')       : new_cfg['gw']       = params[:gw]
    params[:info].to_s.empty?     ? new_cfg.delete('info')     : new_cfg['info']     = params[:info]
    params[:term].to_s.empty?     ? new_cfg.delete('term')     : new_cfg['term']     = params[:term]

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

  # ---------------------------------------------------------------------------
  # Helper: Auto-Assign Management IP
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Helper: Schema Validation (Block undefined profiles)
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Helper: Sync Node to Terraform config.yml (Text-Based)
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Helper: Remove Node from Terraform config.yml
  # ---------------------------------------------------------------------------
  def remove_node_from_terraform_config!(node_name, full_lab_yaml)
    vm_topology = full_lab_yaml['topology']&.first || {}
    ctrl_node, _ = find_node_in_raw_yaml(vm_topology, 'ansible')
    ctrl_node ||= find_node_in_raw_yaml(vm_topology, 'controller').first
    
    work_dir = ctrl_node&.dig('terraform', 'work_dir')
    return if work_dir.nil? || work_dir.strip.empty?

    config_path = "/root/ctlabs-terraform/#{work_dir}/config.yml"
    return unless File.exist?(config_path)

    tf_config = YAML.load_file(config_path) || {}
    if tf_config['vms']
      tf_config['vms'].reject! { |v| v['name'] == node_name }
      File.write(config_path, tf_config.to_yaml)
    end
  end

  # ---------------------------------------------------------------------------
  # Helper: Check if a profile is used by any node
  # ---------------------------------------------------------------------------
  def profile_in_use?(yaml, target_type, target_profile)
    vm = yaml['topology']&.first || {}
    
    # Gather all nodes across all planes (or flat nodes array)
    nodes_to_scan = vm['planes'] ? vm['planes'].values.map { |p| p['nodes'] } : [vm['nodes']]
    
    nodes_to_scan.compact.each do |node_group|
      node_group.values.each do |n|
        node_type = n['type'] || 'host'
        node_prof = n['profile'] || n['kind'] || 'linux'
        
        # If we find a match, it is in use!
        if node_type.to_s == target_type.to_s && node_prof.to_s == target_profile.to_s
          return true
        end
      end
    end
    false
  end

  # ---------------------------------------------------------------------------
  # Helper to safely resolve the lab file path (Runtime vs Base)
  # ---------------------------------------------------------------------------
  def get_lab_file_path(lab_name)
    runtime_path = "#{LOCK_DIR}/#{lab_name.gsub('/', '_')}.yml"
    (Lab.running? && Lab.current_name == lab_name && File.file?(runtime_path)) ? runtime_path : File.join(LABS_DIR, lab_name)
  end

  # ---------------------------------------------------------------------------
  # Maps switches to their connected router's gateway IP
  # ---------------------------------------------------------------------------
  def generate_switch_gw_map(lab_path, links)
    switch_gw_map = {}
    begin
      full_path = File.join("..", "labs", lab_path)
      return switch_gw_map unless File.exist?(full_path)

      raw_yaml = YAML.load_file(full_path) || {}
      raw_nodes = raw_yaml['topology']&.first&.dig('nodes') || {}
      
      (links || []).each do |l|
        node_a = raw_nodes[l[:node_a]] || {}
        node_b = raw_nodes[l[:node_b]] || {}
        
        if ['router', 'gateway', 'controller'].include?(node_a['type']) && node_b['type'] == 'switch'
          ip_cidr = node_a['nics'] && node_a['nics'][l[:int_a]]
          switch_gw_map[l[:node_b]] = ip_cidr.split('/').first if ip_cidr
        elsif ['router', 'gateway', 'controller'].include?(node_b['type']) && node_a['type'] == 'switch'
          ip_cidr = node_b['nics'] && node_b['nics'][l[:int_b]]
          switch_gw_map[l[:node_a]] = ip_cidr.split('/').first if ip_cidr
        end
      end
    rescue => e
      puts "Failed to generate switch GW map: #{e.message}"
    end
    switch_gw_map
  end

  # ---------------------------------------------------------------------------
  # Safely resolves and reads the contents of the Ansible inventory files
  # ---------------------------------------------------------------------------
  def fetch_inventory_contents
    mgmt_path = 'public/inventory.ini'
    data_path = 'public/inventory_data.ini'

    if Lab.running?
      begin
        full_path = get_lab_file_path(Lab.current_name)
        lab = Lab.new(cfg: full_path, log: LabLog.null)
        
        pubdir = lab.instance_variable_get(:@pubdir)
        if pubdir
          mgmt_path = File.join(pubdir, 'inventory.ini')
          data_path = File.join(pubdir, 'inventory_data.ini')
        end
      rescue => e
        # Silently fallback to standard public paths on error
      end
    end

    {
      mgmt: File.file?(mgmt_path) ? File.read(mgmt_path) : "Management inventory not generated.\nRun './ctlabs.rb -i' to generate.",
      data: File.file?(data_path) ? File.read(data_path) : "Data inventory not generated.\nRun './ctlabs.rb -i' to generate."
    }
  end

  # ---------------------------------------------------------------------------
  # 
  # ---------------------------------------------------------------------------
  def fetch_latest_log_info
    latest_log_path = Dir.glob(File.join(LOG_DIR, "*.log")).max_by { |f| File.mtime(f) }
    return nil unless latest_log_path

    latest_log_file = File.basename(latest_log_path)
    lab_name        = "Unknown"
    action_name     = "action"

    if match = latest_log_file.match(/^ctlabs_\d+_(.+)_([a-zA-Z]+)\.log$/)
      lab_name    = match[1]
      action_name = match[2]
    end

    { path: latest_log_path, lab: lab_name, action: action_name }
  end

  # ---------------------------------------------------------------------------
  # Parses a log filename into a clean, display-ready hash
  # ---------------------------------------------------------------------------
  def parse_log_metadata(log_path)
    basename = File.basename(log_path, '.log')
    
    if basename.start_with?('build_')
      parts = basename.split('_')
      lab_name = parts[1..-2].join('_') rescue 'Unknown Image'
      timestamp = parts.last.to_i rescue 0
      action = 'Build'
    else
      parts = basename.split('_')
      timestamp = parts[1].to_i rescue 0
      lab_name = parts[2..-2].join('_').gsub(/\.yml$/, '.yml') rescue 'Unknown Lab'
      action = case parts.last
               when 'up' then 'Start'
               when 'down' then 'Stop'
               when 'adhoc' then 'AdHoc'
               else parts.last.to_s.capitalize
               end
    end

    time_str = timestamp > 0 ? Time.at(timestamp).strftime('%Y-%m-%d %H:%M:%S') : 'Unknown time'
    { lab_name: lab_name, action: action, time_str: time_str }
  end
end
