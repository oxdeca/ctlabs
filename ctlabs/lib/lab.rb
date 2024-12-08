
# -----------------------------------------------------------------------------
# File        : ctlabs/lib/lab.rb
# Description : lab class; reads in config and manages lab
# License     : MIT License
# -----------------------------------------------------------------------------

class Lab
  attr_writer :dotfile, :dtype, :diagram
  attr_reader :name, :desc

  def initialize(cfg, vm_name=nil, dlevel="warn")
    @log = LabLog.new(level: dlevel)
    @log.write "== Lab =="
    @pubdir = "/srv/ctlabs-server/public"

    unless File.directory?(@pubdir)
      FileUtils.mkdir_p(@pubdir)
    end

    if( File.file?(cfg) )
      File.open("#{@pubdir}/config.yml", 'w') do |f|
        f.write( File.read(cfg) )
      end
    end

    @cfg = YAML.load(File.read(cfg))
    @log.write "#{__method__}(): file=#{cfg},cfg=#{@cfg},vm=#{vm_name}"

    @vm_name  = vm_name
    @name     = @cfg['name']     || ''
    @desc     = @cfg['desc']     || ''
    @defaults = @cfg['defaults'] || {}
    @dns      = @cfg['dns']      || []
    @domain   = @cfg['domain']   || "ctlabs.internal"
    @mgmt     = @cfg['mgmt']     || {}
    @dnatgw   = {}

    # hack, before we start the nodes make sure ip_forwarding is enabled
    %x( echo 1 > /proc/sys/net/ipv4/ip_forward )
    # another hack, elastic search needs more virtual memory areas to start
    %( echo 262144 > /proc/sys/vm/max_map_count )
    @nodes  = init_nodes(vm_name)
    @links  = init_links(vm_name)
    @links += init_mgmt_links(vm_name)
  end

  def find_vm(name)
    @log.write "#{__method__}(): vm=#{name}"

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

  def init_nodes(vm_name)
    @log.write "#{__method__}(): vm=#{vm_name}"

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
        node = Node.new( { 'name' => n, 'defaults' => @defaults, 'log' => @log, 'dns' => mgmt['dns'], 'domain' => domain }.merge( cfg['nodes'][n] ) )
        nodes << node
      else
        node = Node.new( { 'name' => n, 'defaults' => @defaults, 'log' => @log, 'dns' => dns, 'domain' => domain }.merge( cfg['nodes'][n] ) )
        # assign the node a mgmt-ip
        node.nics['eth0'] = "#{net}#{cnt}/#{mask}"
        cnt += 1
        nodes << node
      end
    end
    nodes
  end

  def init_mgmt_links(vm_name)
    @log.write "#{__method__}(): vm=#{vm_name}"

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
    @log.write "#{__method__}(): vm=#{vm_name}"

    cfg   = find_vm(vm_name)
    links = cfg['links']
    @mgmt = cfg['mgmt'] || @mgmt
    links
  end

  def add_node(name, node={})
    @log.write "#{__method__}(): name=#{name}"

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
    @log.write "#{__method__}(): name=#{name}"

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
    @log.write "#{__method__}(): "

    chain = "#{@name.upcase}-DNAT"
    # find main ipv4 address
    vmip  = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).rstrip
    vmips = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).split
    natgw = find_node('natgw')
    via   = nil
    #p "natgw=#{natgw}"
    if( !natgw.nil? && !natgw.dnat.nil? )
      @log.write "#{__method__}(): natgw=#{natgw}"

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
        @log.write "#{__method__}(): node=#{node},vxlan=#{node.vxlan}"

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
        @log.write "#{__method__}(): node=#{node},dnat=#{node.dnat}"
        #p @dnatgw
        #p vmip
        #p node

        router = find_node(natgw.dnat.split(':')[0])
        node.dnat.each do |r|
          @log.write "#{__method__}(): #{vmip}:#{r[0]} -> #{node.nics['eth1'].split('/')[0]}:#{r[1]}"
          puts "#{vmip}:#{r[0]} -> #{node.nics['eth1'].split('/')[0]}:#{r[1]}"
          
          %x( iptables -tnat -C #{chain} -p #{r[2]||"tcp"} -d #{vmip} --dport #{r[0]} -j DNAT --to-destination=#{via}:#{r[0]} 2> /dev/null )
          if $?.exitstatus > 0
            %x( iptables -tnat -I #{chain} -p #{r[2]||"tcp"} -d #{vmip} --dport #{r[0]} -j DNAT --to-destination=#{via}:#{r[0]} )
            %x( ip netns exec #{router.netns} iptables -tnat -I PREROUTING -p #{r[2]||"tcp"} -d #{via} --dport #{r[0]} -j DNAT --to-destination #{node.nics['eth1'].split('/')[0]}:#{r[1]})
          end
        end

      end

      if( ! node.dnat.nil? and node.type == 'controller' )
        @log.write "#{__method__}(): node=#{node},dnat=#{node.dnat}"
        router   = find_node('ro0')
        mgmt_via = router.nics['eth1'].split('/')[0]
        node.dnat.each do |r|
          %x( iptables -tnat -C #{chain} -p #{r[2]||"tcp"} -d #{vmip} --dport #{r[0]} -j DNAT --to-destination=#{mgmt_via}:#{r[1]} 2> /dev/null )
          if $?.exitstatus > 0
            @log.write "#{__method__}(): #{vmip}:#{r[0]} -> #{node.nics['eth0'].split('/')[0]}:#{r[1]}"
            puts "#{vmip}:#{r[0]} -> #{node.nics['eth0'].split('/')[0]}:#{r[1]}"
            %x( iptables -tnat -I #{chain} -p #{r[2]||"tcp"} -d #{vmip} --dport #{r[0]} -j DNAT --to-destination=#{mgmt_via}:#{r[0]} )
            %x( ip netns exec #{router.netns} iptables -tnat -I PREROUTING -p #{r[2]||"tcp"} -d #{mgmt_via} --dport #{r[0]} -j DNAT --to-destination #{node.nics['eth0'].split('/')[0]}:#{r[1]})
          end
        end

      end

    end
  end

  def del_dnat
    @log.write "#{__method__}(): "

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
    @log.write "#{__method__}(): "

    puts "Starting Nodes:"
    @nodes.each { |node| node.run }

    puts "Starting Links:"
    @links.each { |l| Link.new( 'nodes' => @nodes, 'links' => l, 'log' => @log, 'mgmt' => @mgmt ) }
    #@links.each { |l| Link.new(@nodes, l, @log) }

    puts "DNAT:"
    add_dnat

    sleep 1
  end

  def run_playbook(play)
    @log.write "#{__method__}(): "
    cmd    = nil

    # make sure ctrl and all mgmt-sshd are up and running
    # TOOD

    ctrl = find_node('ansible')
    play.class == String ? cmd = play : cmd = ctrl.play
    domain = find_vm(@vm_name)['domain'] || @domain

    if cmd.class == String
      puts "Playbook found: #{cmd} -eCTLABS_DOMAIN=#{domain}"
      system("docker exec -it #{ctrl.name} sh -c 'cd /root/ctlabs-ansible && #{cmd} -eCTLABS_DOMAIN=#{domain}'")
    else
      puts "No Playbook found."
    end
  end

  def down
    @log.write "#{__method__}(): "

    puts "Stopping Nodes:"
    @nodes.each{ |node| node.stop }
    del_dnat
  end

end
