# -----------------------------------------------------------------------------
# File        : ctlabs/lib/lab.rb
# Description : lab class; reads in config and manages lab
# License     : MIT License
# -----------------------------------------------------------------------------

require 'open3'
require 'shellwords'

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
    @server_ip  = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3]

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
    lab_flashcards = File.join(File.dirname(@cfg_file), 'flashcards.json')
    public_flashcards = '/srv/ctlabs-server/public/flashcards.json'
    
    if File.file?(lab_flashcards)
      FileUtils.cp(lab_flashcards, public_flashcards)
      @log.info "Loaded flashcards from lab: #{lab_flashcards}"
    end
  end

  #
  # runs ansible playbook, given via
  # 1. command args
  # 2. defined in lab configuration
  #
  def run_playbook_old(play, output="shell")
    @log.write "#{__method__}(): ", "debug"
    cmd    = nil
    ctrl   = find_node('ansible')
    domain = find_vm(@vm_name)['domain'] || @domain

    if play.class == String && !play.empty?
      play_cmd = "#{play} -eCTLABS_DOMAIN=#{domain} -eCTLABS_HOST=#{@server_ip}"
    elsif ctrl.play.class == String && !ctrl.play.empty?
      play_cmd = "#{ctrl.play} -eCTLABS_DOMAIN=#{domain} -eCTLABS_HOST=#{@server_ip}"
    elsif ctrl.play['book'].class == String
      play_inv  = " -i ./inventories/#{ctrl.play['inv'] || @name + ".ini"}" || " -i ./inventories/#{@name}.ini"
      play_env  = " -eCTLABS_DOMAIN=#{domain} -eCTLABS_HOST=#{@server_ip} #{(ctrl.play['env'] || []).map{|e| " -e#{e}" }.join}"
      play_book = " ./playbooks/#{ctrl.play['book']}"
      play_tags = " -t#{ctrl.play['tags'].join(",")}"
      play_cmd  = "ansible-playbook #{play_inv} #{play_book} #{play_tags} #{play_env} "
    end

    if play_cmd.class == String
      @log.info "Playbook found: #{cmd} -eCTLABS_DOMAIN=#{domain} -eCTLABS_HOST=#{@server_ip}"
      #system("docker exec #{ctrl.name} sh -c 'cd /root/ctlabs-ansible && #{cmd} -eCTLABS_DOMAIN=#{domain} -eCTLABS_HOST=#{@server_ip}'")
      @log.info "Playbook found: #{play_cmd}"
      if output == "shell"
        system("docker exec #{ctrl.name} sh -c 'cd /root/ctlabs-ansible && ANSIBLE_FORCE_COLOR=1 #{play_cmd}'")
      else
        stream_docker_exec(ctrl.name, play_cmd, output)
      end
    else
      @log.write "#{__method__}(): No Playbook found."
      @log.info "No Playbook found."
    end
  end

  def run_playbook_old1(play = nil, log_file_path = nil)
    @log.write "#{__method__}(): play=#{play.inspect}, log_file_path=#{log_file_path}", "debug"
    
    # VALIDATION: Lab must be running
    unless self.class.running? && self.class.current_name == @relative_path
      raise "Cannot run playbook: Lab '#{@relative_path}' is not running. Start it first with --up"
    end
    
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
    
    # Execute with proper output handling
    if log_file_path
      # Stream directly to log file (realtime visibility in web UI)
      stream_docker_exec(ctrl.name, play_cmd, log_file_path)
    else
      # Fallback to shell output
      success = system("docker exec #{ctrl.name} sh -c 'cd /root/ctlabs-ansible && ANSIBLE_FORCE_COLOR=1 #{play_cmd}'")
      unless success
        @log.info "Playbook execution failed (exit code: #{$?.exitstatus})"
        raise "Playbook execution failed"
      end
    end
    
    @log.info "Playbook execution completed"
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

  def stream_docker_exec_old(container_name, play_cmd, log_file_path = nil)
    inner_command = "cd /root/ctlabs-ansible && ANSIBLE_FORCE_COLOR=1 #{play_cmd} 2>&1"
    cmd = ['docker', 'exec', container_name, 'sh', '-c', inner_command]
  
    Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
      stdin.close
  
      # Optional: write to log file
      log_file = log_file_path ? File.open(log_file_path, 'a') : nil
  
      # Stream both stdout and stderr as they arrive
      begin
        while (line = stdout.gets)
          # Yield or process line in real time
          yield line if block_given?
          log_file&.write(line)
          log_file&.flush
        end
  
        # Drain any remaining stderr (in case of late errors)
        while (err_line = stderr.gets)
          yield err_line if block_given?
          log_file&.write(err_line)
          log_file&.flush
        end
      rescue => e
        error_msg = "Error during streaming: #{e.message}\n"
        yield error_msg if block_given?
        log_file&.write(error_msg)
      ensure
        log_file&.close
        exit_status = wait_thr.value.exitstatus
        yield "[Command exited with status: #{exit_status}]\n" if block_given?
      end
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

end # end class Lab