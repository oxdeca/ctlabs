
# -----------------------------------------------------------------------------
# File        : ctlabs/lib/link.rb
# Description : link class
# License     : MIT License
# -----------------------------------------------------------------------------
#
# Desc: creates most network devices (mostly veth) and moves them into the
#       container namespaces. Some images need to add a wait routine for the 
#       interfaces to be read before the image boots, e.g. arista ceos.
# 
#
class Link
  attr_reader :node1, :node2, :nic1, :nic2, :mgmt
 
  def initialize(args) #nodes, links, log)
    @links  = args['links']
    @nodes  = args['nodes']
    @mgmt   = args['mgmt']


    #@log = log || LabLog.new
    @log = args['log'] || LabLog.new
    @log.write "== Link ==", "debug"
    @log.write "#{__method__}(): nodes=#{@nodes.object_id},links=#{@links},mgmt=#{@mgmt}", 'debug'
    @log.write "#{__method__}(): nodes=#{@nodes},links=#{@links},mgmt=#{@mgmt}"          , 'debug'
 
    # @links    = links
    # @nodes    = nodes
 
    n1, @nic1 = @links[0].split(':')
    n2, @nic2 = @links[1].split(':')
 
    @node1    = find_node(n1)
    @node2    = find_node(n2)
 
    @log.write "initialize(): node1=#{@node1},nic1=#{@nic1}", "debug"
    @log.write "initialize(): node2=#{@node2},nic2=#{@nic2}", "debug"
 
    connect
  end
 
  def find_node(name)
    @log.write "find_node(): name=#{name}", "debug"
 
    @nodes.each do |node|
      if( node.name == name )
        return node
      end
    end
  end
 
  def nic_exists?(node, nic)
    @log.write "#{__method__}():", "debug"
 
    %x( ip netns exec #{node.netns} ip link ls #{nic} 2>/dev/null )
    if $?.exitstatus == 0
      true
    else
      false
    end
  end
 
  def add_dnat
    true
  end
 
  #
  # assume all nodes are container and are connected via veth pair
  #
  def connect()
    @log.write "#{__method__}(): #{@links[0]} -- #{@links[1]}", "debug"
    @log.info "#{__method__}(): #{@links[0]} -- #{@links[1]}"
 
    create_veth
 
    move_link(@node1, @nic1)
    add_ip(@node1, @nic1)
    create_bond(@node1)
    create_mgmt(@node1)
 
    move_link(@node2, @nic2)
    add_ip(@node2, @nic2)
    create_bond(@node2)
    create_mgmt(@node2)
 
    set_gateway(@node1, @nic1, @node2, @nic2)
    set_gateway(@node2, @nic2, @node1, @nic1)
  end

  #
  #  add gateway/snat
  #
  def set_gateway(node1, nic1, node2, nic2)
    @log.write "#{__method__}(): #{node1}:#{nic1} -- #{node2}:#{nic2}", "debug"

    case node1.type
      when 'host', 'router', 'switch', 'controller'
 
        #
        # adding default gateway and snat
        #
        if( !node1.gw.nil? )
          @log.write "#{__method__}(): node1(host,router,switch) - adding default gw #{node1.gw}", "debug"
          %x( ip netns exec #{node1.netns} ip route add default via #{node1.gw} 2>/dev/null )
          if( node1.type == 'router' && node1.snat )
            snat_nic = %x( ip netns exec #{node1.netns} ip route get #{node1.gw} 2>/dev/null | grep dev | awk '{print $3}' ).rstrip
            if (!snat_nic.empty?)
              %x( ip netns exec #{node1.netns} iptables -tnat -C POSTROUTING -o #{snat_nic} -j MASQUERADE 2> /dev/null )
              if $?.exitstatus > 0
                %x( ip netns exec #{node1.netns} iptables -tnat -A POSTROUTING -o #{snat_nic} -j MASQUERADE )
              end
            end
          end
          if(node2.type == 'gateway')
            %x( ip netns exec #{node1.netns} iptables -tnat -C POSTROUTING -o #{nic1} -j MASQUERADE 2> /dev/null )
            if $?.exitstatus > 0
              %x( ip netns exec #{node1.netns} iptables -tnat -A POSTROUTING -o #{nic1} -j MASQUERADE )
            end
            if(node1.type == 'router')
              @dnatgw = node1
            end
          end
        end
 
      when 'gateway'
        @log.write "#{__method__}(): node1(gateway) - adding link to bridge", "debug"
        %x( ip link set #{node1.name}#{nic1} master #{node1.name} up )
    end
  end
 
  #
  # adding ip addresses
  #
  def add_ip(node, nic)
    case node.type
      when 'host', 'router', 'switch', 'controller'
        if( !node.nics.nil? && !node.nics[nic].to_s.empty? )
          @log.write "#{__method__}(): node(host,router,switch) - adding ip addr #{nic}:#{node.nics[nic]}", "debug"
          %x( ip netns exec #{node.netns} ip addr add #{node.nics[nic]} dev #{nic} 2>/dev/null )
        end
    end
  end
 
  #
  # moving link to namespace and rename nic in new namespace
  #
  def move_link (node, nic)
    case node.type
      when 'host', 'router', 'switch', 'controller'
        #%x( ip netns exec #{node.netns} ip link ls #{nic} 2> /dev/null )
        #if $?.exitstatus > 0
        if( ! nic_exists?(node, nic) )
          @log.write "#{__method__}(): node(host,router,switch) - moving veth endpoints into container", "debug"
          %x( ip link set #{node.name}#{nic} netns #{node.netns} )
  
          @log.write "#{__method__}(): node(host,router,switch) - changing name in container", "debug"
          %x( ip netns exec #{node.netns} ip link set #{node.name}#{nic} name #{nic} mtu #{node.mtu} up )
          
          if(node.type == 'switch' && ['linux', 'mgmt'].include?(node.kind) )
            @log.write "#{__method__}(): node(host,router,switch) - attaching #{nic} to bridge #{node.name}", "debug"
            %x( ip netns exec #{node.netns} ip link set #{nic} master #{node.name} )
          elsif(node.type == 'switch' && ['ovs'].include?(node.kind) && nic != "eth0" )
            @log.write "#{__method__}(): node(host,router,switch) - attaching #{nic} to openvswitch #{node.name}", "debug"
            %x( docker exec #{node.name} sh -c '/usr/bin/ovs-vsctl add-port #{node.name} #{nic}' )
          end
        end
    end
  end
 
  # --------------- NICs ----------------
 
  #
  # create veth pair
  #
  def create_veth
    if( !( nic_exists?(@node1, @nic1) && nic_exists?(@node2, @nic2) ) )
      @log.write "#{__method__}(): adding veth pair", "debug"
      %x( ip link ls #{@node1.name}#{@nic1} 2>/dev/null )
      if $?.exitstatus > 0
        %x( ip link add #{@node1.name}#{@nic1} type veth peer #{@node2.name}#{@nic2} )
      end
    end
  end

  #
  # create mgmt vrf
  #
  def create_mgmt(node)
    case node.type
      when 'host', 'switch', 'router'
        @log.write "#{__method__}(): adding mgmt vrf", "debug"
        if node.kind == 'mgmt'
          @log.write "#{__method__}(): skipping mgmt vrf (node.kind == 'mgmt')", "debug"
          return # skip over as mgmt not needed
        end
        %x( ip netns exec #{node.netns} ip link ls eth0 2> /dev/null )
        if $?.exitstatus == 0
          %x( ip netns exec #{node.netns} ip link ls mgmt 2> /dev/null )
          if $?.exitstatus > 0
            @log.write "#{__method__}(): node(host,switch,router) - adding mgmt vrf", "debug"
            @log.write "#{__method__}(): node=#{node.inspect}", "debug"
            %x( ip netns exec #{node.netns} ip link add mgmt type vrf table 99 )
            %x( ip netns exec #{node.netns} ip link set mgmt up )
            %x( ip netns exec #{node.netns} ip link set eth0 master mgmt )
            %x( ip netns exec #{node.netns} ip route add default via #{@mgmt['gw']} vrf mgmt )
          end
        end
    end
  end
 
  #
  # create bond interface
  #
  def create_bond(node)
    if( !node.bonds.nil? )
      @log.write "#{__method__}(): node(host) - adding bonding", "debug"
      node.bonds.each do |bond|

        %x( ip netns exec #{node.netns} ip link ls #{bond[0]} 2> /dev/null )
        if $?.exitstatus > 0
          @log.write "#{__method__}(): node(host) - adding #{bond[0]}(#{bond[1]['nics'].join(',')})", "debug"
          %x( ip netns exec #{node.netns} ip link add #{bond[0]} type bond mode #{bond[1]['mode']}  )
        end

        @log.write "#{__method__}(): node(host) - configuring  #{bond[0]}(#{bond[1]['nics'].join(',')})", "debug"
        bond[1]['nics'].each do |nic|

          %x( ip netns exec #{node.netns} ip link ls #{nic} 2> /dev/null )
          if $?.exitstatus == 0
            %x( ip netns exec #{node.netns} ip link set #{nic} down )
            %x( ip netns exec #{node.netns} ip link set #{nic} master #{bond[0]} )
            %x( ip netns exec #{node.netns} ip link set #{nic} up )
          end
        end

        # 
        %x( ip netns exec #{node.netns} ip link set #{bond[0]} up )

        #
        # VLAN bonds
        #
        if(! bond[1]['vlan'].nil? )
          bond[1]['vlan'].each do |vnic|

            %x( ip netns exec #{node.netns} ip link ls #{bond[0]}.#{vnic[0]} 2> /dev/null )
            if $?.exitstatus > 0
              @log.write "#{__method__}(): node2(host) - adding #{bond[0]}.#{vnic[0]}", "debug"
              %x( ip netns exec #{node.netns} ip link add link #{bond[0]} name #{bond[0]}.#{vnic[0]} type vlan id #{vnic[0]} )
              %x( ip netns exec #{node.netns} ip link set #{bond[0]}.#{vnic[0]} up )
              %x( ip netns exec #{node.netns} ip addr add #{vnic[1]} dev #{bond[0]}.#{vnic[0]} )
            end
          end
        elsif( bond[1]['ipv4'] != '' )
          @log.write "#{__method__}(): node(host) - add ip addr #{bond[0]}:#{bond[1]['ipv4']}", "debug"
          %x( ip netns exec #{node.netns} ip addr add #{bond[1]['ipv4']} dev #{bond[0]} )
        end

      end

    end
  end
 
end # class Link
