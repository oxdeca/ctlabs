# -----------------------------------------------------------------------------
# File        : ctlabs/lib/lab.rb
# Description : lab class; reads in config and manages lab
# License     : MIT License
# -----------------------------------------------------------------------------

require 'open3'
require 'shellwords'
require 'yaml'

class Lab
  attr_writer :dotfile, :dtype, :diagram
  attr_reader :name, :desc, :nodes, :links, :defaults, :topology

  LAB_OPERATION_LOCK = '/var/run/ctlabs/lab_operation.lock'
  LOCK_FILE          = '/var/run/ctlabs/running_lab'.freeze
  PLAYBOOK_DIR       = '/root/ctlabs-ansible'.freeze
  PLAYBOOK_LOCK_DIR  = '/var/run/ctlabs/playbook_locks'.freeze

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

    global_data = File.file?(::GLOBAL_PROFILES) ? YAML.load_file(::GLOBAL_PROFILES) : {}
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

  def self.acquire_lock!(name)
    raise ArgumentError, "Lab name must be relative path like 'dir/lab.yml'" unless name =~ %r{^[^/]+/[^/]+\.yml$}
    raise "A lab is already running: #{current_name}" if running?
    FileUtils.mkdir_p(File.dirname(LOCK_FILE))
    File.write(LOCK_FILE, name)
  end

  def self.release_lock!
    File.delete(LOCK_FILE) if File.file?(LOCK_FILE)
  end

  def find_vm(name)
    @log.write "#{__method__}(): vm=#{name}", "debug"

    vm = nil
    @cfg['topology'].each_with_index do |v, i|
      if( v['name'] == name || v['hv'] == name )
        vm = @cfg['topology'][i]
        break
      end
    end
    if( vm.nil? )
      vm = @cfg['topology'][0]
    end

    # --- v2.0 SCHEMA NORMALIZER ---
    # Automatically flattens 'planes' into the legacy 'nodes' array
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
      # Ensure .ssh directory exists
      system("docker exec #{node.name} mkdir -p /root/.ssh")
      system("docker exec #{node.name} chmod 700 /root/.ssh")

      # The controller gets the PRIVATE key so it can SSH into other nodes/GCP
      if node.type == 'controller'
        system("docker cp #{priv_key} #{node.name}:/root/.ssh/id_ed25519")
        system("docker cp #{pub_key_path} #{node.name}:/root/.ssh/id_ed25519.pub")
        system("docker exec #{node.name} chmod 600 /root/.ssh/id_ed25519")
        system("docker exec #{node.name} chmod 644 /root/.ssh/id_ed25519.pub")
      end

      # ALL nodes get the PUBLIC key in their authorized_keys
      system("docker exec #{node.name} sh -c \"echo '#{pub_key}' >> /root/.ssh/authorized_keys\"")
      system("docker exec #{node.name} chmod 600 /root/.ssh/authorized_keys")
      
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

  def add_adhoc_node(node_name, node_cfg, target_switch = nil)
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

    vm_name = @vm_name || @cfg['topology'][0]['hv'] || @cfg['topology'][0]['name']
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
            tf_cmd = "cd /root/ctlabs-terraform/#{tf_dir} && " \
                     "(terraform workspace select #{workspace} || terraform workspace new #{workspace}) && " \
                     "terraform init -upgrade && terraform apply -auto-approve"

            `#{engine} exec #{ctrl_name} bash -c '#{tf_cmd}'`

            # 2. Fetch the JSON output
            tf_output_json = `#{engine} exec #{ctrl_name} bash -c 'cd /root/ctlabs-terraform/#{tf_dir} && terraform output -json provisioned_vms'`.strip
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
                  File.write(lab_file, live_yaml.to_yaml)
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

  def up
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

    # --- NEW: BATCH TERRAFORM PROVISIONING ---
    ctrl = find_node('ansible') || @nodes.find { |n| n.type == 'controller' }
    if ctrl
      node_cfg = @cfg['topology'][0]['nodes'][ctrl.name] || {}
      
      # Only run Terraform if a working directory is explicitly configured
      if node_cfg['terraform'] && node_cfg['terraform']['work_dir'] && !node_cfg['terraform']['work_dir'].strip.empty?
        @log.info "Executing Terraform provisioning phase..."
        begin
          # Call run_terraform synchronously. If it fails, the lab startup will abort here.
          run_terraform(ctrl.name, nil, nil, nil, 'apply')
          
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

  def run_playbook(play = nil, log_file_path = nil)
    @log.write "#{__method__}(): play=#{play.inspect}, log_file_path=#{log_file_path}", "debug"
    
    # VALIDATION: Lab must be running
    unless self.class.running? && self.class.current_name == @relative_path
      raise "Cannot run playbook: Lab '#{@relative_path}' is not running. Start it first with --up"
    end
    
    # ACQUIRE PLAYBOOK LOCK (prevents concurrent execution)
    playbook_lock = nil
    begin
      playbook_lock = self.class.acquire_playbook_lock!(@relative_path)
      
      ctrl = find_node('ansible')
      raise "No 'ansible' controller node found in topology" if ctrl.nil?
      
      domain = (@cfg['domain'] || @domain)
      
      # Determine playbook command (same logic as before)
      if play.is_a?(String) && !play.strip.empty?
        play_cmd = play.strip + " -e CTLABS_DOMAIN=#{domain} -e CTLABS_HOST=#{@server_ip}"
      elsif ctrl.play.is_a?(String) && !ctrl.play.strip.empty?
        play_cmd = ctrl.play.strip + " -e CTLABS_DOMAIN=#{domain} -e CTLABS_HOST=#{@server_ip}"
      elsif ctrl.play.is_a?(Hash) && ctrl.play['book'].is_a?(String)
        inv_file  = ctrl.play['inv'] || "#{@name}.ini"
        play_inv  = " -i ./inventories/#{inv_file}"
        play_env  = " -e CTLABS_DOMAIN=#{domain} -e CTLABS_HOST=#{@server_ip}"
        play_env += " #{(ctrl.play['env'] || []).map { |e| " -e #{e}" }.join}"
        play_book = " ./playbooks/#{ctrl.play['book']}"
        play_tags = ctrl.play['tags'] ? " -t #{ctrl.play['tags'].join(',')}" : ''
        play_cmd  = "ansible-playbook#{play_inv}#{play_book}#{play_tags}#{play_env}"
      else
        raise "No playbook specified and no default playbook configured for 'ansible' node"
      end
      
      @log.info "Executing playbook: #{play_cmd}"
      
      # Execute with dual-stream output
      if log_file_path
        stream_docker_exec(ctrl.name, play_cmd, log_file_path)
      else
        success = system("docker exec #{ctrl.name} sh -c 'cd /root/ctlabs-ansible && ANSIBLE_FORCE_COLOR=1 #{play_cmd}'")
        unless success
          @log.info "Playbook execution failed (exit code: #{$?.exitstatus})"
          raise "Playbook execution failed"
        end
      end
      
      @log.info "Playbook execution completed"
      
    ensure
      # ALWAYS release lock (even on failure)
      self.class.release_playbook_lock!(playbook_lock) if playbook_lock
    end
  end

  def run_terraform(target_node_name = nil, log_path = nil, web_v_token = nil, web_v_addr = nil, action = 'apply')
    @log.write "#{__method__}(): target=#{target_node_name.inspect}", "debug"

    ctrl = target_node_name ? find_node(target_node_name) : @nodes.find { |n| n.type == 'controller' }
    raise "No controller node found in topology to run Terraform." unless ctrl

    node_cfg  = @cfg['topology'][0]['nodes'][ctrl.name] || {}
    tf_cfg    = node_cfg['terraform'] || {}
    vault_cfg = tf_cfg['vault'] || {}
    
    workspace = tf_cfg['workspace'].to_s.strip
    workspace = 'default' if workspace.empty?
    
    vars      = tf_cfg['vars'] || []
    var_args  = vars.map { |v| "-var '#{v}'" }.join(" ")

    tf_work_dir = tf_cfg['work_dir'] && !tf_cfg['work_dir'].empty? ? tf_cfg['work_dir'] : '.'
    work_dir = "/root/ctlabs-terraform/#{tf_work_dir}"
    
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

    v_project = vault_cfg['project'].to_s.strip
    v_roleset = vault_cfg['roleset'].to_s.strip
    v_roleset = 'terraform-runner' if v_roleset.empty?

    exec_env = ""

    if !v_project.empty?
      # Fail fast if the web session doesn't have a token!
      if web_v_token.nil? || web_v_token.empty?
        error_msg = "\n❌ ERROR: Vault GCP integration enabled for '#{v_project}', but you are not logged in.\n👉 Please use the Vault Login button in the UI.\n"
        File.open(log_path, 'a') { |f| f.puts error_msg } if log_path
        raise "Missing Vault Token for GCP Authentication."
      end
      
      # --- THE NEW ARCHITECTURE: Fetch GCP token in Ruby! ---
      begin
        gcp_token = VaultAuth.get_gcp_token(web_v_addr, web_v_token, v_project, v_roleset)
        
        # Inject the raw Google Token directly into Terraform's environment
        exec_env += "-e GOOGLE_OAUTH_ACCESS_TOKEN='#{gcp_token}' "
        exec_env += "-e CLOUDSDK_AUTH_ACCESS_TOKEN='#{gcp_token}' " # For good measure
      rescue => e
        error_msg = "\n❌ ERROR: Could not generate GCP credentials from Vault: #{e.message}\n"
        File.open(log_path, 'a') { |f| f.puts error_msg } if log_path
        raise e
      end
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

                  # SCHEMA-AWARE LOOKUP: Check both legacy 'nodes' and modern 'planes'
                  vm_topology = live_yaml['topology']&.first || {}
                  target = nil
                  
                  if vm_topology['nodes'] && vm_topology['nodes'][vm_name]
                    target = vm_topology['nodes'][vm_name]
                  elsif vm_topology['planes']
                    vm_topology['planes'].each do |_, p_data|
                      if p_data && p_data['nodes'] && p_data['nodes'][vm_name]
                        target = p_data['nodes'][vm_name]
                        break
                      end
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
              File.write(@cfg_file, live_yaml.to_yaml)
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

  def stream_docker_exec(container_name, play_cmd, log_file_path = nil)
    inner_command = "cd /root/ctlabs-ansible && ANSIBLE_FORCE_COLOR=1 #{play_cmd} 2>&1"
    cmd = ['docker', 'exec', container_name, 'sh', '-c', inner_command]
  
    # Open log file ONCE before streaming (critical for web UI visibility)
    log_file = log_file_path ? File.open(log_file_path, 'a') : nil
  
    Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
      stdin.close
  
      begin
        # Stream stdout → BOTH CLI ($stdout) AND log file
        Thread.new do
          while (line = stdout.gets)
            $stdout.print(line)
            $stdout.flush
            log_file&.write(line)
            log_file&.flush
          end
        end
  
        # Stream stderr → BOTH CLI ($stderr) AND log file
        Thread.new do
          while (err_line = stderr.gets)
            $stderr.print(err_line)
            $stderr.flush
            log_file&.write(err_line)
            log_file&.flush
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
        exit_status = wait_thr.value.exitstatus
        summary = "[Playbook exited with status: #{exit_status}]\n"
        $stdout.print(summary)
        $stdout.flush
        File.open(log_file_path, 'a') { |f| f.write(summary) } if log_file_path && exit_status != 0
      end
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
