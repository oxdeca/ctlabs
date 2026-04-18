# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/automation_controller.rb
# Description : Controller for Ansible and Terraform management
# License     : MIT License
# -----------------------------------------------------------------------------

class AutomationController < BaseController
  # ===================================================
  # ANSIBLE
  # ===================================================

  # Fetch Ansible config for the Editor
  get '/labs/*/ansible/config' do
    content_type :json
    lab_name = params[:splat].first
    lab_path = Lab.get_file_path(lab_name)

    begin
      full_yaml = YAML.load_file(lab_path)
      vm = full_yaml['topology']&.first || {}
      name, base_data, _ = Lab.find_automation_controller(vm)
      
      raise "No controller node found in topology" unless name

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
    halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')

    begin
      content = AutomationService.read_ansible_file(filepath)
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
      AutomationService.ansible_tree.to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  post '/labs/*/ansible/edit' do
    lab_name = params[:splat].first
    lab_path = Lab.get_file_path(lab_name)

    begin
      full_yaml = YAML.load_file(lab_path)
      vm = full_yaml['topology']&.first || {}
      name, base_data, plane = Lab.find_automation_controller(vm)
      
      raise "No ansible controller node found in topology" unless name

      play_cfg = base_data['play'] || {}
      play_cfg = {} if play_cfg.is_a?(String)

      params[:book].to_s.strip.empty? ? play_cfg.delete('book') : play_cfg['book'] = params[:book].strip
      params[:inv].to_s.strip.empty? ? play_cfg.delete('inv') : play_cfg['inv'] = params[:inv].strip

      if params[:custom_inv] && !params[:custom_inv].to_s.strip.empty?
        play_cfg['custom_inv'] = params[:custom_inv].to_s.strip
      else
        play_cfg.delete('custom_inv')
      end

      env_str = params[:env].to_s.strip
      if env_str.empty?
        play_cfg.delete('env')
      else
        play_cfg['env'] = env_str.split(/\r?\n/).map(&:strip).reject(&:empty?)
      end

      params[:tags] && !params[:tags].to_s.strip.empty? ? play_cfg['tags'] = params[:tags].to_s.split(",").map(&:strip).reject(&:empty?) : play_cfg.delete('tags')

      base_data['play'] = play_cfg
      
      if plane
        full_yaml['topology'][0]['planes'][plane]['nodes'][name] = base_data
      else
        full_yaml['topology'][0]['nodes'][name] = base_data
      end
      
      LabRepository.write_formatted_yaml(lab_path, full_yaml)

      ans_files = JSON.parse(params[:ans_files] || '{}')
      AutomationService.write_ansible_files(ans_files)

      content_type :json
      { success: true, message: "Configuration and files updated successfully." }.to_json
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
    halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')

    begin
      AutomationService.delete_ansible_file(filepath)
      { success: true }.to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  post '/labs/*/playbook' do
    lab_name = params[:splat].first
    halt 400, { error: "No lab is running" }.to_json unless Lab.current_name == lab_name
    halt 400, { error: "Playbook running!" }.to_json if Lab.playbook_running?(lab_name)

    log_path = LabLog.latest_for_running_lab
    Thread.new do
      begin
        lab_instance = Lab.new(cfg: Lab.get_file_path(lab_name), relative_path: lab_name)
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

  get '/labs/*/terraform/config' do
    content_type :json
    lab_name = params[:splat].first
    lab_path = Lab.get_file_path(lab_name)

    begin
      full_yaml = YAML.load_file(lab_path)
      vm = full_yaml['topology']&.first || {}
      name, node_cfg, _ = Lab.find_automation_controller(vm)
      tf_cfg = node_cfg ? (node_cfg['terraform'] || {}) : {}
      { json: { tf: tf_cfg } }.to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  get '/labs/*/terraform/tree' do
    content_type :json
    begin
      AutomationService.terraform_tree.to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  get '/labs/*/terraform/file' do
    content_type :json
    filepath = params[:path].to_s.strip
    halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')

    begin
      content = AutomationService.read_terraform_file(filepath)
      { content: content }.to_json
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
      AutomationService.read_terraform_workdir_files(work_dir).to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  post '/labs/*/terraform/edit' do
    lab_name = params[:splat].first
    lab_path = Lab.get_file_path(lab_name)

    begin
      full_yaml = YAML.load_file(lab_path)
      vm = full_yaml['topology']&.first || {}
      name, base_data, plane = Lab.find_automation_controller(vm)
      
      raise "No controller node found in topology" unless name

      tf_cfg = base_data['terraform'] || {}

      params[:work_dir].to_s.strip.empty? ? tf_cfg.delete('work_dir') : tf_cfg['work_dir'] = params[:work_dir].strip
      params[:workspace].to_s.strip.empty? ? tf_cfg.delete('workspace') : tf_cfg['workspace'] = params[:workspace].strip

      vars_str = params[:vars].to_s.strip
      if vars_str.empty?
        tf_cfg.delete('vars')
      else
        tf_cfg['vars'] = vars_str.split(/\r?\n/).map(&:strip).reject(&:empty?)
      end

      commands_str = params[:commands].to_s.strip
      if commands_str.empty?
        tf_cfg.delete('commands')
      else
        tf_cfg['commands'] = commands_str
      end

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
      
      if plane
        full_yaml['topology'][0]['planes'][plane]['nodes'][name] = base_data
      else
        full_yaml['topology'][0]['nodes'][name] = base_data
      end
      
      LabRepository.write_formatted_yaml(lab_path, full_yaml)

      tf_files = JSON.parse(params[:tf_files] || '{}')
      AutomationService.write_terraform_files(tf_files)

      content_type :json
      { success: true, message: "Configuration and all files saved successfully." }.to_json
    rescue Exception => e
      status 400
      content_type :json
      { success: false, error: "Backend error: #{e.message}" }.to_json
    end
  end

  post '/labs/*/terraform/file/delete' do
    content_type :json
    filepath = params[:filepath].to_s.strip
    halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')

    begin
      AutomationService.delete_terraform_file(filepath)
      { success: true }.to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  post '/labs/*/terraform' do
    lab_name = params[:splat].first
    action   = params[:action] || 'apply'

    halt 400, { error: "No lab is running" }.to_json unless Lab.current_name == lab_name
    halt 400, { error: "Terraform already running!" }.to_json if Lab.terraform_running?(lab_name) rescue false

    log_path = LabLog.latest_for_running_lab
    Thread.new do
      begin
        lab_instance = Lab.new(cfg: Lab.get_file_path(lab_name), relative_path: lab_name)
        File.open(log_path, 'a') { |f| f.puts "\n--- Manual Terraform apply triggered ---\n" }
        lab_instance.run_terraform(
          params[:node_name],
          log_path,
          session[:vault_token],
          session[:vault_addr],
          action
        )
      rescue => e
        File.open(log_path, 'a') { |f| f.puts "\n⚠️ Terraform failed: #{e.message}\n" }
      end
    end
    content_type :json
    { success: true }.to_json
  end
end
