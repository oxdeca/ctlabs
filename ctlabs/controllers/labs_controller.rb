# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/labs_controller.rb
# Description : Controller for Lab management
# License     : MIT License
# -----------------------------------------------------------------------------

class LabsController < BaseController
  # --- Lab Listing ---
  get '/labs' do
    @labs = Lab.all
    @selected_lab = Lab.current_name || session[:selected_lab] || (@labs.first if @labs.any?)
    session[:adhoc_dnat_rules] ||= {}

    running = Lab.current
    if running && @selected_lab == running.relative_path
      # Load from disk and update session for consistency
      lab_name_safe = running.relative_path.gsub(/\//, '_').gsub(/[^a-zA-Z0-9_.\-]/, '')
      lock_dir = defined?(::LOCK_DIR) ? ::LOCK_DIR : '/var/run/ctlabs'
      adhoc_file = "#{lock_dir}/adhoc_dnat_#{lab_name_safe}.json"
      if File.file?(adhoc_file)
        session[:adhoc_dnat_rules] ||= {}
        session[:adhoc_dnat_rules][running.relative_path] = JSON.parse(File.read(adhoc_file), :symbolize_names => true)
      end
    end

    erb :labs
  end

  # --- Download Lab Config ---
  get '/labs/download' do
    lab_name = params[:lab]
    path = Lab.get_file_path(lab_name)

    if File.file?(path)
      send_file path, :filename => "custom_#{File.basename(lab_name)}", :type => 'application/x-yaml'
    else
      halt 404, "Configuration file not found."
    end
  end

  # --- Create New Lab ---
  post '/labs/new' do
    begin
      LabRepository.create_lab(params[:lab_name], params[:desc])
      redirect '/labs'
    rescue => e
      halt 400, e.message
    end
  end

  # --- Save Running State to Base Lab ---
  post '/labs/*/save' do
    content_type :json
    lab_name = params[:splat].first

    begin
      source_path = Lab.get_file_path(lab_name)
      labs_dir = LabRepository.labs_dir
      base_path = File.join(labs_dir, "#{lab_name.gsub('.yml', '')}.yml")

      yaml = YAML.load_file(source_path) || {}
      LabRepository.save_lab(lab_name, yaml, base_path)

      { success: true, message: "Lab overwritten successfully" }.to_json
    rescue => e
      status 500
      { success: false, error: "Backend Crash: #{e.message}" }.to_json
    end
  end

  # --- Save Running State as New Lab ---
  post '/labs/*/save_as' do
    lab_name = params[:splat].first
    new_lab_name = params[:new_lab_name].to_s.strip.gsub(/[^a-zA-Z0-9_\-\/\.]/, '')
    new_desc = params[:new_desc].to_s.strip
    force_overwrite = params[:force] == 'true'

    halt 400, { success: false, error: "New lab name is required" }.to_json if new_lab_name.empty?

    new_lab_name += '.yml' unless new_lab_name.end_with?('.yml')
    labs_dir = LabRepository.labs_dir
    new_lab_path = File.join(labs_dir, new_lab_name)

    if File.exist?(new_lab_path) && !force_overwrite
      halt 400, { success: false, error: "EXISTS" }.to_json
    end

    begin
      source_path = Lab.get_file_path(lab_name)
      original_base_path = File.join(labs_dir, "#{lab_name.gsub('.yml', '')}.yml")
      
      yaml = YAML.load_file(source_path) || {}

      # Update metadata
      base_name = File.basename(new_lab_name, '.yml')
      yaml['name'] = base_name
      yaml['desc'] = new_desc unless new_desc.empty?

      FileUtils.mkdir_p(File.dirname(new_lab_path))
      LabRepository.write_formatted_yaml(new_lab_path, yaml, original_base_path)

      { success: true, message: "Lab saved as #{new_lab_name}", new_lab: new_lab_name }.to_json
    rescue => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # --- Execute Lab Up/Down ---
  post '/labs/execute' do
    action = params[:action]
    halt 400, "Invalid action" unless %w[up down].include?(action)

    if action == 'up'
      lab_name = params[:lab_name]
      halt 400, "Invalid lab" unless lab_name && Lab.all.include?(lab_name)
      if Lab.running?
        halt 400, "A lab is already running: #{Lab.current_name}. Stop it first."
      end
    else # down
      unless Lab.running?
        halt 400, "No lab is currently running."
      end
      lab_name = Lab.current_name
    end

    labs_dir = LabRepository.labs_dir
    source_path = File.join(labs_dir, lab_name)
    lock_dir = defined?(::LOCK_DIR) ? ::LOCK_DIR : '/var/run/ctlabs'
    runtime_path = "#{lock_dir}/#{lab_name.gsub('/', '_')}.yml"
    log = LabLog.for_lab(lab_name: lab_name, action: action)

    v_token = session[:vault_token]
    v_addr  = session[:vault_addr]

    Thread.new do
      begin
        if action == 'up'
          FileUtils.cp(source_path, runtime_path)
          lab_instance = Lab.new(cfg: runtime_path, relative_path: lab_name, log: log)
          lab_instance.up(v_token, v_addr)
          log.info "--- Lab #{lab_name} UP completed ---"

          begin
            lab_instance.run_playbook(nil, log.path)
            log.info "--- Ansible playbook completed ---"
          rescue => e
            log.info "⚠️  Playbook failed but lab is running: #{e.message}"
          end
        else
          lab_instance = Lab.new(cfg: runtime_path, relative_path: lab_name, log: log)
          lab_instance.down
          log.info "--- Lab #{lab_name} DOWN completed ---"
          FileUtils.rm_f(runtime_path)
        end
        
        log.info "--- Operation finished ---"
        log.close
        
      rescue => e
        log.info "ERROR: #{e.message}"
        log.info e.backtrace.join("\n")
        log.close
      end
    end
    
    log_id = register_log(log.path)
    redirect "/logs?id=#{log_id}"
  end

  # --- Lab Action (Legacy start/stop via CLI) ---
  post '/labs/action' do
    lab_name = params[:lab_name]
    action   = params[:action]

    unless lab_name && Lab.all.include?(lab_name)
      halt 400, "Invalid lab"
    end

    session[:selected_lab] = lab_name

    labs_dir = LabRepository.labs_dir
    lab_path = File.join(labs_dir, lab_name)
    
    script_dir = defined?(::SCRIPT_DIR) ? ::SCRIPT_DIR : File.expand_path('../', __dir__)
    ctlabs_script = defined?(::CTLABS_SCRIPT) ? ::CTLABS_SCRIPT : './ctlabs.rb'

    cmd = case action
          when 'start'
            "cd #{script_dir} && #{ctlabs_script} -c #{lab_path.shellescape} -up"
          when 'stop'
            "cd #{script_dir} && #{ctlabs_script} -c #{lab_path.shellescape} -d"
          else
            halt 400, "Unknown action"
          end

    @output = `#{cmd} 2>&1`
    @success = $?.success?
    @selected_lab = lab_name

    erb :lab_action_result
  end

  # --- Info Card Fragment ---
  get '/labs/*/info_card' do
    content_type 'text/html'
    lab_name = params[:splat].first

    if !lab_name || !lab_name.end_with?('.yml') || lab_name.include?('..') || lab_name.include?("\0")
      halt 404, "Invalid lab name."
    end

    unless Lab.all.include?(lab_name)
      halt 404, "Lab '#{lab_name}' not found."
    end

    labs_dir = LabRepository.labs_dir
    lab_file_path = File.join(labs_dir, lab_name)
    lab_info = Lab.metadata(lab_file_path)

    erb :lab_details, layout: false, locals: { info_hash: lab_info }
  end

  # --- Lab Info JSON ---
  get '/labs/*/info' do
    content_type :json
    lab_name = params[:splat].first

    if !lab_name || !lab_name.end_with?('.yml') || lab_name.include?('..') || lab_name.include?("\0")
      halt 404, { error: "Invalid lab name." }.to_json
    end

    unless Lab.all.include?(lab_name)
      halt 404, { error: "Lab '#{lab_name}' not found." }.to_json
    end

    labs_dir = LabRepository.labs_dir
    lab_file_path = File.join(labs_dir, lab_name)
    Lab.metadata(lab_file_path).to_json
  end

  # --- Lab Metadata JSON ---
  get '/labs/*/meta' do
    content_type :json
    lab_path = params[:splat].first
    labs_dir = LabRepository.labs_dir
    full_path = File.join(labs_dir, lab_path)
    
    begin
      cfg = YAML.load_file(full_path) || {}
      vm = cfg['topology']&.first || {}
      mgmt = vm['mgmt'] || {}
      
      {
        name: cfg['name'] || '',
        desc: cfg['desc'] || '',
        vm_name: vm['name'] || '',
        vm_dns: (vm['dns'] || []).join(', '),
        mgmt_vrfid: mgmt['vrfid'] || '',
        mgmt_dns: (mgmt['dns'] || []).join(', '),
        mgmt_net: mgmt['net'] || '',
        mgmt_gw: mgmt['gw'] || ''
      }.to_json
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  # --- Edit Lab Metadata ---
  post '/labs/*/edit_meta' do
    content_type :json
    lab_path = params[:splat].first
    
    begin
      LabRepository.update_metadata(lab_path, params)
      { message: "Lab metadata updated successfully." }.to_json
    rescue => e
      status 500
      { error: "Failed to update lab: #{e.message}" }.to_json
    end
  end
end
