# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/controller_controller.rb
# Description : WebUI routes for the GLOBAL control plane (ctl-ctrl + ctl-* plane).
#
#               The controller is not a lab, so none of the /labs/* routes apply.
#               Instead of duplicating the Ansible/Terraform editor modal + JS,
#               the lab-scoped endpoints under /labs/<x>/ansible|terraform are
#               mirrored here under /controller/... backed by the controller's
#               overlay store (see Controller.overlays). Playbook/terraform runs
#               go through Controller#lab (a standalone Lab view of the plane).
# License     : MIT License
# -----------------------------------------------------------------------------

class ControllerController < BaseController
  # ===================================================
  # Control-plane nodes + exposed services
  # ===================================================

  post '/controller/nodes' do
    content_type :json
    begin
      node = Controller.add_node(params[:name], {
        'type' => params[:type],
        'ipv4' => params[:ipv4],
        'kind' => params[:kind]
      })
      msg = "Control-plane node '#{params[:name]}' added."
      msg << ' Restart the controller to apply (ctlabs.rb --controller=up).' if Controller.running?
      { success: true, message: msg, node: node }.to_json
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  post '/controller/nodes/delete' do
    content_type :json
    begin
      if Controller.remove_node(params[:name])
        msg = "Control-plane node '#{params[:name]}' removed."
        msg << ' Restart the controller to apply.' if Controller.running?
        { success: true, message: msg }.to_json
      else
        { success: false, error: "Node '#{params[:name]}' is a built-in control-plane node and cannot be removed." }.to_json
      end
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  post '/controller/services' do
    content_type :json
    begin
      svc = Controller.add_service(params[:node], params[:external_port], params[:internal_port], (params[:protocol] || 'tcp'), params[:name])
      applied = live_apply_services
      { success: true, service: svc,
        message: applied ? "Service #{svc[:node]}:#{svc[:ext]} -> #{svc[:int]}/#{svc[:proto]} added."
                         : "Service added. It takes effect on the next controller start." }.to_json
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  post '/controller/services/delete' do
    content_type :json
    begin
      node = params[:node].to_s
      ext  = params[:ext].to_i
      int  = params[:int].to_i
      proto = (params[:proto] || 'tcp').to_s.downcase

      # Best-effort live teardown first (no-op if not installed / controller down).
      begin
        Controller.new.lab.del_adhoc_dnat(node, ext, int, proto) if Controller.running?
      rescue => e
        content_type :json
        # continue: the overlay entry is still removed below
      end

      if Controller.remove_service(node, ext, proto)
        { success: true, message: 'Service removed.' }.to_json
      else
        { success: false, error: "Service #{node}:#{ext}/#{proto} is built-in and cannot be removed." }.to_json
      end
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  # ===================================================
  # ANSIBLE (controller-scoped)
  # ===================================================

  get '/controller/ansible/config' do
    content_type :json
    begin
      play      = Controller.controller_play
      setup_yaml = (play['setup'] || {}).to_yaml.sub(/\A---\s*\n/, '')
      { json: { play: play, setup_yaml: setup_yaml } }.to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  get '/controller/ansible/file' do
    content_type :json
    filepath = params[:path].to_s.strip
    halt 400, { error: 'Invalid path' }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')
    begin
      { content: AutomationService.read_ansible_file(filepath) }.to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  get '/controller/ansible/tree' do
    content_type :json
    AutomationService.ansible_tree.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end

  get '/controller/ansible/profiles' do
    content_type :json
    AutomationService.read_profile_files.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end

  post '/controller/ansible/file/delete' do
    content_type :json
    filepath = params[:filepath].to_s.strip
    halt 400, { error: 'Invalid path' }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')
    AutomationService.delete_ansible_file(filepath)
    { success: true }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end

  post '/controller/ansible/edit' do
    content_type :json
    begin
      play_cfg = Controller.controller_play
      play_cfg = {} unless play_cfg.is_a?(Hash)

      params[:book].to_s.strip.empty? ? play_cfg.delete('book') : play_cfg['book'] = params[:book].strip
      params[:inv].to_s.strip.empty? ? play_cfg.delete('inv') : play_cfg['inv'] = params[:inv].strip

      if params[:custom_inv] && !params[:custom_inv].to_s.strip.empty?
        play_cfg['custom_inv'] = params[:custom_inv].to_s.strip
      else
        play_cfg.delete('custom_inv')
      end

      env_str = params[:env].to_s.strip
      env_str.empty? ? play_cfg.delete('env') : play_cfg['env'] = env_str.split(/\r?\n/).map(&:strip).reject(&:empty?)

      if params[:tags] && !params[:tags].to_s.strip.empty?
        play_cfg['tags'] = params[:tags].to_s.split(',').map(&:strip).reject(&:empty?)
      else
        play_cfg.delete('tags')
      end

      setup_str = params[:setup].to_s.strip
      if setup_str.empty?
        play_cfg.delete('setup')
      else
        parsed = YAML.safe_load(setup_str, aliases: true)
        raise 'must be a mapping of role -> config' unless parsed.is_a?(Hash)
        play_cfg['setup'] = parsed
      end

      Controller.update_controller_play(play_cfg)

      ans_files = JSON.parse(params[:ans_files] || '{}')
      AutomationService.write_ansible_files(ans_files)

      profile_files = {}
      profile_files['play_profiles_ctl.yml']  = params[:play_profiles]  if params[:play_profiles]  && !params[:play_profiles].to_s.strip.empty?
      profile_files['setup_profiles_ctl.yml'] = params[:setup_profiles] if params[:setup_profiles] && !params[:setup_profiles].to_s.strip.empty?
      AutomationService.write_profile_files(profile_files) unless profile_files.empty?

      { success: true, message: 'Configuration and files updated successfully.' }.to_json
    rescue Exception => e
      status 400
      { success: false, error: "Backend error: #{e.message}" }.to_json
    end
  end

  post '/controller/playbook' do
    content_type :json
    halt 400, { error: 'Controller is not running. Start it with ctlabs.rb --controller=up' }.to_json unless Controller.running?
    halt 400, { error: 'Playbook already running for the controller' }.to_json if Automation.playbook_running?(controller_lab_name)

    log_path = LabLog.for_lab(lab_name: 'controller', action: 'run').path
    Thread.new do
      begin
        controller = Controller.new(log: LabLog.append_to(log_path))
        controller.lab.run_playbook(nil, log_path)
      rescue => e
        File.open(log_path, 'a') { |f| f.puts "\n⚠️ Controller playbook failed: #{e.message}\n" }
      end
    end
    { success: true, log_url: "/logs?id=#{register_log(log_path)}" }.to_json
  end

  post '/controller/playbook/stop' do
    content_type :json
    ok, message = Automation.stop_playbook!(controller_lab_name, request.env['REMOTE_USER'])
    content_type :json
    { success: ok, message: message }.to_json
  end

  # ===================================================
  # TERRAFORM (controller-scoped)
  # ===================================================

  get '/controller/terraform/config' do
    content_type :json
    { json: { tf: Controller.controller_terraform } }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end

  get '/controller/terraform/profiles' do
    content_type :json
    AutomationService.read_profile_files.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end

  get '/controller/terraform/tree' do
    content_type :json
    AutomationService.terraform_tree.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end

  get '/controller/terraform/file' do
    content_type :json
    filepath = params[:path].to_s.strip
    halt 400, { error: 'Invalid path' }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')
    { content: AutomationService.read_terraform_file(filepath) }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end

  get '/controller/terraform/files' do
    content_type :json
    work_dir = params[:work_dir].to_s.strip
    halt 400, { error: 'Invalid working directory' }.to_json if work_dir.empty? || work_dir.include?('..')
    AutomationService.read_terraform_workdir_files(work_dir).to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end

  post '/controller/terraform/file/delete' do
    content_type :json
    filepath = params[:filepath].to_s.strip
    halt 400, { error: 'Invalid path' }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')
    AutomationService.delete_terraform_file(filepath)
    { success: true }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end

  post '/controller/terraform/edit' do
    content_type :json
    begin
      tf_cfg = Controller.controller_terraform
      tf_cfg = {} unless tf_cfg.is_a?(Hash)

      params[:work_dir].to_s.strip.empty? ? tf_cfg.delete('work_dir') : tf_cfg['work_dir'] = params[:work_dir].strip
      params[:workspace].to_s.strip.empty? ? tf_cfg.delete('workspace') : tf_cfg['workspace'] = params[:workspace].strip

      vars_str = params[:vars].to_s.strip
      vars_str.empty? ? tf_cfg.delete('vars') : tf_cfg['vars'] = vars_str.split(/\r?\n/).map(&:strip).reject(&:empty?)

      commands_str = params[:commands].to_s.strip
      commands_str.empty? ? tf_cfg.delete('commands') : tf_cfg['commands'] = commands_str

      auth_method = params[:auth_method].to_s.strip
      tf_cfg.delete('auth')
      tf_cfg.delete('profile')

      case auth_method
      when 'env'
        cred_file = params[:env_credentials].to_s.strip
        project   = params[:env_project].to_s.strip
        extra_raw = params[:env_extra].to_s.split(/\r?\n/).map(&:strip).reject(&:empty?)

        unless cred_file.empty? && project.empty? && extra_raw.empty?
          tf_cfg['auth'] = {
            'method'           => 'env',
            'credentials_file' => cred_file,
            'project'          => project
          }
          tf_cfg['auth']['extra_vars'] = extra_raw unless extra_raw.empty?
        end
      when 'vault'
        v_project = params[:vault_project].to_s.strip
        v_roleset = params[:vault_roleset].to_s.strip
        unless v_project.empty?
          tf_cfg['auth'] = { 'method' => 'vault', 'project' => v_project,
                             'roleset' => v_roleset.empty? ? 'terraform-runner' : v_roleset }
        end
      when 'wif'
        wif_scopes = params[:wif_scopes].to_s.split(/\r?\n/).map(&:strip).reject(&:empty?)
        unless params[:wif_vault_role].to_s.strip.empty?
          tf_cfg['auth'] = {
            'method'          => 'wif',
            'vault_role'      => params[:wif_vault_role].to_s.strip,
            'audience'        => params[:wif_audience].to_s.strip,
            'service_account' => params[:wif_service_account].to_s.strip
          }
          tf_cfg['auth']['scopes'] = wif_scopes unless wif_scopes.empty?
        end
      when 'profile'
        profile_name = params[:auth_profile].to_s.strip
        tf_cfg['profile'] = profile_name unless profile_name.empty?
      end

      tf_cfg.delete('vault')

      tf_auth_profiles = params[:tf_auth_profiles]
      AutomationService.write_profile_files('terraform_profiles_ctl.yml' => tf_auth_profiles) if tf_auth_profiles && !tf_auth_profiles.to_s.strip.empty?

      Controller.update_controller_terraform(tf_cfg)

      tf_files = JSON.parse(params[:tf_files] || '{}')
      AutomationService.write_terraform_files(tf_files)

      { success: true, message: 'Configuration and all files saved successfully.' }.to_json
    rescue Exception => e
      status 400
      { success: false, error: "Backend error: #{e.message}" }.to_json
    end
  end

  post '/controller/terraform' do
    content_type :json
    halt 400, { error: 'Controller is not running. Start it with ctlabs.rb --controller=up' }.to_json unless Controller.running?

    action = params[:action] || 'apply'
    tf_cfg = Controller.controller_terraform
    if tf_cfg['work_dir'].to_s.strip.empty?
      halt 400, { error: 'No terraform working directory configured for the controller. Use the Edit (gear) button.' }.to_json
    end

    log_path = LabLog.for_lab(lab_name: 'controller', action: 'tf').path
    Thread.new do
      begin
        controller = Controller.new(log: LabLog.append_to(log_path))
        controller.lab.run_terraform(
          Controller::NAME,
          log_path,
          session[:vault_token],
          session[:vault_addr],
          action
        )
      rescue => e
        File.open(log_path, 'a') { |f| f.puts "\n⚠️ Controller terraform failed: #{e.message}\n" }
      end
    end
    { success: true, log_url: "/logs?id=#{register_log(log_path)}" }.to_json
  end

  helpers do
    # Identity used for the controller's playbook run-state / lock files. Must
    # match what Automation.run_playbook records for the standalone Lab, whose
    # relative_path is 'controller/topology.yml'.
    def controller_lab_name
      'controller/topology.yml'
    end

    # Re-run add_dnat against the merged topology so a service added while the
    # controller is up is forwarded immediately. add_dnat is idempotent (it
    # `-C`s each rule first), so existing base rules are untouched. Returns
    # whether it applied live.
    def live_apply_services
      return false unless Controller.running?
      begin
        Controller.new.lab.add_dnat
        true
      rescue => e
        false
      end
    end
  end
end
