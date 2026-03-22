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

    # write the current lab config to ctlabs-server pubdir
    if( File.file?(cfg) )
      File.open("#{@pubdir}/config.yml", 'w') do |f|
        f.write( File.read(cfg) )
      end
    end

    # process lab config
    @cfg = YAML.load(File.read(cfg))
    @log.write "#{__method__}(): file=#{cfg},cfg=#{@cfg},relative_path=#{@relative_path},vm=#{vm_name}", "debug"

    @vm_name    = vm_name
    @name       = @cfg['name']      || ''
    @ephemeral  = @cfg['ephemeral'] || true
    @desc       = @cfg['desc']      || ''
    @defaults   = @cfg['defaults']  || {}
    @topology   = @cfg['topology']  || {}
    @dns        = @cfg['dns']       || []
    @domain     = @cfg['domain']    || "ctlabs.internal"
    @mgmt       = @cfg['mgmt']      || {}
    @dnatgw     = {}
    #@server_ip  = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3]
    @server_ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }&.ip_address || '127.0.0.1'

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

#  def self.acquire_lock!(name)
#    raise "A lab is already running: #{current_name}" if running?
#    FileUtils.mkdir_p(File.dirname(LOCK_FILE))
#    File.write(LOCK_FILE, name)
#  end

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
      if( v['name'] == name )
        vm = @cfg['topology'][i]
        break
      end
    end
    if( vm.nil? )
      vm = @cfg['topology'][0]
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
    mgmt   = cfg['mgmt']   || @mgmt
    net    = mgmt['net']   || "192.168.40.0/24"

    # 
    tmp  = net.split('/')
    mask = tmp[1]
    net  = tmp[0].split('.')[0..2].join('.') + '.' 

    # start range for mgmt-ip's
    cnt = 20

    cfg['nodes'].each_key do |n|
      if cfg['nodes'][n]['kind'] == 'mgmt' || cfg['nodes'][n]['type'] == 'controller'
        node = Node.new( { 'name' => n, 'ephemeral' => @ephemeral, 'defaults' => @defaults, 'log' => @log, 'dns' => mgmt['dns'], 'domain' => domain }.merge( cfg['nodes'][n] ) )
        nodes << node
      else
        node = Node.new( { 'name' => n, 'ephemeral' => @ephemeral, 'defaults' => @defaults, 'log' => @log, 'dns' => dns, 'domain' => domain }.merge( cfg['nodes'][n] ) )
        # assign the node a mgmt-ip
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

    (switches + router + hosts).each do |n|
      links << [ "sw0:eth#{cnt}", "#{n}:eth0" ]
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

  # TODO
  # check if the rule already exists
  def add_dnat
    @log.write "#{__method__}(): ", "debug"

    chain = "#{@name.upcase}-DNAT"
    # find main ipv4 address
    vmip  = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).rstrip
    vmips = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).split
    natgw = find_node('natgw')
    via   = nil
    #p "natgw=#{natgw}"
    if( !natgw.nil? && !natgw.dnat.nil? )
      @log.write "#{__method__}(): natgw=#{natgw}", "debug"

      ro, nic = natgw.dnat.split(':')
      node    = find_node(ro)
      via     = node.nics[nic].split('/')[0]
    end

    # create new chain if it does not exist
    #vmip = %x( ip -4 addr ls eth0 | grep inet | awk '{print $2}' ).rstrip
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
        router       = find_node(natgw.dnat.split(':')[0])
        #router, intf = node.vxlan['via'].split(':')
        #node         = find_node(router)
        #via          = node.nics[intf].split('/')[0]
        #via          = find_node('natgw').via

        %x( iptables -tnat -C #{chain} -p udp -d #{local} --dport #{lport} -j DNAT --to-destination #{via}:#{lport} 2> /dev/null )
        if $?.exitstatus > 0
          %x( iptables -tnat -I #{chain} -p udp -d #{local} --dport #{lport} -j DNAT --to-destination #{via}:#{lport} )
          %x( ip netns exec #{router.netns} iptables -tnat -I PREROUTING -p udp -d #{via} --dport #{lport} -j DNAT --to-destination #{node.ipv4.split('/')[0]}:#{lport})
        end

      end

      #
      # DNAT
      #
      if( ! node.dnat.nil? and node.type == 'host' )
        @log.write "#{__method__}(): node=#{node},dnat=#{node.dnat}", "debug"
        #p @dnatgw
        #p vmip
        #p node

        router = find_node(natgw.dnat.split(':')[0])
        dnic   = 'eth1'
        node.dnat.each do |r|
          if r[1].to_s.include?(':')
            dnic, dport = r[1].split(':')
          else
            dport = r[1]
          end
          @log.info "#{vmip}:#{r[0]} -> #{node.nics[dnic].split('/')[0]}:#{dport}"
          
          %x( iptables -tnat -C #{chain} -p #{r[2]||"tcp"} -d #{vmip} --dport #{r[0]} -j DNAT --to-destination=#{via}:#{r[0]} 2> /dev/null )
          if $?.exitstatus > 0
            %x( iptables -tnat -I #{chain} -p #{r[2]||"tcp"} -d #{vmip} --dport #{r[0]} -j DNAT --to-destination=#{via}:#{r[0]} )
            %x( ip netns exec #{router.netns} iptables -tnat -I PREROUTING -p #{r[2]||"tcp"} -d #{via} --dport #{r[0]} -j DNAT --to-destination #{node.nics[dnic].split('/')[0]}:#{dport})
          end
        end

      end

      if( ! node.dnat.nil? and node.type == 'controller' )
        @log.write "#{__method__}(): node=#{node},dnat=#{node.dnat}", "debug"
        router   = find_node('ro0')
        mgmt_via = router.nics['eth1'].split('/')[0]
        node.dnat.each do |r|
          %x( iptables -tnat -C #{chain} -p #{r[2]||"tcp"} -d #{vmip} --dport #{r[0]} -j DNAT --to-destination=#{mgmt_via}:#{r[1]} 2> /dev/null )
          if $?.exitstatus > 0
            @log.info "#{vmip}:#{r[0]} -> #{node.nics['eth0'].split('/')[0]}:#{r[1]}"
            %x( iptables -tnat -I #{chain} -p #{r[2]||"tcp"} -d #{vmip} --dport #{r[0]} -j DNAT --to-destination=#{mgmt_via}:#{r[0]} )
            %x( ip netns exec #{router.netns} iptables -tnat -I PREROUTING -p #{r[2]||"tcp"} -d #{mgmt_via} --dport #{r[0]} -j DNAT --to-destination #{node.nics['eth0'].split('/')[0]}:#{r[1]})
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
  
    if node.type == 'controller'
      # === MGMT NETWORK PATH (implicit via ro0) ===
      router = find_node('ro0')
      raise "'ro0' router not found for controller DNAT" if router.nil?
      raise "'ro0' missing eth1" unless router.nics.key?('eth1')
  
      mgmt_via = router.nics['eth1'].split('/')[0]
      target_ip = node.nics['eth0']&.split('/')&.first
      raise "Controller node missing eth0" if target_ip.nil?
  
      # Rule 1: Host → ro0 (mgmt gateway)
      rule1_check = "iptables -t nat -C #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination #{mgmt_via}:#{ext_port}"
      rule1_add   = "iptables -t nat -I #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination #{mgmt_via}:#{ext_port}"
  
      unless system(rule1_check)
        @log.write "#{__method__}(): Adding mgmt DNAT rule 1: #{rule1_add}", "debug"
        raise "Failed rule 1: #{$?.exitstatus}" unless system(rule1_add)
      end
  
      router_netns = %x( docker ps --format '{{.ID}}' --filter name=#{router.name} ).rstrip
      # Rule 2: Inside ro0 netns → final controller
      rule2_check = "ip netns exec #{router_netns} iptables -t nat -C PREROUTING -p #{proto} -d #{mgmt_via} --dport #{ext_port} -j DNAT --to-destination #{target_ip}:#{int_port}"
      rule2_add   = "ip netns exec #{router_netns} iptables -t nat -I PREROUTING -p #{proto} -d #{mgmt_via} --dport #{ext_port} -j DNAT --to-destination #{target_ip}:#{int_port}"
  
      unless system(rule2_check)
        @log.write "#{__method__}(): Adding mgmt DNAT rule 2: #{rule2_add}", "debug"
        raise "Failed rule 2: #{$?.exitstatus}" unless system(rule2_add)
      end
  
      @log.info "[ADHOC DNAT] (MGMT) #{vmip}:#{ext_port} ➡ #{mgmt_via}:#{ext_port} ➡ #{target_ip}:#{int_port}"
  
    elsif node.type == 'host'
      # === DATA NETWORK PATH (via natgw) ===
      natgw = find_node('natgw')
      raise "No 'natgw' node found (required for host DNAT)" if natgw.nil?
      raise "'natgw' has no 'dnat' attribute" if natgw.dnat.nil?
  
      parts = natgw.dnat.to_s.split(':')
      raise "Invalid natgw.dnat format" unless parts.length == 2
      router_name, nic = parts
      raise "Empty router/interface in natgw.dnat" if router_name.empty? || nic.empty?
  
      router = find_node(router_name)
      raise "Router '#{router_name}' not found" if router.nil?
      raise "Interface '#{nic}' missing on router" unless router.nics.key?(nic)
  
      via = router.nics[nic].split('/')[0]
      target_ip = node.nics['eth1']&.split('/')&.first
      raise "Host node missing eth1" if target_ip.nil?
  
      # Rule 1: Host → natgw internal IP (same port)
      rule1_check = "iptables -t nat -C #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination #{via}:#{ext_port}"
      rule1_add   = "iptables -t nat -I #{chain} -p #{proto} -d #{vmip} --dport #{ext_port} -j DNAT --to-destination #{via}:#{ext_port}"
  
      unless system(rule1_check)
        @log.write "#{__method__}(): Adding data DNAT rule 1: #{rule1_add}", "debug"
        raise "Failed rule 1: #{$?.exitstatus}" unless system(rule1_add)
      end
  
      router_netns = %x( docker ps --format '{{.ID}}' --filter name=#{router.name} ).rstrip
      # Rule 2: Inside router netns → final host
      rule2_check = "ip netns exec #{router_netns} iptables -t nat -C PREROUTING -p #{proto} -d #{via} --dport #{ext_port} -j DNAT --to-destination #{target_ip}:#{int_port}"
      rule2_add   = "ip netns exec #{router_netns} iptables -t nat -I PREROUTING -p #{proto} -d #{via} --dport #{ext_port} -j DNAT --to-destination #{target_ip}:#{int_port}"
  
      unless system(rule2_check)
        @log.write "#{__method__}(): Adding data DNAT rule 2: #{rule2_add}", "debug"
        raise "Failed rule 2: #{$?.exitstatus}" unless system(rule2_add)
      end
  
      @log.info "[ADHOC DNAT] (DATA) #{vmip}:#{ext_port} ➡ #{via}:#{ext_port} ➡ #{target_ip}:#{int_port}"
  
    else
      raise "AdHoc DNAT only supported for 'host' and 'controller' nodes"
    end
  
    return { node: node.name, type: node.type, proto: proto, external_port: "#{vmip}:#{ext_port}", internal_port: "#{target_ip}:#{int_port}", adhoc: true }
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

    # 2. Determine explicitly vs implicitly managed networks
    type = node_cfg['type']
    kind = node_cfg['kind']
    is_explicit_mgmt = (type == 'controller' || (type == 'router' && kind == 'mgmt'))
    needs_implicit_mgmt = (['host', 'switch'].include?(type) || (type == 'router' && kind != 'mgmt'))

    # Calculate next available Mgmt IP safely
    vm_name = @vm_name || @cfg['topology'][0]['name']
    cfg_vm  = find_vm(vm_name)
    mgmt    = cfg_vm['mgmt'] || @mgmt || {}
    net     = mgmt['net'] || "192.168.40.0/24"
    
    tmp  = net.split('/')
    mask = tmp[1]
    net_prefix = tmp[0].split('.')[0..2].join('.') + '.' 
    
    used_ips = @nodes.map do |n| 
      n.nics['eth0'].to_s.split('/')[0].to_s.split('.').last.to_i if n.nics && !n.nics['eth0'].to_s.strip.empty?
    end.compact
    
    mgmt_ip = "#{net_prefix}#{(used_ips.max || 20) + 1}/#{mask}"

    # 3. Create Runtime Configuration
    runtime_cfg = Marshal.load(Marshal.dump(node_cfg)) # Deep clone
    runtime_cfg['nics'] ||= {}
    
    if is_explicit_mgmt
      # Explicit mgmt nodes MUST have eth0 explicitly in the YAML
      if runtime_cfg['nics']['eth0'].nil? || runtime_cfg['nics']['eth0'].strip.empty?
        runtime_cfg['nics']['eth0'] = mgmt_ip
        node_cfg['nics'] ||= {}
        node_cfg['nics']['eth0'] = mgmt_ip
      end
    elsif needs_implicit_mgmt
      # Implicit mgmt nodes get eth0 at runtime, but it MUST NOT save to YAML
      runtime_cfg['nics']['eth0'] = mgmt_ip
      node_cfg['nics'].delete('eth0') if node_cfg['nics']
    end
    
    node_cfg['adhoc'] = true # Tag for UI

    # 4. Instantiate Node with RUNTIME config
    node = Node.new({
      'name'      => node_name,
      'ephemeral' => @ephemeral,
      'defaults'  => @defaults,
      'log'       => @log,
      'domain'    => cfg_vm['domain'] || @domain,
      'dns'       => cfg_vm['dns'] || @dns
    }.merge(runtime_cfg))

    @nodes << node
    node.run

    # 5. Connect Mgmt Interface to sw0 sequentially
    if !(kind == 'mgmt' && type == 'switch') && type != 'gateway'
      sw0 = find_node('sw0')
      if sw0
        used_sw0 = @links.map do |l| 
          if l[0] =~ /^sw0:eth(\d+)$/
            $1.to_i
          elsif l[1] =~ /^sw0:eth(\d+)$/
            $1.to_i
          end
        end.compact
        
        next_sw0_port = 1
        next_sw0_port += 1 while used_sw0.include?(next_sw0_port)

        mgmt_link = ["sw0:eth#{next_sw0_port}", "#{node_name}:eth0"]
        @links << mgmt_link
        Link.new('nodes' => @nodes, 'links' => mgmt_link, 'log' => @log, 'mgmt' => mgmt)
      end
    end

    # 6. Connect Data Interface to Target Switch sequentially
    data_link = nil
    if target_switch && !target_switch.to_s.strip.empty?
      if target_sw_node = find_node(target_switch)
        used_sw = @links.map do |l| 
          if l[0] =~ /^#{target_switch}:eth(\d+)$/
            $1.to_i
          elsif l[1] =~ /^#{target_switch}:eth(\d+)$/
            $1.to_i
          end
        end.compact
        
        next_port = 1
        next_port += 1 while used_sw.include?(next_port)

        data_link = ["#{target_switch}:eth#{next_port}", "#{node_name}:eth1"]
        @links << data_link
        Link.new('nodes' => @nodes, 'links' => data_link, 'log' => @log, 'mgmt' => mgmt)
      end
    end

    @log.info "[ADHOC NODE] Started node #{node_name}"

    # CACHE THE EXACT TEXT FOR SAVING LATER
    begin
      FileUtils.mkdir_p('/var/run/ctlabs')
      runtime_file = "/var/run/ctlabs/#{@relative_path.gsub('/', '_')}.adhoc"
      File.open(runtime_file, 'a') do |f|
        clean_cfg = Marshal.load(Marshal.dump(node_cfg))
        clean_cfg.delete('adhoc')
        
        # 8 spaces for node name
        yaml_str = "      #{node_name}:\n"
        # 10 spaces for attributes
        yaml_str << "        type : #{clean_cfg['type']}\n" if clean_cfg['type']
        yaml_str << "        kind : #{clean_cfg['kind']}\n" if clean_cfg['kind'] && !clean_cfg['kind'].to_s.empty?
        yaml_str << "        gw   : #{clean_cfg['gw']}\n" if clean_cfg['gw'] && !clean_cfg['gw'].to_s.empty?
        
        # NEVER save explicit nics for switches. Strip eth0 for all others.
        if clean_cfg['type'] != 'switch' && clean_cfg['nics'] && clean_cfg['nics'].any? { |k,v| k != 'eth0' }
          yaml_str << "        nics :\n"
          clean_cfg['nics'].each { |nic, ip| yaml_str << "          #{nic}: #{ip}\n" unless nic == 'eth0' }
        end
        
        f.puts "===NODE==="
        f.puts yaml_str.chomp # Chomp removes the trailing newline for cleaner injection
        
        if data_link
          f.puts "===LINK==="
          f.puts "      - [ \"#{data_link[0]}\",  \"#{data_link[1]}\" ]\n"
        end
      end
    rescue => e
      @log.write("Failed to write adhoc state cache: #{e.message}", "error")
    end

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

    # 5. Check Exit Status
    if $?.success?
      msg = "\n✅ Terraform execution completed successfully.\n"
      @log.info msg.strip
      File.open(log_path, 'a') { |f| f.puts msg } if log_path
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

end # end class Lab
