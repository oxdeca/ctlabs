# -----------------------------------------------------------------------------
# File        : ctlabs/routes/automation.rb
# License     : MIT License
# -----------------------------------------------------------------------------

# ===================================================
# ANSIBLE
# ===================================================
ANS_BASE_DIR = '/root/ctlabs-ansible'.freeze

# Fetch Ansible config for the Editor
get '/labs/*/ansible/config' do
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

# Scan the directory to populate the File Browser Dropdown
get '/labs/*/ansible/tree' do
  content_type :json
  begin
    files = []
    if Dir.exist?(ANS_BASE_DIR)
      # Recursively search the entire directory
      Dir.glob(File.join(ANS_BASE_DIR, "**", "*")).each do |file|
        next if File.directory?(file)
        
        # Ignore noisy hidden folders so the dropdown is clean
        next if file.include?('/.git/') || file.include?('/__pycache__/') || file.include?('/.idea/')
        
        # Add relative path to array (e.g., "playbooks/main.yml")
        files << file.sub(ANS_BASE_DIR + '/', '')
      end
    end
    files.sort.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

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
    
    params[:book].to_s.strip.empty? ? play_cfg.delete('book') : play_cfg['book'] = params[:book].strip
    params[:inv].to_s.strip.empty? ? play_cfg.delete('inv') : play_cfg['inv'] = params[:inv].strip
    
    if params[:custom_inv] && !params[:custom_inv].to_s.strip.empty?
      play_cfg['custom_inv'] = params[:custom_inv].to_s.strip
    else
      play_cfg.delete('custom_inv')
    end
    
    # Safely parse Environment Variables across different OS line-endings
    env_str = params[:env].to_s.strip
    if env_str.empty?
      play_cfg.delete('env')
    else
      play_cfg['env'] = env_str.split(/\r?\n/).map(&:strip).reject(&:empty?)
    end

    params[:tags] && !params[:tags].to_s.strip.empty? ? play_cfg['tags'] = params[:tags].to_s.split(",").map(&:strip).reject(&:empty?) : play_cfg.delete('tags')

    base_data['play'] = play_cfg
    full_yaml['topology'][0]['nodes'][ansible_node_name] = base_data
    write_formatted_yaml(lab_path, full_yaml)

    ans_files = JSON.parse(params[:ans_files] || '{}')
    ans_files.each do |filepath, content|
      next if filepath.include?('..') || filepath.start_with?('/')
      full_path = File.join(ANS_BASE_DIR, filepath)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
      FileUtils.chmod("+x", full_path) if filepath.end_with?('.py') || filepath.end_with?('.sh')
    end

    content_type :json
    { success: true, message: "Configuration and files updated successfully." }.to_json
  
  # Catch ALL exceptions to guarantee JSON response instead of HTML crash pages
  rescue Exception => e
    status 400
    content_type :json
    { success: false, error: "Backend error: #{e.message}" }.to_json
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

# get '/labs/*/terraform/config' do
#   content_type :json
#   lab_name = params[:splat].first
#   lab_path = get_lab_file_path(lab_name)
# 
#   begin
#     lab = Lab.new(cfg: lab_path, log: LabLog.null)
#     ctrl = lab.find_node('ansible') || lab.nodes.find { |n| n.type == 'controller' }
#     raise "No controller node found in topology" unless ctrl
#     
#     { json: { tf: ctrl.terraform || {} } }.to_json
#   rescue => e
#     status 400
#     { error: e.message }.to_json
#   end
# end

get '/labs/*/terraform/config' do
  content_type :json
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    # Bypass memory and read directly from YAML to preserve the vault block!
    full_yaml = YAML.load_file(lab_path)
    nodes = full_yaml['topology'][0]['nodes'] || {}
    ctrl_node = nodes.values.find { |n| n['type'] == 'controller' } || nodes['ansible'] || {}
    tf_cfg = ctrl_node['terraform'] || {}
    
    { json: { tf: tf_cfg } }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end
 
# Recursive Tree for Terraform
get '/labs/*/terraform/tree' do
  content_type :json
  begin
    files = []
    if Dir.exist?(TF_BASE_DIR)
      Dir.glob(File.join(TF_BASE_DIR, "**", "*")).each do |file|
        next if File.directory?(file)
        next if file.include?('/.terraform/') || file.include?('/.git/') || file.end_with?('.tfstate') || file.end_with?('.tfstate.backup')
        files << file.sub(TF_BASE_DIR + '/', '')
      end
    end
    files.sort.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

# Fetch by exact path
get '/labs/*/terraform/file' do
  content_type :json
  filepath = params[:path].to_s.strip
  halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')

  begin
    full_path = File.join(TF_BASE_DIR, filepath)
    content = File.file?(full_path) ? File.read(full_path) : "# New file: #{filepath}\n"
    { content: content }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

# Fetch file contents directly from the Host VM's bind mount (Batch Load)
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

#post '/labs/*/terraform/edit' do
#  lab_name = params[:splat].first
#  lab_path = get_lab_file_path(lab_name)
#
#  begin
#    full_yaml = YAML.load_file(lab_path)
#    controller_node_name = full_yaml['topology'][0]['nodes'].keys.find { |k| full_yaml['topology'][0]['nodes'][k]['type'] == 'controller' || k == 'ansible' }
#    
#    base_data = full_yaml['topology'][0]['nodes'][controller_node_name] || {}
#    tf_cfg = base_data['terraform'] || {}
#    
#    params[:work_dir].to_s.strip.empty? ? tf_cfg.delete('work_dir') : tf_cfg['work_dir'] = params[:work_dir].strip
#    params[:workspace].to_s.strip.empty? ? tf_cfg.delete('workspace') : tf_cfg['workspace'] = params[:workspace].strip
#    
#    # Safely parse Variables
#    vars_str = params[:vars].to_s.strip
#    if vars_str.empty?
#      tf_cfg.delete('vars')
#    else
#      tf_cfg['vars'] = vars_str.split(/\r?\n/).map(&:strip).reject(&:empty?)
#    end
#
#    # --- NEW: PARSE VAULT CONFIG ---
#    v_project = params[:vault_project].to_s.strip
#    v_roleset = params[:vault_roleset].to_s.strip
#    
#    if v_project.empty?
#      tf_cfg.delete('vault')
#    else
#      tf_cfg['vault'] = {
#        'project' => v_project,
#        'roleset' => v_roleset.empty? ? 'terraform-runner' : v_roleset
#      }
#    end
#
#    base_data['terraform'] = tf_cfg
#    full_yaml['topology'][0]['nodes'][controller_node_name] = base_data
#    write_formatted_yaml(lab_path, full_yaml)
#
#    tf_files = JSON.parse(params[:tf_files] || '{}')
#    tf_files.each do |filepath, content|
#      next if filepath.include?('..') || filepath.start_with?('/') 
#      full_path = File.join(TF_BASE_DIR, filepath)
#      FileUtils.mkdir_p(File.dirname(full_path))
#      File.write(full_path, content)
#    end
#
#    content_type :json
#    { success: true, message: "Configuration and all files saved successfully." }.to_json
#  
#  # Catch ALL exceptions to guarantee JSON response
#  rescue Exception => e
#    status 400
#    content_type :json
#    { success: false, error: "Backend error: #{e.message}" }.to_json
#  end
#end

post '/labs/*/terraform/edit' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path)
    controller_node_name = full_yaml['topology'][0]['nodes'].keys.find { |k| full_yaml['topology'][0]['nodes'][k]['type'] == 'controller' || k == 'ansible' }
    
    base_data = full_yaml['topology'][0]['nodes'][controller_node_name] || {}
    tf_cfg = base_data['terraform'] || {}
    
    params[:work_dir].to_s.strip.empty? ? tf_cfg.delete('work_dir') : tf_cfg['work_dir'] = params[:work_dir].strip
    params[:workspace].to_s.strip.empty? ? tf_cfg.delete('workspace') : tf_cfg['workspace'] = params[:workspace].strip
    
    vars_str = params[:vars].to_s.strip
    if vars_str.empty?
      tf_cfg.delete('vars')
    else
      tf_cfg['vars'] = vars_str.split(/\r?\n/).map(&:strip).reject(&:empty?)
    end

    # --- NEW: PARSE VAULT CONFIG ---
    v_project = params[:vault_project].to_s.strip
    v_roleset = params[:vault_roleset].to_s.strip
    
    if v_project.empty?
      tf_cfg.delete('vault')
    else
      tf_cfg['vault'] = {
        'project' => v_project,
        'roleset' => v_roleset.empty? ? 'terraform-runner' : v_roleset
      }
    end

    base_data['terraform'] = tf_cfg
    full_yaml['topology'][0]['nodes'][controller_node_name] = base_data
    write_formatted_yaml(lab_path, full_yaml)

    tf_files = JSON.parse(params[:tf_files] || '{}')
    tf_files.each do |filepath, content|
      next if filepath.include?('..') || filepath.start_with?('/') 
      full_path = File.join(TF_BASE_DIR, filepath)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
    end

    content_type :json
    { success: true, message: "Configuration and all files saved successfully." }.to_json
  rescue Exception => e
    status 400
    content_type :json
    { success: false, error: "Backend error: #{e.message}" }.to_json
  end
end

# Delete by exact path
post '/labs/*/terraform/file/delete' do
  content_type :json
  filepath = params[:filepath].to_s.strip
  halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')
  
  begin
    full_path = File.join(TF_BASE_DIR, filepath)
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
      lab_instance.run_terraform(
        params[:node_name], 
        log_path, 
        session[:vault_token], # <-- Pass the web session token
        session[:vault_addr]   # <-- Pass the web session address
      )
    rescue => e
      File.open(log_path, 'a') { |f| f.puts "\n⚠️ Terraform failed: #{e.message}\n" }
    end
  end
  content_type :json
  { success: true }.to_json
end
