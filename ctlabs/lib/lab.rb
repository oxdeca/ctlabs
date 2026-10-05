# -----------------------------------------------------------------------------
# File        : ctlabs/lib/lab.rb
# Description : lab class; reads in config and manages lab
# License     : MIT License
# -----------------------------------------------------------------------------

# open3 + set moved to lib/automation.rb (stream_docker_exec / build_play_setup).
require 'shellwords'
require 'yaml'
require 'json'
require 'socket'
require 'fileutils'
require_relative '../services/lab_repository'
require_relative 'automation'

class Lab
  # Ansible + Terraform live in lib/automation.rb; mixed in here so Lab keeps
  # lab.run_playbook / lab.run_terraform. See that module's header for what
  # stays Lab's job (up, add_adhoc_node, metadata) vs. automation's.
  include Automation

  attr_writer :dotfile, :dtype, :diagram
  attr_reader :name, :desc, :nodes, :links, :defaults, :topology, :cfg_file, :relative_path
  attr_accessor :log

  LAB_OPERATION_LOCK = '/var/run/ctlabs/lab_operation.lock'
  LOCK_FILE          = '/var/run/ctlabs/running_lab'.freeze

  # node_profiles.yml is node/container profile data, not ansible fact data, so
  # this one stays here - but it shares Automation's box-local override mechanism.
  def self.global_profiles_path; Automation.profile_override_path('node_profiles.yml'); end

  #def initialize(cfg, vm_name=nil, dlevel="warn")
  def initialize(args={})
    cfg           = args[:cfg]
    vm_name       = args[:vm_name]
    dlevel        = args[:dlevel]
    relative_path = args[:relative_path]

    @cfg_file      = cfg
    @relative_path = relative_path || File.basename(cfg)
    @log           = args[:log]    || LabLog.null
    @pubdir        = "/srv/ctlabs-server/public"

    @log.write "== Lab ==", "debug"

    unless File.directory?(@pubdir)
      FileUtils.mkdir_p(@pubdir)
    end

    # --- 1. Calculate Server IP Early ---
    @server_ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }&.ip_address || '127.0.0.1'

    # --- 2. Read, Expand, and Distribute Config ---
    if( File.file?(cfg) )
      raw_yaml = File.read(cfg)
      
      # DYNAMIC VARIABLE EXPANSION
      # Replaces ${ctlabs_host} with the actual IP address
      expanded_yaml = raw_yaml.gsub('${ctlabs_host}', @server_ip)
      
      # Write the EXPANDED config to the public dir so the frontend UI gets the real IPs
      File.open("#{@pubdir}/config.yml", 'w') do |f|
        f.write(expanded_yaml)
      end

      # Process the EXPANDED config into the backend memory
      @cfg = YAML.load(expanded_yaml)
    else
      @cfg = {}
    end

    @log.write "#{__method__}(): file=#{cfg},cfg=#{@cfg},relative_path=#{@relative_path},vm=#{vm_name}", "debug"

    @vm_name    = vm_name
    @name       = @cfg['name']      || ''
    @ephemeral  = @cfg['ephemeral'] || true
    @desc       = @cfg['desc']      || ''

    global_profiles_path = Lab.global_profiles_path
    global_data = File.file?(global_profiles_path) ? YAML.load_file(global_profiles_path) : {}
    global_profiles = global_data['profiles'] || global_data['defaults'] || {}

    local_profiles  = @cfg['profiles'] || @cfg['defaults'] || {}

    # Merge them! Local lab overrides take precedence over global settings.
    @defaults   = merge_profiles(global_profiles, local_profiles)

    @topology   = @cfg['topology']  || {}
    @dns        = @cfg['dns']       || []
    @domain     = @cfg['domain']    || "ctlabs.internal"
    @mgmt       = @cfg['mgmt']      || {}
    @dnatgw     = {}

    # hack, before we start the nodes make sure ip_forwarding is enabled
    %x( echo 1 > /proc/sys/net/ipv4/ip_forward )
    # another hack, elastic search needs more virtual memory areas to start
    %( echo 262144 > /proc/sys/vm/max_map_count )
    
    @nodes  = init_nodes(vm_name)
    @links  = init_links(vm_name)
    @links += init_mgmt_links(vm_name)
  end

  def self.running?
    File.file?(LOCK_FILE)
  end

  def self.current_name
    File.read(LOCK_FILE).strip if running?
  rescue
    nil
  end

  # Returns the currently running Lab instance
  def self.current
    name = current_name
    name ? find(name) : nil
  end

  # Returns an array of all available lab names (relative paths)
  def self.all
    labs_dir = defined?(::LABS_DIR) ? ::LABS_DIR : File.expand_path('../../labs', __FILE__)
    Dir.glob(File.join(labs_dir, "**", "*.yml"))
       .reject { |f| File.basename(f) =~ %r{^.*_profiles.yml$} }
       .map { |f| f.sub(labs_dir + '/', '') }
       .sort
  end

  # Finds and returns a Lab instance by its relative name (e.g., 'db/db01.yml')
  # Automatically handles loading from the runtime copy if the lab is currently running.
  def self.find(name)
    path = get_file_path(name)
    return nil unless File.file?(path)
    new(cfg: path, relative_path: name)
  end

  # Canonical runtime-copy path for a lab.
  # Dedicated `runtime/` folder under the lock dir + a single `.yml` ending,
  # so the filename alone makes it obvious this is a temporary runtime copy.
  # Single source of truth shared by CLI (ctlabs.rb), webgui start (labs_controller)
  # and the runtime resolver (get_file_path) — writers MUST use this helper.
  def self.get_runtime_path(lab_name)
    lock_dir = defined?(::LOCK_DIR) ? ::LOCK_DIR : '/var/run/ctlabs'
    base     = lab_name.to_s.sub(/\.yml$/, '').gsub('/', '_')
    File.join(lock_dir, 'runtime', "#{base}.yml")
  end

  # THE single runtime-copy writer. Both the CLI (ctlabs.rb) and the webgui
  # (labs_controller) MUST create runtime copies through this: it owns mkdir_p
  # + cp so the runtime/ folder can never silently not-exist for one tier again
  # (the exact ENOENT on /var/run/ctlabs/runtime/k3s_k3s01.yml we just fixed).
  def self.create_runtime_copy(lab_name, source_path)
    runtime_path = get_runtime_path(lab_name)
    FileUtils.mkdir_p(File.dirname(runtime_path))
    FileUtils.cp(source_path, runtime_path)
    runtime_path
  end

  # Safely resolves the lab file path (Runtime vs Base) - Moved from LabHelper
  def self.get_file_path(lab_name)
    labs_dir     = defined?(::LABS_DIR) ? ::LABS_DIR : File.expand_path('../../labs', __FILE__)
    runtime_path = get_runtime_path(lab_name)
    (running? && current_name == lab_name && File.file?(runtime_path)) ? runtime_path : File.join(labs_dir, lab_name)
  end

  def self.acquire_lock!(name)
    raise ArgumentError, "Lab name must be relative path like 'dir/lab.yml'" unless name =~ %r{^[^/]+/[^/]+\.yml$}
    raise "A lab is already running: #{current_name}" if running?
    FileUtils.mkdir_p(File.dirname(LOCK_FILE))
    File.write(LOCK_FILE, name)
  end

  def self.release_lock!
    File.delete(LOCK_FILE) if File.file?(LOCK_FILE)
  end

  # ---------------------------------------------------------------------------
  # Helper: Find node in raw YAML (supports v1 and v2) - Moved from LabHelper
  # ---------------------------------------------------------------------------
  def self.find_node_in_raw_yaml(vm_cfg, node_name)
    if vm_cfg['nodes'] && vm_cfg['nodes'][node_name]
      return vm_cfg['nodes'][node_name], nil
    elsif vm_cfg['planes']
      vm_cfg['planes'].each do |p_name, p_data|
        if p_data && p_data['nodes'] && p_data['nodes'][node_name]
          return p_data['nodes'][node_name], p_name
        end
      end
    end
    [nil, nil]
  end

  def find_vm(name)
    @log.write "#{__method__}(): vm=#{name}", "debug"

    vm = nil
    @cfg['topology'].each_with_index do |v, i|
      if( v['hv'] == name )
        vm = @cfg['topology'][i]
        break
      end
    end
    if( vm.nil? )
      vm = @cfg['topology'][0]
    end

    # --- SCHEMA NORMALIZER (in-memory only) ---
    # Flattens 'planes' into a single 'nodes' hash and hoists 'planes.mgmt' up
    # to vm['mgmt'] so node/link lookup code can stay plane-agnostic.
    # On disk every lab is 'hv' + 'planes'; this never writes a flat schema.
    if vm && vm['planes'] && vm['nodes'].nil?
      flat_nodes = {}
      
      vm['planes'].each do |plane_name, plane_data|
        next unless plane_data && plane_data['nodes']
        
        # Hoist Management Network Settings to the root VM level
        if plane_name == 'mgmt'
          vm['mgmt'] ||= {}
          ['net', 'gw', 'dns', 'vrfid'].each do |k|
            vm['mgmt'][k] = plane_data[k] if plane_data.key?(k)
          end
        end

        # Flatten Nodes and Tag their Plane & Profile
        plane_data['nodes'].each do |n_name, n_cfg|
          n_cfg['plane'] = plane_name
          n_cfg['kind']  = n_cfg['profile'] if n_cfg['profile'] # Alias profile -> kind
          flat_nodes[n_name] = n_cfg
        end
      end
      
      vm['nodes'] = flat_nodes
    end

    vm
  end

  def find_node(name)
    @nodes.find { |n| n.name == name }
  end

  # Returns detailed metadata about a lab for the UI (Moved from ApplicationHelper)
  def self.metadata(yaml_file_path, adhoc_rules_by_lab = {})
    labs_dir = defined?(::LABS_DIR) ? ::LABS_DIR : File.expand_path('../../labs', __FILE__)
    lock_dir = defined?(::LOCK_DIR) ? ::LOCK_DIR : '/var/run/ctlabs'

    lab_name = yaml_file_path.sub(labs_dir + '/', '')
    refresh_visuals(lab_name)
    
    is_running = running? && current_name == lab_name
    actual_path = get_file_path(lab_name)

    # Load runtime lab and base lab to compute the diff
    lab = Lab.new(cfg: actual_path, log: LabLog.null)
    base_lab = is_running ? Lab.new(cfg: yaml_file_path, log: LabLog.null) : lab

    # Map base nodes and base DNATs for comparison
    base_nodes_list = base_lab.nodes.map(&:name)
    base_dnats = {}
    base_lab.nodes.each { |n| base_dnats[n.name] = n.dnat || [] }

    info = { lab_name: File.basename(yaml_file_path, '.yml'), lab_path: lab_name, desc: lab.desc || '' }

    # --- BULLETPROOF LINKS PARSER ---
    raw_links = []
    if base_lab.topology.is_a?(Array) && base_lab.topology.first.is_a?(Hash)
      raw_links = base_lab.topology.first['links'] || []
    elsif base_lab.topology.is_a?(Hash)
      raw_links = base_lab.topology['links'] || []
    end

    info[:links] = raw_links.map do |l|
      if l.is_a?(Array) && l.size == 2
         n_a, i_a = l[0].split(':', 2)
         n_b, i_b = l[1].split(':', 2)
         { node_a: n_a, int_a: i_a, node_b: n_b, int_b: i_b, ep1: l[0], ep2: l[1] }
      else
         nil
      end
    end.compact
    # --------------------------------

    # Images Map
    images = []
    images_map = {}
    if lab.defaults
      lab.defaults.each do |tk, tv|
        if tv.is_a?(Hash)
          images_map[tk] = tv.keys
          tv.each do |kk, kv|
            if kv
              # Grab any keys that aren't the standard three
              core_keys = ['image', 'caps', 'env']
              extras = kv.reject { |k, _| core_keys.include?(k) }
              extras_yaml = extras.empty? ? "" : extras.to_yaml.sub("---\n", "").strip

              images << {
                type: tk, 
                kind: kk, 
                image: kv['image'] || 'N/A',
                provider: kv['provider'] || 'local',
                caps: kv['caps'] || [],
                env: kv['env'] || [],
                extras: extras_yaml
              }
            end
          end
        else
          images_map[tk] = []
        end
      end
    end
    info[:images] = images
    info[:images_map] = images_map

    # Let the Node class figure out who is running!
    Node.bulk_update_status(lab.nodes) if is_running

    # Nodes (With Diffing)
    nodes = []
    if lab.nodes
      lab.nodes.each do |node|
        image_ref = 'N/A'
        if lab.defaults && lab.defaults[node.type] && lab.defaults[node.type][node.kind || 'linux']
          image_ref = lab.defaults[node.type][node.kind || 'linux']['image'] || 'N/A'
        end
          
        is_adhoc = !base_nodes_list.include?(node.name)

        node_info = {
          name: node.name,
          type: node.type   || 'N/A',
          kind: node.kind   || 'N/A',
          provider: node.provider || 'local',
          image: image_ref,
          cpus: 'N/A',
          memory: 'N/A',
          adhoc: is_adhoc,
          running: node.is_running 
        }
        nodes << node_info
      end
    end

    info[:nodes] = nodes
    info[:switches] = lab.nodes.select { |n| n.type == 'switch' }.map(&:name)
    info[:gateways] = lab.nodes.map { |n| n.gw }.compact.reject { |g| g.to_s.strip.empty? }.uniq

    # Ansible
    ansible_info = { playbook: 'N/A', inventory: 'N/A', environment: [], tags: [], roles: [] }
    ctrl = lab.find_node("ansible")
    if ctrl && !ctrl.play.nil?
      if ctrl.play.is_a?(Hash)
        # Calculate Default Inventory Name (e.g. net01.ini) if not explicitly set
        default_inv = "#{File.basename(yaml_file_path, '.yml')}.ini"
        ansible_info[:inventory]   = ctrl.play['inv'] && !ctrl.play['inv'].empty? ? ctrl.play['inv'] : default_inv
        
        ansible_info[:playbook]    = ctrl.play['book']  || 'N/A'
        ansible_info[:environment] = ctrl.play['env']   || []
        ansible_info[:tags]        = ctrl.play['tags']  || []
        ansible_info[:roles]       = ctrl.play['roles'] || ctrl.play['tags'] || []
      else
        ansible_info[:playbook]    = ctrl.play.to_s
        ansible_info[:inventory]   = "#{File.basename(yaml_file_path, '.yml')}.ini"
      end
    end
    info[:ansible] = ansible_info


    # Terraform
    terraform_info = { workspace: 'default', work_dir: 'N/A', vars: [] }
    ctrl = lab.find_node("ansible")
    
    if ctrl && ctrl.respond_to?(:terraform) && !ctrl.terraform.nil?
      terraform_info[:workspace] = ctrl.terraform['workspace'] || 'default'
      terraform_info[:work_dir]  = ctrl.terraform['work_dir']  || 'N/A'
      terraform_info[:vars]      = ctrl.terraform['vars']      || []
    end
    info[:terraform] = terraform_info


    # DNAT (With Diffing)
    vip  = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).rstrip
    exposed_ports = []
    if lab.nodes
      lab.nodes.each do |node|
        if (defined? node.dnat) && !node.dnat.nil? && node.dnat.is_a?(Array) && ['host', 'controller', 'router', 'server', 'gateway'].include?(node.type.to_s.downcase)
          node.dnat.each do |p|

            # Check if this exact rule exists in the base YAML
            base_rule_exists = base_dnats[node.name] && base_dnats[node.name].is_a?(Array) && base_dnats[node.name].any? { |bp| p[0].to_s == bp[0].to_s && p[1].to_s == bp[1].to_s && (p[2] || 'tcp').to_s == (bp[2] || 'tcp').to_s }
            is_adhoc_dnat = !base_rule_exists

            # Smart IP fallback mapping
            rip = ""
            if node.type == 'controller'
              rip = node.nics['eth0']&.split('/')&.first
            else
              # Try eth1 (data), fallback to eth0 (mgmt/edge), fallback to tun0 (vpn)
              rip = node.nics['eth1']&.split('/')&.first || node.nics['eth0']&.split('/')&.first || node.nics['tun0']&.split('/')&.first
            end

            node_info = {
              node: node.name,
              type: node.type,
              proto: p[2] || 'tcp',
              external_port: "#{vip}:#{p[0]}",
              internal_port: "#{rip || 'N/A'}:#{p[1]}",
              adhoc: is_adhoc_dnat,
              raw_ext: p[0],   
              raw_int: p[1]    
            }
            exposed_ports << node_info
          end
        end
      end
    end

    info[:exposed_ports] = exposed_ports
    return info
  rescue => e
    { error: "Error processing lab info: #{e.message}" }
  end

  # Helper to automatically regenerate Topology Maps and Inventories ONLY if needed
  def self.refresh_visuals(lab_name, force: false)
    begin
      labs_dir = defined?(::LABS_DIR) ? ::LABS_DIR : File.expand_path('../../labs', __FILE__)
      actual_path = get_file_path(lab_name)
      base_path = File.join(labs_dir, lab_name)

      # SMART CACHE CHECK
      pubdir = '/srv/ctlabs-server/public'
      topo_file = File.join(pubdir, 'topo.png')
      tracker_file = File.join(pubdir, '.topo_tracker')
      
      needs_rebuild = force
      
      if !needs_rebuild
        # 1. Did we choose a different lab from the dropdown?
        last_drawn_lab = File.exist?(tracker_file) ? File.read(tracker_file).strip : ""
        if last_drawn_lab != lab_name
          needs_rebuild = true
          
        # 2. Was the YAML edited (via UI or CLI) since we last drew the map?
        elsif File.exist?(topo_file) && File.exist?(actual_path)
          needs_rebuild = true if File.mtime(actual_path) > File.mtime(topo_file)
          
        # 3. Are the images missing entirely?
        else
          needs_rebuild = true
        end
      end

      # Skip heavy processing if nothing changed!
      return unless needs_rebuild

      # Generate visuals
      lab = Lab.new(cfg: actual_path, log: LabLog.null)
      lab.visualize
      lab.inventory
      
      # Update the tracker file with the currently drawn lab
      File.write(tracker_file, lab_name)
      
    rescue => e
      puts "[Warning] Failed to generate visuals for #{lab_name}: #{e.message}"
    end
  end

  # ---------------------------------------------------------------------------
  # Helper: Check if a profile is used by any node - Moved from LabHelper
  # ---------------------------------------------------------------------------
  def self.profile_in_use?(yaml, target_type, target_profile)
    vm = yaml['topology']&.first || {}
    
    # Gather all nodes across all planes
    nodes_to_scan = vm['planes'].values.map { |p| p['nodes'] }
    
    nodes_to_scan.compact.each do |node_group|
      node_group.values.each do |n|
        node_type = n['type'] || 'host'
        node_prof = n['profile'] || n['kind'] || 'linux'
        
        # If we find a match, it is in use!
        if node_type.to_s == target_type.to_s && node_prof.to_s == target_profile.to_s
          return true
        end
      end
    end
    false
  end

  def init_nodes(vm_name)
    @log.write "#{__method__}(): vm=#{vm_name}", "debug"

    nodes = []
    cfg    = find_vm(vm_name)
    dns    = cfg['dns']    || @dns
    domain = cfg['domain'] || @domain
    mgmt   = cfg['mgmt']   || cfg['planes']['mgmt'] || @mgmt
    net    = mgmt['net']   || "192.168.99.0/24"

    # 
    tmp  = net.split('/')
    mask = tmp[1]
    net  = tmp[0].split('.')[0..2].join('.') + '.' 

    # start range for mgmt-ip's
    cnt = 20

    cfg['nodes'].each_key do |n|
      node_cfg = cfg['nodes'][n]
      
      # Determine if the node lives outside the local Docker engine
      is_remote = ['rhost', 'external'].include?(node_cfg['type']) || ['gcp', 'external', 'aws', 'azure'].include?(node_cfg['provider'].to_s.downcase)

      if node_cfg['plane'] == 'mgmt' || node_cfg['kind'] == 'mgmt' || is_remote
        node = Node.new( { 'name' => n, 'ephemeral' => @ephemeral, 'defaults' => @defaults, 'log' => @log, 'dns' => mgmt['dns'], 'domain' => domain }.merge( node_cfg ) )
        nodes << node
      else
        node = Node.new( { 'name' => n, 'ephemeral' => @ephemeral, 'defaults' => @defaults, 'log' => @log, 'dns' => dns, 'domain' => domain }.merge( node_cfg ) )
        # assign the node a mgmt-ip ONLY if it's local
        node.nics['eth0'] = "#{net}#{cnt}/#{mask}"
        cnt += 1
        nodes << node
      end
    end
    nodes
  end

  def init_mgmt_links(vm_name)
    @log.write "#{__method__}(): vm=#{vm_name}", "debug"

    cfg      = find_vm(vm_name)
    switches = []
    router   = []
    hosts    = []
    links    = []
    cnt      = 2

    cfg['nodes'].each do |name, node|
      is_remote = ['rhost', 'external'].include?(node['type']) || ['gcp', 'external', 'aws', 'azure'].include?(node['provider'].to_s.downcase)
      next if is_remote

      if !(node['kind'] == 'mgmt' && node['type'] == 'switch' )
        case node['type']
          when 'controller'
            links << [ "sw0:eth1", "#{name}:eth0" ]
          when 'switch'
            switches << name
          when 'router'
            router << name
          when 'host'
            hosts << name
        end
      end
    end

    sw0 = find_node('sw0')
    (switches + router + hosts).each do |n|
      links << [ "sw0:eth#{cnt}", "#{n}:eth0" ]
      sw0.nics["eth#{cnt}"] = '' if sw0 && sw0.nics
      cnt += 1
    end
    links
  end

  def init_links(vm_name)
    @log.write "#{__method__}(): vm=#{vm_name}", "debug"

    cfg   = find_vm(vm_name)
    links = cfg['links']
    @mgmt = cfg['mgmt'] || @mgmt
    links
  end

  def add_node(name, node={})
    @log.write "#{__method__}(): name=#{name}", "debug"

    @nodes << Node.new( { 'name' => name, 'log' => @log }.merge( node ) )
  end

  def visualize
    @graph = Graph.new(name: @name, nodes: @nodes, links: @links, binding: binding, log: @log, pubdir: @pubdir)
    @graph.to_png(@graph.get_mgmt_topo, 'mgmt_topo')
    @graph.to_png(@graph.get_mgmt_cons, 'mgmt_con')
    @graph.to_png(@graph.get_topology, 'topo')
    @graph.to_png(@graph.get_cons, 'con')

    @graph.to_svg(@graph.get_mgmt_topo, 'mgmt_topo')
    @graph.to_svg(@graph.get_mgmt_cons, 'mgmt_con')
    @graph.to_svg(@graph.get_topology, 'topo')
    @graph.to_svg(@graph.get_cons, 'con')
  end

  def inventory
    @graph = Graph.new(name: @name, nodes: @nodes, links: @links, binding: binding, log: @log, pubdir: @pubdir)
    @graph.to_ini(@graph.get_inventory, @name)
    @graph.to_data_ini(@graph.get_data_inventory, @name)
    deploy_dnsmasq(@graph.to_dnsmasq(@graph.get_dnsmasq, @name))
  end

  def dnsmasq
    @graph = Graph.new(name: @name, nodes: @nodes, links: @links, binding: binding, log: @log, pubdir: @pubdir)
    deploy_dnsmasq(@graph.to_dnsmasq(@graph.get_dnsmasq, @name))
  end
    
  # Deploys the generated dnsmasq zone into the lab's controller container
  # (selected by type, never a hardcoded name): cp the conf into the
  # container's /etc/dnsmasq.d/ and restart dnsmasq there. clamps the
  # conf-dir=/etc/dnsmasq.d promise in lib/graph.rb:806.
  def deploy_dnsmasq(conf_path)
    return if conf_path.to_s.empty? || !File.file?(conf_path.to_s)
    
    controller = @nodes.find { |n| n.respond_to?(:type) && n.type.to_s == 'controller' }
    if controller.nil?
      @log.write "#{__method__}(): no controller node in #{@name}; skipping dnsmasq deploy", "warn"
      return
    end
   
    engine  = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
    ctr     = controller.name
    base    = File.basename(conf_path)
    
    @log.write "#{__method__}(): conf=#{conf_path},controller=#{ctr},engine=#{engine}", "debug"
    
    ran = %x( #{engine} cp "#{conf_path}" #{ctr}:/etc/dnsmasq.d/#{base} 2>&1 )
    if $?.success?
      %x( #{engine} exec #{ctr} systemctl restart dnsmasq 2>&1 )
    end
    @log.write "#{__method__}(): ran=#{ran.inspect},exit=#{$?.exitstatus}", "debug"
    $?.success?
  end

  def find_node(name)
    @log.write "#{__method__}(): name=#{name}", "debug"

    @nodes.each do |node|
      if node.name == name
        return node
      end
    end
    return nil
  end

  def hotplug_link(ep1, ep2)
    @log.write "[HOTPLUG] Connecting link: #{ep1} <--> #{ep2}", "info"
    @nodes.each { |n| n.resolve_runtime! if n.respond_to?(:resolve_runtime!) }

    Link.new({ 'links' => [ep1, ep2], 'nodes' => @nodes, 'mgmt' => @mgmt, 'log' => @log })
    
    # Re-apply IPs after the physical pipe is constructed
    [ep1, ep2].each do |endpoint|
      node_name, nic = endpoint.split(':')
      node = find_node(node_name)
      node.hotplug_ip(nic, node.nics[nic]) if node && node.nics && node.nics[nic]
    end
  end

  def hotunplug_link(ep1, ep2)
    @log.write "[HOTPLUG] Disconnecting link: #{ep1} <--> #{ep2}", "info"
    @nodes.each { |n| n.resolve_runtime! if n.respond_to?(:resolve_runtime!) }

    # Pass 'false' to prevent it from automatically connecting!
    link = Link.new({ 'links' => [ep1, ep2], 'nodes' => @nodes, 'mgmt' => @mgmt, 'log' => @log }, false)
    link.disconnect
  end

  def add_dnat
    @log.write "#{__method__}(): ", "debug"

    chain = "#{@name.upcase}-DNAT"
    vmip  = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).rstrip
    vmips = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).split
    natgw = find_node('natgw')

    # create new chain if it does not exist
    %x( iptables -tnat -S #{chain} 2> /dev/null )
    if $?.exitstatus > 0
      %x( iptables -tnat -N #{chain} )
      vmips.each do |ip|
        %x( iptables -tnat -I PREROUTING -d #{ip} -j #{chain} )
      end
    end

    @nodes.each do |node|
      #
      # VXLAN
      #
      if( ! node.vxlan.nil? )
        @log.write "#{__method__}(): node=#{node},vxlan=#{node.vxlan}", "debug"

        local, lport = node.vxlan['local'].split(':')
        
        # Resolve VXLAN router dynamically
        target_route = natgw.dnat.is_a?(Hash) ? (natgw.dnat[node.plane] || natgw.dnat.values.first) : natgw.dnat
        router_name  = target_route.split(':')[0]
        router       = find_node(router_name)

        %x( iptables -tnat -C #{chain} -p udp -d #{local} --dport #{lport} -j DNAT --to-destination #{router.via}:#{lport} 2> /dev/null )
        if $?.exitstatus > 0
          %x( iptables -tnat -I #{chain} -p udp -d #{local} --dport #{lport} -j DNAT --to-destination #{router.via}:#{lport} )
          %x( ip netns exec #{router.netns} iptables -tnat -I PREROUTING -p udp -d #{router.via} --dport #{lport} -j DNAT --to-destination #{node.ipv4.split('/')[0]}:#{lport})
        end
      end
      #
      # DNAT (Dynamic Routing Dictionary & Port Forwarding)
      #
      if !node.dnat.nil? && node.dnat.is_a?(Array) && ['host', 'controller', 'server', 'gateway', 'router'].include?(node.type)
        @log.write "#{__method__}(): node=#{node.name}, dnat=#{node.dnat}", "debug"

        # --- THE SMART LOOKUP ---
        target_route = nil
        if natgw && natgw.dnat
          if natgw.dnat.is_a?(Hash)
            # Use the explicit routing dictionary!
            target_route = natgw.dnat[node.plane] || natgw.dnat.values.first
          else
            # Legacy Fallback (so old YAMLs don't break)
            target_route = node.plane == 'mgmt' ? 'ro0:eth1' : natgw.dnat
          end
        end

        next unless target_route

        # Extract the specific router and its IP
        router_name, router_nic = target_route.split(':')
        router = find_node(router_name)
        via = router.nics[router_nic].split('/')[0]

        # Target IP: Smart fallback (eth1, eth0, tun0, wg0)
        target_ip = node.nics['eth1']&.split('/')&.first || 
                    node.nics['eth0']&.split('/')&.first || 
                    node.nics['tun0']&.split('/')&.first ||
                    node.nics['wg0']&.split('/')&.first

        node.dnat.each do |r|
          ext_port = r[0]
          int_port = r[1].to_s.include?(':') ? r[1].split(':')[1] : r[1]
          proto    = r[2] || 'tcp'

          @log.info "#{vmip}:#{ext_port} -> #{target_ip}:#{int_port} (#{proto})"
          
          if target_ip == via
            # OPTIMIZATION: Direct translation on the host
            %x( iptables -tnat -C #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination=#{via}:#{int_port} 2> /dev/null )
            if $?.exitstatus > 0
              %x( iptables -tnat -I #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination=#{via}:#{int_port} )
            end
          else
            # TARGET IS BEHIND ROUTER: 2-step hop
            %x( iptables -tnat -C #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination=#{via}:#{ext_port} 2> /dev/null )
            if $?.exitstatus > 0
              %x( iptables -tnat -I #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination=#{via}:#{ext_port} )
              %x( ip netns exec #{router.netns} iptables -tnat -I PREROUTING -p #{proto} -d #{via} --dport #{ext_port} -j DNAT --to-destination #{target_ip}:#{int_port} )
            end
          end
        end
      end
    end
  end


  def add_adhoc_dnat(node_name, ext_port, int_port, proto = 'tcp')
    @log.write "#{__method__}(): node=#{node_name}, #{ext_port}->#{int_port}/#{proto}", "debug"

    chain = "#{@name.upcase}-DNAT"
    vmip  = %x(ip route get 1.1.1.1 2>/dev/null | awk 'NR==1{print $7}').strip

    node = find_node(node_name)
    raise "Node '#{node_name}' not found" if node.nil?

    natgw = find_node('natgw')
    raise "No 'natgw' node found (required for DNAT)" if natgw.nil?
    raise "'natgw' has no 'dnat' attribute" if natgw.dnat.nil?

    # --- THE SMART LOOKUP ---
    target_route = nil
    if natgw.dnat.is_a?(Hash)
      target_route = natgw.dnat[node.plane] || natgw.dnat.values.first
    else
      target_route = node.plane == 'mgmt' ? 'ro0:eth1' : natgw.dnat
    end

    parts = target_route.to_s.split(':')
    raise "Invalid natgw route format: #{target_route}" unless parts.length == 2
    
    router_name, nic = parts
    router = find_node(router_name)
    raise "Router '#{router_name}' not found" if router.nil?
    raise "Interface '#{nic}' missing on router" unless router.nics.key?(nic)

    via = router.nics[nic].split('/')[0]
    
    # Target IP: Smart fallback
    target_ip = node.nics['eth1']&.split('/')&.first || 
                node.nics['eth0']&.split('/')&.first || 
                node.nics['tun0']&.split('/')&.first ||
                node.nics['wg0']&.split('/')&.first
                
    raise "Node #{node.name} missing suitable network interface" if target_ip.nil?

    if target_ip == via
      # OPTIMIZATION: Direct translation on the Host
      rule1_check = "iptables -t nat -C #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination #{via}:#{int_port}"
      rule1_add   = "iptables -t nat -I #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination #{via}:#{int_port}"

      unless system(rule1_check)
        @log.write "#{__method__}(): Adding optimized DNAT rule 1: #{rule1_add}", "debug"
        raise "Failed optimized rule 1: #{$?.exitstatus}" unless system(rule1_add)
      end
    else
      # TARGET IS BEHIND ROUTER: 2-step hop
      rule1_check = "iptables -t nat -C #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination #{via}:#{ext_port}"
      rule1_add   = "iptables -t nat -I #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination #{via}:#{ext_port}"

      unless system(rule1_check)
        @log.write "#{__method__}(): Adding DNAT rule 1: #{rule1_add}", "debug"
        raise "Failed rule 1: #{$?.exitstatus}" unless system(rule1_add)
      end

      router_netns = %x( docker ps --format '{{.ID}}' --filter name=#{router.name} ).rstrip
      
      rule2_check = "ip netns exec #{router_netns} iptables -t nat -C PREROUTING -p #{proto} -d #{via} --dport #{ext_port} -j DNAT --to-destination #{target_ip}:#{int_port}"
      rule2_add   = "ip netns exec #{router_netns} iptables -t nat -I PREROUTING -p #{proto} -d #{via} --dport #{ext_port} -j DNAT --to-destination #{target_ip}:#{int_port}"

      unless system(rule2_check)
        @log.write "#{__method__}(): Adding DNAT rule 2: #{rule2_add}", "debug"
        raise "Failed rule 2: #{$?.exitstatus}" unless system(rule2_add)
      end
    end

    @log.info "[ADHOC DNAT] #{vmip}:#{ext_port} ➡ #{via}:#{ext_port} ➡ #{target_ip}:#{int_port}"

    return { node: node.name, type: node.type, proto: proto, external_port: "#{vmip}:#{ext_port}", internal_port: "#{target_ip}:#{int_port}", adhoc: true }
  end

  # Generates a dedicated SSH key pair for the lab and distributes it
  def setup_lab_ssh_keys
    @log.info "Setting up Lab-wide Bootstrap SSH keys..."
    
    FileUtils.mkdir_p('/var/run/ctlabs/keys')
    safe_name = @relative_path.gsub('/', '_')
    priv_key = "/var/run/ctlabs/keys/#{safe_name}_id_ed25519"
    pub_key_path = "#{priv_key}.pub"

    # Generate the key pair if it doesn't already exist for this session
    unless File.exist?(priv_key)
      system("ssh-keygen -t ed25519 -f #{priv_key} -N '' -q -C 'lab-#{safe_name}'")
    end

    pub_key = File.read(pub_key_path).strip

    @nodes.each do |node|
      inject_ssh_key_to_node(node, priv_key, pub_key_path, pub_key)
    end
  end

  # Mounts the keys into a specific container via Docker Exec
  def inject_ssh_key_to_node(node, priv_key, pub_key_path, pub_key)
    # Skip remote hosts since we don't have local docker exec access to them
    return if ['rhost', 'external', 'gateway'].include?(node.type)

    begin
      # Login user for this node. The public key must land in THAT user's home
      # (node_profiles.yml sets `user: ansible` for everything that has the
      # account), otherwise sshd will never offer it to the login we use.
      login_user = (node.user.nil? || node.user.to_s.empty?) ? 'root' : node.user.to_s
      home       = login_user == 'root' ? '/root' : "/home/#{login_user}"

      # Ensure .ssh directory exists
      system("docker exec #{node.name} mkdir -p #{home}/.ssh")
      system("docker exec #{node.name} chmod 700 #{home}/.ssh")
      system("docker exec #{node.name} chown #{login_user}:#{login_user} #{home}/.ssh") unless login_user == 'root'

      # The controller gets the PRIVATE key so it can SSH into other nodes/GCP.
      # It goes into root's home AND the profile login user's home: the web
      # terminal and any operator running `ansible -i ... -m ping` by hand use
      # the profile user (ansible), whose ssh identity home is $HOME. With the
      # key only under /root, every host came back UNREACHABLE from the
      # terminal with "Permission denied (publickey,...)" even though the
      # playbooks (exec'd as root) worked fine. Not a privilege escalation:
      # the profile user has passwordless sudo and could read root's key anyway.
      if node.type == 'controller'
        key_homes = ['/root']
        key_homes << home unless login_user == 'root'

        key_homes.each do |key_home|
          next unless system("docker exec #{node.name} mkdir -p #{key_home}/.ssh")

          system("docker cp #{priv_key} #{node.name}:#{key_home}/.ssh/id_ed25519")
          system("docker cp #{pub_key_path} #{node.name}:#{key_home}/.ssh/id_ed25519.pub")
          system("docker exec #{node.name} chmod 700 #{key_home}/.ssh")
          system("docker exec #{node.name} chmod 600 #{key_home}/.ssh/id_ed25519")
          system("docker exec #{node.name} chmod 644 #{key_home}/.ssh/id_ed25519.pub")
          # docker cp preserves the host file's root ownership, and ssh refuses a
          # private key the caller does not own.
          system("docker exec #{node.name} chown -R #{login_user}:#{login_user} #{key_home}/.ssh") unless key_home == '/root'
        end
      end

      # ALL nodes get the PUBLIC key in their login user's authorized_keys
      system("docker exec #{node.name} sh -c \"echo '#{pub_key}' >> #{home}/.ssh/authorized_keys\"")
      unless login_user == 'root'
        system("docker exec #{node.name} chown #{login_user}:#{login_user} #{home}/.ssh/authorized_keys")
      end
      system("docker exec #{node.name} chmod 600 #{home}/.ssh/authorized_keys")

    rescue => e
      @log.write("Failed to inject SSH keys to #{node.name}: #{e.message}", "error")
    end
  end

  def get_next_switch_port(switch_name)
    used_ports = @links.map do |l|
      if l[0] =~ /^#{switch_name}:eth(\d+)$/
        $1.to_i
      elsif l[1] =~ /^#{switch_name}:eth(\d+)$/
        $1.to_i
      end
    end.compact
    
    next_port = 1
    next_port += 1 while used_ports.include?(next_port)
    next_port
  end

def add_adhoc_node(node_name, node_cfg, target_switch = nil, web_v_token = nil, web_v_addr = nil)
  @log.write "#{__method__}(): node=#{node_name}, cfg=#{node_cfg}, switch=#{target_switch}", "debug"
    raise "Node '#{node_name}' already exists" if find_node(node_name)

    # 1. Fetch live container namespace IDs for existing nodes
    @nodes.each do |n|
      if n.netns.nil?
        cid = %x( docker ps --format '{{.ID}}' --filter name=#{n.name} ).strip
        n.instance_variable_set(:@netns, cid) unless cid.empty?
      end
    end

    type = node_cfg['type'] || 'host'
    kind = node_cfg['kind'] || node_cfg['profile'] || 'linux'
    plane = node_cfg['plane'] || 'data'
    is_remote = ['rhost', 'external'].include?(type) || ['gcp', 'external', 'aws', 'azure'].include?(node_cfg['provider'].to_s.downcase)

    vm_name = @vm_name || @cfg['topology'][0]['hv']
    cfg_vm  = find_vm(vm_name)
    mgmt    = cfg_vm['mgmt'] || @mgmt || {}
    
    # 2. SMART IP CALCULATION
    target_nic = is_remote ? 'tun0' : 'eth0'
    node_cfg['nics'] ||= {}
    
    if node_cfg['nics'][target_nic].to_s.strip.empty?
      net = mgmt['net'] || "192.168.99.0/24"
      
      # Gather all IPs currently in use in memory to find the true highest IP
      used_ips = @nodes.flat_map do |n|
        ips = n.nics&.values&.map { |ip| ip.to_s.split('/')[0] } || []
        ips << n.ipv4.to_s.split('/')[0] if n.ipv4 && !n.ipv4.to_s.empty?
        ips
      end.compact.reject(&:empty?)
      
      require 'ipaddr'
      subnet = IPAddr.new(net)
      ip_range = subnet.to_range.to_a
      start_idx = [20, ip_range.size - 2].min
      
      next_ip = ip_range[start_idx..-2].find { |ip| !used_ips.include?(ip.to_s) }
      node_cfg['nics'][target_nic] = "#{next_ip}/#{subnet.prefix}" if next_ip
    end

    # 3. Instantiate Node
    node_cfg['adhoc'] = true 
    
    node = Node.new({
      'name'      => node_name,
      'ephemeral' => @ephemeral,
      'defaults'  => @defaults,
      'log'       => @log,
      'domain'    => cfg_vm['domain'] || @domain,
      'dns'       => cfg_vm['dns'] || @dns
    }.merge(node_cfg))

    @nodes << node

    # --- TERRAFORM AUTO-PROVISIONING (BACKGROUNDED) ---
    if is_remote && node_cfg['terraform'] && !node_cfg['terraform'].empty?
      @log.info "Queueing auto-provisioning for Node #{node_name} via Terraform in the background..."

      ctrl = find_node('ansible')
      if ctrl
        ctrl_name = ctrl.name
        tf_dir = node_cfg['terraform']['work_dir'] || '.'
        workspace = node_cfg['terraform']['workspace'] || 'default'
        lab_file = @cfg_file

        # Detach the execution from the HTTP request thread!
        Thread.new do
          begin
            @log.info "[BG-TASK] Starting Terraform apply for #{node_name}..."
            engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'

            # 1. Run Terraform Apply directly in the container
            tf_cmd = "cd #{Automation::TF_DIR_CTL}/#{tf_dir} && " \
                     "(terraform workspace select #{workspace} || terraform workspace new #{workspace}) && " \
                     "terraform init -upgrade && terraform apply -auto-approve"

            v_env  = ""
            v_env += "-e VAULT_TOKEN='#{web_v_token}' " if web_v_token && !web_v_token.empty?
            v_env += "-e VAULT_ADDR='#{web_v_addr}' "   if web_v_addr  && !web_v_addr.empty?
            v_env += "-e VAULT_SKIP_VERIFY=true "       if web_v_token &&  web_v_addr

            begin
              gcp_env = GcpAuth.env_vars(node_cfg['terraform'], { addr: web_v_addr, token: web_v_token })
              gcp_env.each { |key, value| v_env += "-e #{key}='#{value}' " }
            rescue => e
              @log.write("[BG-TASK] Could not generate GCP credentials: #{e.message}", "error")
            end

            `#{engine} exec #{v_env}#{ctrl_name} bash -c '#{tf_cmd}'`

            # 2. Fetch the JSON output
            tf_output_json = `#{engine} exec #{v_env}#{ctrl_name} bash -c 'cd #{Automation::TF_DIR_CTL}/#{tf_dir} && terraform output -json provisioned_vms'`.strip
            vms_out = JSON.parse(tf_output_json)

            # 3. Safely update the YAML file with the new IPs
            if vms_out[node_name]
              pub_ip = vms_out[node_name]['public_ip']
              priv_ip = vms_out[node_name]['private_ip']

              @log.info "[BG-TASK] Mapped Terraform IPs for #{node_name}: eth0=#{pub_ip}, eth1=#{priv_ip}"

              # Read and update the file directly to avoid memory race conditions with the live lab
              if File.exist?(lab_file)
                live_yaml = YAML.load_file(lab_file)
                
                # Navigate through the schema safely to find the node
                target = live_yaml['topology'][0]['nodes'][node_name]
                if target
                  target['nics'] ||= {}
                  target['nics']['eth0'] = "#{pub_ip}/32" if pub_ip
                  target['nics']['eth1'] = "#{priv_ip}/24" if priv_ip
                  LabRepository.write_formatted_yaml(lab_file, live_yaml, lab_file)
                end
              end
            end
          rescue => e
            @log.write("[BG-TASK] Terraform auto-provisioning failed: #{e.message}", "error")
          end
        end
      end
    end

    node.run unless is_remote

    unless is_remote
      safe_name = @relative_path.gsub('/', '_')
      priv_key = "/var/run/ctlabs/keys/#{safe_name}_id_ed25519"
      if File.exist?(priv_key)
        pub_key = File.read("#{priv_key}.pub").strip
        inject_ssh_key_to_node(node, priv_key, "#{priv_key}.pub", pub_key)
      end
    end

    # 4. SMART WIRING (Prevents dual-wiring eth1 in mgmt plane)
    data_link = nil
    
    if is_remote
      # Remote node wiring
      if target_switch && !target_switch.strip.empty?
        next_port = get_next_switch_port(target_switch)
        data_link = ["#{target_switch}:eth#{next_port}", "#{node_name}:tun0"]
        @links << data_link
      end
    elsif plane == 'mgmt' || type == 'controller'
      # MGMT PLANE: Only one connection needed (eth0 -> target_switch or sw0)
      actual_switch = (target_switch && !target_switch.strip.empty?) ? target_switch : 'sw0'
      if find_node(actual_switch)
        next_port = get_next_switch_port(actual_switch)
        data_link = ["#{actual_switch}:eth#{next_port}", "#{node_name}:eth0"]
        @links << data_link
        Link.new('nodes' => @nodes, 'links' => data_link, 'log' => @log, 'mgmt' => mgmt)
      end
    else
      # DATA PLANE: Needs OOB Mgmt (eth0 -> sw0) AND Data (eth1 -> target_switch)
      if !(kind == 'mgmt' && type == 'switch') && type != 'gateway'
        if find_node('sw0')
          next_sw0 = get_next_switch_port('sw0')
          mgmt_link = ["sw0:eth#{next_sw0}", "#{node_name}:eth0"]
          @links << mgmt_link
          Link.new('nodes' => @nodes, 'links' => mgmt_link, 'log' => @log, 'mgmt' => mgmt)
        end
      end
      
      if target_switch && !target_switch.strip.empty?
        if find_node(target_switch)
          next_port = get_next_switch_port(target_switch)
          data_link = ["#{target_switch}:eth#{next_port}", "#{node_name}:eth1"]
          @links << data_link
          Link.new('nodes' => @nodes, 'links' => data_link, 'log' => @log, 'mgmt' => mgmt)
        end
      end
    end

    @log.info "[ADHOC NODE] Started node #{node_name}"
    inventory

    [node_cfg, data_link]
  end


  def del_dnat
    @log.write "#{__method__}(): ", "debug"

    chain = "#{@name.upcase}-DNAT"
    vmip  = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).rstrip
    vmips = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).split
    #vmips  = %x( ip route | grep default | awk '{print $9}' ).split
    #vmip = %x( ip -4 addr ls eth0 | grep inet | awk '{print $2}' ).rstrip
    vmips.each do |ip|
      %x( iptables -tnat -D PREROUTING -d #{ip} -j #{chain} )
    end
    %x( iptables -tnat -F #{chain} )
    %x( iptables -tnat -X #{chain} )
  end

  def up(web_v_token = nil, web_v_addr = nil)
    self.class.acquire_lock!(@relative_path)
  
    @log.info "Starting Lab: #{@relative_path}"
    synchronize_lab_operation do
      @log.info "Starting Nodes:"
      @nodes.each { |node| node.run }
  
      @log.info "Starting Links:"
      @links.each do |l|
        Link.new('nodes' => @nodes, 'links' => l, 'log' => @log, 'mgmt' => @mgmt)
      end
  
      @log.info "DNAT:"
      add_dnat
    end

    setup_lab_ssh_keys

    ctrl = find_node('ansible') || @nodes.find { |n| n.type == 'controller' }
    if ctrl
      node_cfg = @cfg['topology'][0]['nodes'][ctrl.name] || {}
      
      # Only run Terraform if a working directory is explicitly configured
      if node_cfg['terraform'] && node_cfg['terraform']['work_dir'] && !node_cfg['terraform']['work_dir'].strip.empty?
        @log.info "Executing Terraform provisioning phase..."
        begin
          # Call run_terraform synchronously. If it fails, the lab startup will abort here.
          run_terraform(ctrl.name, nil, web_v_token, web_v_addr, 'apply')
          
          # CRITICAL: We must reload the lab YAML into memory because Terraform
          # may have injected new public/private IPs for the cloud VMs!
          @log.info "Reloading topology to capture Terraform IP assignments..."
          @cfg = YAML.load_file(@cfg_file)
          
          # Re-initialize nodes so the new IPs are available for the Ansible inventory
          @nodes = init_nodes(@vm_name)
        rescue => e
          @log.write("Terraform provisioning failed: #{e.message}", "error")
          #raise "Lab startup aborted due to Terraform failure: #{e.message}"
        end
      end
    end
    # -----------------------------------------

    @log.info "Generating fresh Ansible inventory..."
    inventory

    # Copy lab-specific flashcards if they exist
    lab_flashcards    = File.join(File.dirname(@cfg_file), 'flashcards.json')
    public_flashcards = '/srv/ctlabs-server/public/flashcards.json'
    
    if File.file?(lab_flashcards)
      FileUtils.cp(lab_flashcards, public_flashcards)
      @log.info "Loaded flashcards from lab: #{lab_flashcards}"
    end
  end

  def down
    begin
      # Validate we own the lock
      if self.class.running? && self.class.current_name != @relative_path
        raise "Cannot stop '#{@relative_path}': currently running lab is '#{self.class.current_name}'"
      end
  
      @log.info "Stopping Lab: #{@relative_path}"
  
      synchronize_lab_operation do
        @log.info "Stopping Nodes:"
        @nodes.each { |node| node.stop }
  
        @log.info "Removing DNAT rules..."
        del_dnat
      end

      # Clear any unsaved AdHoc cache!
      FileUtils.rm_f("/var/run/ctlabs/#{@relative_path.gsub('/', '_')}.adhoc")
    ensure
      self.class.release_lock!
    end
  end

  private

  def generate_log_path(action)
    require 'fileutils'
    FileUtils.mkdir_p('/var/log/ctlabs')
    timestamp = Time.now.to_i
    safe_name = @relative_path.gsub(/\//, '_').gsub(/[^a-zA-Z0-9_.\-]/, '')
    "/var/log/ctlabs/ctlabs_#{timestamp}_#{safe_name}_#{action}.log"
  end

  def synchronize_lab_operation
    lock_dir = File.dirname(LAB_OPERATION_LOCK)
    Dir.mkdir(lock_dir, 0755) unless Dir.exist?(lock_dir)
  
    File.open(LAB_OPERATION_LOCK, File::CREAT | File::RDWR) do |f|
      f.flock(File::LOCK_EX)  # ← THIS IS THE KEY LINE
      yield
    ensure
      # Lock is automatically released when file is closed
    end
  end

  # Textually appends AdHoc changes to preserve the user's YAML formatting perfectly
  def self.save_runtime_to_base(lab_path)
    full_path = File.join("..", "labs", lab_path)
    runtime_file = "/var/run/ctlabs/#{lab_path.gsub('/', '_')}.adhoc"
    
    return true unless File.exist?(runtime_file) # Nothing to save
    return false unless File.file?(full_path)
    
    begin
      lines = File.readlines(full_path)
      adhoc_data = File.read(runtime_file)
      
      new_nodes = []
      new_links = []
      
      current_block = nil
      adhoc_data.each_line do |line|
        if line.strip == "===NODE==="
          current_block = new_nodes
        elsif line.strip == "===LINK==="
          current_block = new_links
        else
          current_block << line if current_block
        end
      end

      # Ensure the file ends with a newline so we don't mash words together
      lines << "\n" if !lines.last.to_s.end_with?("\n")
      
      # 1. Inject Nodes
      if new_nodes.any?
        # Find `links:` with any amount of leading whitespace
        links_idx = lines.index { |l| l.match?(/^\s*links:/) }
        
        if links_idx
          lines.insert(links_idx, *new_nodes)
        else
          lines.concat(new_nodes)
        end
      end
      
      # 2. Inject Links at the absolute bottom of the file
      if new_links.any?
        lines.concat(new_links)
      end
      
      File.write(full_path, lines.join)
      FileUtils.rm_f(runtime_file) 
      
      return true
    rescue => e
      puts "Error saving runtime to base: #{e.message}"
      return false
    end
  end

  # Intelligently merges lab overrides on top of global profiles
  def merge_profiles(global, local)
    merged = Marshal.load(Marshal.dump(global)) # Deep clone global
    return merged if local.nil? || local.empty?

    local.each do |type, kinds|
      merged[type] ||= {}
      next unless kinds.is_a?(Hash)
      
      kinds.each do |kind, attrs|
        merged[type][kind] ||= {}
        if attrs.is_a?(Hash)
          # Arrays like 'caps' or 'env' should be combined or overwritten
          # Here we just use a standard hash merge for simplicity, 
          # which overwrites the global attributes with the local ones.
          merged[type][kind].merge!(attrs)
        end
      end
    end
    merged
  end

end # end class Lab
