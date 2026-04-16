# -----------------------------------------------------------------------------
# File        : ctlabs/routes/labs.rb
# License     : MIT License
# -----------------------------------------------------------------------------

get '/labs' do
  @labs = all_labs
  @selected_lab = get_running_lab || session[:selected_lab] || (@labs.first if @labs.any?)
  session[:adhoc_dnat_rules] ||= {}

  # (DELETED THE @lab_info = parse_lab_info(...) BLOCK ENTIRELY)

  # In /labs route
  running = get_running_lab
  if running && @selected_lab == running
    # Load from disk and update session for consistency
    lab_name_safe = running.gsub(/\//, '_').gsub(/[^a-zA-Z0-9_.\-]/, '')
    adhoc_file = "#{LOCK_DIR}/adhoc_dnat_#{lab_name_safe}.json"
    if File.file?(adhoc_file)
      session[:adhoc_dnat_rules] ||= {}
      session[:adhoc_dnat_rules][running] = JSON.parse(File.read(adhoc_file), :symbolize_names => true)
    end
  end

  erb :labs
end

get '/labs/download' do
  lab_name = params[:lab]
  
  # Try to grab the active runtime file first
  runtime_path = File.join(LOCK_DIR, "#{lab_name.gsub('/', '_')}.yml")
  
  # Fallback to the base lab file if it's not currently running
  file_path = File.file?(runtime_path) ? runtime_path : File.join(LABS_DIR, lab_name)

  if File.file?(file_path)
    # Send the file as a downloadable attachment
    send_file file_path, :filename => "custom_#{File.basename(lab_name)}", :type => 'application/x-yaml'
  else
    halt 404, "Configuration file not found."
  end
end

post '/labs/new' do
  lab_name = params[:lab_name].to_s.strip.gsub(/[^a-zA-Z0-9_\-\/]/, '') # sanitize
  desc = params[:desc].to_s.strip
  
  lab_name += '.yml' unless lab_name.end_with?('.yml')
  lab_path = File.join(LABS_DIR, lab_name)

  if File.exist?(lab_path)
    halt 400, "A lab with that filename already exists!"
  end

  FileUtils.mkdir_p(File.dirname(lab_path))
  
  # Base name without the .yml extension
  base_name = File.basename(lab_name, '.yml')

  # Use a Heredoc to perfectly preserve spacing, alignment, and arrays!
  default_yaml = <<~YAML
    # -----------------------------------------------------------------------------
    # File        : ctlabs/labs/#{lab_name}
    # Description : #{desc}
    # -----------------------------------------------------------------------------

    name: #{base_name}
    desc: #{desc}

    defaults:
      controller:
        linux:
          image: ctlabs/c9/ctrl
      switch:
        mgmt:
          image: ctlabs/c9/ctrl
          ports: 16
        linux:
          image: ctlabs/c9/base
          ports: 6
      host:
        linux:
          image: ctlabs/c9/base
        db2:
          image: ctlabs/misc/db2
          caps: [SYS_NICE,IPC_LOCK,IPC_OWNER]
        cbeaver:
          image: ctlabs/misc/cbeaver
        d12:
          image: ctlabs/d12/base
        kali:
          image: ctlabs/kali/base
        parrot:
          image: ctlabs/parrot/base
        slapd:
          image: ctlabs/d12/base
          caps: [SYS_PTRACE]
      router:
        frr:
          image: ctlabs/c9/frr
          caps : [SYS_NICE,NET_BIND_SERVICE]
        mgmt:
          image: ctlabs/c9/frr
          caps : [SYS_NICE,NET_BIND_SERVICE]

    topology:
      - name: #{base_name}-vm1
        dns : [192.168.10.11, 192.168.10.12, 8.8.8.8]
        mgmt:
          vrfid : 99
          dns   : [1.1.1.1, 8.8.8.8]
          net   : 192.168.99.0/24
          gw    : 192.168.99.1
        nodes:
          ansible :
            type : controller
            gw   : 192.168.99.1
            nics :
              eth0: 192.168.99.3/24
            vols : ['/root/ctlabs-ansible/:/root/ctlabs-ansible/:Z,rw', '/srv/jupyter/ansible/:/srv/jupyter/work/:Z,rw']
            play: 
              book: ctlabs.yml
              tags: [up, setup, ca, bind, jupyter, smbadc, slapd, sssd]
            dnat :
              - [9988, 8888]
          sw0:
            type  : switch
            kind  : mgmt
            ipv4  : 192.168.99.11/24
            gw    : 192.168.99.1
          ro0:
            type : router
            kind : mgmt
            gw   : 192.168.15.1
            nics :
              eth0: 192.168.99.1/24
              eth1: 192.168.15.2/29
          natgw:
            type : gateway
            ipv4 : 192.168.15.1/29
            snat : true
            dnat : ro1:eth1
          sw1:
            type : switch
          sw2:
            type : switch
          sw3:
            type : switch
          ro1:
            type : router
            kind : frr
            gw   : 192.168.15.1
            nics :
              eth1: 192.168.15.3/29
              eth2: 192.168.10.1/24
              eth3: 192.168.20.1/24
              eth4: 192.168.30.1/24
        links: []
  YAML

  File.write(lab_path, default_yaml)
  redirect '/labs' # Refresh the page to show the new lab in the dropdown
end

post '/labs/*/save' do
  content_type :json
  lab_name = params[:splat].first

  begin
    source_path = get_lab_file_path(lab_name) # Gets the RUNNING state
    base_path = File.join(LABS_DIR, "#{lab_name.gsub('.yml', '')}.yml")

    yaml = YAML.load_file(source_path) || {}
    
    # Save running state, using base_path to steal the original header
    write_formatted_yaml(base_path, yaml, base_path)

    { success: true, message: "Lab overwritten successfully" }.to_json
  rescue => e
    status 500
    { success: false, error: "Backend Crash: #{e.message}" }.to_json
  end
end

post '/labs/*/save_as' do
  lab_name = params[:splat].first
  new_lab_name = params[:new_lab_name].to_s.strip.gsub(/[^a-zA-Z0-9_\-\/\.]/, '')
  new_desc = params[:new_desc].to_s.strip
  force_overwrite = params[:force] == 'true'

  halt 400, { success: false, error: "New lab name is required" }.to_json if new_lab_name.empty?

  new_lab_name += '.yml' unless new_lab_name.end_with?('.yml')
  new_lab_path = File.join(LABS_DIR, new_lab_name)

  if File.exist?(new_lab_path) && !force_overwrite
    halt 400, { success: false, error: "EXISTS" }.to_json
  end

  begin
    source_path = get_lab_file_path(lab_name) # Gets the RUNNING state!
    original_base_path = File.join(LABS_DIR, "#{lab_name.gsub('.yml', '')}.yml")
    
    yaml = YAML.load_file(source_path) || {}

    # Update metadata
    base_name = File.basename(new_lab_name, '.yml')
    yaml['name'] = base_name
    yaml['desc'] = new_desc unless new_desc.empty?

    FileUtils.mkdir_p(File.dirname(new_lab_path))
    
    # Save running state to NEW file, stealing the header from the OLD base file
    write_formatted_yaml(new_lab_path, yaml, original_base_path)

    { success: true, message: "Lab saved as #{new_lab_name}", new_lab: new_lab_name }.to_json
  rescue => e
    status 500
    { success: false, error: e.message }.to_json
  end
end

post '/labs/execute' do
  action = params[:action]
  halt 400, "Invalid action" unless %w[up down].include?(action)

  if action == 'up'
    lab_name = params[:lab_name]
    labs_list = all_labs
    halt 400, "Invalid lab" unless lab_name && labs_list.include?(lab_name)
    if Lab.running?
      halt 400, "A lab is already running: #{Lab.current_name}. Stop it first."
    end
  else # down
    unless Lab.running?
      halt 400, "No lab is currently running."
    end
    lab_name = Lab.current_name
    labs_list = all_labs
    halt 500, "Running lab not found" unless labs_list.include?(lab_name)
  end

  source_path = File.join(LABS_DIR, lab_name)
  runtime_path = "#{LOCK_DIR}/#{lab_name.gsub('/', '_')}.yml"
  log = LabLog.for_lab(lab_name: lab_name, action: action)

  Thread.new do
    begin
      if action == 'up'
        FileUtils.cp(source_path, runtime_path)
        lab_instance = Lab.new(cfg: runtime_path, relative_path: lab_name, log: log)
        lab_instance.up
        log.info "--- Lab #{lab_name} UP completed ---"

        # ✅ RUN PLAYBOOK ONCE with built-in concurrency protection
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
  
  redirect "/logs?file=#{URI.encode_www_form_component(log.path)}"
end

post '/labs/action' do
  @labs = all_labs
  lab_name = params[:lab_name]
  action   = params[:action]

  unless lab_name && @labs.include?(lab_name)
    halt 400, "Invalid lab"
  end

  session[:selected_lab] = lab_name

  lab_path = File.join(LABS_DIR, lab_name)
  cmd = case action
        when 'start'
          "cd #{SCRIPT_DIR} && #{CTLABS_SCRIPT} -c #{lab_path.shellescape} -up"
        when 'stop'
          "cd #{SCRIPT_DIR} && #{CTLABS_SCRIPT} -c #{lab_path.shellescape} -d"
        else
          halt 400, "Unknown action"
        end

  @output = `#{cmd} 2>&1`
  @success = $?.success?
  @selected_lab = lab_name

  erb :lab_action_result
end

get '/labs/*/info_card' do
  content_type 'text/html' # Return HTML fragment

  # params[:splat] is an Array containing the matched '*' part(s).
  # For the URL /labs/lpic2/lpic210.yml/info_card, params[:splat] will be ["lpic2/lpic210.yml"]
  lab_name_parts = params[:splat]

  # Extract the lab name string from the first element of the splat array
  lab_name = lab_name_parts.first if lab_name_parts && lab_name_parts.length > 0

  # --- Validation (same as before) ---
  # Ensure lab_name exists, ends with .yml, and doesn't contain dangerous patterns
  if !lab_name || !lab_name.end_with?('.yml') || lab_name.include?('..') || lab_name.include?("\0")
    halt 404, "Invalid lab name."
  end

  labs_list = all_labs
  unless labs_list.include?(lab_name)
    halt 404, "Lab '#{lab_name}' not found."
  end

  # --- Processing (same as before) ---
  lab_file_path = File.join(LABS_DIR, lab_name)
  lab_info = parse_lab_info(lab_file_path)

  # Use local variables if they exist, otherwise fallback to the instance variable
  data_to_pass = defined?(lab_info) ? lab_info : @lab_info
  erb :lab_details, layout: false, locals: { info_hash: data_to_pass }
end

# Add this route *before* the main routes, or wherever appropriate
# This route catches /labs/ANYTHING/info
get '/labs/*/info' do
  content_type :json

  # params[:splat] is an Array containing the matched '*' part(s).
  # For the URL /labs/k3s/k3s01.yml/info, params[:splat] will be ["k3s/k3s01.yml"]
  lab_name_parts = params[:splat]

  # Extract the lab name string from the first element of the splat array
  lab_name = lab_name_parts.first if lab_name_parts && lab_name_parts.length > 0

  # --- Validation ---
  # Ensure lab_name exists, ends with .yml, and doesn't contain dangerous patterns
  if !lab_name || !lab_name.end_with?('.yml') || lab_name.include?('..') || lab_name.include?("\0")
    # Return a JSON error object with a 404 status
    halt 404, { error: "Invalid lab name." }.to_json
  end

  # Check if the requested lab name exists in the list of known labs
  labs_list = all_labs
  unless labs_list.include?(lab_name)
    # Return a JSON error object with a 404 status
    halt 404, { error: "Lab '#{lab_name}' not found." }.to_json
  end

  lab_file_path = File.join(LABS_DIR, lab_name)
  lab = Lab.new(cfg: lab_file_path)
  #puts "nodes"
  #lab.nodes.each do |node|
  #  p "Node: #{node}"
  #end
  #p lab.nodes

  # --- Processing ---
  # Construct the full path to the lab file
  lab_file_path = File.join(LABS_DIR, lab_name)

  # Call the helper function to parse the lab's YAML file
  lab_info = parse_lab_info(lab_file_path)

  # --- Response ---
  # Send the parsed information back as a JSON string
  lab_info.to_json
end

# Get current Lab Metadata for the Edit Modal
get '/labs/*/meta' do
  content_type :json
  lab_path = params[:splat].first
  full_path = File.join("..", "labs", lab_path)
  
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

# Update Lab Metadata safely using a text-replacement scanner
post '/labs/*/edit_meta' do
  content_type :json
  lab_path = params[:splat].first
  full_path = File.join("..", "labs", lab_path)
  
  begin
    lines = File.readlines(full_path)
    
    # Process variables
    formatted_vm_dns = params[:vm_dns].to_s.split(',').map(&:strip).reject(&:empty?).join(', ')
    formatted_mgmt_dns = params[:mgmt_dns].to_s.split(',').map(&:strip).reject(&:empty?).join(', ')
    
    new_lines = []
    in_topology = false
    in_vm = false
    in_mgmt = false
    in_nodes = false
    
    # We will track what we've injected so we can add missing keys
    seen = { name: false, desc: false, vm_name: false, vm_dns: false, vrfid: false, mgmt_dns: false, net: false, gw: false }

    lines.each do |line|
      if line.match?(/^\s+nodes:/) || line.match?(/^\s+links:/)
        in_nodes = true
      end
      
      if in_nodes
        new_lines << line
        next
      end

      # Track Block State
      if line.match?(/^topology:/)
        in_topology = true
      elsif in_topology && line.match?(/^\s+- vm:/)
        in_vm = true
      elsif in_vm && line.match?(/^\s+mgmt:/)
        in_mgmt = true
      end

      # Perform Replacements & Mark as Seen
      if !in_topology && line.match?(/^name:/)
        new_lines << "name: #{params[:name]}\n"
        seen[:name] = true
      elsif !in_topology && line.match?(/^desc:/)
        new_lines << "desc: #{params[:desc]}\n"
        seen[:desc] = true
      elsif in_vm && !in_mgmt && line.match?(/^\s+name:/)
        new_lines << "    name: #{params[:vm_name]}\n"
        seen[:vm_name] = true
      elsif in_vm && !in_mgmt && line.match?(/^\s+dns\s*:/)
        new_lines << "    dns : [#{formatted_vm_dns}]\n"
        seen[:vm_dns] = true
      elsif in_mgmt && line.match?(/^\s+vrfid\s*:/)
        new_lines << "      vrfid : #{params[:mgmt_vrfid]}\n"
        seen[:vrfid] = true
      elsif in_mgmt && line.match?(/^\s+dns\s*:/)
        new_lines << "      dns   : [#{formatted_mgmt_dns}]\n"
        seen[:mgmt_dns] = true
      elsif in_mgmt && line.match?(/^\s+net\s*:/)
        new_lines << "      net   : #{params[:mgmt_net]}\n"
        seen[:net] = true
      elsif in_mgmt && line.match?(/^\s+gw\s*:/)
        new_lines << "      gw    : #{params[:mgmt_gw]}\n"
        seen[:gw] = true
      
      # INJECT MISSING KEYS RIGHT BEFORE THE NEXT BLOCK STARTS
      elsif line.match?(/^defaults:/) || line.match?(/^topology:/)
        new_lines << "name: #{params[:name]}\n" unless seen[:name]
        new_lines << "desc: #{params[:desc]}\n" unless seen[:desc]
        new_lines << line
      elsif in_vm && !in_mgmt && line.match?(/^\s+mgmt:/)
        new_lines << "    name: #{params[:vm_name]}\n" unless seen[:vm_name] || params[:vm_name].empty?
        new_lines << "    dns : [#{formatted_vm_dns}]\n" unless seen[:vm_dns] || formatted_vm_dns.empty?
        new_lines << line
      elsif in_mgmt && line.match?(/^\s+nodes:/)
        new_lines << "      vrfid : #{params[:mgmt_vrfid]}\n" unless seen[:vrfid] || params[:mgmt_vrfid].empty?
        new_lines << "      dns   : [#{formatted_mgmt_dns}]\n" unless seen[:mgmt_dns] || formatted_mgmt_dns.empty?
        new_lines << "      net   : #{params[:mgmt_net]}\n" unless seen[:net] || params[:mgmt_net].empty?
        new_lines << "      gw    : #{params[:mgmt_gw]}\n" unless seen[:gw] || params[:mgmt_gw].empty?
        new_lines << line
      else
        new_lines << line
      end
    end
    
    File.write(full_path, new_lines.join)
    { message: "Lab metadata updated successfully." }.to_json
  rescue => e
    status 500
    { error: "Failed to update lab: #{e.message}" }.to_json
  end
end
