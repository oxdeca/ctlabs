
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

    @cfg = YAML.load(File.read(cfg))
    @log.write "#{__method__}(): file=#{cfg},cfg=#{@cfg},vm=#{vm_name}"

    @name     = @cfg['name']     || ''
    @desc     = @cfg['desc']     || ''
    @defaults = @cfg['defaults'] || {}
    @dns      = @cfg['dns']      || []
    @dnatgw   = {}

    @nodes = init_nodes(vm_name)
    @links = init_links(vm_name)
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
    cfg = find_vm(vm_name)
    dns = cfg['dns'] || @dns

    cfg['nodes'].each_key do |n|
      nodes << Node.new( { 'name' => n, 'defaults' => @defaults, 'log' => @log, 'dsn' => dns }.merge( cfg['nodes'][n] ))
    end
    nodes
  end

  def init_links(vm_name)
    @log.write "#{__method__}(): vm=#{vm_name}"

    cfg   = find_vm(vm_name)
    links = cfg['links']
    links
  end

  def add_node(name, node={})
    @log.write "#{__method__}(): name=#{name}"

    @nodes << Node.new( { 'name' => name, 'log' => @log }.merge( node ) )
  end

  def visualize
    @graph = Graph.new(name: @name, nodes: @nodes, links: @links, binding: binding, log: @log)
    @graph.to_png(@graph.get_topology, 'topo')
    @graph.to_png(@graph.get_connections, 'con')

    @graph.to_svg(@graph.get_topology, 'topo')
    @graph.to_svg(@graph.get_connections, 'con')
  end

  def inventory
    @graph = Graph.new(name: @name, nodes: @nodes, links: @links, binding: binding, log: @log)
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
    vmip  = %x( ip route | grep default | awk '{print $9}' | head -n1 ).rstrip
    vmips  = %x( ip route | grep default | awk '{print $9}' ).split
    natgw = find_node('natgw')
    via   = nil
    #p "natgw=#{natgw}"
    if( !natgw.nil? && !natgw.dnat.nil? )
      @log.write "#{__method__}(): natgw=#{natgw}"

      ro, nic = natgw.dnat.split(':')
      node    = find_node(ro)
      via     = node.nics[nic].split('/')[0]
    end

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
          %x( iptables -tnat -C #{chain} -p #{r[2]||"tcp"} -d #{vmip} --dport #{r[0]} -j DNAT --to-destination=#{via}:#{r[1]} 2> /dev/null )
          if $?.exitstatus > 0
            %x( iptables -tnat -I #{chain} -p #{r[2]||"tcp"} -d #{vmip} --dport #{r[0]} -j DNAT --to-destination=#{via}:#{r[0]} )
            %x( ip netns exec #{router.netns} iptables -tnat -I PREROUTING -p #{r[2]||"tcp"} -d #{via} --dport #{r[0]} -j DNAT --to-destination #{node.nics['eth1'].split('/')[0]}:#{r[1]})
          end
        end

      end

    end
  end

  def del_dnat
    @log.write "#{__method__}(): "

    chain = "#{@name.upcase}-DNAT"
    vmips  = %x( ip route | grep default | awk '{print $9}' ).split
    #vmip = %x( ip -4 addr ls eth0 | grep inet | awk '{print $2}' ).rstrip
    vmips.each do |ip|
      %x( iptables -tnat -D PREROUTING -d #{ip} -j #{chain} )
    end
    %x( iptables -tnat -F #{chain} )
    %x( iptables -tnat -X #{chain} )
  end

  def up
    @log.write "#{__method__}(): "

    @nodes.each { |node| node.run }
    @links.each { |l| Link.new(@nodes, l, @log) }
    add_dnat
  end

  def down
    @log.write "#{__method__}(): "

    @nodes.each{ |node| node.stop }
    del_dnat
  end

end
