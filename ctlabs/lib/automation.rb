# -----------------------------------------------------------------------------
# File        : ctlabs/lib/automation.rb
# Description : Ansible + Terraform automation for a Lab. Owns everything that
#               knows about ansible-playbook, ctlabs-ansible, terraform and the
#               execution locks around them:
#                 - the ansible fact-profile paths (setup/role/terraform_profiles)
#                 - playbook artifact generation (build_play_setup, *_yml)
#                 - execution (run_playbook, run_terraform, stream_docker_exec)
#                 - execution locks / running-state probes
#                 - discovery of the lab's automation controller node
#
#               Mixed into Lab with `include` (instance API), so Lab keeps
#               lab.run_playbook / lab.run_terraform. The class-level helpers
#               have no Lab state to read and are called as Automation.xxx.
#
#               Lab-level orchestration that merely *triggers* automation
#               (#up, #add_adhoc_node, .metadata) deliberately stays in Lab.
# License     : MIT License
# -----------------------------------------------------------------------------

require 'json'
require 'open3'
require 'set'
require 'yaml'
require 'fileutils'
require 'time'
require_relative '../services/lab_repository'

module Automation
  # Box-local overrides live under /root/.ctlabs/labs/<file> and, when present,
  # shadow the repo-shipped default entirely (no merging - see design-guide.md).
  # Resolved fresh on every call (NOT cached into a constant) so the long-lived
  # webgui process picks up a box-local file dropped in after boot, same as the
  # ~/.ctlabs-server/auth override (base_controller.rb) - a frozen constant would
  # only re-check at the next process start (CLI runs are fine either way since
  # each invocation is a fresh process, but the puma server is not).
  def self.profile_override_path(basename)
    override = "/root/.ctlabs/labs/#{basename}"
    File.exist?(override) ? override : "/root/ctlabs/labs/#{basename}"
  end

  def self.setup_profiles_path;     profile_override_path('setup_profiles.yml');     end
  def self.role_profiles_path;      profile_override_path('role_profiles.yml');      end
  def self.terraform_profiles_path; profile_override_path('terraform_profiles.yml'); end

  # The repos live under the host's /root, but /root is mode 0750 root:root in
  # the controller image, so the `ansible` user cannot traverse into it. The
  # controller therefore bind-mounts them at the *_CTL paths below (see
  # labs/node_profiles.yml). Anything this process executes via `docker exec`
  # MUST use the _CTL form; anything it reads/writes itself (it runs as root on
  # the host) uses the host form. Using the host path inside the container fails
  # with "Permission denied" even though the mount is present.
  ANSIBLE_DIR        = '/root/ctlabs-ansible'.freeze
  ANSIBLE_DIR_CTL    = '/srv/ctlabs/ctlabs-ansible'.freeze
  TF_DIR             = '/root/ctlabs-terraform'.freeze
  TF_DIR_CTL         = '/srv/ctlabs/ctlabs-terraform'.freeze
  PLAY_SETUP_FILE    = "#{ANSIBLE_DIR}/.play_setup.json"
  PLAY_SETUP_FILE_CTL= "#{ANSIBLE_DIR_CTL}/.play_setup.json"
  PLAYBOOK_LOCK_DIR  = '/var/run/ctlabs/playbook_locks'.freeze

  # ---------------------------------------------------------------------------
  # Helper: Find Controller in Raw YAML (Moved from automation route)
  # ---------------------------------------------------------------------------
  def self.find_automation_controller(vm_cfg)
    if vm_cfg['nodes']
      name = vm_cfg['nodes'].keys.find { |k| k == 'ansible' || vm_cfg['nodes'][k]['type'] == 'controller' }
      return name, vm_cfg['nodes'][name], nil if name
    end
    
    if vm_cfg['planes']
      vm_cfg['planes'].each do |p_name, p_data|
        if p_data && p_data['nodes']
          name = p_data['nodes'].keys.find { |k| k == 'ansible' || p_data['nodes'][k]['type'] == 'controller' }
          return name, p_data['nodes'][name], p_name if name
        end
      end
    end
    
    [nil, nil, nil]
  end

  # Acquire playbook execution lock (with stale lock cleanup)
  def self.acquire_playbook_lock!(lab_name, timeout: 30)
    lock_path = "#{PLAYBOOK_LOCK_DIR}/#{lab_name.gsub(%r{[^a-zA-Z0-9_.\-/]}, '_').gsub('/', '_')}.lock"
    FileUtils.mkdir_p(PLAYBOOK_LOCK_DIR)
    
    # Check for stale lock (PID no longer exists)
    if File.file?(lock_path)
      begin
        pid = File.read(lock_path).strip.to_i
        if pid > 0
          Process.kill(0, pid)  # Raises Errno::ESRCH if PID doesn't exist
        else
          # Invalid PID → stale lock
          FileUtils.rm_f(lock_path)
        end
      rescue Errno::ESRCH
        # PID doesn't exist → stale lock, clean it up
        @log&.write "Cleaning stale playbook lock for #{lab_name} (PID #{pid} gone)", "debug"
        FileUtils.rm_f(lock_path)
      rescue => e
        # Unknown error → assume lock is valid
        raise "Playbook already running for lab '#{lab_name}' (lock held by PID #{pid || 'unknown'})"
      end
    end
    
    # Attempt to acquire lock with timeout
    timeout.times do
      begin
        lock_file = File.open(lock_path, File::CREAT | File::EXCL | File::WRONLY)
        lock_file.write(Process.pid.to_s)
        lock_file.flush
        return lock_path  # Return path to release later
      rescue Errno::EEXIST
        # Lock exists → wait and retry
        sleep 1
      end
    end
    
    raise "Timeout: Playbook already running for lab '#{lab_name}' (lock file: #{lock_path})"
  end

  # Release playbook execution lock
  def self.release_playbook_lock!(lock_path)
    FileUtils.rm_f(lock_path) if lock_path && File.file?(lock_path)
  rescue => e
    @log&.write "Warning: Failed to release playbook lock #{lock_path}: #{e.message}", "debug"
  end

  # Check if playbook is currently running
  def self.playbook_running?(lab_name)
    lock_path = "#{PLAYBOOK_LOCK_DIR}/#{lab_name.gsub(%r{[^a-zA-Z0-9_.\-/]}, '_').gsub('/', '_')}.lock"
    return false unless File.file?(lock_path)
    
    # Verify lock isn't stale
    begin
      pid = File.read(lock_path).strip.to_i
      return false if pid == 0
      Process.kill(0, pid)  # Raises if PID doesn't exist
      true
    rescue Errno::ESRCH
      # Stale lock → clean up and return false
      FileUtils.rm_f(lock_path)
      false
    rescue
      true  # Unknown state → assume running
    end
  end

  # ---------------------------------------------------------------------------
  # Cancel a running playbook
  # ---------------------------------------------------------------------------
  # Where the run's identity lives. Kept separate from the .lock file on
  # purpose: the lock holds Process.pid (the server/CLI process, used only for
  # staleness detection), which must never be killed. This file holds the PID of
  # the `docker exec` client plus the container the playbook runs in, which is
  # what actually has to die.
  def self.playbook_run_state_path(lab_name)
    "#{PLAYBOOK_LOCK_DIR}/#{lab_name.gsub(%r{[^a-zA-Z0-9_.\-/]}, '_').gsub('/', '_')}.run"
  end

  # A playbook the user stopped looks like a failure to the shell, but it is a
  # deliberate cancellation. ansible-playbook catches SIGTERM and exits 143
  # (128+15); if it dies from the signal itself, wait_thr reports it as
  # "terminated by SIG<n>". Both mean "stopped", not "broken".
  def self.playbook_stopped?(status)
    s = status.to_s
    s == '143' || s.start_with?('terminated by SIG')
  end

  # Whether the user pressed Stop for the run recorded in pid_file. The exit
  # status cannot answer this on its own: Stop kills the host-side `docker exec`
  # client, so the status we observe is usually 1, never 143. The app already
  # knows the stop was deliberate, so it records that intent rather than guessing
  # it back out of the status.
  def self.stop_requested?(pid_file)
    return false if pid_file.nil? || !File.file?(pid_file)

    state = begin
      JSON.parse(File.read(pid_file))
    rescue
      {}
    end

    state['stop_requested'].to_s.strip != ''
  end

  # Returns [success, message]
  def self.stop_playbook!(lab_name, requested_by = nil)
    state_path = playbook_run_state_path(lab_name)
    return [false, 'No playbook run is active for this lab.'] unless File.file?(state_path)

    state = begin
      JSON.parse(File.read(state_path))
    rescue
      {}
    end

    container = state['container'].to_s
    pid       = state['pid'].to_i
    log_path  = state['log']
    actions   = []

    # Who pressed Stop. Rack::Auth::Basic sets REMOTE_USER from the Basic auth
    # header, so this is the real authenticated user, not client-supplied input.
    actor = requested_by.to_s.strip
    actor = 'unknown' if actor.empty?

    # 1. Kill the playbook inside the controller container. This is the one that
    #    matters: SIGTERM makes ansible abort and release its host connections.
    #    Killing only the `docker exec` client would leave the playbook running
    #    detached inside the container.
    unless container.empty?
      # Match on the executable, not the whole command line, so we never
      # accidentally match our own pkill (which carries the pattern as an arg).
      exe = state['command'].to_s.split(/\s+/).find { |w| w =~ %r{\A[a-zA-Z0-9_./-]+\z} && !w.include?('=') } || 'ansible-playbook'
      # Bracket the first character: the ERE "[a]nsible-playbook" still matches
      # the target's cmdline but NOT our own `sh -c pkill -f [a]nsible-playbook`,
      # which is what stops pkill from killing its own shell mid-flight.
      pattern = "[#{exe[0]}]#{exe[1..]}"
      begin
        out = `docker exec #{container} sh -c 'pkill -TERM -f #{pattern}' 2>&1`
        actions << if $?.success?
          "sent SIGTERM to #{exe} in #{container}"
        else
          "no #{exe} process found in #{container} (it may have just finished)"
        end
        File.open(log_path, 'a') { |f| f.puts "\n⚠️ Stop requested by user (#{actor}).\n" } if log_path && File.file?(log_path)
      rescue => e
        actions << "could not signal #{container}: #{e.message}"
      end
    end

    # 2. Kill the host-side `docker exec` client so the streaming thread and its
    #    popen3 block unwind and the playbook lock is released normally.
    if pid > 0
      begin
        Process.kill('TERM', pid)
        actions << "terminated stream process #{pid}"
      rescue Errno::ESRCH
        actions << 'stream process already gone'
      rescue => e
        actions << "could not terminate stream process #{pid}: #{e.message}"
      end
    end

    # Record the intent BEFORE signalling, so the flag is on disk even if the
    # playbook dies mid-flight. run_playbook reads it back out of this same file
    # (see stream_docker_exec) to tell a deliberate stop from a real failure.
    begin
      state['stop_requested']   = Time.now.utc.iso8601
      state['stop_requested_by'] = actor
      File.write(state_path, state.to_json)
    rescue => e
      actions << "could not record stop request: #{e.message}"
    end

    # Do NOT delete the run-state or lock file here - run_playbook's ensure
    # block releases the lock once the thread actually unwinds, which is the
    # only way to know the playbook really stopped.
    [true, actions.empty? ? 'Stop requested.' : actions.join('; ')]
  end

  # Check if Terraform is currently running for a specific lab (used by the UI to disable the button)
  def self.terraform_running?(lab_path)
    # Simple check: see if a terraform process is running inside the lab's controller container
    # You may need to adjust the container naming convention based on how your CTLABS script names them!
    lab_base_name = File.basename(lab_path, '.yml')
    engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
    
    # Check running processes in the controller (assuming the container name contains the lab name and 'ansible' or 'controller')
    # This is a safe, non-blocking check
    cmd = "#{engine} ps --format '{{.Names}}' | grep #{lab_base_name} | head -n 1"
    container_name = `#{cmd}`.strip
    return false if container_name.empty?

    # Check if 'terraform' is in the process list of that container
    `#{engine} exec #{container_name} ps aux | grep -v grep | grep terraform`.strip != ""
  end

  def build_play_setup(play_cfg)
    setup_profiles_path = Automation.setup_profiles_path
    role_profiles_path  = Automation.role_profiles_path
    setup_profiles = File.file?(setup_profiles_path) ?
      (YAML.load_file(setup_profiles_path)['profiles'] || {}) : {}
    role_profiles  = File.file?(role_profiles_path) ?
      (YAML.load_file(role_profiles_path)['profiles'] || {}) : {}

    play_tags = Array(play_cfg['tags'] || []).map(&:to_s)
    result    = {}

    # process explicit play.setup entries (profile + per-host overrides)
    (play_cfg['setup'] || {}).each do |role, cfg|
      cfg        = cfg || {}
      named_prof = cfg['profile'] && setup_profiles[cfg['profile']]
      base_prof  = named_prof || setup_profiles[role]
      base       = base_prof ? Marshal.load(Marshal.dump(base_prof)) : {}
      base.delete('role')

      result[role] = deep_merge(base, cfg.reject { |k, _| k == 'profile' })
    end

    # for roles in play.tags but not play.setup, load setup_profile defaults
    # matching by profile name == role profile name in role_profiles.yml
    role_profiles.each do |profile_name, rp_cfg|
      next if result.key?(profile_name)
      role_tags = Array(rp_cfg['tags'] || []).map(&:to_s)
      next unless (role_tags & play_tags).any?
      next unless setup_profiles.key?(profile_name)
      base = Marshal.load(Marshal.dump(setup_profiles[profile_name]))
      base.delete('role')
      result[profile_name] = base
    end

    # Bake `defaults:` into each per-host entry so that
    # play_setup[role][hostname] always contains the full config.
    # Per-host keys are node names; role-wide defaults live under `defaults:`.
    # Per-host `profile:` overrides the base profile for that host.
    node_names = @nodes.map(&:name).to_set
    result.transform_values! do |role_cfg|
      role_defaults = role_cfg['defaults'] || {}
      per_hosts     = role_cfg.select { |k, _| node_names.include?(k) }
      base          = role_cfg.reject { |k, _| k == 'defaults' || node_names.include?(k) }
      shared        = deep_merge(base, role_defaults)
      if per_hosts.empty?
        shared
      else
        baked = per_hosts.transform_values do |hcfg|
          host_prof_name = hcfg.delete('profile')
          if host_prof_name && setup_profiles[host_prof_name]
            host_base     = Marshal.load(Marshal.dump(setup_profiles[host_prof_name]))
            host_base.delete('role')
            host_defaults = host_base['defaults'] || {}
            host_rest     = host_base.reject { |k, _| k == 'defaults' }
            host_shared   = deep_merge(host_rest, host_defaults)
            deep_merge(shared, deep_merge(host_shared, hcfg))
          else
            deep_merge(shared, hcfg)
          end
        end
        shared.merge(baked)
      end
    end

    File.write(PLAY_SETUP_FILE, JSON.pretty_generate({ 'play_setup' => result }))
    @log.write "#{__method__}(): wrote #{PLAY_SETUP_FILE}", "debug"
    result
  end

  def generate_setup_yml(play_cfg)
    role_profiles_path = Automation.role_profiles_path
    profiles  = File.file?(role_profiles_path) ?
      (YAML.load_file(role_profiles_path)['profiles'] || {}) : {}

    existing  = @nodes.map(&:name)
    play_tags = Array(play_cfg['tags'] || []).map(&:to_s)
    setup_cfg = play_cfg['setup'] || {}

    header = <<~HEADER
      ---

      # ------------------------------------------------------------------------------
      # File        : ctlabs-ansible/playbooks/setup.yml
      # Description : ctlabs phase 3 - write local facts (generated by lab.rb)
      # ------------------------------------------------------------------------------

      - name : ctlabs.playbooks.setup
        hosts: all:!rhosts
        tags : setup
        tasks:
          - name: ctlabs.playbooks.setup.facts_dir.linux
            when: ansible_shell_type | default('sh') != 'powershell'
            file:
              path : "{{ ctg_facts_dir }}"
              state: directory
            
          - name: ctlabs.playbooks.setup.facts_dir.windows
            when: ansible_shell_type | default('sh') == 'powershell'
            win_file:
              path : "{{ ctg_facts_dir }}"
              state: directory

    HEADER

    plays = profiles.map do |profile_name, cfg|
      next unless cfg['role']
      next unless File.file?("#{ANSIBLE_DIR}/roles/#{cfg['role']}/tasks/facts.yml")

      role_tags = Array(cfg['tags'] || []).map(&:to_s)
      next unless (role_tags & play_tags).any?

      role_setup  = setup_cfg[profile_name]
      setup_hosts = role_setup && role_setup['hosts']
      grouped     = cfg['hosts'].is_a?(Array) && cfg['hosts'].first.is_a?(Hash)
      hosts_pattern = if setup_hosts.is_a?(Array) && setup_hosts.first.is_a?(Hash)
        resolved = setup_hosts.flat_map { |g| Array(g['group']) }.uniq & existing
        resolved.empty? ? nil : resolved.join(',')
      elsif setup_hosts.is_a?(String)
        setup_hosts
      elsif setup_hosts
        resolved = Array(setup_hosts) & existing
        resolved.empty? ? nil : resolved.join(',')
      elsif grouped
        resolved = cfg['hosts'].flat_map { |g| Array(g['group']) }.uniq & existing
        resolved.empty? ? nil : resolved.join(',')
      elsif cfg['hosts'].is_a?(String)
        cfg['hosts']
      else
        resolved = Array(cfg['hosts']) & existing
        resolved.empty? ? nil : resolved.join(',')
      end
      next unless hosts_pattern

      <<~PLAY
        - name : ctlabs.playbooks.setup.#{profile_name}
          hosts: #{hosts_pattern}
          tags : setup
          tasks:
            - name: ctlabs.playbooks.setup.#{profile_name}.facts
              include_role:
                name      : #{cfg['role']}
                tasks_from: facts.yml
              vars:
                ctlabs_role_facts: "{{ (play_setup['#{profile_name}'] | default({}))[inventory_hostname] | default(play_setup['#{profile_name}'] | default({})) }}"

      PLAY
    end.compact

    path = "#{ANSIBLE_DIR}/playbooks/setup.yml"
    File.write(path, header + plays.join)
    @log.write "#{__method__}(): wrote #{path}", "debug"
  end

  def generate_ctlabs_yml(play_cfg)
    role_profiles_path = Automation.role_profiles_path
    profiles = File.file?(role_profiles_path) ?
      (YAML.load_file(role_profiles_path)['profiles'] || {}) : {}

    existing  = @nodes.map(&:name)
    play_tags = Array(play_cfg['tags'] || []).map(&:to_s)

    book   = play_cfg['book'] || 'ctlabs.yml'
    header = <<~HEADER
      ---

      # ------------------------------------------------------------------------------
      # File        : ctlabs-ansible/playbooks/#{book}
      # Description : ctlabs phase 4 - run roles (generated by lab.rb)
      # ------------------------------------------------------------------------------

      - import_playbook: up.yml
      - import_playbook: setup.yml

    HEADER

    plays = profiles.flat_map do |profile_name, cfg|
      next [] unless cfg['role']
      role_tags = Array(cfg['tags'] || []).map(&:to_s)
      next [] unless (role_tags & play_tags).any?

      setup_cfg   = (play_cfg['setup'] || {})[profile_name]
      setup_hosts = setup_cfg && setup_cfg['hosts']

      effective_groups = if setup_hosts.is_a?(Array) && setup_hosts.first.is_a?(Hash)
        setup_hosts
      elsif cfg['hosts'].is_a?(Array) && cfg['hosts'].first.is_a?(Hash)
        cfg['hosts']
      else
        nil
      end

      if effective_groups
        effective_groups.filter_map do |grp|
          grp_hosts = Array(grp['group']) & existing
          next if grp_hosts.empty?
          grp_tags = (Array(grp['tags']).map(&:to_s) + role_tags).uniq
          <<~PLAY
            - name : ctlabs.playbooks.ctlabs.#{profile_name}
              hosts: #{grp_hosts.join(',')}
              tags : [#{grp_tags.join(', ')}]
              roles:
                - roles/#{cfg['role']}

          PLAY
        end
      else
        hosts_pattern = if setup_hosts.is_a?(String)
          setup_hosts
        elsif setup_hosts
          resolved = Array(setup_hosts) & existing
          resolved.empty? ? nil : resolved.join(',')
        elsif cfg['hosts'].is_a?(String)
          cfg['hosts']
        else
          resolved = Array(cfg['hosts']) & existing
          resolved.empty? ? nil : resolved.join(',')
        end
        next [] unless hosts_pattern
        [<<~PLAY]
          - name : ctlabs.playbooks.ctlabs.#{profile_name}
            hosts: #{hosts_pattern}
            tags : [#{role_tags.join(', ')}]
            roles:
              - roles/#{cfg['role']}

        PLAY
      end
    end.compact

    path = "#{ANSIBLE_DIR}/playbooks/#{book}"
    File.write(path, header + plays.join)
    @log.write "#{__method__}(): wrote #{path}", "debug"
  end

  def run_playbook(play = nil, log_file_path = nil)
    @log.write "#{__method__}(): play=#{play.inspect}, log_file_path=#{log_file_path}", "debug"

    # VALIDATION: Lab must be running
    unless self.class.running? && self.class.current_name == @relative_path
      raise "Cannot run playbook: Lab '#{@relative_path}' is not running. Start it first with --up"
    end

    # ACQUIRE PLAYBOOK LOCK (prevents concurrent execution)
    playbook_lock = nil
    begin
      playbook_lock = Automation.acquire_playbook_lock!(@relative_path)

      ctrl = find_node('ansible')
      raise "No 'ansible' controller node found in topology" if ctrl.nil?

      domain   = (@cfg['domain'] || @domain)
      play_cfg = ctrl.play.is_a?(Hash) ? ctrl.play : {}

      # generate ansible artifacts from lab topology + profiles
      build_play_setup(play_cfg)
      generate_setup_yml(play_cfg)
      generate_ctlabs_yml(play_cfg)

      # Determine playbook command
      if play.is_a?(String) && !play.strip.empty?
        play_cmd = play.strip + " -e CTLABS_DOMAIN=#{domain} -e CTLABS_HOST=#{@server_ip}"
      elsif ctrl.play.is_a?(String) && !ctrl.play.strip.empty?
        play_cmd = ctrl.play.strip + " -e CTLABS_DOMAIN=#{domain} -e CTLABS_HOST=#{@server_ip}"
      elsif play_cfg['book'].is_a?(String)
        inv_file  = play_cfg['inv'] || "#{@name}.ini"
        play_inv  = " -i ./inventories/#{inv_file}"
        play_env  = " -e CTLABS_DOMAIN=#{domain} -e CTLABS_HOST=#{@server_ip}"
        play_env += " -e @#{PLAY_SETUP_FILE_CTL}"
        play_env += " #{(play_cfg['env'] || []).map { |e| " -e #{e}" }.join}"
        play_book = " ./playbooks/#{play_cfg['book']}"
        play_tags = play_cfg['tags'] ? " -t #{play_cfg['tags'].join(',')}" : ''
        play_cmd  = "ansible-playbook -b#{play_inv}#{play_book}#{play_tags}#{play_env}"
      else
        raise "No playbook specified and no default playbook configured for 'ansible' node"
      end

      @log.info "Executing playbook: #{play_cmd}"

      # Single execution path for web GUI and CLI alike. stream_docker_exec
      # already streams to $stdout and appends to the log when given one, and
      # tolerates log_file_path == nil - so the old `system("docker exec ...")`
      # fallback was dead code (every caller passes a log path) that only
      # duplicated the command string and diverged in error handling.
      status = stream_docker_exec(ctrl.name, play_cmd, log_file_path,
                                  pid_file: log_file_path ? Automation.playbook_run_state_path(@relative_path) : nil)

      # Reaching this point does NOT mean the playbook succeeded: it may have
      # been stopped by the user (SIGTERM/143) or failed outright. Say which.
      if status == '0'
        @log.info "--- Playbook execution completed ---"
      elsif @stop_requested || Automation.playbook_stopped?(status)
        # Not a failure: the user asked for it. Either we recorded the stop
        # request ourselves, or the playbook died from an external SIGTERM
        # (someone pkill'd it in the container). Do not raise, or the CLI would
        # exit non-zero and labs_controller would log "Playbook failed" for a
        # deliberate cancellation.
        @log.info "--- Playbook execution stopped by user (status #{status}) ---"
      else
        @log.info "--- Playbook execution failed (status #{status}) ---"
        # Preserve the contract callers rely on: ctlabs.rb --play turns this
        # rescue into "exit 1", and labs_controller logs "Playbook failed but
        # lab is running".
        raise "Playbook execution failed (status #{status})"
      end

      status

    ensure
      # ALWAYS release lock (even on failure)
      Automation.release_playbook_lock!(playbook_lock) if playbook_lock
    end
  end

  def run_terraform(target_node_name = nil, log_path = nil, web_v_token = nil, web_v_addr = nil, action = 'apply')
    @log.write "#{__method__}(): target=#{target_node_name.inspect}", "debug"

    ctrl = target_node_name ? find_node(target_node_name) : @nodes.find { |n| n.type == 'controller' }
    raise "No controller node found in topology to run Terraform." unless ctrl

    node_cfg  = @cfg['topology'][0]['nodes'][ctrl.name] || {}
    tf_cfg    = node_cfg['terraform'] || {}

    workspace = tf_cfg['workspace'].to_s.strip
    workspace = 'default' if workspace.empty?
    
    vars      = tf_cfg['vars'] || []
    var_args  = vars.map { |v| "-var '#{v}'" }.join(" ")

    tf_work_dir = tf_cfg['work_dir'] && !tf_cfg['work_dir'].empty? ? tf_cfg['work_dir'] : '.'
    work_dir = "#{TF_DIR_CTL}/#{tf_work_dir}"
    
    custom_script = tf_cfg['commands'].to_s.strip

    # --- NEW: Smart Execution Router ---
    if action == 'destroy'
      # 1. DESTROY ALWAYS WINS (Ignores custom scripts)
      base_tf_cmd = <<~CMD.gsub("\n", " ").strip
        cd #{work_dir} && 
        (terraform workspace select #{workspace} || terraform workspace new #{workspace}) && 
        terraform init -upgrade && 
        terraform destroy -auto-approve #{var_args}
      CMD
    elsif !custom_script.empty?
      # 2. CUSTOM SCRIPT (Only runs if action is apply)
      base_tf_cmd = <<~CMD.strip
        cd #{work_dir} && 
        (terraform workspace select #{workspace} || terraform workspace new #{workspace}) && 
        #{custom_script}
      CMD
    else
      # 3. STANDARD APPLY
      base_tf_cmd = <<~CMD.gsub("\n", " ").strip
        cd #{work_dir} && 
        (terraform workspace select #{workspace} || terraform workspace new #{workspace}) && 
        terraform init -upgrade && 
        terraform apply -auto-approve #{var_args}
      CMD
    end

    exec_env  = ""
    exec_env += "-e VAULT_TOKEN='#{web_v_token}' " if web_v_token && !web_v_token.empty?
    exec_env += "-e VAULT_ADDR='#{web_v_addr}' "   if web_v_addr  && !web_v_addr.empty?
    exec_env += "-e VAULT_SKIP_VERIFY=true "       if web_v_token &&  web_v_addr

    # --- Fetch GCP credentials in Ruby, dispatched on terraform.auth.method ---
    begin
      gcp_env = GcpAuth.env_vars(tf_cfg, { addr: web_v_addr, token: web_v_token })
      gcp_env.each { |key, value| exec_env += "-e #{key}='#{value}' " }
    rescue => e
      error_msg = "\n❌ ERROR: Could not generate GCP credentials: #{e.message}\n👉 Please use the Vault Login button in the UI.\n"
      File.open(log_path, 'a') { |f| f.puts error_msg } if log_path
      raise e
    end

    # No more Python wrappers! Just pure Terraform.
    tf_command = base_tf_cmd

    engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
    
    full_cmd = "#{engine} exec #{exec_env}#{ctrl.name} bash -c '#{tf_command.gsub("'", "'\\''")}'"

    @log.info "Executing Terraform on #{ctrl.name}: #{tf_command}" 

    # 4. Stream the output
    if log_path
      File.open(log_path, 'a') do |f|
        f.puts "\n" + "="*50
        f.puts "🚀 TERRAFORM EXECUTION STARTED"
        f.puts "="*50
        f.puts "Target Node : #{ctrl.name}"
        f.puts "Workspace   : #{workspace}"
        f.puts "Variables   : #{vars.empty? ? 'None' : vars.join(', ')}"
        f.puts "-"*50 + "\n"
      end
    end

    IO.popen("#{full_cmd} 2>&1") do |io|
      File.open(log_path, 'a') do |f|
        io.each_line do |line|
          $stdout.print(line) # Mirror to backend CLI
          $stdout.flush
          f.puts line
          f.flush # Force write so the UI picks it up instantly
        end
      end if log_path
    end

    # 5. Check Exit Status and Harvest IPs
    if $?.success?
      msg = "\n✅ Terraform execution completed successfully.\n"
      @log.info msg.strip
      File.open(log_path, 'a') { |f| f.puts msg } if log_path

      # ONLY harvest IPs if this was an 'apply' action
      if action == 'apply'
        begin
          @log.info "Harvesting provisioned IPs from terraform.tfstate..."
          
          # Handle Workspace paths correctly
          state_file = workspace == 'default' ? "#{work_dir}/terraform.tfstate" : "#{work_dir}/terraform.tfstate.d/#{workspace}/terraform.tfstate"

          if File.exist?(state_file)
            state_data = JSON.parse(File.read(state_file))
            live_yaml = YAML.load_file(@cfg_file)
            updates_made = false

            (state_data['resources'] || []).each do |res|
              # Target GCP Compute Instances
              if res['type'] == 'google_compute_instance'
                (res['instances'] || []).each do |inst|
                  attrs = inst['attributes'] || {}
                  vm_name = attrs['name']
                  
                  next unless vm_name

                  # Extract IPs from GCP network interface schema
                  nic = attrs['network_interface']&.first || {}
                  priv_ip = nic['network_ip']
                  pub_ip  = nic.dig('access_config', 0, 'nat_ip') rescue nil

                  # Find the node in the modern planes schema
                  vm_topology = live_yaml['topology']&.first || {}
                  target = nil

                  vm_topology['planes'].each do |_, p_data|
                    if p_data && p_data['nodes'] && p_data['nodes'][vm_name]
                      target = p_data['nodes'][vm_name]
                      break
                    end
                  end

                  if target && (priv_ip || pub_ip)
                    target['nics'] ||= {}
                    target['nics']['eth0'] = "#{pub_ip}/32" if pub_ip
                    target['nics']['eth1'] = "#{priv_ip}/24" if priv_ip
                    if pub_ip
                      target['term'] = "ssh://ansible@#{pub_ip}"
                    end
                    updates_made = true
                    
                    log_msg = "Mapped Terraform IPs for #{vm_name}: eth0=#{pub_ip || 'none'}, eth1=#{priv_ip || 'none'}"
                    @log.info log_msg
                    File.open(log_path, 'a') { |f| f.puts "[IP Harvest] #{log_msg}" } if log_path
                  end
                end
              end
            end

            # Write the updated IPs back to the base lab file
            if updates_made
              LabRepository.write_formatted_yaml(@cfg_file, live_yaml, @cfg_file)
              @log.info "Successfully saved new IPs to lab YAML."
              File.open(log_path, 'a') { |f| f.puts "[IP Harvest] ✅ Successfully saved new IPs to #{@relative_path}" } if log_path
            end
          else
            @log.info "No terraform.tfstate found at #{state_file}. Skipping IP harvest."
          end
        rescue => e
          @log.error "Failed to harvest Terraform IPs: #{e.message}"
          File.open(log_path, 'a') { |f| f.puts "⚠️ IP Harvest failed: #{e.message}" } if log_path
        end
      end
    else
      msg = "\n⚠️ Terraform execution failed.\n"
      @log.info msg.strip
      File.open(log_path, 'a') { |f| f.puts msg } if log_path
      raise "Terraform process returned a non-zero exit code."
    end
  end

  # Streams the command's output to $stdout AND (when log_file_path is given)
  # to that log file. A nil log_file_path is fine - it just streams to stdout -
  # so callers never need a second execution path.
  #
  # Returns the child's status as a String: '0', '143', 'terminated by SIG15',
  # or 'unknown' if the status could not be determined.
  def stream_docker_exec(container_name, play_cmd, log_file_path = nil, pid_file: nil)
    inner_command = "cd #{ANSIBLE_DIR_CTL} && ANSIBLE_FORCE_COLOR=1 #{play_cmd} 2>&1"
    cmd = ['docker', 'exec', container_name, 'sh', '-c', inner_command]
  
    # Open log file ONCE before streaming (critical for web UI visibility)
    log_file = log_file_path ? File.open(log_file_path, 'a') : nil
  
    # Assigned in the ensure block below, read after the popen3 block returns.
    result = nil
  
    Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
      stdin.close

      # Record what is running so the UI can cancel it. wait_thr.pid is the
      # host-side `docker exec` client - NOT Process.pid (that is the server,
      # and killing it would take the whole web UI down).
      if pid_file
        begin
          File.write(pid_file, {
            'pid'       => wait_thr.pid,
            'container' => container_name,
            'command'   => play_cmd,
            'log'       => log_file_path,
            'started'   => Time.now.utc.iso8601
          }.to_json)
        rescue => e
          @log&.write "Warning: could not record playbook run state: #{e.message}", "debug"
        end
      end

      begin
        # Stream stdout → BOTH CLI ($stdout) AND log file
        # IOError here is the normal end-of-stream when the process is killed
        # (Stop button), not an error worth a backtrace in the server log.
        Thread.new do
          begin
            while (line = stdout.gets)
              $stdout.print(line)
              $stdout.flush
              log_file&.write(line)
              log_file&.flush
            end
          rescue IOError
            nil
          end
        end
  
        # Stream stderr → BOTH CLI ($stderr) AND log file
        Thread.new do
          begin
            while (err_line = stderr.gets)
              $stderr.print(err_line)
              $stderr.flush
              log_file&.write(err_line)
              log_file&.flush
            end
          rescue IOError
            nil
          end
        end
  
        # Wait for command completion
        wait_thr.value
  
      rescue => e
        error_msg = "Error during playbook streaming: #{e.message}\n"
        $stderr.print(error_msg)
        $stderr.flush
        log_file&.write(error_msg)
        log_file&.flush
      ensure
        # Critical: close log file AFTER all streaming completes
        log_file&.close
        # Capture the stop intent BEFORE the run-state file is removed below,
        # otherwise run_playbook has no way to tell "user pressed Stop" from
        # "playbook broke" - the exit status is 1 either way.
        @stop_requested = Automation.stop_requested?(pid_file)
        FileUtils.rm_f(pid_file) if pid_file
        # wait_thr.value is nil if this thread itself was killed, and for a
        # signalled process .exitstatus is nil too (.termsig is set instead) -
        # which is exactly what happens when the user presses Stop. Report the
        # signal so the log ends with something meaningful.
        proc_status = wait_thr.value
        status_str = if proc_status.nil?
                       'unknown'
                     elsif proc_status.signaled?
                       "terminated by SIG#{proc_status.termsig}"
                     else
                       proc_status.exitstatus.to_s
                     end
        summary = "[Playbook exited with status: #{status_str}]\n"
        $stdout.print(summary)
        $stdout.flush
        File.open(log_file_path, 'a') { |f| f.write(summary) } if log_file_path && status_str != '0'
        # Hand the status back to the caller so run_playbook can say what
        # actually happened (succeeded / stopped / failed) instead of assuming
        # that reaching this point means success.
        result = status_str
      end
    end

    result
  end

  private

  def deep_clone(obj)
    Marshal.load(Marshal.dump(obj))
  end

  def deep_merge(base, override)
    return deep_clone(override) unless base.is_a?(Hash) && override.is_a?(Hash)
    result = deep_clone(base)
    override.each do |k, v|
      result[k] = result[k].is_a?(Hash) && v.is_a?(Hash) ? deep_merge(result[k], v) : deep_clone(v)
    end
    result
  end
end # end module Automation
