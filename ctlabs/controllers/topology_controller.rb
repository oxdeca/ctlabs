# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/topology_controller.rb
# Description : Controller for Lab Topology management
# License     : MIT License
# -----------------------------------------------------------------------------

class TopologyController < BaseController
  # --- Fetch Raw YAML ---
  get '/labs/*/raw' do
    lab_name = params[:splat].first
    lab_path = Lab.get_file_path(lab_name)
    
    if File.exist?(lab_path)
      content_type 'text/plain'
      File.read(lab_path)
    else
      status 404
      "File not found"
    end
  end

  # --- Save Raw YAML ---
  post '/labs/*/raw' do
    lab_name = params[:splat].first
    lab_path = Lab.get_file_path(lab_name)
    
    begin
      yaml_content = params[:yaml_content]
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

  # --- Fetch Cloud Config ---
  get '/labs/*/cloud_config' do
    lab_name = params[:splat].first
    lab_path = Lab.get_file_path(lab_name)
    
    begin
      full_yaml = YAML.load_file(lab_path) || {}
      vm_topology = full_yaml['topology']&.first || {}
      ctrl_node, _ = Lab.find_node_in_raw_yaml(vm_topology, 'ansible')
      ctrl_node ||= Lab.find_node_in_raw_yaml(vm_topology, 'controller').first

      work_dir = ctrl_node&.dig('terraform', 'work_dir')
      raise "No Terraform working directory configured for this lab." if work_dir.nil? || work_dir.strip.empty?

      config_path = "/root/ctlabs-terraform/#{work_dir}/config.yml"
      raise "config.yml not found at: #{config_path}" unless File.exist?(config_path)

      content_type :json
      { success: true, content: File.read(config_path) }.to_json
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # --- Save Cloud Config ---
  post '/labs/*/cloud_config' do
    lab_name = params[:splat].first
    lab_path = Lab.get_file_path(lab_name)
    
    begin
      full_yaml = YAML.load_file(lab_path) || {}
      vm_topology = full_yaml['topology']&.first || {}
      ctrl_node, _ = Lab.find_node_in_raw_yaml(vm_topology, 'ansible')
      ctrl_node ||= Lab.find_node_in_raw_yaml(vm_topology, 'controller').first

      work_dir = ctrl_node&.dig('terraform', 'work_dir')
      raise "No Terraform working directory configured for this lab." if work_dir.nil? || work_dir.strip.empty?

      config_path = "/root/ctlabs-terraform/#{work_dir}/config.yml"
      
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
end
