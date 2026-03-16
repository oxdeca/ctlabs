# -----------------------------------------------------------------------------
# File        : ctlabs/routes/automation.rb
# License     : MIT License
# -----------------------------------------------------------------------------

# ===================================================
# ANSIBLE
# ===================================================
ANS_BASE_DIR = '/root/ctlabs-ansible'.freeze

# Fetch Ansible config for the Editor
get '/labs/*/node/ansible' do
  content_type :json
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path)
    ctrl_node_name = full_yaml['topology'][0]['nodes'].keys.find { |k| full_yaml['topology'][0]['nodes'][k]['type'] == 'controller' || k == 'ansible' }
    raise "No controller node found in topology" unless ctrl_node_name
    
    base_data = full_yaml['topology'][0]['nodes'][ctrl_node_name] || {}
    play = base_data['play'] || {}
    
    { json: { play: play } }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

# Fetch a single specific Ansible file
get '/labs/*/ansible/file' do
  content_type :json
  filepath = params[:path].to_s.strip
  
  # Security: Prevent escaping out of /root/ctlabs-ansible/
  halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')

  begin
    full_path = File.join(ANS_BASE_DIR, filepath)
    
    # If the file exists, return it. If it doesn't, return a blank slate so they can create it!
    content = File.file?(full_path) ? File.read(full_path) : "# New file: #{filepath}\n"
    
    { content: content }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

# Edit Ansible Config AND write dynamic files
post '/labs/*/ansible/edit' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path)
    ansible_node_name = full_yaml['topology'][0]['nodes'].keys.find { |k| k == 'ansible' || full_yaml['topology'][0]['nodes'][k]['type'] == 'controller' }
    raise "No ansible controller node found in topology" unless ansible_node_name
    
    base_data = full_yaml['topology'][0]['nodes'][ansible_node_name] || {}
    play_cfg = base_data['play'] || {}
    play_cfg = {} if play_cfg.is_a?(String)
    
    # Update Settings (removed work_dir)
    params[:book].to_s.strip.empty? ? play_cfg.delete('book') : play_cfg['book'] = params[:book].strip
    params[:env] && !params[:env].strip.empty? ? play_cfg['env'] = params[:env].split("\n").map(&:strip).reject(&:empty?) : play_cfg.delete('env')
    params[:tags] && !params[:tags].strip.empty? ? play_cfg['tags'] = params[:tags].split(",").map(&:strip).reject(&:empty?) : play_cfg.delete('tags')

    base_data['play'] = play_cfg
    full_yaml['topology'][0]['nodes'][ansible_node_name] = base_data
    write_formatted_yaml(lab_path, full_yaml)

    # Decode and save all dynamically edited files
    ans_files = JSON.parse(params[:ans_files] || '{}')

    ans_files.each do |filepath, content|
      # Security constraints
      next if filepath.include?('..') || filepath.start_with?('/')
      
      full_path = File.join(ANS_BASE_DIR, filepath)
      
      # Ensure the subdirectory exists (e.g., creating roles/my_role/tasks/ if it doesn't exist)
      FileUtils.mkdir_p(File.dirname(full_path))
      
      File.write(full_path, content)
    end

    content_type :json
    { success: true, message: "Configuration and files updated successfully." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# Delete a specific Ansible file
post '/labs/*/ansible/file/delete' do
  content_type :json
  filepath = params[:filepath].to_s.strip
  
  # Security constraints to prevent directory traversal attacks
  halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')
  
  begin
    full_path = File.join(ANS_BASE_DIR, filepath)
    
    # Only attempt to delete if the file actually exists on disk (safely ignores typos that were never saved)
    File.delete(full_path) if File.exist?(full_path)
    
    { success: true }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

post '/labs/*/playbook' do
  lab_name = params[:splat].first
  halt 400, { error: "No lab is running" }.to_json unless get_running_lab == lab_name
  halt 400, { error: "Playbook running!" }.to_json if Lab.playbook_running?(lab_name)

  log_path = LabLog.latest_for_running_lab
  Thread.new do
    begin
      lab_instance = Lab.new(cfg: get_lab_file_path(lab_name), relative_path: lab_name)
      File.open(log_path, 'a') { |f| f.puts "\n--- Manual Ansible playbook run triggered ---\n" }
      lab_instance.run_playbook(nil, log_path)
    rescue => e
      File.open(log_path, 'a') { |f| f.puts "\n⚠️ Playbook failed: #{e.message}\n" }
    end
  end
  content_type :json
  { success: true }.to_json
end


# ===================================================
# TERRAFORM
# ===================================================
TF_BASE_DIR = '/root/ctlabs-terraform'.freeze

get '/labs/*/node/terraform' do
  content_type :json
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    lab = Lab.new(cfg: lab_path, log: LabLog.null)
    ctrl = lab.find_node('ansible') || lab.nodes.find { |n| n.type == 'controller' }
    raise "No controller node found in topology" unless ctrl
    
    { json: { tf: ctrl.terraform || {} } }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

get '/labs/*/terraform/files' do
  content_type :json
  work_dir = params[:work_dir].to_s.strip
  halt 400, { error: "Invalid working directory" }.to_json if work_dir.empty? || work_dir.include?('..')

  begin
    target_dir = File.join(TF_BASE_DIR, work_dir)
    response = {}
    
    # 1. Provide default blank templates if the directory doesn't exist yet
    ['config.yml', 'main.tf', 'provider.tf'].each { |f| response[f] = "" }

    # 2. Discover ALL existing files in the directory
    if Dir.exist?(target_dir)
      Dir.glob(File.join(target_dir, "*")).each do |file_path|
        next if File.directory?(file_path) # Skip folders
        filename = File.basename(file_path)
        
        # Read text content. (Limit to standard text files to avoid trying to read binaries)
        if filename.match?(/\.(tf|yml|yaml|json|sh|txt|tfvars|conf)$/i) || filename == 'Makefile'
          response[filename] = File.read(file_path)
        end
      end
    end

    response.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

post '/labs/*/terraform/edit' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path)
    controller_node_name = full_yaml['topology'][0]['nodes'].keys.find { |k| full_yaml['topology'][0]['nodes'][k]['type'] == 'controller' || k == 'ansible' }
    raise "No controller node found in topology" unless controller_node_name
    
    base_data = full_yaml['topology'][0]['nodes'][controller_node_name] || {}
    tf_cfg = base_data['terraform'] || {}
    
    params[:work_dir].to_s.strip.empty? ? tf_cfg.delete('work_dir') : tf_cfg['work_dir'] = params[:work_dir].strip
    params[:workspace].to_s.strip.empty? ? tf_cfg.delete('workspace') : tf_cfg['workspace'] = params[:workspace].strip
    params[:vars] && !params[:vars].strip.empty? ? tf_cfg['vars'] = params[:vars].split("\n").map(&:strip).reject(&:empty?) : tf_cfg.delete('vars')

    base_data['terraform'] = tf_cfg
    full_yaml['topology'][0]['nodes'][controller_node_name] = base_data
    write_formatted_yaml(lab_path, full_yaml)

    # Decode the dynamic files payload
    tf_files = JSON.parse(params[:tf_files] || '{}')
    work_dir = params[:work_dir].to_s.strip

    if !work_dir.empty? && !work_dir.include?('..')
      target_dir = File.join(TF_BASE_DIR, work_dir)
      FileUtils.mkdir_p(target_dir)
      
      tf_files.each do |filename, content|
        # Security: Prevent escaping out of the work directory via filename
        next if filename.include?('..') || filename.include?('/') 
        File.write(File.join(target_dir, filename), content)
      end
    end

    content_type :json
    { success: true, message: "Configuration and all files saved successfully." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# Delete a specific Terraform file
post '/labs/*/terraform/file/delete' do
  content_type :json
  work_dir = params[:work_dir].to_s.strip
  filename = params[:filename].to_s.strip
  
  # Security constraints
  halt 400, { error: "Invalid path" }.to_json if work_dir.empty? || work_dir.include?('..') || filename.empty? || filename.include?('/') || filename.include?('..')
  
  begin
    full_path = File.join(TF_BASE_DIR, work_dir, filename)
    
    File.delete(full_path) if File.exist?(full_path)
    
    { success: true }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

post '/labs/*/terraform' do
  lab_name = params[:splat].first
  halt 400, { error: "No lab is running" }.to_json unless get_running_lab == lab_name
  halt 400, { error: "Terraform already running!" }.to_json if Lab.terraform_running?(lab_name) rescue false

  log_path = LabLog.latest_for_running_lab
  Thread.new do
    begin
      lab_instance = Lab.new(cfg: get_lab_file_path(lab_name), relative_path: lab_name)
      File.open(log_path, 'a') { |f| f.puts "\n--- Manual Terraform apply triggered ---\n" }
      lab_instance.run_terraform(nil, log_path)
    rescue => e
      File.open(log_path, 'a') { |f| f.puts "\n⚠️ Terraform failed: #{e.message}\n" }
    end
  end
  content_type :json
  { success: true }.to_json
end
