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
require 'psych'
require 'fileutils'
require 'time'
require 'cgi'
require_relative '../services/lab_repository'

module Automation
  # Box-local overrides live under /root/.ctlabs/labs/<file> and, when present,
  # shadow the repo-shipped default entirely (no merging - see design-guide.md).
  # Resolved fresh on every call (NOT cached into a constant) so the long-lived
  # webgui process picks up a box-local file dropped in after boot, same as the
  # ~/.ctlabs-server/auth override (base_controller.rb) - a frozen constant would
  # only re-check at the next process start (CLI runs are fine either way since
  # each invocation is a fresh process, but the puma server is not).
  #
  # Only node_profiles.yml still lives in the repo's labs/ dir; the automation
  # profiles (setup/role/terraform) moved to automation/<scope>/ - see below.
  def self.profile_override_path(basename)
    override = "/root/.ctlabs/labs/#{basename}"
    File.exist?(override) ? override : "/root/ctlabs/labs/#{basename}"
  end

  # Automation profile files, split by instance so the lab and the persistent
  # control-plane controller never share (or clobber) each other's config:
  #   automation/lab/  - the lab instance (Lab automation)
  #   automation/ctl/  - the controller instance (standalone ctl-ctrl)
  # Box-local overrides live under /root/.ctlabs/automation/<scope>/<file> and
  # shadow the repo default entirely.
  AUTOMATION_DIR = '/root/ctlabs/ctlabs/automation'.freeze

  def self.automation_profiles_path(scope, basename)
    override = "/root/.ctlabs/automation/#{scope}/#{basename}"
    File.exist?(override) ? override : "#{AUTOMATION_DIR}/#{scope}/#{basename}"
  end

  def self.setup_profiles_path;         automation_profiles_path('lab', 'setup_profiles.yml');     end
  def self.play_profiles_path;          automation_profiles_path('lab', 'play_profiles.yml');      end
  def self.terraform_profiles_path;     automation_profiles_path('lab', 'terraform_profiles.yml'); end
  def self.setup_profiles_ctl_path;     automation_profiles_path('ctl', 'setup_profiles.yml');     end
  def self.play_profiles_ctl_path;      automation_profiles_path('ctl', 'play_profiles.yml');      end
  def self.terraform_profiles_ctl_path; automation_profiles_path('ctl', 'terraform_profiles.yml'); end

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
  # Host-side write paths (this process runs on the host; Ruby File.write must
  # use these). The controller container bind-mounts the same repo at
  # ANSIBLE_DIR_CTL, so its artifacts need SEPARATE FILENAMES (not just a
  # different mount path) to avoid lab/controller clobbering each other.
  PLAY_SETUP_FILE    = "#{ANSIBLE_DIR}/playbooks/.play_setup_lab.json"
  PLAY_SETUP_FILE_CTL= "#{ANSIBLE_DIR}/playbooks/.play_setup_ctl.json"
  # In-container read paths: the playbook command executes inside the
  # controller container, so `-e @...` must use the mounted (_CTL) form.
  PLAY_SETUP_FILE_INNER     = "#{ANSIBLE_DIR_CTL}/playbooks/.play_setup_lab.json"
  PLAY_SETUP_FILE_CTL_INNER = "#{ANSIBLE_DIR_CTL}/playbooks/.play_setup_ctl.json"
  PLAYBOOK_FILE_CTL  = "#{ANSIBLE_DIR_CTL}/playbooks/ctlabs-ctl.yml"
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

  EXACT_VAR_REGEX    = /\A(?:\{\{|\$\{)\s*([a-zA-Z0-9_.-]+(?:\s*\|[^\}]+)?)\s*(?:\}\}|\})\z/.freeze
  EMBEDDED_VAR_REGEX = /(?:\{\{|\$\{)\s*([a-zA-Z0-9_.-]+(?:\s*\|[^\}]+)?)\s*(?:\}\}|\})/.freeze

  def self.clean_env_val(val)
    return val unless val.is_a?(String)
    val = val.strip
    if (val.start_with?('"') && val.end_with?('"')) || (val.start_with?("'") && val.end_with?("'"))
      val = val[1..-2]
    end
    if val =~ /\A-?\d+\z/
      val.to_i
    elsif val =~ /\A-?\d+\.\d+\z/
      val.to_f
    elsif val.casecmp('true').zero?
      true
    elsif val.casecmp('false').zero?
      false
    elsif val.casecmp('null').zero? || val.casecmp('nil').zero?
      nil
    else
      val
    end
  end

  def self.parse_env_vars(env_input)
    result = {}
    return result if env_input.nil?

    if env_input.is_a?(Hash)
      env_input.each { |k, v| result[k.to_s] = clean_env_val(v) }
      return result
    end

    items = if env_input.is_a?(Array)
      env_input
    elsif env_input.is_a?(String)
      env_input.split(/\r?\n/)
    else
      Array(env_input)
    end

    items.each do |item|
      next if item.nil?
      str = item.to_s.strip
      next if str.empty? || str.start_with?('#')
      if str =~ /\A([a-zA-Z0-9_.-]+)\s*[:=]\s*(.*)\z/
        k = $1.strip
        v = $2.strip
        result[k] = clean_env_val(v)
      end
    end
    result
  end

  def self.lookup_var(token, vars_map)
    return [false, nil] if vars_map.nil?
    key = token.to_s.strip
    return [true, vars_map[key]] if vars_map.key?(key)
    return [true, vars_map[key.to_sym]] if vars_map.key?(key.to_sym)

    if key.include?('.')
      parts = key.split('.')
      current = vars_map
      found = true
      parts.each do |part|
        if current.is_a?(Hash)
          if current.key?(part)
            current = current[part]
          elsif current.key?(part.to_sym)
            current = current[part.to_sym]
          else
            found = false
            break
          end
        elsif current.is_a?(Array) && part =~ /\A\d+\z/
          idx = part.to_i
          if idx >= 0 && idx < current.size
            current = current[idx]
          else
            found = false
            break
          end
        else
          found = false
          break
        end
      end
      return [true, current] if found
    end

    [false, nil]
  end

  def self.parse_filter_args(args_str)
    return [] if args_str.nil? || args_str.strip.empty?
    args = []
    tokens = args_str.scan(/(?:"(?:\\.|[^"])*"|'(?:\\.|[^'])*'|[^,]+)/).map(&:strip)
    tokens.each do |tok|
      if (tok.start_with?('"') && tok.end_with?('"')) || (tok.start_with?("'") && tok.end_with?("'"))
        args << tok[1..-2]
      elsif tok =~ /\A-?\d+\z/
        args << tok.to_i
      elsif tok =~ /\A-?\d+\.\d+\z/
        args << tok.to_f
      elsif tok.casecmp('true').zero?
        args << true
      elsif tok.casecmp('false').zero?
        args << false
      elsif tok.casecmp('null').zero? || tok.casecmp('nil').zero?
        args << nil
      else
        args << tok
      end
    end
    args
  end

  def self.apply_filter(val, filter_name, args)
    case filter_name.downcase
    when 'upper'
      val.to_s.upcase
    when 'lower'
      val.to_s.downcase
    when 'capitalize'
      val.to_s.capitalize
    when 'title'
      val.to_s.split.map(&:capitalize).join(' ')
    when 'trim', 'strip'
      val.to_s.strip
    when 'replace'
      old_s = args[0].to_s
      new_s = (args[1] || '').to_s
      val.to_s.gsub(old_s, new_s)
    when 'default', 'd'
      fallback = args[0]
      bool_override = args[1] == true
      if val.nil? || (bool_override ? !val : (val == '' || val == false))
        fallback
      else
        val
      end
    when 'int', 'integer'
      val.to_s.to_i
    when 'float'
      val.to_s.to_f
    when 'bool'
      return false if val.nil? || val == false || val == 0 || val == '0' || val.to_s.downcase == 'false'
      true
    when 'string'
      val.to_s
    when 'first'
      val.is_a?(Array) ? val.first : val.to_s[0]
    when 'last'
      val.is_a?(Array) ? val.last : val.to_s[-1]
    when 'join'
      sep = (args[0] || '').to_s
      val.is_a?(Array) ? val.join(sep) : val.to_s
    when 'split'
      sep = args[0] ? args[0].to_s : ' '
      val.to_s.split(sep)
    when 'length', 'count'
      val.respond_to?(:size) ? val.size : val.to_s.length
    when 'reverse'
      val.is_a?(Array) ? val.reverse : val.to_s.reverse
    when 'sort'
      val.is_a?(Array) ? val.sort : val
    when 'unique'
      val.is_a?(Array) ? val.uniq : val
    when 'abs'
      val.respond_to?(:abs) ? val.abs : val.to_i.abs
    when 'round'
      val.to_f.round(args[0] ? args[0].to_i : 0)
    when 'urlencode'
      CGI.escape(val.to_s)
    else
      :filter_not_supported
    end
  end

  def self.eval_expression(expr, vars_map)
    parts = expr.split('|').map(&:strip)
    var_token = parts.shift
    
    found, val = lookup_var(var_token, vars_map)

    parts.each do |f_str|
      if f_str =~ /\A([a-zA-Z0-9_]+)(?:\((.*)\))?\z/
        f_name = $1
        args = parse_filter_args($2)
        if f_name.downcase == 'default' || f_name.downcase == 'd'
          val = found ? apply_filter(val, f_name, args) : args[0]
          found = true
        elsif found
          new_val = apply_filter(val, f_name, args)
          return [false, nil] if new_val == :filter_not_supported
          val = new_val
        else
          return [false, nil]
        end
      else
        return [false, nil]
      end
    end

    return [false, nil] unless found
    [true, val]
  end

  def self.interpolate_profile_value(val, vars_map)
    case val
    when Hash
      val.each_with_object({}) do |(k, v), h|
        new_k = k.is_a?(String) ? interpolate_profile_value(k, vars_map) : k
        h[new_k] = interpolate_profile_value(v, vars_map)
      end
    when Array
      val.map { |item| interpolate_profile_value(item, vars_map) }
    when String
      if (m = val.match(EXACT_VAR_REGEX))
        found, resolved = eval_expression(m[1], vars_map)
        return resolved if found
        return val
      end

      if val =~ EMBEDDED_VAR_REGEX
        val.gsub(EMBEDDED_VAR_REGEX) do |match|
          expr = $1
          found, resolved = eval_expression(expr, vars_map)
          found ? resolved.to_s : match
        end
      else
        val
      end
    else
      val
    end
  end

  def self.resolve_nested_vars(vars_map)
    return {} unless vars_map.is_a?(Hash)
    resolved = vars_map.dup
    10.times do
      changed = false
      resolved.each do |k, v|
        new_v = interpolate_profile_value(v, resolved)
        if new_v != v
          resolved[k] = new_v
          changed = true
        end
      end
      break unless changed
    end
    resolved
  end

  def build_automation_vars(play_cfg, sp_raw = {}, pp_raw = {})
    vars = {}

    # 1. vars from play_profiles.yml
    vars.merge!(pp_raw['vars']) if pp_raw.is_a?(Hash) && pp_raw['vars'].is_a?(Hash)

    # 2. vars from setup_profiles.yml
    vars.merge!(sp_raw['vars']) if sp_raw.is_a?(Hash) && sp_raw['vars'].is_a?(Hash)

    # 3. Built-in lab facts
    server_ip = @server_ip
    server_ip ||= (Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }&.ip_address || '127.0.0.1') if defined?(Socket)
    server_ip ||= '127.0.0.1'

    lab_domain = (@cfg.is_a?(Hash) ? @cfg['domain'] : nil) || @domain || 'ctlabs.internal'
    lab_name   = @name.to_s

    vars['CTLABS_HOST']   = server_ip
    vars['ctlabs_host']   = server_ip
    vars['CTLABS_DOMAIN'] = lab_domain
    vars['ctlabs_domain'] = lab_domain
    vars['domain']        = lab_domain
    vars['lab_name']      = lab_name
    vars['LAB_NAME']      = lab_name

    nodes_info = {}
    Array(@nodes).each do |node|
      next unless node.respond_to?(:name)
      node_name = node.name.to_s
      ip        = node.respond_to?(:ipv4) && node.ipv4 ? node.ipv4.to_s.split('/').first : ''
      fqdn      = node.respond_to?(:fqdn) ? node.fqdn.to_s : ''
      ipv4_cidr = node.respond_to?(:ipv4) ? node.ipv4.to_s : ''

      vars["#{node_name}_ip"] = ip unless ip.empty?
      nodes_info[node_name] = {
        'ip'   => ip,
        'ipv4' => ipv4_cidr,
        'fqdn' => fqdn
      }
    end
    vars['nodes'] = nodes_info

    # 4. Lab YAML play.vars / play_cfg['vars']
    vars.merge!(play_cfg['vars']) if play_cfg.is_a?(Hash) && play_cfg['vars'].is_a?(Hash)

    # 5. Lab YAML play.setup.vars
    vars.merge!(play_cfg['setup']['vars']) if play_cfg.is_a?(Hash) && play_cfg.dig('setup', 'vars').is_a?(Hash)

    # 6. WebUI Environment variables / play_cfg['env']
    if play_cfg.is_a?(Hash) && play_cfg['env']
      env_vars = Automation.parse_env_vars(play_cfg['env'])
      vars.merge!(env_vars)
      if env_vars.key?('CTLABS_HOST')
        vars['ctlabs_host'] = env_vars['CTLABS_HOST']
      elsif env_vars.key?('ctlabs_host')
        vars['CTLABS_HOST'] = env_vars['ctlabs_host']
      end
      if env_vars.key?('CTLABS_DOMAIN')
        vars['ctlabs_domain'] = env_vars['CTLABS_DOMAIN']
        vars['domain']        = env_vars['CTLABS_DOMAIN']
      elsif env_vars.key?('domain')
        vars['CTLABS_DOMAIN'] = env_vars['domain']
        vars['ctlabs_domain'] = env_vars['domain']
      end
    end

    Automation.resolve_nested_vars(vars)
  end

  # Walk Psych AST to find duplicate scalar keys among siblings of any mapping.
  # Merge keys ('<<') and non-scalar keys are ignored.
  def self.find_duplicate_yaml_keys(node, prefix = [], &block)
    return unless node

    if node.is_a?(Psych::Nodes::Mapping)
      seen = {}
      node.children.each_slice(2) do |key_node, val_node|
        if key_node.is_a?(Psych::Nodes::Scalar) && key_node.value != '<<'
          key_str = key_node.value
          current_path = (prefix + [key_str]).join('.')
          if seen.key?(key_str)
            first_line = seen[key_str].start_line + 1
            dup_line   = key_node.start_line + 1
            yield(current_path, dup_line, first_line)
          else
            seen[key_str] = key_node
          end
          find_duplicate_yaml_keys(val_node, prefix + [key_str], &block)
        else
          find_duplicate_yaml_keys(val_node, prefix, &block)
        end
      end
    elsif node.is_a?(Psych::Nodes::Sequence)
      node.children.each_with_index do |child, idx|
        find_duplicate_yaml_keys(child, prefix + [idx.to_s], &block)
      end
    elsif node.is_a?(Psych::Nodes::Document) || node.is_a?(Psych::Nodes::Stream)
      node.children.each do |child|
        find_duplicate_yaml_keys(child, prefix, &block)
      end
    end
  end

  # Loads profile YAML, warns on duplicate mapping keys via log, and returns parsed Hash.
  def self.load_profiles(path, log: nil)
    return {} unless File.file?(path)

    if log.respond_to?(:write)
      log.write("load_profiles(#{path}): loaded profile mapping", "debug")
    elsif log.respond_to?(:debug)
      log.debug("load_profiles(#{path}): loaded profile mapping")
    end

    begin
      doc = Psych.parse_file(path)
      if doc
        find_duplicate_yaml_keys(doc) do |key_path, dup_line, first_line|
          msg = "load_profiles(#{path}): duplicate key \"#{key_path}\" at line #{dup_line} " \
                "(first defined at line #{first_line}); last definition wins"
          if log.respond_to?(:write)
            log.write(msg, "warn")
          elsif log.respond_to?(:warn)
            log.warn(msg)
          else
            warn(msg)
          end
        end
      end
    rescue Psych::SyntaxError => e
      msg = "load_profiles(#{path}): YAML syntax error: #{e.message}"
      if log.respond_to?(:write)
        log.write(msg, "warn")
      elsif log.respond_to?(:warn)
        log.warn(msg)
      end
    rescue => e
      msg = "load_profiles(#{path}): error checking duplicate keys: #{e.message}"
      if log.respond_to?(:write)
        log.write(msg, "warn")
      elsif log.respond_to?(:warn)
        log.warn(msg)
      end
    end

    raw = YAML.load_file(path) || {}
    raw.is_a?(Hash) ? raw : {}
  end

  def load_profiles(path)
    Automation.load_profiles(path, log: @log)
  end

  def load_automation_profiles(play_cfg)
    if @standalone
      sp_path = Automation.setup_profiles_ctl_path
      pp_path = Automation.play_profiles_ctl_path
    else
      sp_path = Automation.setup_profiles_path
      pp_path = Automation.play_profiles_path
    end
    sp_raw = load_profiles(sp_path)
    pp_raw = load_profiles(pp_path)

    sp_raw = {} unless sp_raw.is_a?(Hash)
    pp_raw = {} unless pp_raw.is_a?(Hash)

    vars_map = build_automation_vars(play_cfg, sp_raw, pp_raw)

    setup_profiles = Automation.interpolate_profile_value(sp_raw['profiles'] || {}, vars_map)
    play_profiles  = Automation.interpolate_profile_value(pp_raw['profiles'] || {}, vars_map)

    raw_setup = (play_cfg.is_a?(Hash) && play_cfg['setup'].is_a?(Hash)) ? play_cfg['setup'].reject { |k, _| k == 'vars' } : {}
    setup_cfg = Automation.interpolate_profile_value(raw_setup, vars_map)

    [setup_profiles, play_profiles, setup_cfg, vars_map]
  end

  def build_play_setup(play_cfg, base_dir: nil)
    ans_base = base_dir || (play_cfg['root_dir'].to_s.strip.empty? ? ANSIBLE_DIR : play_cfg['root_dir'].to_s.strip)
    out_file = @standalone ? "#{ans_base}/playbooks/.play_setup_ctl.json" : "#{ans_base}/playbooks/.play_setup_lab.json"
    setup_profiles, play_profiles, setup_cfg, _ = load_automation_profiles(play_cfg)

    play_tags     = Array(play_cfg['tags'] || []).map(&:to_s)
    result        = {}
    activated_by  = {}

    # process explicit play.setup entries (profile + per-host overrides)
    setup_cfg.each do |role, cfg|
      cfg        = cfg || {}
      named_prof = cfg['profile'] && setup_profiles[cfg['profile']]
      base_prof  = named_prof || setup_profiles[role]
      base       = base_prof ? Marshal.load(Marshal.dump(base_prof)) : {}
      base.delete('role')

      result[role] = deep_merge(base, cfg.reject { |k, _| k == 'profile' })
    end

    # for roles in play.tags but not play.setup, load setup_profile defaults.
    # Activation and fact selection are two separate lookups:
    #   1. ACTIVATION: any of the play profile's tags (its own name is appended
    #      last) present in play.tags — this is how one shared alias tag like
    #      `rke2` activates rke2-server AND rke2-control AND rke2-worker.
    #   2. FACTS: first tag that is BOTH in play.tags AND a setup_profiles key
    #      (explicit tags win — e.g. lab tag `rke2` -> setup_profile `rke2`),
    #      else the play profile's OWN NAME if setup_profiles has it
    #      (rke2-server -> setup_profile rke2-server). So with only per-role
    #      setup profiles, play.tags `[rke2]` is enough: the shared tag runs
    #      the profiles, each one loads the facts named after itself.
    play_profiles.each do |profile_name, profile_cfg|
      next if result.key?(profile_name)
      role_tags = (Array(profile_cfg['tags'] || []).map(&:to_s) + [profile_name.to_s]).uniq
      next unless (role_tags & play_tags).any?
      sp_key = role_tags.find { |t| play_tags.include?(t) && setup_profiles.key?(t) }
      sp_key ||= profile_name.to_s if setup_profiles.key?(profile_name.to_s)
      next unless sp_key
      base = Marshal.load(Marshal.dump(setup_profiles[sp_key]))
      base.delete('role')
      result[profile_name] = base
      activated_by[profile_name] = sp_key
    end

    # Facts are authoritative: one fact file per host+role. If the play tags
    # activate multiple profiles writing facts for the same host+role, the
    # last facts play in play_profiles.yml order wins — warn so an overlap is
    # never silently order-dependent. A profile writes facts for its own
    # `hosts:` entries only (baked setup data may carry sibling hosts), and
    # only for roles that ship tasks/facts.yml.
    node_names = (@nodes || []).map(&:name).to_set
    writers = Hash.new { |h, k| h[k] = [] }
    result.each_key do |profile_name|
      profile_cfg = play_profiles[profile_name]
      next unless profile_cfg && profile_cfg['role']
      role = profile_cfg['role'].to_s
      next if role.empty?
      next unless File.file?("#{ans_base}/roles/#{role}/tasks/facts.yml")
      Array(profile_cfg['hosts']).uniq.each do |host|
        next unless node_names.include?(host)
        writers[[host, role]] << "#{profile_name} [setup: #{activated_by[profile_name]}]"
      end
    end
    writers.each do |(host, role), from|
      next unless from.size > 1
      @log.write "#{__method__}(): FACTS CLASH: #{host} (#{role}) gets facts from " \
                 "#{from.join(', ')} — last one in play_profiles.yml order wins; " \
                 "activate one profile per host+role via play.tags", "warn"
    end

    # Bake `defaults:` into each per-host entry so that
    # play_setup[role][hostname] always contains the full config.
    # Per-host keys are node names; role-wide defaults live under `defaults:`.
    # Per-host `profile:` overrides the base profile for that host.
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

    File.write(out_file, JSON.pretty_generate({ 'play_setup' => result }))
    @log.write "#{__method__}(): wrote #{out_file}", "debug"
    result
  end

  # Seed for a setup playbook's .tpl when it doesn't exist yet — the phase 3
  # header we've always generated. Edit the seeded file to change what a
  # scope's setup run touches (e.g. drop `all:!rhosts` for the controller).
  PLAY_SETUP_TPL_SEED = <<~TPL.freeze
    ---

    # ------------------------------------------------------------------------------
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

    {{PLAYS}}
  TPL

  # The line in a .tpl that the generated plays are written into. Anchored so
  # that Jinja like "{{ ctg_facts_dir }}" or a comment mentioning the
  # placeholder is never mistaken for it.
  PLACEHOLDER_RE = /^[ \t]*\{\{PLAYS\}\}[ \t]*$/.freeze

  def generate_setup_yml(play_cfg, base_dir: nil)
    ans_base = base_dir || (play_cfg['root_dir'].to_s.strip.empty? ? ANSIBLE_DIR : play_cfg['root_dir'].to_s.strip)
    out_path = @standalone ? "#{ans_base}/playbooks/setup_ctl.yml" : "#{ans_base}/playbooks/setup.yml"
    _, profiles, setup_cfg, _ = load_automation_profiles(play_cfg)

    existing  = (@nodes || []).map(&:name)
    play_tags = Array(play_cfg['tags'] || []).map(&:to_s)

    plays = profiles.map do |profile_name, cfg|
      next unless cfg['role']
      next unless File.file?("#{ans_base}/roles/#{cfg['role']}/tasks/facts.yml")

      role_tags = (Array(cfg['tags'] || []).map(&:to_s) + [profile_name.to_s]).uniq
      next unless (role_tags & play_tags).any?

      role_setup  = setup_cfg[profile_name]
      setup_hosts = role_setup && role_setup['hosts']
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

    # Same mechanism as the phase-4 playbook: the .tpl beside the output holds
    # everything static — header and the facts_dir play, including which hosts
    # it targets. We only replace the placeholder line with the generated
    # per-profile facts plays.
    tpl_path = "#{out_path}.tpl"
    File.write(tpl_path, PLAY_SETUP_TPL_SEED) unless File.file?(tpl_path)
    tpl  = File.read(tpl_path)
    body = tpl.match?(PLACEHOLDER_RE) ?
      tpl.sub(PLACEHOLDER_RE) { plays.join } :
      "#{tpl.rstrip}\n\n#{plays.join}"

    File.write(out_path, body)
    @log.write "#{__method__}(): wrote #{out_path} (template: #{tpl_path})", "debug"
  end

  # Seed for a playbook's .tpl when it doesn't exist yet — the template we've
  # always generated from. Once written it is yours to edit; that file (not
  # this code) decides what a run imports.
  PLAYBOOK_TPL_SEED = <<~TPL.freeze
    ---

    # ------------------------------------------------------------------------------
    # Description : ctlabs phase 4 - run roles (generated by lab.rb)
    # ------------------------------------------------------------------------------

    - import_playbook: up.yml
    - import_playbook: setup.yml

    {{PLAYS}}
  TPL

  def generate_ctlabs_yml(play_cfg, base_dir: nil)
    ans_base = base_dir || (play_cfg['root_dir'].to_s.strip.empty? ? ANSIBLE_DIR : play_cfg['root_dir'].to_s.strip)
    out_dir = "#{ans_base}/playbooks"
    _, profiles, setup_cfg, _ = load_automation_profiles(play_cfg)

    existing  = (@nodes || []).map(&:name)
    play_tags = Array(play_cfg['tags'] || []).map(&:to_s)

    book = play_cfg['book'] || (@standalone ? 'ctlabs-ctl.yml' : 'ctlabs.yml')
    out_path = "#{out_dir}/#{book}"
    tpl_path = "#{out_path}.tpl"

    plays = profiles.flat_map do |profile_name, cfg|
      next [] unless cfg['role']
      role_tags = (Array(cfg['tags'] || []).map(&:to_s) + [profile_name.to_s]).uniq
      next [] unless (role_tags & play_tags).any?

      role_setup  = setup_cfg[profile_name]
      setup_hosts = role_setup && role_setup['hosts']

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
    end.compact

    # The template beside the playbook is the single source of truth for
    # everything static: header, which playbooks get imported (up.yml /
    # setup*.yml), fixed plays. All that's left here is replacing the
    # placeholder line with the generated role plays.
    File.write(tpl_path, PLAYBOOK_TPL_SEED) unless File.file?(tpl_path)
    tpl       = File.read(tpl_path)
    body = tpl.match?(PLACEHOLDER_RE) ?
      tpl.sub(PLACEHOLDER_RE) { plays.join } :
      "#{tpl.rstrip}\n\n#{plays.join}"

    File.write(out_path, body)
    @log.write "#{__method__}(): wrote #{out_path} (template: #{tpl_path})", "debug"
  end

  def run_playbook(play = nil, log_file_path = nil)
    @log.write "#{__method__}(): play=#{play.inspect}, log_file_path=#{log_file_path}", "debug"

    # VALIDATION: Lab must be running. The persistent controller is its own
    # standalone "lab" (no global lab lock), so skip the lock check there.
    unless @standalone || (self.class.running? && self.class.current_name == @relative_path)
      raise "Cannot run playbook: Lab '#{@relative_path}' is not running. Start it first with --up"
    end

    # ACQUIRE PLAYBOOK LOCK (prevents concurrent execution)
    playbook_lock = nil
    begin
      playbook_lock = Automation.acquire_playbook_lock!(@relative_path)

      # A workload lab runs on its in-lab `ansible` node; the standalone
      # controller topology (ctl-ctrl) has no `ansible` node, so fall back to
      # the controller node itself.
      ctrl = find_node('ansible') || @nodes.find { |n| n.type.to_s == 'controller' }
      raise "No 'ansible' controller node found in topology" if ctrl.nil?

      play_cfg = ctrl.play.is_a?(Hash) ? ctrl.play : {}

      ans_base_host = play_cfg['root_dir'].to_s.strip.empty? ? ANSIBLE_DIR : play_cfg['root_dir'].to_s.strip
      ans_base_ctl  = play_cfg['root_dir_ctl'] || (ans_base_host.start_with?('/srv/ctlabs/') ? ans_base_host : ans_base_host.sub(%r{\A/root/}, '/srv/ctlabs/'))

      # generate ansible artifacts from lab topology + profiles
      build_play_setup(play_cfg, base_dir: ans_base_host)
      generate_setup_yml(play_cfg, base_dir: ans_base_host)
      generate_ctlabs_yml(play_cfg, base_dir: ans_base_host)

      vars_map = build_automation_vars(play_cfg)
      domain   = vars_map['CTLABS_DOMAIN'] || (@cfg['domain'] || @domain)
      host_ip  = vars_map['CTLABS_HOST'] || @server_ip

      # Determine playbook command
      if play.is_a?(String) && !play.strip.empty?
        play_cmd = play.strip + " -e CTLABS_DOMAIN=#{domain} -e CTLABS_HOST=#{host_ip}"
      elsif ctrl.play.is_a?(String) && !ctrl.play.strip.empty?
        play_cmd = ctrl.play.strip + " -e CTLABS_DOMAIN=#{domain} -e CTLABS_HOST=#{host_ip}"
      elsif play_cfg['book'].is_a?(String)
        if @standalone
          inv_file = play_cfg['inv'] || 'controller.ini'
          play_book_path = "./playbooks/#{play_cfg['book'] || 'ctlabs-ctl.yml'}"
        else
          inv_file  = play_cfg['inv'] || "#{@name}.ini"
          play_book_path = " ./playbooks/#{play_cfg['book']}"
        end
        # Always use a .ini inventory filename so -i ./inventories/<inv> resolves.
        inv_file += '.ini' if inv_file && !inv_file.include?('/') && !inv_file.end_with?('.ini')
        play_inv  = " -i ./inventories/#{inv_file}"
        play_env  = " -e CTLABS_DOMAIN=#{domain} -e CTLABS_HOST=#{host_ip}"
        inner_setup_file = @standalone ? "#{ans_base_ctl}/playbooks/.play_setup_ctl.json" : "#{ans_base_ctl}/playbooks/.play_setup_lab.json"
        play_env += " -e @#{inner_setup_file}"
        play_env += " #{(play_cfg['env'] || []).map { |e| " -e #{e}" }.join}"
        play_book = " #{play_book_path}"
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
      status = stream_docker_exec(controller_exec_name, play_cmd, log_file_path,
                                  pid_file: log_file_path ? Automation.playbook_run_state_path(@relative_path) : nil,
                                  ansible_dir_ctl: ans_base_ctl)

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

    # The node's own parsed config covers both schemas (top-level `nodes` for a
    # lab, `planes.<p>.nodes` for the standalone controller); fall back to the
    # raw top-level lookup for older lab YAMLs.
    tf_cfg = ctrl.respond_to?(:terraform) && ctrl.terraform.is_a?(Hash) ? ctrl.terraform : {}
    if tf_cfg.empty?
      node_cfg = ((@cfg['topology'][0]['nodes'] || {})[ctrl.name]) || {}
      tf_cfg   = node_cfg['terraform'] || {}
    end

    workspace = tf_cfg['workspace'].to_s.strip
    workspace = 'default' if workspace.empty?
    
    vars      = tf_cfg['vars'] || []
    var_args  = vars.map { |v| "-var '#{v}'" }.join(" ")

    tf_base_host = tf_cfg['root_dir'].to_s.strip.empty? ? TF_DIR : tf_cfg['root_dir'].to_s.strip
    tf_base_ctl  = tf_cfg['root_dir_ctl'] || (tf_base_host.start_with?('/srv/ctlabs/') ? tf_base_host : tf_base_host.sub(%r{\A/root/}, '/srv/ctlabs/'))

    tf_work_dir = tf_cfg['work_dir'] && !tf_cfg['work_dir'].empty? ? tf_cfg['work_dir'] : '.'
    work_dir = "#{tf_base_ctl}/#{tf_work_dir}"
    
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
      gcp_env = GcpAuth.env_vars(tf_cfg, { addr: web_v_addr, token: web_v_token },
                                 scope: (@standalone ? 'ctl' : 'lab'),
                                 repo_dir_ctl: tf_base_ctl)
      gcp_env.each { |key, value| exec_env += "-e #{key}='#{value}' " }
    rescue => e
      error_msg = "\n❌ ERROR: Could not generate GCP credentials: #{e.message}\n👉 Please use the Vault Login button in the UI.\n"
      File.open(log_path, 'a') { |f| f.puts error_msg } if log_path
      raise e
    end

    # No more Python wrappers! Just pure Terraform.
    tf_command = base_tf_cmd

    engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'

    # Cloud/terraform runs on the persistent controller (ctl-ctrl) when it is
    # up -- it holds the persistent terraform state/workspace and reaches the
    # cloud without a lab. Otherwise it runs on the lab's own in-lab controller.
    exec_ctrl = (ctrl.type.to_s == 'controller' && persistent_controller_up?) ? Controller::NAME : ctrl.name

    full_cmd = "#{engine} exec #{exec_env}#{exec_ctrl} bash -c '#{tf_command.gsub("'", "'\\''")}'"

    @log.info "Executing Terraform on #{exec_ctrl}: #{tf_command}" 

    # 4. Stream the output
    if log_path
      File.open(log_path, 'a') do |f|
        f.puts "\n" + "="*50
        f.puts "🚀 TERRAFORM EXECUTION STARTED"
        f.puts "="*50
        f.puts "Target Node : #{exec_ctrl}"
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
          host_work_dir = "#{tf_base_host}/#{tf_work_dir}"
          state_file = workspace == 'default' ? "#{host_work_dir}/terraform.tfstate" : "#{host_work_dir}/terraform.tfstate.d/#{workspace}/terraform.tfstate"

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
  def stream_docker_exec(container_name, play_cmd, log_file_path = nil, pid_file: nil, ansible_dir_ctl: nil, terraform_dir_ctl: nil)
    # Export the repo dirs the ctlabs-ansible group_vars expect
    # (inventories/group_vars/all/ctlabs.yml: ctg_ansible_repo_dir et al. resolve
    # from these env vars). They must be exported, not left to the group_vars
    # fallback: lookup('env', X) returns '' (not undefined) when unset, so the
    # `| default(path)` there never applies and the var becomes empty - a role
    # writing to "{{ ctg_ansible_repo_dir }}/..." (e.g. the ctlabs_vault init
    # output) then lands in the container's ephemeral "/" and is lost on the next
    # controller recreate, breaking vault unseal. The mounted paths below are the
    # same ones ANSIBLE_DIR_CTL/TF_DIR_CTL already assume.
    ans_ctl = ansible_dir_ctl || ANSIBLE_DIR_CTL
    tf_ctl  = terraform_dir_ctl || TF_DIR_CTL
    repo_env = "CTLABS_ANSIBLE_REPO_DIR=#{ans_ctl} " \
               "CTLABS_TERRAFORM_REPO_DIR=#{tf_ctl} " \
               "CTLABS_TOOLS_REPO_DIR=/srv/ctlabs/ctlabs-tools"
    inner_command = "cd #{ans_ctl} && #{repo_env} ANSIBLE_FORCE_COLOR=1 #{play_cmd} 2>&1"
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

  # Hash merge where lists UNITE instead of replace: base (defaults) items
  # first, then override (per-host) additions, deduplicated. A per-host
  # entry therefore ADDS to a defaults list, never silently overrides it —
  # change a default for everyone in the defaults; repeating a default item
  # per-host is deduplicated, not doubled. (YAML anchors can't do this: the
  # `<<` merge key works on maps only, and list anchors would still require
  # enumerating the shared items per host.)
  def deep_merge(base, override)
    return deep_clone(override) unless base.is_a?(Hash) && override.is_a?(Hash)
    result = deep_clone(base)
    override.each do |k, v|
      if result[k].is_a?(Hash) && v.is_a?(Hash)
        result[k] = deep_merge(result[k], v)
      elsif result[k].is_a?(Array) && v.is_a?(Array)
        result[k] = (result[k] + v).uniq
      else
        result[k] = deep_clone(v)
      end
    end
    result
  end
end # end module Automation
