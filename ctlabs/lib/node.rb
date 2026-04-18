# -----------------------------------------------------------------------------
# File        : ctlabs/lib/node.rb
# Description : node class; describes the container
# License     : MIT License
# -----------------------------------------------------------------------------

require 'fileutils'

class Node
  attr_reader :name, :fqdn, :kind, :type, :image, :env, :cmd, :caps, :priv, :cid, :nics, :ports, :gw, :ipv4, :dnat, :snat, :vxlan, :netns, :eos, :bonds, :defaults, :via, :mtu, :dns, :mgmt, :devs, :play, :ephemeral, :info, :urls, :term, :terraform, :plane, :provider, :user, :peers
  attr_writer :nics
  attr_accessor :is_running

  def initialize(args)
    @defaults   = args['defaults']
    @name       = args['name' ]
    @ephemeral  = args['ephemeral'] || true
    @domain     = args['domain']    || "ctlabs.internal"
    @fqdn       = args['fqdn' ]     || "#{@name}.#{@domain}"
    @dns        = args['dns'  ]     || []
    @mgmt       = args['mgmt' ]
    @type       = args['type' ]
    @plane      = args['plane']     || (args['type'] == 'controller' ? 'mgmt' : 'data')
    @provider   = args['provider']  || 'local'
    @peers      = args['peers']     || args[:peers] || {}
    @eos        = args['eos'  ]     || 'linux'
    @kind       = args['profile' ]  || args['kind'] || 'linux'
    @kvm        = args['kvm'  ]     || false
    @image      = args['image']
    @env        = args['env'  ]     || []
    @cmd        = args['cmd'  ]
    @play       = args['play' ]
    @terraform  = args[:terraform]  || args['terraform']
    @nics       = args['nics' ]     || {}
    @bonds      = args['bonds']
    @ports      = args['ports']   # ||  @defaults[@type][@kind]['ports'] || 4
    @gw         = args['gw'   ]
    @ipv4       = args['ipv4' ]
    @snat       = args['snat' ]
    @vxlan      = args['vxlan']
    @dnat       = args['dnat' ]
    @mtu        = args['mtu'  ]     || 1460
    @priv       = args['priv' ]     || false
    @devs       = args['devs' ]     || []
    @info       = args[:info  ]     || args['info' ]
    @urls       = args[:urls  ]     || args['urls' ]
    @term       = args[:term  ]     || args['term' ]
    @is_running = false

    # --- NEW: Smart Ansible User Resolution ---
    parsed_user = args['user'] || args[:user]
    
    # Fallback 1: Check Profile defaults
    if (parsed_user.nil? || parsed_user.empty?) && @defaults && @defaults[@type] && @defaults[@type][@kind]
      parsed_user = @defaults[@type][@kind]['user']
    end

    # Fallback 2: Extract from SSH term string for remote nodes (e.g., ssh://ansible@1.2.3.4)
    if (parsed_user.nil? || parsed_user.empty?) && remote? && @term.to_s.start_with?('ssh://')
      require 'uri'
      parsed_user = URI.parse(@term).user rescue nil
    end

    # Fallback 3: Default to root for local containers
    @user = (parsed_user && !parsed_user.empty?) ? parsed_user : 'root'
    # ------------------------------------------

    dcaps       = [ 'NET_ADMIN', 'NET_RAW', 'SYS_ADMIN', 'AUDIT_WRITE', 'AUDIT_CONTROL' ]
    dvols       = [] # [ '/sys/fs/cgroup:/sys/fs/cgroup:ro' ]
    @caps       = (! args['caps'].nil?) ? args['caps'] + dcaps : dcaps
    @vols       = (! args['vols'].nil?) ? args['vols'] + dvols : dvols 

    @log = args['log'] || LabLog.null
    @log.write "== Node ==", "debug"
    @log.write "#{__method__}(): name=#{@name},fqdn=#{@fqdn},eos=#{@eos},kind=#{@kind},kvm=#{@kvm},type=#{@type},image=#{@image},env=#{@env},cmd=#{@cmd},nics=#{@nics},ports=#{@ports},gw=#{@gw},ipv4=#{@ipv4},mgmt=#{@mgmt},snat=#{@snat},vxlan=#{@vxlan},dnat=#{@dnat},mtu=#{@mtu},priv=#{@priv},caps=#{@caps},vols=#{@vols},defaults=#{@defaults}", "debug"

    case @type
      when 'switch', 'router', 'host', 'controller'
       @defaults ||= {}
        type_defs = @defaults[@type] || {}
        kind_defs = type_defs[@kind] || {}
        
        @caps  = @caps + kind_defs['caps'] if kind_defs['caps']
        @ports = @ports || kind_defs['ports'] || 4
        @devs  = kind_defs['devs'] || @devs
      when 'gateway'
        @ports = @ports || 2
#        @caps  = (!@defaults[@type][@kind]['caps' ].nil?) ? @caps + @defaults[@type][@kind]['caps' ] : @caps
#        @ports = @ports.nil?  && (!@defaults[@type][@kind]['ports'].nil?) ? @defaults[@type][@kind]['ports'] : @ports || 4
#        @devs  = (!@defaults[@type][@kind]['devs'].nil?)  ? @defaults[@type][@kind]['devs'] : @devs
#      when 'gateway'
#        @ports = @ports.nil? ? 2 : @ports
    end

    switch_ports
  end

  # set max ports of a switch
  def switch_ports
    @log.write "#{__method__}(): ports=#{@ports}", "debug"

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

  def remote?
    ['gcp', 'external', 'aws', 'azure'].include?(@provider.to_s.downcase) || ['rhost', 'external'].include?(@type.to_s.downcase)
  end

  # CLASS METHOD: Solves the N+1 problem by doing one master check
  def self.bulk_update_status(nodes)
    return if nodes.empty?

    podman_running = `podman ps --format '{{.Names}}' 2>/dev/null`.split("\n").map(&:strip)
    docker_running = `docker ps --format '{{.Names}}' 2>/dev/null`.split("\n").map(&:strip)
    active_containers = (podman_running + docker_running).uniq

    require 'socket'

    nodes.each do |node|
      # 1. Abstract Overlays are always "Running" conceptually
      if node.type == 'tunnel' && ['openvpn', 'wireguard', 'ipsec'].include?(node.provider.to_s.downcase)
        node.is_running = true

      # 2. Local Gateways (NAT bridges): Check if the network interface exists on the host
      elsif node.type == 'gateway' && node.provider.to_s.downcase == 'local'
        node.is_running = Socket.getifaddrs.any? { |iface| iface.name == node.name }

      # 3. Remote hosts: Use native Ruby Socket
      elsif node.remote?
        string_nics = (node.nics || {}).transform_keys(&:to_s)
        raw_ip = string_nics['eth0'] || node.gw || string_nics['eth1'] || string_nics['tun0']
        ip = raw_ip.to_s.split('/').first.to_s.strip

        if ip && !ip.empty?
          begin
            Socket.tcp(ip, 22, connect_timeout: 1.5) { |sock| true }
            node.is_running = true
          rescue StandardError
            node.is_running = false
          end
        else
          node.is_running = false
        end

      # 4. Local nodes check the container engine
      else
        node.is_running = active_containers.include?(node.name)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helper: Parse Form Data (Moved from LabHelper)
  # ---------------------------------------------------------------------------
  def self.parse_form_data(params, base_data = {})
    new_cfg         = base_data.dup

    new_cfg['type'] = params[:type] unless params[:type].to_s.empty?
    params[:plane].to_s.empty?    ? new_cfg.delete('plane')    : new_cfg['plane']    = params[:plane]
    params[:profile].to_s.empty?  ? new_cfg.delete('profile')  : new_cfg['profile']  = params[:profile]
    params[:provider].to_s.empty? ? new_cfg.delete('provider') : new_cfg['provider'] = params[:provider]
    params[:gw].to_s.empty?       ? new_cfg.delete('gw')       : new_cfg['gw']       = params[:gw]
    params[:info].to_s.empty?     ? new_cfg.delete('info')     : new_cfg['info']     = params[:info]
    params[:term].to_s.empty?     ? new_cfg.delete('term')     : new_cfg['term']     = params[:term]

    if params[:nics] && !params[:nics].strip.empty?
      new_cfg['nics'] = params[:nics].split("\n").map { |l| l.split('=').map(&:strip) }.to_h.reject { |k,v| k.nil? || v.nil? }
    else
      new_cfg.delete('nics')
    end

    if params[:urls_text] && !params[:urls_text].strip.empty?
      urls_hash = {}
      params[:urls_text].split("\n").each do |line|
        title, link = line.split('|', 2)
        urls_hash[title.strip] = link.strip if title && !title.strip.empty? && link && !link.strip.empty?
      end
      new_cfg['urls'] = urls_hash unless urls_hash.empty?
    else
      new_cfg.delete('urls')
    end

    ['vols', 'env', 'devs'].each do |field|
      if params[field] && !params[field].strip.empty?
        new_cfg[field] = params[field].split("\n").map(&:strip).reject(&:empty?)
      else
        new_cfg.delete(field)
      end
    end

    # --- PARSE TERRAFORM CONFIG ---
    if params[:terraform] && !params[:terraform].strip.empty?
      require 'json'
      begin
        new_cfg['terraform'] = JSON.parse(params[:terraform])
      rescue JSON::ParserError
        # Silently ignore bad JSON payloads
      end
    else
      new_cfg.delete('terraform')
    end

    new_cfg
  end

  # ---------------------------------------------------------------------------
  # Helper: Auto-Assign Management IP (Moved from LabHelper)
  # ---------------------------------------------------------------------------
  def self.auto_assign_mgmt_ip!(node_cfg, full_yaml)
    target_nic = (node_cfg['provider'] && node_cfg['provider'] != 'local') ? 'tun0' : 'eth0'
    node_cfg['nics'] ||= {}

    if node_cfg['nics'][target_nic].to_s.empty?
      mgmt_net_str = full_yaml.dig('topology', 0, 'planes', 'mgmt', 'net') || full_yaml.dig('topology', 0, 'mgmt', 'net') || "192.168.99.0/24"
      used_ips = []

      vm = full_yaml['topology'][0]
      nodes_to_scan = vm['planes'] ? vm['planes'].values.map { |p| p['nodes'] } : [vm['nodes']]

      nodes_to_scan.compact.each do |node_group|
        node_group.each do |_, n|
          n['nics']&.values&.each { |ip| used_ips << ip.split('/')[0] if ip }
          used_ips << n['ipv4'].split('/')[0] if n['ipv4'] && !n['ipv4'].to_s.empty?
        end
      end

      require 'ipaddr'
      begin
        subnet = IPAddr.new(mgmt_net_str)
        ip_range = subnet.to_range.to_a
        start_idx = [20, ip_range.size - 2].min
        next_ip = ip_range[start_idx..-2].find { |ip| !used_ips.include?(ip.to_s) }

        if next_ip
          node_cfg['nics'][target_nic] = "#{next_ip}/#{subnet.prefix}"
        end
      rescue => e
        puts "[IP Calc Error] Could not auto-calculate IP: #{e.message}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helper: Schema Validation (Block undefined profiles) - Moved from LabHelper
  # ---------------------------------------------------------------------------
  def self.validate_profile!(node_cfg, full_yaml)
    type = node_cfg['type'] || 'host'
    profile = node_cfg['profile'] || node_cfg['kind']

    # Only validate if a profile is explicitly requested
    return if profile.nil? || profile.to_s.strip.empty?

    # 1. Check local lab overrides first
    profile_key = full_yaml.key?('profiles') ? 'profiles' : 'defaults'
    return if full_yaml.dig(profile_key, type, profile)

    # 2. Check the global profiles dictionary
    global_profiles_path = defined?(::GLOBAL_PROFILES) ? ::GLOBAL_PROFILES : File.expand_path('../../../labs/node_profiles.yml', __FILE__)
    if File.exist?(global_profiles_path)
      global_yaml = YAML.load_file(global_profiles_path) || {}
      global_key = global_yaml.key?('profiles') ? 'profiles' : 'defaults'
      
      return if global_yaml.dig(global_key, type, profile)
    end

    # 3. If it's in neither place, block it!
    raise "Schema Error: Profile '#{profile}' is not defined for type '#{type}'. Please create it in the global config/profiles.yml file or override it in this lab."
  end

  # ---------------------------------------------------------------------------
  # Helper: Sync Node to Terraform config.yml (Text-Based) - Moved from LabHelper
  # ---------------------------------------------------------------------------
  def self.sync_to_terraform!(node_name, node_cfg, full_lab_yaml, cloud_vm_yaml_payload)
    return unless node_cfg['provider'].to_s.downcase == 'gcp'
    return if cloud_vm_yaml_payload.nil? || cloud_vm_yaml_payload.strip.empty?

    vm_topology = full_lab_yaml['topology']&.first || {}
    ctrl_node, _ = Lab.find_node_in_raw_yaml(vm_topology, 'ansible')
    ctrl_node ||= Lab.find_node_in_raw_yaml(vm_topology, 'controller').first
    
    work_dir = ctrl_node&.dig('terraform', 'work_dir')
    return if work_dir.nil? || work_dir.strip.empty?

    config_path = "/root/ctlabs-terraform/#{work_dir}/config.yml"
    
    unless File.exist?(config_path)
      puts "[Warning] config.yml not found at #{config_path}. Cannot save Cloud VM snippet."
      return
    end

    # --- INDENTATION NORMALIZER ---
    lines = cloud_vm_yaml_payload.rstrip.lines
    first_line_indent = lines.first[/\A\s*/].length
    
    payload = lines.map do |line|
      unindented = line.sub(/\A\s{0,#{first_line_indent}}/, '')
      "  #{unindented}"
    end.join + "\n"
    # ------------------------------

    content = File.read(config_path)

    regex = /^(\s*)-\s*name\s*:\s*#{Regexp.escape(node_name)}\b.*?(?=(^\s*-\s*name\s*:|^\S|\z))/m

    if content.match?(regex)
      content.sub!(regex, payload)
    else
      if content.match?(/^vms:\s*$/)
        content.sub!(/^vms:\s*$/, "vms:\n" + payload)
      else
        content += "\n\nvms:\n" + payload
      end
    end

    File.write(config_path, content)
    puts "[SUCCESS] Updated #{node_name} in #{config_path}"
  end

  # ---------------------------------------------------------------------------
  # Helper: Remove Node from Terraform config.yml - Moved from LabHelper
  # ---------------------------------------------------------------------------
  def self.remove_from_terraform!(node_name, full_lab_yaml)
    vm_topology = full_lab_yaml['topology']&.first || {}
    ctrl_node, _ = Lab.find_node_in_raw_yaml(vm_topology, 'ansible')
    ctrl_node ||= Lab.find_node_in_raw_yaml(vm_topology, 'controller').first
    
    work_dir = ctrl_node&.dig('terraform', 'work_dir')
    return if work_dir.nil? || work_dir.strip.empty?

    config_path = "/root/ctlabs-terraform/#{work_dir}/config.yml"
    return unless File.exist?(config_path)

    tf_config = YAML.load_file(config_path) || {}
    if tf_config['vms']
      tf_config['vms'].reject! { |v| v['name'] == node_name }
      File.write(config_path, tf_config.to_yaml)
    end
  end

  # Ping the node (Moved from nodes route)
  def ping
    return true if @type == 'tunnel' && ['openvpn', 'wireguard', 'ipsec'].include?(@provider.to_s.downcase)

    string_nics = (@nics || {}).transform_keys(&:to_s) rescue @nics
    raw_ip = string_nics['eth0'] || @gw || string_nics['eth1'] || string_nics['tun0']
    target_ip = raw_ip.to_s.split('/').first.to_s.strip

    return false if target_ip.empty?

    begin
      require 'socket'
      require 'timeout'
      Timeout.timeout(1.0) do
        Socket.tcp(target_ip, 22, connect_timeout: 1.0) { |_| true }
      end
      true
    rescue StandardError
      false
    end
  end

  # INSTANCE METHOD: Single check
  def running?
    require 'socket'
    
    if @type == 'tunnel' && ['openvpn', 'wireguard', 'ipsec'].include?(@provider.to_s.downcase)
      return true
      
    # Local Gateway Check
    elsif @type == 'gateway' && @provider.to_s.downcase == 'local'
      return Socket.getifaddrs.any? { |iface| iface.name == @name }

    elsif remote?
      string_nics = (@nics || {}).transform_keys(&:to_s)
      raw_ip = string_nics['eth0'] || @gw || string_nics['eth1'] || string_nics['tun0']
      ip = raw_ip.to_s.split('/').first.to_s.strip

      return false if ip.empty?

      begin
        Socket.tcp(ip, 22, connect_timeout: 1.5) { |sock| true }
        return true
      rescue StandardError
        return false
      end
      
    else
      engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
      system("#{engine} inspect -f '{{.State.Running}}' #{@name} >/dev/null 2>&1")
    end
  end

  def run
    @log.write "#{__method__}(): name=#{@name}", "debug"

    @log.info "#{__method__}(): #{@name}"
    case @type
      when 'host', 'router', 'switch', 'controller'
        @env << "CTLABS_PLANE=#{@plane}" unless @env.any? { |e| e.start_with?('CTLABS_PLANE=') }

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
            f.write( ERB.new(startup_config, trim_mode:'-').result(binding) )
          end
          File.open("/tmp/#{@name}/flash/if-wait.sh", "w") do |f|
            f.write( ERB.new(if_wait, trim_mode:'-').result(binding) )
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


        #%x( docker run -d #{@ephemeral ? "--rm" : ""} --hostname #{@fqdn} --name #{@name} --net none --cgroupns=private #{env} #{kvm} #{devs} #{priv} #{caps} #{vols} #{image} #{@cmd} 2>/dev/null )
        %x( docker run -d --rm --hostname #{@fqdn} --name #{@name} --net none --cgroupns=private #{env} #{kvm} #{devs} #{priv} #{caps} #{vols} #{image} #{@cmd} 2>/dev/null )
        sleep 1
        @cid     = %x( docker ps --format '{{.ID}}' --filter name=#{@name} ).rstrip
        @cpid    = %x( docker inspect -f '{{.State.Pid}}' #{@cid} ).rstrip
        @inotify = %x( /usr/bin/printf "256" > /proc/sys/fs/inotify/max_user_instances )
        @vmem    = %x( /usr/bin/printf "262144" > /proc/sys/vm/max_map_count )
        %x( docker exec #{@name} sh -c '/usr/bin/printf "domain #{@domain}\n#{dns}\noptions timeout:1 attempts:1\n" > /etc/resolv.conf' )
        @netns = add_netns
        #add_nics

        #
        # linux bridge
        #
        if(@type == 'switch' && [ 'linux', 'mgmt' ].include?(@kind) )
          @log.write "#{__method__}(): (switch) - adding bridge", "debug"

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

            @log.write "#{__method__}(): (switch) - adding vxlan interface vxlan#{@vxlan['id']}:#{ipv4} -> #{remote}:#{dstport}", "debug"
            %x( ip netns exec #{@netns} ip link add vxlan#{@vxlan['id']} type vxlan id #{@vxlan['id']} local #{ipv4} remote #{remote} dstport #{dstport} )
            %x( ip netns exec #{@netns} ip link set vxlan#{@vxlan['id']} master #{@name} up )

            #ipt_rule('insert', "PREROUTING -tnat -p udp -d #{@vxlan['local']} --dport #{@vxlan['lport']} -j DNAT --to-destination 192.168.40.2:#{@vxlan['lport']}")
            #ipt_rule('insert', "PREROUTING -tnat -p udp -d 192.168.40.2       --dport #{@vxlan['lport']} -j DNAT --to-destination #{@ipv4}:4789")
            # this needs to be done in the router container and on the host after 
            #ipt_rule('insert', "PREROUTING -tnat -p udp -d <HOST_IP>   --dport #{dstport} -j DNAT --to-destination <ROUTER_IP>:#{dstport}")
            #ipt_rule('insert', "PREROUTING -tnat -p udp -d <ROUTER_IP> --dport #{dstport} -j DNAT --to-destination <SWITCH_IP>:4789")
          end
        end

        #
        # openvswitch
        #
        if(@type == 'switch' && [ 'ovs' ].include?(@kind) )
          @log.write "#{__method__}(): (switch) - adding openvswitch", "debug"

          # check if kernel module was loaded
          res = %x(modprobe openvswitch)
          if $?.exitstatus > 0
            @log.write "#{__method__}(): ERROR: #{res}", error
            @log.info "ERROR: #{res}"
            exit(1)
          end

          %x( ip netns exec #{@netns} ip link ls #{@name} 2>/dev/null )
          if $?.exitstatus > 0
            %x( docker exec #{@name} sh -c '/usr/bin/ovs-vsctl add-br #{@name}' )
           # if(! @ipv4.nil? )
           #   %x( ip netns exec #{@netns} ip addr add #{@ipv4} dev #{@name} )
           # end

           # if(! @gw.nil? )
           #   %x( ip netns exec #{@netns} ip route add default via #{@gw} )
           # end
          end
        end

      when 'gateway'
        @log.write "#{__method__}(): (gateway) - adding gateway", "debug"
        %x( ip link ls #{@name} 2>/dev/null )
        if $?.exitstatus > 0 
          %x( ip link add #{@name} type bridge )
          %x( ip link set dev #{@name} up )
        end

        @ipv4 ? %x( ip addr add #{@ipv4} dev #{@name} 2>/dev/null ) : false
        ipt_rule('append', "FORWARD   -i #{@name} -o #{@name} -j ACCEPT")
        if(@snat)
          @log.write "#{__method__}(): (gateway) - set snat gateway", "debug"
          ipt_rule('append', "FORWARD ! -i #{@name}   -o #{@name} -j ACCEPT")
          ipt_rule('append', "FORWARD   -i #{@name} ! -o #{@name} -j ACCEPT")
          ipt_rule('insert', "POSTROUTING -tnat ! -o #{@name} -s #{@ipv4} -j MASQUERADE")
        end
        if(! @dnat.nil?)
          @log.write "#{__method__}(): (gateway) - dnatgw=#{@dnat}", "debug"
          #ro, nic = @dnat.split(':')
          #node = find_node(ro)
          #@via = node.nics[nic].split('/')[0]
        end

    end
  end

  def resolve_runtime!
    return if remote? || @type == 'gateway'
    
    # Guarantee MTU is present
    @mtu = 1460 if @mtu.nil? || @mtu.to_s.strip.empty?
    
    # Recover the Container ID so we can find the existing network namespace symlink
    if @netns.nil? || @netns.to_s.strip.empty?
      engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
      cid = %x( #{engine} inspect -f '{{.Id}}' #{@name} 2>/dev/null ).strip
      
      if !cid.empty?
        @cid = cid
        @netns = cid # ctlabs uses the container ID for the netns symlink

        # Safeguard: Recreate the symlink just in case it was lost
        cpid = %x( #{engine} inspect -f '{{.State.Pid}}' #{@name} 2>/dev/null ).strip
        if !cpid.empty? && cpid != '0'
          %x( mkdir -vp /var/run/netns/ 2>/dev/null )
          %x( ln -sfT /proc/#{cpid}/ns/net /var/run/netns/#{@cid} 2>/dev/null )
        end
      end
    end
  end

  def hotplug_ip(nic, ip)
    resolve_runtime!
    return false if remote? || @type == 'gateway' || @netns.nil? || @netns.to_s.empty?

    @log.info "[HOTPLUG] Configuring #{nic} with #{ip} on #{@name}"
    system("ip netns exec #{@netns} ip link set #{nic} up 2>/dev/null")
    system("ip netns exec #{@netns} ip addr flush dev #{nic} 2>/dev/null")
    success = system("ip netns exec #{@netns} ip addr add #{ip} dev #{nic} 2>/dev/null")
    
    @log.info "[HOTPLUG] Failed to assign IP to #{nic}" unless success
    success
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
    @log.write "#{__method__}(): mode=#{mode},rule=#{rule}", "debug"

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
    @log.write "#{__method__}(): #{@cid}", "debug"

    #p "name: #{@name}, cid: #{@cid}, cpid: #{@cpid}"
    %x( mkdir -vp /var/run/netns/ )
    %x( ln -sfT /proc/#{@cpid}/ns/net /var/run/netns/#{@cid} )
    @cid
  end

  def stop
    @log.write "#{__method__}(): name=#{@name}", "debug"

    @log.info "#{__method__}(): #{@name}..."
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
