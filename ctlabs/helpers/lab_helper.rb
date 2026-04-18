# -----------------------------------------------------------------------------
# File        : ctlabs/helpers/lab_helper.rb
# License     : MIT License
# -----------------------------------------------------------------------------

module LabHelper

  def find_node_in_raw_yaml(vm_cfg, node_name)
    Lab.find_node_in_raw_yaml(vm_cfg, node_name)
  end

  def parse_node_form_data(params, base_data = {})
    Node.parse_form_data(params, base_data)
  end

  def auto_assign_mgmt_ip!(node_cfg, full_yaml)
    Node.auto_assign_mgmt_ip!(node_cfg, full_yaml)
  end

  def validate_node_profile!(node_cfg, full_yaml)
    Node.validate_profile!(node_cfg, full_yaml)
  end

  def sync_node_to_terraform_config!(node_name, node_cfg, full_lab_yaml, cloud_vm_yaml_payload)
    Node.sync_to_terraform!(node_name, node_cfg, full_lab_yaml, cloud_vm_yaml_payload)
  end

  def remove_node_from_terraform_config!(node_name, full_lab_yaml)
    Node.remove_from_terraform!(node_name, full_lab_yaml)
  end

  def profile_in_use?(yaml, target_type, target_profile)
    Lab.profile_in_use?(yaml, target_type, target_profile)
  end

  def get_lab_file_path(lab_name)
    Lab.get_file_path(lab_name)
  end

  # ---------------------------------------------------------------------------
  # Maps switches to their connected router's gateway IP
  # ---------------------------------------------------------------------------
  def generate_switch_gw_map(lab_path, links)
    switch_gw_map = {}
    begin
      full_path = Lab.get_file_path(lab_path)
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
        full_path = Lab.get_file_path(Lab.current_name)
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
