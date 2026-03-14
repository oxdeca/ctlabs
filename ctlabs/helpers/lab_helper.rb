# -----------------------------------------------------------------------------
# File        : ctlabs/helpers/lab_helper.rb
# License     : MIT License
# -----------------------------------------------------------------------------

module LabHelper
  # Helper to safely resolve the lab file path (Runtime vs Base)
  def get_lab_file_path(lab_name)
    runtime_path = "#{LOCK_DIR}/#{lab_name.gsub('/', '_')}.yml"
    (Lab.running? && Lab.current_name == lab_name && File.file?(runtime_path)) ? runtime_path : File.join(LABS_DIR, lab_name)
  end

  # Maps switches to their connected router's gateway IP
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

  # Safely resolves and reads the contents of the Ansible inventory files
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
end
