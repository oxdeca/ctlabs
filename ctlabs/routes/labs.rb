# -----------------------------------------------------------------------------
# File        : ctlabs/routes/labs.rb
# License     : MIT License
# -----------------------------------------------------------------------------

# Download the active runtime YAML configuration
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

get '/demo' do
  erb :demo
end

get '/flashcards' do
  @read_only = Lab.running?
  erb :flashcards
end

# Save flashcards (Blocked if Lab is Running)
post '/flashcards/data' do
  content_type :json
  
  # Security: Block saves if Lab is running
  if Lab.running?
     status 403
     return { success: false, error: 'Read-Only Mode: Cannot save while Lab is running.' }.to_json
  end
  
  begin
    data        = JSON.parse(request.body.read)
    public_file = '/srv/ctlabs-server/public/flashcards.json'
    
    if !data['set'] || !data['set']['cards'] || data['set']['cards'].empty?
      status 400
      { success: false, error: 'Cannot save empty flashcard set' }.to_json
    else
      File.write(public_file, JSON.pretty_generate(data))
      { success: true }.to_json
    end
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

get '/markdown' do
  erb :markdown
end

post '/upload' do
  uploaded_file = params[:file]
  return halt erb(:upload), BADREQ unless uploaded_file

  filename = uploaded_file[:tempfile].path

  puts "File received: #{filename}\nContents: #{File.read(filename).unpack("H*")}"
  if File.zero?(filename)
    puts "Error: The file is empty"
    return halt erb(:upload), BADREQ
  end

  FileUtils.cp(filename, UPLOAD_DIR + '/' + uploaded_file[:filename] )
  #File.rename(filename, UPLOAD_DIR + '/' + uploaded_file[:filename] )
  #File.unlink(filename)

  redirect '/upload'
end

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

# ---------------------------------------------------
# LABS
# ---------------------------------------------------

# Create a Brand New Lab YAML with the Default Base Environment
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

# Save runtime state to base YAML
post '/labs/*/save' do
  content_type :json
  # Using splat handles the slash in 'dev/test.yml' perfectly
  lab_path = params[:splat].first
  
  begin
    # NOTE: Replace 'Lab.save_runtime_to_base' with whatever your actual Ruby method
    # is for saving the lab state!
    if Lab.save_runtime_to_base(lab_path) 
      { message: "Lab saved successfully" }.to_json
    else
      status 500
      { error: "Failed to save lab configuration to disk." }.to_json
    end
  rescue => e
    status 500
    { error: "Backend Crash: #{e.message}" }.to_json
  end
end

# Save Current Lab (Base or Runtime) as a New File
post '/labs/*/save_as' do
  lab_name = params[:splat].first
  new_lab_name = params[:new_lab_name].to_s.strip.gsub(/[^a-zA-Z0-9_\-\/]/, '')
  new_desc = params[:new_desc].to_s.strip
  
  halt 400, { success: false, error: "New lab name is required" }.to_json if new_lab_name.empty?
  
  new_lab_name += '.yml' unless new_lab_name.end_with?('.yml')
  new_lab_path = File.join(LABS_DIR, new_lab_name)
  
  if File.exist?(new_lab_path)
    halt 400, { success: false, error: "A lab with that filename already exists!" }.to_json
  end
  
  begin
    # get_lab_file_path automatically grabs the runtime lock file if the lab is currently running!
    source_path = get_lab_file_path(lab_name)
    yaml = YAML.load_file(source_path) || {}
    
    # Update the internal metadata for the new lab
    base_name = File.basename(new_lab_name, '.yml')
    yaml['name'] = base_name
    yaml['desc'] = new_desc unless new_desc.empty?
    
    # Ensure the target directory exists (e.g. custom/my_new_lab.yml)
    FileUtils.mkdir_p(File.dirname(new_lab_path))
    
    write_formatted_yaml(new_lab_path, yaml)
    
    { success: true, message: "Lab saved as #{new_lab_name}", new_lab: new_lab_name }.to_json
  rescue => e
    status 400
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

# Add this route *before* the main routes, and importantly, BEFORE the '/labs/*/info' route
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

# ---------------------------------------------------
# NODES
# ---------------------------------------------------

# Add a New Node to the Base YAML
post '/labs/*/node/new' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path) || {}
    node_name = params[:node_name].strip
    
    raise "Node name is required." if node_name.empty?
    
    # Bulletproof YAML path generation
    yaml['topology'] ||= [{}]
    yaml['topology'][0] ||= {}
    yaml['topology'][0]['nodes'] ||= {}
    
    raise "Node '#{node_name}' already exists!" if yaml['topology'][0]['nodes'].key?(node_name)

    yaml['topology'][0]['nodes'][node_name] = {
      'type' => params[:type],
      'kind' => params[:kind]
    }
    write_formatted_yaml(lab_path, yaml)
    { success: true, message: "Node '#{node_name}' added to base configuration." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

post '/labs/*/node' do
  lab_name = params[:splat].first
  halt 400, "AdHoc Nodes only allowed on the running lab" unless get_running_lab == lab_name
  node_name = params[:node_name]

  node_cfg = { 'type' => params[:type] || 'host', 'kind' => params[:kind] || 'linux' }
  node_cfg['gw'] = params[:gw].strip if params[:gw] && !params[:gw].strip.empty?
  node_cfg['nics'] = { 'eth1' => params[:ip].strip } if params[:ip] && !params[:ip].strip.empty?

  begin
    lab_path = get_lab_file_path(lab_name)
    lab = Lab.new(cfg: lab_path)
    
    # Start node and get config/links
    cfg_out, data_link = lab.add_adhoc_node(node_name, node_cfg, params[:switch])

    # Append to runtime YAML
    data = YAML.load_file(lab_path)
    data['topology'][0]['nodes'][node_name] = cfg_out
    
    data['topology'][0]['links'] ||= []
    if data_link
      data['topology'][0]['links'] << data_link
      
      # Auto-expand switch port capacity if necessary
      sw_name = params[:switch].strip
      sw_port = data_link[0].split(':eth').last.to_i
      sw_node = data['topology'][0]['nodes'][sw_name]
      if sw_node
        current_ports = sw_node['ports'] || 4 
        if sw_port > current_ports
          sw_node['ports'] = sw_port
        end
      end
    end
    
    write_formatted_yaml(lab_path, data)
    
    content_type :json
    { success: true, message: "AdHoc Node '#{node_name}' started" }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

get '/labs/*/node/:node_name' do
  lab_name = params[:splat].first
  node_name = params[:node_name]
  lab_path = get_lab_file_path(lab_name)

  node_cfg = nil
  if File.file?(lab_path)
    data = YAML.load_file(lab_path)
    node_cfg = data['topology'][0]['nodes'][node_name] if data['topology'] && data['topology'][0]
  end

  node_cfg ||= { 'type' => 'host', 'kind' => 'linux', 'gw' => '', 'nics' => { 'eth1' => '' } }
  
  yaml_str = node_cfg.to_yaml
  yaml_str = yaml_str.gsub(/^(\s*)- -\s*(.+?)\n\1  -\s*(.+?)\n\1  -\s*(.+?)\n/) { "#{$1}- [#{$2}, #{$3}, #{$4}]\n" }
  yaml_str = yaml_str.gsub(/^(\s*)- -\s*(.+?)\n\1  -\s*(.+?)\n/) { "#{$1}- [#{$2}, #{$3}]\n" }

  content_type :json
  { yaml: yaml_str, json: node_cfg }.to_json
end

post '/labs/*/node/:node_name/edit' do
  lab_name = params[:splat].first
  node_name = params[:node_name]
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path)
    base_data = full_yaml['topology'][0]['nodes'][node_name] || {}

    if params[:format] == 'form'
      new_cfg = base_data.dup
      new_cfg['type'] = params[:type] unless params[:type].to_s.empty?
      params[:kind].to_s.empty? ? new_cfg.delete('kind') : new_cfg['kind'] = params[:kind]
      params[:gw].to_s.empty? ? new_cfg.delete('gw') : new_cfg['gw'] = params[:gw]
      
      # NEW: Process the Info field
      params[:info].to_s.empty? ? new_cfg.delete('info') : new_cfg['info'] = params[:info]
      params[:term].to_s.empty? ? new_cfg.delete('term') : new_cfg['term'] = params[:term]

      if params[:nics] && !params[:nics].strip.empty?
        new_cfg['nics'] = params[:nics].split("\n").map { |l| l.split('=').map(&:strip) }.to_h.reject { |k,v| k.nil? || v.nil? }
      else
        new_cfg.delete('nics')
      end

      # NEW: Process the Custom URLs Textarea
      if params[:urls_text] && !params[:urls_text].strip.empty?
        urls_hash = {}
        params[:urls_text].split("\n").each do |line|
          title, link = line.split('|', 2)
          # Only add if both a title and a link exist on the line
          if title && !title.strip.empty? && link && !link.strip.empty?
            urls_hash[title.strip] = link.strip 
          end
        end
        new_cfg['urls'] = urls_hash unless urls_hash.empty?
      else
        new_cfg.delete('urls')
      end

    else
      new_cfg = YAML.safe_load(params[:yaml_data])
    end

    full_yaml['topology'][0]['nodes'][node_name] = new_cfg
    write_formatted_yaml(lab_path, full_yaml)

    content_type :json
    { success: true, message: "Node configuration saved." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# Delete a Node, Stop the Container, and Clean up Dangling Links
post '/labs/*/node/:node_name/delete' do
  lab_name = params[:splat].first
  node_name = params[:node_name]
  lab_path = get_lab_file_path(lab_name)
  
  begin
    # 1. Stop the live container if the lab is running
    if Lab.running? && Lab.current_name == lab_name
      lab = Lab.new(cfg: lab_path, log: LabLog.null)
      target_node = lab.find_node(node_name)
      target_node.stop if target_node
    end

    # 2. Remove the node from the YAML
    yaml = YAML.load_file(lab_path)
    yaml['topology'][0]['nodes'].delete(node_name)

    # 3. SCRUB ORPHANED LINKS: Remove any links connected to this node!
    yaml['topology'][0]['links']&.reject! do |l|
      l.is_a?(Array) && (l[0].start_with?("#{node_name}:") || l[1].start_with?("#{node_name}:"))
    end

    # 4. Save the file (This updates the timestamp, which triggers the visual Smart Cache on reload!)
    write_formatted_yaml(lab_path, yaml)
    
    { success: true, message: "Node deleted and orphaned links removed." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# ---------------------------------------------------
# LINKS
# ---------------------------------------------------
# Add or Edit a Network Link
post '/labs/*/link/save' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    yaml['topology'][0]['links'] ||= []

    ep1 = "#{params[:node_a]}:#{params[:int_a]}"
    ep2 = "#{params[:node_b]}:#{params[:int_b]}"
    
    # Native Format: ["h1:eth1", "sw1:eth1"]
    new_link = [ep1, ep2]

    if params[:old_ep1] && params[:old_ep2] && !params[:old_ep1].empty?
      # Update Existing Link
      idx = yaml['topology'][0]['links'].find_index do |l|
        l.is_a?(Array) && l.include?(params[:old_ep1]) && l.include?(params[:old_ep2])
      end
      idx ? (yaml['topology'][0]['links'][idx] = new_link) : (yaml['topology'][0]['links'] << new_link)
    else
      # Add New Link
      yaml['topology'][0]['links'] << new_link
    end

    write_formatted_yaml(lab_path, yaml)
    { success: true, message: "Link saved successfully." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# Delete a Network Link
post '/labs/*/link/delete' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    yaml['topology'][0]['links']&.reject! do |l|
      l.is_a?(Array) && l.include?(params[:ep1]) && l.include?(params[:ep2])
    end
    write_formatted_yaml(lab_path, yaml)
    { success: true, message: "Link deleted." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# ---------------------------------------------------
# DNAT
# ---------------------------------------------------
post '/labs/*/dnat' do
  lab_name = params[:splat].first
  halt 400, "AdHoc DNAT only allowed on the running lab" unless get_running_lab == lab_name

  begin
    lab_path = get_lab_file_path(lab_name)
    lab = Lab.new(cfg: lab_path)
    rule = lab.add_adhoc_dnat(params[:node], params[:external_port].to_i, params[:internal_port].to_i, (params[:protocol] || 'tcp').downcase)

    # Append to runtime YAML
    data = YAML.load_file(lab_path)
    data['topology'][0]['nodes'][params[:node]]['dnat'] ||= []
    data['topology'][0]['nodes'][params[:node]]['dnat'] << [params[:external_port].to_i, params[:internal_port].to_i, (params[:protocol] || 'tcp').downcase]
    
    # Save beautifully formatted YAML
    write_formatted_yaml(lab_path, data)

    content_type :json
    { success: true, message: "AdHoc DNAT rule added" }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# Delete a DNAT Rule
post '/labs/*/dnat/delete' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    node = params[:node]
    dnat_rules = yaml['topology'][0]['nodes'][node]['dnat'] rescue nil
    
    if dnat_rules
      dnat_rules.reject! do |r| 
        r[0].to_s == params[:ext].to_s && r[1].to_s == params[:int].to_s && (r[2] || 'tcp').to_s == params[:proto].to_s
      end
      yaml['topology'][0]['nodes'][node].delete('dnat') if dnat_rules.empty?
      write_formatted_yaml(lab_path, yaml)
    end
    { success: true, message: "DNAT rule deleted." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

# ---------------------------------------------------
# ANSIBLE
# ---------------------------------------------------
# Edit Ansible Playbook Configuration
post '/labs/*/ansible/edit' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path)
    
    # Locate the ansible controller node
    ansible_node_name = full_yaml['topology'][0]['nodes'].keys.find { |k| k == 'ansible' || full_yaml['topology'][0]['nodes'][k]['type'] == 'controller' }
    raise "No ansible controller node found in topology" unless ansible_node_name
    
    base_data = full_yaml['topology'][0]['nodes'][ansible_node_name] || {}
    
    # Initialize or reset the play configuration
    play_cfg = base_data['play'] || {}
    play_cfg = {} if play_cfg.is_a?(String) # Convert raw strings to hashes
    
    # 1. Update Playbook
    params[:book].to_s.strip.empty? ? play_cfg.delete('book') : play_cfg['book'] = params[:book].strip
    
    # 2. Update Environment Variables
    if params[:env] && !params[:env].strip.empty?
      play_cfg['env'] = params[:env].split("\n").map(&:strip).reject(&:empty?)
    else
      play_cfg.delete('env')
    end
    
    # 3. Update Tags
    if params[:tags] && !params[:tags].strip.empty?
      play_cfg['tags'] = params[:tags].split(",").map(&:strip).reject(&:empty?)
    else
      play_cfg.delete('tags')
    end

    # Save it back
    base_data['play'] = play_cfg
    full_yaml['topology'][0]['nodes'][ansible_node_name] = base_data
    write_formatted_yaml(lab_path, full_yaml)

    content_type :json
    { success: true, message: "Ansible configuration updated." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
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
