
# -----------------------------------------------------------------------------
# File        : ctlabs/lib/node.rb
# Description : node class; describes the container
# License     : MIT License
# -----------------------------------------------------------------------------

require 'fileutils'

class Node
  attr_reader :name, :fqdn, :kind, :type, :image, :env, :cmd, :caps, :priv, :cid, :nics, :ports, :gw, :ipv4, :dnat, :snat, :vxlan, :netns, :eos, :bonds, :defaults, :via, :mtu, :dns, :mgmt, :devs, :play
  attr_writer :nics

  def initialize(args)
    @defaults  = args['defaults']
    @name      = args['name' ]
    @domain    = args['domain'] || "ctlabs.internal"
    @fqdn      = args['fqdn' ]  || "#{@name}.#{@domain}"
    @dns       = args['dns'  ]  || []
    @mgmt      = args['mgmt' ]
    @type      = args['type' ]
    @eos       = args['eos'  ]  || 'linux'
    @kind      = args['kind' ]  || 'linux'
    @kvm       = args['kvm'  ]  || false
    @image     = args['image']
    @env       = args['env'  ]  || []
    @cmd       = args['cmd'  ]
    @play      = args['play' ]
    @nics      = args['nics' ]  || {}
    @bonds     = args['bonds']
    @ports     = args['ports']  # ||  @defaults[@type][@kind]['ports'] || 4
    @gw        = args['gw'   ]
    @ipv4      = args['ipv4' ]
    @snat      = args['snat' ]
    @vxlan     = args['vxlan']
    @dnat      = args['dnat' ]
    @mtu       = args['mtu'  ]  || 1460
    @priv      = args['priv' ]  || false
    @devs      = args['devs' ]  || []

    dcaps      = [ 'NET_ADMIN', 'NET_RAW', 'SYS_ADMIN', 'AUDIT_WRITE', 'AUDIT_CONTROL' ]
    dvols      = [] # [ '/sys/fs/cgroup:/sys/fs/cgroup:ro' ]
    @caps      = (! args['caps'].nil?) ? args['caps'] + dcaps : dcaps
    @vols      = (! args['vols'].nil?) ? args['vols'] + dvols : dvols 

    @log = args['log'] || LabLog.new
    @log.write "== Node =="
    @log.write "#{__method__}(): name=#{@name},fqdn=#{@fqdn},eos=#{@eos},kind=#{@kind},kvm=#{@kvm},type=#{@type},image=#{@image},env=#{@env},cmd=#{@cmd},nics=#{@nics},ports=#{@ports},gw=#{@gw},ipv4=#{@ipv4},mgmt=#{@mgmt},snat=#{@snat},vxlan=#{@vxlan},dnat=#{@dnat},mtu=#{@mtu},priv=#{@priv},caps=#{@caps},vols=#{@vols},defaults=#{@defaults}"

    case @type
      when 'switch', 'router', 'host', 'controller'
        @caps  = (!@defaults[@type][@kind]['caps' ].nil?) ? @caps + @defaults[@type][@kind]['caps' ] : @caps
        @ports = @ports.nil?  && (!@defaults[@type][@kind]['ports'].nil?) ? @defaults[@type][@kind]['ports'] : @ports || 4
        @devs  = (!@defaults[@type][@kind]['devs'].nil?)  ? @defaults[@type][@kind]['devs'] : @devs
      when 'gateway'
        @ports = @ports.nil? ? 2 : @ports
    end

    switch_ports
  end

  # set max ports of a switch
  def switch_ports
    @log.write "#{__method__}(): ports=#{@ports}"

    case
      when [ 'switch', 'gateway' ].include?(@type)
        #@nics = {}
        for i in 0..@ports do
          #@nics.merge!( {"p#{i}" => '' } )
          if( @nics["eth#{i}"].nil? )
            @nics.merge!( {"eth#{i}" => '' } )
          end
        end
    end
  end

  def run
    @log.write "#{__method__}(): name=#{@name}"

    puts "#{__method__}(): #{@name}"
    case @type
      when 'host', 'router', 'switch', 'controller'
        caps  = @caps.map { |c| "--cap-add #{c} " }.join
        vols  = @vols.map { |v| "-v #{v} "}.join
        env   = @env.map  { |e| "-e #{e} "}.join
        priv  = @priv ? '--privileged' : ''
        kvm   = @kvm ? File.exists?("/dev/kvm") ? '--device /dev/kvm --device /dev/net/tun' : '--device /dev/net/tun' : ''
        devs  = @devs.map{ |d| "--device #{d} " }.join
        dns   = @dns.map { |ns| "nameserver #{ns}" }.join("\n")
        image = @image.nil? ? @defaults[@type][@kind]['image'] : @image
        @vols.each { |v| FileUtils.mkdir_p(v.split(':')[0]) }

        #
        # Arista Switch
        # 
        if(@kind == 'arista')
          #File.open("/tmp/#{@name}.startup-config", "w" ) do |f|
          File.exists?("/tmp/#{@name}") ? false : Dir.mkdir("/tmp/#{@name}")
          File.exists?("/tmp/#{@name}/flash") ? false : Dir.mkdir("/tmp/#{@name}/flash")
          File.open("/tmp/#{@name}/flash/startup-config", "w" ) do |f|
            f.write( ERB.new(startup_config, nil, '-').result(binding) )
          end
          File.open("/tmp/#{@name}/flash/if-wait.sh", "w") do |f|
            f.write( ERB.new(if_wait, nil, '-').result(binding) )
          end

          caps  = ''
          @env  = ['INTFTYPE=eth', 'ETBA=1', 'SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1', 'CEOS=1', 'EOS_PLATFORM=ceoslab', 'container=docker', 'MAPETH0=1', 'MGMT_INTF=eth0']
          env   = @env.map  { |e| "-e #{e} "}.join
          priv  = '--privileged'
          #vols << "-v /tmp/#{@name}.startup-config:/mnt/flash/startup-config:rw"
          vols << "-v /tmp/#{@name}/flash:/mnt/flash:rw,Z"
          @cmd  = "/bin/bash -c '/usr/bin/sleep 20; exec /sbin/init " +  @env.map { |e| "systemd.setenv=#{e} "}.join + "'"
          #@cmd  = "/bin/bash -c '/mnt/flash/if-wait.sh #{@nics.size}; exec /sbin/init " +  @env.map { |e| "systemd.setenv=#{e} "}.join + "'"
        end


        %x( docker run -itd --rm --hostname #{@fqdn} --name #{@name} --net none --cgroupns=private #{env} #{kvm} #{devs} #{priv} #{caps} #{vols} #{image} #{@cmd} 2>/dev/null )
        sleep 1
        @cid     = %x( docker ps --format '{{.ID}}' --filter name=#{@name} ).rstrip
        @cpid    = %x( docker inspect -f '{{.State.Pid}}' #{@cid} ).rstrip
        @inotify = %x( /usr/bin/printf "256" > /proc/sys/fs/inotify/max_user_instances )
        @vmem    = %x( /usr/bin/printf "262144" > /proc/sys/vm/max_map_count )
        %x( docker exec -it  #{@name} sh -c '/usr/bin/printf "domain #{@domain}\n#{dns}\noptions timeout:1 attempts:1\n" > /etc/resolv.conf' )
        @netns = add_netns
        #add_nics

        #
        # linux bridge
        #
        if(@type == 'switch' && [ 'linux', 'mgmt' ].include?(@kind) )
          @log.write "#{__method__}(): (switch) - adding bridge"

          %x( ip netns exec #{@netns} ip link ls #{@name} 2>/dev/null )
          if $?.exitstatus > 0
            %x( ip netns exec #{@netns} ip link add #{@name} type bridge )
            %x( ip netns exec #{@netns} ip link set #{@name} up )
            if(! @ipv4.nil? )
              %x( ip netns exec #{@netns} ip addr add #{@ipv4} dev #{@name} )
            end

            if(! @gw.nil? )
              %x( ip netns exec #{@netns} ip route add default via #{@gw} )
            end
          end
          #{}%x( ip netns exec #{@netns} ip link set #{@nic1} master #{@name} )

          if(@vxlan)
            remote, dport = @vxlan['remote'].split(':')
            dstport       = dport || 4789
            ipv4          = @ipv4.split('/')[0]

            @log.write "#{__method__}(): (switch) - adding vxlan interface vxlan#{@vxlan['id']}:#{ipv4} -> #{remote}:#{dstport}"
            %x( ip netns exec #{@netns} ip link add vxlan#{@vxlan['id']} type vxlan id #{@vxlan['id']} local #{ipv4} remote #{remote} dstport #{dstport} )
            %x( ip netns exec #{@netns} ip link set vxlan#{@vxlan['id']} master #{@name} up )

            #ipt_rule('insert', "PREROUTING -tnat -p udp -d #{@vxlan['local']} --dport #{@vxlan['lport']} -j DNAT --to-destination 192.168.40.2:#{@vxlan['lport']}")
            #ipt_rule('insert', "PREROUTING -tnat -p udp -d 192.168.40.2       --dport #{@vxlan['lport']} -j DNAT --to-destination #{@ipv4}:4789")
            # this needs to be done in the router container and on the host after 
            #ipt_rule('insert', "PREROUTING -tnat -p udp -d <HOST_IP>   --dport #{dstport} -j DNAT --to-destination <ROUTER_IP>:#{dstport}")
            #ipt_rule('insert', "PREROUTING -tnat -p udp -d <ROUTER_IP> --dport #{dstport} -j DNAT --to-destination <SWITCH_IP>:4789")
          end
        end

      when 'gateway'
        @log.write "#{__method__}(): (gateway) - adding gateway"
        %x( ip link ls #{@name} 2>/dev/null )
        if $?.exitstatus > 0 
          %x( ip link add #{@name} type bridge )
          %x( ip link set dev #{@name} up )
        end

        @ipv4 ? %x( ip addr add #{@ipv4} dev #{@name} 2>/dev/null ) : false
        ipt_rule('append', "FORWARD   -i #{@name} -o #{@name} -j ACCEPT")
        if(@snat)
          @log.write "#{__method__}(): (gateway) - set snat gateway"
          ipt_rule('append', "FORWARD ! -i #{@name}   -o #{@name} -j ACCEPT")
          ipt_rule('append', "FORWARD   -i #{@name} ! -o #{@name} -j ACCEPT")
          ipt_rule('insert', "POSTROUTING -tnat ! -o #{@name} -s #{@ipv4} -j MASQUERADE")
        end
        if(! @dnat.nil?)
          @log.write "#{__method__}(): (gateway) - dnatgw=#{@dnat}"
          #ro, nic = @dnat.split(':')
          #node = find_node(ro)
          #@via = node.nics[nic].split('/')[0]
        end

    end
  end

  def if_wait
    %{#!/bin/sh
INTFS=$1  #$(echo $CLAB_INTFS)
SLEEP=0
int_calc ()
{
    index=0
    for i in $(ls -1v /sys/class/net/ | grep -E '^et|^ens|^eno|^e[0-9]'); do
      let index=index+1
    done
    MYINT=$index
}
int_calc
echo "Waiting for all $INTFS interfaces to be connected"
while [ "$MYINT" -lt "$INTFS" ]; do
  echo "Connected $MYINT interfaces out of $INTFS"
  sleep 1
  int_calc
done
echo "Sleeping $SLEEP seconds before boot"
sleep $SLEEP
    }
  end

  def startup_config
    %{
      hostname <%= @name %>
      username admin privilege 15 secret admin

      service routing protocols model multi-agent
      !
      vrf instance MGMT
      !
      management api http-commands
         shutdown
         vrf MGMT
            no shutdown
      !
      management ssh
        shutdown
        vrf MGMT
          no shutdown
      !
      !
      no ip routing
      no ip routing vrf MGMT
      !
      ip route vrf MGMT 0.0.0.0/0 <%= @gw %>
      !
      <%- @nics.each do |nic| -%>
        <%- if nic[0] == 'eth0' -%>
      interface ma0
        vrf MGMT
        <%- else -%>
      interface <%= nic[0] %>
        <%- end -%>
        no shutdown
        <%- if nic[1] != '' -%>
        no switchport
        ip address <%= nic[1] %>
        <%- end -%>
      !
      <%- end -%>
      !
      ip routing
      !
      end
    }
  end

  def ipt_rule(mode, rule)
    @log.write "#{__method__}(): mode=#{mode},rule=#{rule}"

    %x( iptables -C #{rule} 2> /dev/null )
    if $?.exitstatus > 0
      case mode
        when 'append'
          %x( iptables -A #{rule} 2> /dev/null )
        when 'insert'
          %x( iptables -I #{rule} 2> /dev/null )
      end
    elsif $?.exitstatus == 0
      case mode
        when 'delete'
          %x( iptables -D #{rule} 2> /dev/null )
      end
    end
  end

  def add_netns
    @log.write "#{__method__}(): #{@cid}"

    #p "name: #{@name}, cid: #{@cid}, cpid: #{@cpid}"
    %x( mkdir -vp /var/run/netns/ )
    %x( ln -sfT /proc/#{@cpid}/ns/net /var/run/netns/#{@cid} )
    @cid
  end

  def stop
    @log.write "#{__method__}(): name=#{@name}"

    puts "#{__method__}(): #{@name}..."
    case @type
      when 'host', 'router', 'switch', 'controller'
        %x( docker stop #{@name} )
        del_netns
        if( @mgmt )
          ipt_rule('delete', "PREROUTING -tnat -p tcp --dport 2222 -j DNAT --to-destination #{@mgmt}")
        end
      when 'gateway'
        %x( ip link del #{@name} )
        ipt_rule('delete', "FORWARD   -i #{@name}   -o #{@name} -j ACCEPT")
        if(@snat)
          ipt_rule('delete', "FORWARD ! -i #{@name}   -o #{@name} -j ACCEPT")
          ipt_rule('delete', "FORWARD   -i #{@name} ! -o #{@name} -j ACCEPT")
          ipt_rule('delete', "POSTROUTING -tnat ! -o #{@name} -s #{@ipv4} -j MASQUERADE")
        end
        if(@vxlan)
          %x( ip link del vxlan#{@vxlan['id']} )
        end
    end
  end

  def del_netns
    %x( find /var/run/netns/ -xtype l -delete )
  end

end
