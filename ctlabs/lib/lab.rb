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
require_relative 'gcp_auth'
require_relative 'cloud'

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

  # Host public ports reserved for the persistent controller / shared services.
  # DNAT is host iptables on the host public IP, and the controller is always
  # on; a workload lab whose ext_port lands here would shadow a controller
  # service. The single-lab lock means at most one workload lab runs at a time,
  # so lab-vs-lab collisions can't happen -- only lab-vs-controller. Chosen clear
  # of every ext_port labs use today (8xxx services, 9888/9920/9988, 18788-18799).
  RESERVED_DNAT_RANGE = (8400..8499).freeze

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
    # standalone: this Lab is the persistent control-plane controller, not a
    # user lab. It must NOT take the single-lab lock (or no workload lab could
    # run) and must NOT overwrite the webgui's public config. See Controller.
    @standalone    = args[:standalone] || false

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
      # ${ctlabs_host} -> this lab server's public IP, and ${node:...} ->
      # attributes of another node in THIS file (see Lab.expand_placeholders).
      # The latter is what lets a tunnel endpoint stay configurable: the cloud
      # gateway's public IP is written back into the lab YAML by the terraform
      # IP harvest, and ro1's `remote:` picks it up from here on the next load.
      expanded_yaml = self.class.expand_placeholders(raw_yaml, @server_ip, @log)
      
      # Write the EXPANDED config to the public dir so the frontend UI gets the real IPs
      # (skipped in standalone/controller mode, which must not clobber a lab's config)
      unless @standalone
        File.open("#{@pubdir}/config.yml", 'w') do |f|
          f.write(expanded_yaml)
        end
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
    labs_dir = defined?(::LABS_DIR) ? ::LABS_DIR : File.expand_path('../../labs', __dir__)
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
    labs_dir     = defined?(::LABS_DIR) ? ::LABS_DIR : File.expand_path('../../labs', __dir__)
    runtime_path = get_runtime_path(lab_name)
    (running? && current_name == lab_name && File.file?(runtime_path)) ? runtime_path : File.join(labs_dir, lab_name)
  end

  # Resolve a user-supplied lab name to its canonical relative path (with the
  # `.yml` suffix). Accepts:
  #   'net/net01'      -> 'net/net01.yml'   (relative path, no extension)
  #   'net/net01.yml'  -> 'net/net01.yml'   (already canonical)
  #   'net01'          -> 'net/net01.yml'   (unique basename fallback)
  # Returns the input unchanged when nothing matches, so callers still surface a
  # "not found" error for exactly what the user typed.
  def self.resolve_name(name)
    name = name.to_s
    return name if name.empty?

    labs_dir = defined?(::LABS_DIR) ? ::LABS_DIR : File.expand_path('../../labs', __dir__)
    with_yml = name.end_with?('.yml') ? name : "#{name}.yml"

    return with_yml if File.file?(File.join(labs_dir, with_yml))
    return name if name.end_with?('.yml') # canonical but missing -> let caller report it

    matches = all.select { |l| File.basename(l) == with_yml }
    matches.size == 1 ? matches.first : name
  end

  # Human-facing lab name: drop the trailing `.yml` (e.g. 'net/net01.yml' ->
  # 'net/net01'). Display-only — never feed this back into path lookups.
  def self.display_name(name)
    name.to_s.sub(/\.yml\z/, '')
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
  # Reconcile / GC: reap HOST-scoped leftovers from labs that died without a
  # clean `down`. Container netns destruction does not reliably cascade to the
  # host side, so two things leak: the per-lab `<LAB>-DNAT` iptables chain (+
  # its PREROUTING jumps) and the host veth endpoints `<node><nic>`. A lab's own
  # `down` reaps its own; this sweeps everything else. It never touches the
  # running lab or the controller's own chain/interfaces.
  #
  # This is deliberately a name/ownership sweep, not state-based: the leftover
  # resources themselves are the durable record, so a crashed lab is reaped
  # identically to one that was never started.
  # ---------------------------------------------------------------------------
  def self.gc(out = $stdout, dry_run: false)
    running_rel  = running? ? current_name : nil
    running_name = nil

    live_ifaces = {}
    live_chains = ['CTLABS-CONTROLLER-DNAT']
    if running_rel
      begin
        rl = Lab.new(cfg: get_file_path(running_rel), relative_path: running_rel, log: LabLog.null)
        running_name = rl.name.to_s
        live_ifaces.merge!(link_endpoint_ifaces(rl.links))
        live_chains << "#{rl.name.to_s.upcase}-DNAT"
      rescue => e
        # FAIL-SAFE: without the running lab's endpoint set we cannot tell a
        # live interface from a leftover, and another dead lab may reuse the
        # same `<node><nic>` names. Refuse to touch anything rather than risk
        # tearing down the live lab.
        out.puts "  ! could not load running lab #{running_rel}: #{e.message}"
        out.puts "gc: aborted (running lab not resolvable; refusing to reap)"
        return { chains: 0, ifaces: 0, zones: 0, aborted: true }
      end
    end

    reaped = { chains: 0, ifaces: 0, zones: 0 }

    all.each do |rel|
      next if rel == running_rel
      path = get_file_path(rel)
      cfg  = (YAML.load_file(path) rescue nil)
      next unless cfg.is_a?(Hash) && cfg['name'] && cfg['topology']
      name  = cfg['name'].to_s
      chain = "#{name.upcase}-DNAT"

      if !live_chains.include?(chain) && dnat_chain_exists?(chain)
        reap_dnat_chain(chain, out, dry_run)
        reaped[:chains] += 1
      end

      begin
        lab = Lab.new(cfg: path, relative_path: rel, log: LabLog.null)
        link_endpoint_ifaces(lab.links).each_key do |ifn|
          next if live_ifaces[ifn]
          next unless host_interface_exists?(ifn)
          out.puts(dry_run ? "  would delete host iface #{ifn} (#{name})" : "  delete host iface #{ifn} (#{name})")
          %x( ip link delete #{ifn} 2>/dev/null ) unless dry_run
          reaped[:ifaces] += 1
        end
      rescue => e
        out.puts "  ! could not load #{rel}: #{e.message}"
      end
    end

    reaped[:zones] = reap_stale_dnsmasq_zones(running_name, out, dry_run)

    out.puts "gc: #{reaped[:chains]} orphan DNAT chain(s), #{reaped[:ifaces]} orphan host interface(s), #{reaped[:zones]} stale dnsmasq zone(s)#{dry_run ? ' (dry-run)' : ''}"
    reaped
  end

  # Reap stale per-lab dnsmasq zones from the persistent controller. A lab's
  # zone is "<lab>.conf" (Graph#to_dnsmasq); deploy_dnsmasq installs it on `up`
  # and remove_lab_dnsmasq drops it on `down`. A crash -- or the old
  # deploy-on-view bug -- could leave a zone behind, which then resolves reused
  # node names to a dead lab's addresses (see design-guide.md sec.12.9). Only
  # the persistent controller leaks these (an in-lab controller dies with its
  # lab), so we target ctl-ctrl and keep its own files (00-listen.conf + the
  # controller plane's ctlabs-controller.conf) plus the running lab's zone.
  # Conservative: never removes a file it cannot positively classify as stale.
  def self.reap_stale_dnsmasq_zones(running_name, out, dry_run)
    return 0 unless defined?(Controller) && Controller.respond_to?(:running?) && Controller.running?

    engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
    keep   = ['00-listen.conf', 'ctlabs-controller.conf']
    keep  << "#{running_name}.conf" if running_name && !running_name.empty?

    confs = %x( #{engine} exec #{Controller::NAME} ls -1 /etc/dnsmasq.d/ 2>/dev/null )
              .lines.map(&:strip).reject(&:empty?)
    stale = confs.select { |f| f.end_with?('.conf') && !keep.include?(f) }
    return 0 if stale.empty?

    stale.each do |f|
      out.puts(dry_run ? "  would delete stale dnsmasq zone #{f}" : "  delete stale dnsmasq zone #{f}")
    end
    unless dry_run
      rm = stale.map { |f| "rm -f /etc/dnsmasq.d/#{f}" }.join(' && ')
      %x( #{engine} exec #{Controller::NAME} sh -c '#{rm} && systemctl restart dnsmasq' 2>/dev/null )
    end
    stale.length
  end

  # Map a lab's `@links` endpoints to the HOST interface names they create
  # (`<node><nic>`, e.g. "ro1:eth2" -> "ro1eth2").
  def self.link_endpoint_ifaces(links)
    ifaces = {}
    links.each do |ep1, ep2|
      [ep1, ep2].compact.each do |ep|
        node_name, nic = ep.to_s.split(':', 2)
        next if node_name.to_s.empty? || nic.to_s.empty?
        ifaces["#{node_name}#{nic}"] = true
      end
    end
    ifaces
  end

  def self.dnat_chain_exists?(chain)
    system("iptables -tnat -S #{chain} >/dev/null 2>&1")
  end

  def self.reap_dnat_chain(chain, out, dry_run)
    out.puts(dry_run ? "  would reap DNAT chain #{chain}" : "  reap DNAT chain #{chain}")
    return if dry_run
    %x( iptables -tnat -S PREROUTING 2>/dev/null ).each_line do |l|
      next unless l.include?("-j #{chain}")
      %x( iptables -tnat -D #{l.sub(/-A\s+/, '').strip} 2>/dev/null )
    end
    %x( iptables -tnat -F #{chain} 2>/dev/null )
    %x( iptables -tnat -X #{chain} 2>/dev/null )
  end

  # IFNAMSIZ: host-side veth names are `<node><nic>` and capped at 15 chars; a
  # longer name was silently truncated at creation, so it can never match here.
  def self.host_interface_exists?(ifn)
    return false if ifn.to_s.empty? || ifn.length > 15
    system("ip link show #{ifn} >/dev/null 2>&1")
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

  # ---------------------------------------------------------------------------
  # Placeholder expansion — ${...}
  #
  # Runs on the RAW yaml text, before the config is parsed, because the values
  # it substitutes (a cloud gateway's public IP) are themselves only present in
  # the raw file — the IP harvest in Automation#run_terraform writes nics/term
  # back to the lab YAML, and this expansion is what makes those harvested
  # values reach a *different* node's config (e.g. ro1's openvpn `remote:`,
  # which needs gcp-gw's public IP — see design-guide.md sec.12).
  #
  # Grammar (deliberately tiny, no nested/expressions):
  #
  #   ${ctlabs_host}                host public IP of the lab server (legacy)
  #   ${node:<name>}                <name>'s address (see resolution order below)
  #   ${node:<name>:<attr>}         one attribute of <name>
  #   ${node:<name>:<attr>[:<idx>]} index into a list attribute (default 0)
  #
  # Attribute lookup walks the SAME shapes the rest of the code does, so nothing
  # new has to be learned:
  #
  #   1. `nics.<attr>`            e.g. ${node:gcp-gw:nics.eth0}      -> 35.1.2.3
  #                               dotted sub-keys work: nics.eth0.ip
  #   2. top-level key            e.g. ${node:natgw:ipv4}            -> 192.168.15.1
  #   3. `terraform.<attr>`       e.g. ${node:gcp-gw:terraform.work_dir}
  #
  # IP semantics: a value like `192.168.15.1/29` or `35.1.2.3/32` yields the
  # ADDRESS ONLY (CIDR stripped) — endpoints never want the prefix length. Use
  # the `<attr>[:<idx>]` form on a list-valued attribute when several addresses
  # share a key.
  #
  # Unknown placeholders are left VERBATIM (loud in the generated YAML, and the
  # role fails visibly) rather than silently emptied — a tunnel with a blank
  # `remote` is much harder to diagnose than one with a literal `${...}` in it.
  # ---------------------------------------------------------------------------
  PLACEHOLDER_RE = /\$\{([^}]*)\}/.freeze

  def self.expand_placeholders(raw_yaml, server_ip, log = nil)
    return raw_yaml if raw_yaml.nil?

    # Parse once, up front, from the raw (still-unexpanded) text. Placeholders
    # are only ever in the lab file itself, never in the values we read back
    # out of it, so no recursion or re-expansion pass is needed.
    cfg = begin
      YAML.safe_load(raw_yaml, aliases: true)
    rescue Psych::Exception => e
      log&.write "expand_placeholders(): YAML parse failed (#{e.message}); no expansion", 'warn'
      nil
    end

    # Expand line by line so YAML COMMENTS are left completely alone: a comment
    # documenting a placeholder (cloud01.yml explains ${gcp_gw_ip} in prose) must
    # neither be rewritten nor warn. A `#` inside a quoted scalar (e.g. a
    # password) is not a comment, but a placeholder there is a configuration
    # mistake anyway — verbatim is the safe outcome either way.
    raw_yaml.lines.map do |line|
      if line.lstrip.start_with?('#')
        line
      else
        line.gsub(PLACEHOLDER_RE) do
          # `Regexp.last_match` is clobbered by ANY nested regex op (the `match`
          # below, in particular), so capture everything we need from THIS match
          # first — the full token text included, for the verbatim fallbacks.
          whole = Regexp.last_match(0)
          token = Regexp.last_match(1).strip

          if token == 'ctlabs_host'
            server_ip
          elsif (m = token.match(/\Anode:([^:\s]+)(?::([^:\s]+))?(?::(\d+))?\z/))
            name, attr, idx = m[1], m[2], (m[3] || '0').to_i
            resolved = cfg && self.resolve_node_attr(cfg, name, attr, idx)
            if resolved.nil?
              log&.write "expand_placeholders(): ${#{token}} -> unresolved " \
                         "(node=#{name} attr=#{attr || '(address)'}); left verbatim", 'warn'
              whole
            else
              resolved
            end
          else
            log&.write "expand_placeholders(): unknown placeholder ${#{token}}; left verbatim", 'warn'
            whole
          end
        end
      end
    end.join
  end

  # Resolves one `${node:...}` reference against a RAW lab config hash (the
  # `topology` shape, planes included — works before and after `find_vm`'s
  # in-memory flattening, since find_node_in_raw_yaml handles both).
  # `attr` nil => "the node's address", i.e. the most useful single value:
  # nics.eth0, else nics.eth1, else nics.tun0, else top-level ipv4, else gw.
  def self.resolve_node_attr(cfg, node_name, attr = nil, idx = 0)
    vm = (cfg['topology'] || [])[0]
    return nil unless vm

    node_cfg, = find_node_in_raw_yaml(vm, node_name)
    return nil unless node_cfg

    # Dotted path (`nics.eth0`, `terraform.work_dir`) walked segment by segment.
    value =
      if attr.nil?
        %w[eth0 eth1 tun0 wg0].map { |n| node_cfg.dig('nics', n) }
                              .compact.first ||
          node_cfg['ipv4'] || node_cfg['gw']
      else
        segments = attr.split('.')
        segments.reduce(node_cfg) do |acc, key|
          break nil unless acc.is_a?(Hash)
          acc[key]
        end
      end

    value = Array(value)[idx] if value.is_a?(Array)
    return nil if value.nil?

    # Strip CIDR — an endpoint address is never written with a prefix length.
    value.to_s.split('/').first.to_s.strip
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

  # ---------------------------------------------------------------------------
  # Role-based node lookup (replaces hard-coded sw0/ro0/natgw literals).
  # The mgmt switch/router and the NAT gateway are identified by ROLE, not by
  # their historical names, so a second lab-shaped topology (e.g. the persistent
  # controller plane) can use ctl-* names and coexist with a workload lab.
  # Names remain the fallback for schema-compatibility (see design-guide.md).
  # ---------------------------------------------------------------------------
  def mgmt_plane_key
    planes = @cfg.dig('topology', 0, 'planes') || {}
    return 'mgmt' if planes.key?('mgmt')
    ctl = @nodes.find { |n| n.type == 'controller' }
    ctl ? ctl.plane : 'mgmt'
  end

  # The mgmt-plane switch (the L2 core the controller/router hang off).
  def mgmt_switch
    @nodes.find { |n| n.type == 'switch' && n.plane == mgmt_plane_key } || find_node('sw0')
  end

  def mgmt_switch_name
    (sw = mgmt_switch) ? sw.name : 'sw0'
  end

  # The mgmt-plane router (the first hop toward the NAT gateway).
  def mgmt_router
    @nodes.find { |n| n.type == 'router' && n.plane == mgmt_plane_key } || find_node('ro0')
  end

  def mgmt_router_name
    (r = mgmt_router) ? r.name : 'ro0'
  end

  # Anchor for the host / external link in the diagram: the NAT gateway if
  # present, else the mgmt switch (mirrors the old natgw||sw0 fallback).
  def dnat_target_node
    nat_gateway || @nodes.find { |n| n.name == mgmt_switch_name }
  end

  # The NAT/egress gateway: a gateway node with snat, else the edge gateway,
  # else the node literally named natgw (schema fallback).
  def nat_gateway
    @nodes.find { |n| n.type == 'gateway' && n.snat } ||
      @nodes.find { |n| n.type == 'gateway' && n.plane == 'edge' } ||
      find_node('natgw')
  end

  # Legacy target route (router:nic facing the NAT gateway) used when
  # natgw.dnat is NOT an explicit plane->route hash. Derived from the links.
  def mgmt_dnat_target
    router = mgmt_router
    gw     = nat_gateway
    if router && gw
      @links.each do |a, b|
        a = a.to_s
        b = b.to_s
        if a.start_with?("#{router.name}:") && b.start_with?("#{gw.name}:")
          return "#{router.name}:#{a.split(':', 2).last}"
        elsif b.start_with?("#{router.name}:") && a.start_with?("#{gw.name}:")
          return "#{router.name}:#{b.split(':', 2).last}"
        end
      end
    end
    router ? "#{router.name}:eth1" : 'ro0:eth1'
  end

  # ---------------------------------------------------------------------------
  # Persistent controller attach (design-guide.md sec.12.9)
  #
  # When a persistent controller (ctl-ctrl) is running, a workload lab does NOT
  # start its own controller container. Instead the lab's mgmt-switch link that
  # would have gone to the in-lab controller is rewired to an extra NIC on
  # ctl-ctrl, which adopts the lab controller's mgmt IP. Automation then runs
  # inside ctl-ctrl. No controller running => the lab keeps today's behaviour
  # (in-lab controller), i.e. degraded mode.
  # ---------------------------------------------------------------------------
  def controller_node
    @nodes.find { |n| n.type.to_s == 'controller' && n.name != Controller::NAME }
  end

  def container_running?(name)
    return false if name.to_s.empty?
    %x( docker inspect -f '{{.State.Running}}' #{name} 2>/dev/null ).strip == 'true'
  end

  # True when the persistent controller (ctl-ctrl) is up. ctl-ctrl is a
  # separate, persistent node on its own ctl plane: the lab ALWAYS runs its own
  # in-lab controller (the `controller` node, e.g. `ansible`), and ctl-ctrl is
  # additionally wired onto the lab's mgmt plane as an extra OOB host (its own
  # reserved mgmt IP) so the server can drive cloud/terraform/host ops from it
  # and exchange data with the lab controller over the management network.
  def persistent_controller_up?
    return false if @standalone
    defined?(Controller) && Controller.respond_to?(:running?) && Controller.running?
  end

  # Container that owns lab automation: always the lab's own in-lab controller
  # node (created and destroyed with the lab). ctl-ctrl never runs the lab
  # playbook.
  def controller_exec_name
    ctrl = find_node('ansible') || controller_node
    ctrl ? ctrl.name : Controller::NAME
  end

  # Returns detailed metadata about a lab for the UI (Moved from ApplicationHelper)
  def self.metadata(yaml_file_path, adhoc_rules_by_lab = {})
    labs_dir = defined?(::LABS_DIR) ? ::LABS_DIR : File.expand_path('../../labs', __dir__)
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
          plane: node.plane || 'data',
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

    # Wired SNAT gateways (e.g. natgw): a router may uplink to these regardless
    # of plane. "Wired" = referenced by at least one link in the topology.
    linked_nodes = info[:links].flat_map { |l| [l[:node_a], l[:node_b]] }.compact.uniq
    info[:natgws] = lab.nodes.select { |n| n.type == 'gateway' && n.snat && linked_nodes.include?(n.name) }.map(&:name)

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
              # Same rule the topology map uses for its "Web Interface" link
              # (see graph.rb). HTTP(S) is the common case for an exposed service.
              url: vip.to_s.empty? ? nil : "https://#{vip}:#{p[0]}",
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
      labs_dir = defined?(::LABS_DIR) ? ::LABS_DIR : File.expand_path('../../labs', __dir__)
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

    # The mgmt switch is identified by ROLE, not by the literal name 'sw0'.
    mgmt_sw      = mgmt_switch_name
    mgmt_sw_node = mgmt_switch

    cfg['nodes'].each do |name, node|
      is_remote = ['rhost', 'external'].include?(node['type']) || ['gcp', 'external', 'aws', 'azure'].include?(node['provider'].to_s.downcase)
      next if is_remote

      # The mgmt switch itself is the star of the mgmt plane, never a member
      # of it. Excluding it by role also fixes the historical sw0 self-link.
      next if node['type'] == 'switch' && (name == mgmt_sw || node['kind'] == 'mgmt')

      case node['type']
        when 'controller'
          links << [ "#{mgmt_sw}:eth1", "#{name}:eth0" ]
        when 'switch'
          switches << name
        when 'router'
          router << name
        when 'host'
          hosts << name
      end
    end

    (switches + router + hosts).each do |n|
      links << [ "#{mgmt_sw}:eth#{cnt}", "#{n}:eth0" ]
      mgmt_sw_node.nics["eth#{cnt}"] = '' if mgmt_sw_node && mgmt_sw_node.nics
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
    # The controller plane is a standalone Lab, but it must NOT write the shared
    # "current" inventory copy in @pubdir -- that belongs to whichever lab is
    # actually selected/running (the webui Management/Data tabs read it). Give it
    # its own basename so the controller inventory lives in its own file instead
    # of clobbering the lab one. See to_ini/to_data_ini and views/inventory.erb.
    if @standalone
      # Node name is ctlabs-controller (20 chars, near veth IFNAMSIZ limit) but
      # the inventory file must be controller.ini so Ansible's -i resolves.
      @graph.to_ini(@graph.get_inventory, 'controller', 'controller')
      @graph.to_data_ini(@graph.get_data_inventory, 'controller', 'controller_data')
    else
      inv_shared = 'inventory'
      @graph.to_ini(@graph.get_inventory, @name, inv_shared)
      @graph.to_data_ini(@graph.get_data_inventory, @name, "#{inv_shared}_data")
    end
    # Intentionally does NOT deploy dnsmasq: inventory generation also runs on
    # non-start paths (Lab.refresh_visuals when a lab is merely *selected* in the
    # webui, `--ini`), and deploying there leaked a <lab>.conf into the persistent
    # controller for every lab ever viewed. Deployment happens in `up` (after the
    # controller is attached), removal in `down`. See design-guide.md sec.12.9.
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
    # The lab's dnsmasq zone lives in the lab's own in-lab controller (it is
    # created and destroyed with the lab). conf file is named "<lab>.conf" by
    # Graph#to_dnsmasq, so it stays namespaced per lab.
    ctr     = controller.name
    base    = File.basename(conf_path)
    
    @log.write "#{__method__}(): conf=#{conf_path},controller=#{ctr},engine=#{engine}", "debug"
    
     ran = %x( #{engine} cp "#{conf_path}" #{ctr}:/etc/dnsmasq.d/#{base} 2>&1 )
     if $?.success?
       # Ensure the lab controller's dnsmasq also listens on its mgmt interface
       # (eth0) so ctl-ctrl (wired onto mgmt) can query it at 99.5 if needed.
       %x( #{engine} exec #{ctr} sh -c '/usr/bin/printf "interface=eth0\n" > /etc/dnsmasq.d/00-listen.conf 2>/dev/null; systemctl restart dnsmasq' 2>&1 )
     end
    @log.write "#{__method__}(): ran=#{ran.inspect},exit=#{$?.exitstatus}", "debug"
    $?.success?
  end

  # Inverse of deploy_dnsmasq: drop this lab's zone from the controller's
  # /etc/dnsmasq.d and restart dnsmasq, so a stopped lab leaves no host
  # records behind. Labs reuse node names while IPs are dynamic (see
  # design-guide.md sec.12.9), so a lingering "<lab>.conf" would resolve the
  # same name to a different lab's address. Only the lab's own file is
  # removed (the controller's 00-listen.conf is untouched). Runs before the
  # in-lab controller is stopped in `down`.
  def remove_lab_dnsmasq
    controller = @nodes.find { |n| n.respond_to?(:type) && n.type.to_s == 'controller' }
    return if controller.nil?

    ctr    = controller.name
    file   = "/etc/dnsmasq.d/#{@name}.conf"
    engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
    out    = %x( #{engine} exec #{ctr} sh -c 'rm -f #{file} && systemctl restart dnsmasq' 2>&1 )
    @log.write "#{__method__}(): ctr=#{ctr},file=#{file},out=#{out.strip.inspect}", "debug"
    $?.success?
  rescue => e
    @log.write "#{__method__}(): #{e.message}", "warn"
    false
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
    natgw = nat_gateway

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
            target_route = node.plane == 'mgmt' ? mgmt_dnat_target : natgw.dnat
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


  # Reject host DNAT port conflicts up front: a port reserved for the
  # controller, or the same ext_port/proto bound twice within this lab. Called
  # from `up` before anything is started, so a bad lab.yml fails fast instead of
  # silently shadowing another rule (iptables DNAT is first-match-wins).
  def validate_dnat_ports!
    seen = {}
    @nodes.each do |node|
      next unless node.dnat.is_a?(Array)
      node.dnat.each do |r|
        ext   = r[0].to_i
        next if ext <= 0
        proto = (r[2] || 'tcp').to_s
        assert_host_port_available!(ext, proto, node.name, seen)
      end
    end
  end

  # Shared by validate_dnat_ports! and add_adhoc_dnat. `seen` (a hash keyed
  # "port/proto") is optional; when present, intra-lab duplicates are rejected.
  def assert_host_port_available!(ext_port, proto, owner, seen = nil)
    ext = ext_port.to_i
    if !@standalone && RESERVED_DNAT_RANGE.include?(ext)
      raise "Host port #{ext} is reserved for the controller " \
            "(#{RESERVED_DNAT_RANGE}); pick another ext_port for '#{owner}'"
    end
    if seen
      key = "#{ext}/#{proto}"
      if seen[key]
        raise "Duplicate host DNAT binding #{key}: used by both " \
              "'#{seen[key]}' and '#{owner}'"
      end
      seen[key] = owner
    end
  end

  # Container node types that actually start a local container (see Node#run).
  # `gateway` nodes are host bridges and pull no image, so they're excluded.
  CONTAINER_NODE_TYPES = %w[host router switch controller].freeze

  # Normalized list of image tags present in the local engine(s). Mirrors the
  # normalization used by the Container Images / Node Profiles cards (strip
  # registry prefixes so `localhost/ctlabs/x`, `docker.io/ctlabs/x` -> `ctlabs/x`).
  def self.local_images
    imgs  = `podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null`.split("\n").map(&:strip)
    imgs += `docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null`.split("\n").map(&:strip)
    imgs.map! do |img|
      img.sub(%r{^localhost/}, '').sub(%r{^docker\.io/library/}, '').sub(%r{^docker\.io/}, '').sub(%r{^quay\.io/}, '')
    end
    imgs.reject! { |img| img.empty? || img.include?('<none>') }
    imgs.uniq
  end

  # Normalize a single image reference the same way as self.local_images.
  def self.normalize_image(image)
    norm = image.to_s.sub(%r{^localhost/}, '').sub(%r{^docker\.io/library/}, '').sub(%r{^docker\.io/}, '').sub(%r{^quay\.io/}, '')
    norm = "#{norm}:latest" unless norm.include?(':') || norm.include?('@')
    norm
  end

  # Pre-flight: every local node that will start a container must have its
  # profile image present in the local registry. Fails fast with an actionable
  # list instead of a mid-`up` `docker run` failure. Called from `up` before the
  # lock is taken. Remote (cloud/rhost) nodes are provisioned elsewhere and are
  # skipped, as is the in-lab controller when attached to the persistent plane.
  # Only `ctlabs/...` (locally built) images are enforced: public images are
  # pulled on demand by the engine and must not be treated as missing.
  def validate_profiles_ready!
    available = self.class.local_images
    missing   = []

    @nodes.each do |node|
      next unless CONTAINER_NODE_TYPES.include?(node.type.to_s)
      next if node.remote?

      image = node.image
      if image.nil? || image.to_s.strip.empty?
        defs  = (@defaults[node.type] || {})[node.kind] || {}
        image = defs['image']
      end
      next if image.nil? || image.to_s.strip.empty?

      norm = self.class.normalize_image(image)
      next unless norm.start_with?('ctlabs/')
      next if available.include?(norm)

      missing << "  - #{node.name} (#{node.type}/#{node.kind}) -> #{image}"
    end

    return true if missing.empty?

    raise "Container profile image(s) not ready:\n#{missing.join("\n")}\n\n" \
          "Build or import the missing image(s) from the Container Images tab " \
          "before starting this lab."
  end

  def add_adhoc_dnat(node_name, ext_port, int_port, proto = 'tcp')
    assert_host_port_available!(ext_port, proto, node_name)
    @log.write "#{__method__}(): node=#{node_name}, #{ext_port}->#{int_port}/#{proto}", "debug"

    chain = "#{@name.upcase}-DNAT"
    vmip  = %x(ip route get 1.1.1.1 2>/dev/null | awk 'NR==1{print $7}').strip

    node = find_node(node_name)
    raise "Node '#{node_name}' not found" if node.nil?

    natgw = nat_gateway
    raise "No NAT gateway node found (required for DNAT)" if natgw.nil?
    raise "NAT gateway '#{natgw.name}' has no 'dnat' attribute" if natgw.dnat.nil?

    # --- THE SMART LOOKUP ---
    target_route = nil
    if natgw.dnat.is_a?(Hash)
      target_route = natgw.dnat[node.plane] || natgw.dnat.values.first
    else
      target_route = node.plane == 'mgmt' ? mgmt_dnat_target : natgw.dnat
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

      # The lab names netns by the FULL container id (Node#add_netns), and the
      # declared-rule path uses `router.netns` (lab.rb#add_dnat). A short
      # `docker ps` id does NOT resolve (`ip netns exec <short>` -> "No such file
      # or directory"), so rule 2 failed silently and the whole add reported only
      # a masked "An error occurred". Resolve it exactly like add_dnat does.
      router.resolve_runtime! if router.respond_to?(:resolve_runtime!)
      router_netns = router.netns.to_s
      raise "Could not resolve network namespace for router '#{router.name}'" if router_netns.empty?

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

  # Removes the host + router iptables rules that add_adhoc_dnat installed for a
  # single rule. Mirrors add_adhoc_dnat's chain/router/via/target derivation so a
  # WebUI delete actually stops forwarding the port -- previously the delete
  # route only edited the YAML and left the rules live until the lab was torn
  # down (see del_dnat, which flushes the whole chain but only runs on `down`).
  # Best-effort and idempotent: a rule that isn't present is not an error (the
  # chain may already have been flushed by a lab restart).
  def del_adhoc_dnat(node_name, ext_port, int_port, proto = 'tcp')
    @log.write "#{__method__}(): node=#{node_name}, #{ext_port}->#{int_port}/#{proto}", "debug"

    chain    = "#{@name.upcase}-DNAT"
    vmip     = %x(ip route get 1.1.1.1 2>/dev/null | awk 'NR==1{print $7}').strip
    ext_port = ext_port.to_i
    int_port = int_port.to_i
    proto    = (proto || 'tcp').to_s.downcase
    return { removed: false, reason: 'no host address' } if vmip.empty?

    node = find_node(node_name)
    return { removed: false, reason: "node '#{node_name}' not found" } if node.nil?

    # Derive the same via/target_ip pair add_adhoc_dnat used (best effort: a
    # missing natgw/router only means we cannot reach the router-side rule).
    target_ip = node.nics['eth1']&.split('/')&.first ||
                node.nics['eth0']&.split('/')&.first ||
                node.nics['tun0']&.split('/')&.first ||
                node.nics['wg0']&.split('/')&.first

    via    = nil
    router = nil
    natgw  = nat_gateway
    if natgw && natgw.dnat
      target_route = natgw.dnat.is_a?(Hash) ? (natgw.dnat[node.plane] || natgw.dnat.values.first)
                                            : (node.plane == 'mgmt' ? mgmt_dnat_target : natgw.dnat)
      rname, nic = target_route.to_s.split(':')
      router = find_node(rname)
      via    = router.nics[nic].split('/')[0] if router && router.nics.key?(nic)
    end

    removed = false

    # Host chain: delete every rule matching this proto/ext_port regardless of
    # destination form (add_adhoc_dnat installs EITHER the optimized form
    # `via:int_port` OR the 2-step form `via:ext_port`). Enumerating the chain
    # avoids guessing, and needs no `via` resolution.
    %x( iptables -t nat -S #{chain} 2>/dev/null ).each_line do |l|
      next unless l.start_with?("-A #{chain} ")
      next unless l =~ /-p #{Regexp.escape(proto)}(\s|$)/
      next unless l =~ /--dport #{ext_port}(\s|$)/
      next unless l.include?("-j DNAT")
      spec = l.sub(/^-A\s+#{Regexp.escape(chain)}\s+/, '').strip
      cmd  = "iptables -t nat -D #{chain} #{spec}"
      if system("#{cmd} 2>/dev/null")
        removed = true
        @log.write "#{__method__}(): removed host rule: #{cmd}", "debug"
      end
    end

    # Router-side rule (2-step form only): PREROUTING -> target_ip:int_port.
    if router && via && target_ip && target_ip != via
      router.resolve_runtime! if router.respond_to?(:resolve_runtime!)
      netns = router.netns.to_s
      unless netns.empty?
        cmd = "ip netns exec #{netns} iptables -t nat -D PREROUTING -p #{proto} " \
              "-d #{via} --dport #{ext_port} -j DNAT --to-destination #{target_ip}:#{int_port}"
        if system("#{cmd} 2>/dev/null")
          removed = true
          @log.write "#{__method__}(): removed router rule: #{cmd}", "debug"
        end
      end
    end

    @log.info "[ADHOC DNAT DEL] #{vmip}:#{ext_port} #{proto} removed=#{removed}"
    { removed: removed }
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

    # The lab's own controller gets the key (it runs the playbook / SSHes to
    # nodes). When the persistent controller is up it ALSO gets the key, so the
    # server can run ansible/ssh against the lab from ctl-ctrl over the mgmt
    # plane (its own use case: cloud/terraform/host ops + data exchange).
    targets = [node.name]
    targets << Controller::NAME if node.type.to_s == 'controller' && persistent_controller_up?

    targets.each { |target| inject_ssh_key_into(target, node, priv_key, pub_key_path, pub_key) }
  end

  def inject_ssh_key_into(target, node, priv_key, pub_key_path, pub_key)
    begin
      # Login user for this node. The public key must land in THAT user's home
      # (node_profiles.yml sets `user: ansible` for everything that has the
      # account), otherwise sshd will never offer it to the login we use.
      login_user = (node.user.nil? || node.user.to_s.empty?) ? 'root' : node.user.to_s
      home       = login_user == 'root' ? '/root' : "/home/#{login_user}"

      # Ensure .ssh directory exists
      system("docker exec #{target} mkdir -p #{home}/.ssh")
      system("docker exec #{target} chmod 700 #{home}/.ssh")
      system("docker exec #{target} chown #{login_user}:#{login_user} #{home}/.ssh") unless login_user == 'root'

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
          next unless system("docker exec #{target} mkdir -p #{key_home}/.ssh")

          system("docker cp #{priv_key} #{target}:#{key_home}/.ssh/id_ed25519")
          system("docker cp #{pub_key_path} #{target}:#{key_home}/.ssh/id_ed25519.pub")
          system("docker exec #{target} chmod 700 #{key_home}/.ssh")
          system("docker exec #{target} chmod 600 #{key_home}/.ssh/id_ed25519")
          system("docker exec #{target} chmod 644 #{key_home}/.ssh/id_ed25519.pub")
          # docker cp preserves the host file's root ownership, and ssh refuses a
          # private key the caller does not own.
          system("docker exec #{target} chown -R #{login_user}:#{login_user} #{key_home}/.ssh") unless key_home == '/root'
        end
      end

      # ALL nodes get the PUBLIC key in their login user's authorized_keys
      system("docker exec #{target} sh -c \"echo '#{pub_key}' >> #{home}/.ssh/authorized_keys\"")
      unless login_user == 'root'
        system("docker exec #{target} chown #{login_user}:#{login_user} #{home}/.ssh/authorized_keys")
      end
      system("docker exec #{target} chmod 600 #{home}/.ssh/authorized_keys")

    rescue => e
      @log.write("Failed to inject SSH keys to #{node.name} (target #{target}): #{e.message}", "error")
    end
  end

  # Determines the "primary" (non-mgmt) data interface for a node config.
  # Remote/cloud nodes use the overlay tunnel NIC; mgmt-plane nodes use eth0.
  def self.primary_nic_for(node_cfg)
    provider = node_cfg['provider'].to_s.downcase
    is_remote = ['rhost', 'external'].include?(node_cfg['type'].to_s) || ['gcp', 'aws', 'azure', 'external'].include?(provider)
    if is_remote
      # The tunnel interface is whatever the lab actually declares: OpenVPN
      # uses tun0, WireGuard uses wg0. Honour a declared one, otherwise a
      # WireGuard cloud gateway is treated as tun0 and the editor auto-wires a
      # NIC that never exists. tun0 is checked first to keep every existing
      # (OpenVPN) lab byte-identical; tun0 remains the fallback when a remote
      # node declares neither (historical behaviour).
      nics = node_cfg['nics']
      if nics.is_a?(Hash)
        return 'tun0' unless nics['tun0'].to_s.strip.empty?
        return 'wg0'  unless nics['wg0'].to_s.strip.empty?
      end
      return 'tun0'
    end
    return 'eth0' if node_cfg['type'] == 'controller' || node_cfg['plane'] == 'mgmt'
    'eth1'
  end

  # Allocates the next free port on a switch using a raw YAML topology hash
  # (used when wiring links while the lab is stopped / not yet loaded).
  def self.next_free_switch_port(vm, switch_name)
    sw = Regexp.escape(switch_name.to_s)
    used = (vm['links'] || []).flat_map do |l|
      next [] unless l.is_a?(Array)
      l.map { |ep| ep.to_s =~ /^#{sw}:eth(\d+)$/ ? $1.to_i : nil }
    end.compact

    if running?
      engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
      cid = %x( #{engine} inspect -f '{{.Id}}' #{switch_name} 2>/dev/null ).strip
      if !cid.empty?
        out = %x( ip netns exec #{cid} ip -br link show 2>/dev/null )
        out.scan(/eth(\d+)/) { |m| used << m[0].to_i }
      end
    end

    port = 1
    port += 1 while used.include?(port)
    port
  end

  def get_next_switch_port(switch_name)
    used_ports = @links.map do |l|
      if l[0] =~ /^#{switch_name}:eth(\d+)$/
        $1.to_i
      elsif l[1] =~ /^#{switch_name}:eth(\d+)$/
        $1.to_i
      end
    end.compact

    sw_node = find_node(switch_name)
    if sw_node
      sw_node.resolve_runtime! if sw_node.respond_to?(:resolve_runtime!)
      sw_node.nics&.keys&.each do |k|
        used_ports << $1.to_i if k.to_s =~ /^eth(\d+)$/
      end
      if sw_node.netns && !sw_node.netns.to_s.empty?
        out = %x( ip netns exec #{sw_node.netns} ip -br link show 2>/dev/null )
        out.scan(/eth(\d+)/) { |m| used_ports << m[0].to_i }
      end
    elsif Lab.running?
      engine = system('command -v podman >/dev/null 2>&1') ? 'podman' : 'docker'
      cid = %x( #{engine} inspect -f '{{.Id}}' #{switch_name} 2>/dev/null ).strip
      if !cid.empty?
        out = %x( ip netns exec #{cid} ip -br link show 2>/dev/null )
        out.scan(/eth(\d+)/) { |m| used_ports << m[0].to_i }
      end
    end
    
    next_port = 1
    next_port += 1 while used_ports.include?(next_port)
    next_port
  end

def add_adhoc_node(node_name, node_cfg, target_switch = nil, web_v_token = nil, web_v_addr = nil, nic_switches = {})
  @log.write "#{__method__}(): node=#{node_name}, cfg=#{node_cfg}, switch=#{target_switch}", "debug"
    raise "Node '#{node_name}' already exists" if find_node(node_name)

    # 1. Resolve live namespace IDs for existing nodes. Use the canonical
    #    resolver: `docker ps` returns the SHORT container ID while the
    #    /var/run/netns symlink is named by the FULL ID, so the old inline
    #    lookup left every existing node with a netns name that `ip netns`
    #    could not open -- the switch-side veth endpoints were then never
    #    moved out of the host netns and the adhoc node came up with no
    #    carrier (delete/recreate-the-link is what masked it).
    @nodes.each { |n| n.resolve_runtime! if n.respond_to?(:resolve_runtime!) }

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

      ctrl = find_node('ansible') || @nodes.find { |n| n.type == 'controller' }
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
    #    Each interface may target its own switch via nic_switches.
    nic_switches = {} if nic_switches.nil?
    data_links   = []

    if is_remote
      # Remote node wiring (single overlay interface)
      sw = nic_switches['tun0'].to_s.strip
      sw = target_switch.to_s.strip if sw.empty?
      if !sw.empty?
        next_port = get_next_switch_port(sw)
        data_link = ["#{sw}:eth#{next_port}", "#{node_name}:tun0"]
        @links << data_link
        data_links << data_link
      end
    elsif plane == 'mgmt' || type == 'controller'
      # MGMT PLANE: Only one connection needed (eth0 -> target_switch or mgmt switch)
      actual_switch = nic_switches['eth0'].to_s.strip
      actual_switch = target_switch.to_s.strip if actual_switch.empty?
      actual_switch = mgmt_switch_name if actual_switch.empty?
      if find_node(actual_switch)
        next_port = get_next_switch_port(actual_switch)
        data_link = ["#{actual_switch}:eth#{next_port}", "#{node_name}:eth0"]
        @links << data_link
        Link.new('nodes' => @nodes, 'links' => data_link, 'log' => @log, 'mgmt' => mgmt)
        data_links << data_link
      end
    else
      # DATA PLANE: Needs OOB Mgmt (eth0 -> mgmt switch) AND Data NICs
      if !(kind == 'mgmt' && type == 'switch') && type != 'gateway'
        msw = mgmt_switch_name
        msw_node = find_node(msw)
        if msw_node
          next_sw0 = get_next_switch_port(msw)
          mgmt_link = ["#{msw}:eth#{next_sw0}", "#{node_name}:eth0"]
          @links << mgmt_link
          msw_node.nics["eth#{next_sw0}"] = '' if msw_node.nics
          Link.new('nodes' => @nodes, 'links' => mgmt_link, 'log' => @log, 'mgmt' => mgmt)
          data_links << mgmt_link
        end
      end

      # Wire every data interface (eth1, eth2, ...) to its requested switch
      all_nics = (node_cfg['nics'] || {}).keys.map(&:to_s)
      ordered  = (['eth1'] + all_nics).uniq.select { |nic| all_nics.include?(nic) && nic != 'eth0' }

      ordered.each do |nic|
        sw = nic_switches[nic].to_s.strip
        sw = target_switch.to_s.strip if nic == 'eth1' && sw.empty?
        next if sw.empty? || !find_node(sw)

        next_port = get_next_switch_port(sw)
        link      = ["#{sw}:eth#{next_port}", "#{node_name}:#{nic}"]
        @links << link
        Link.new('nodes' => @nodes, 'links' => link, 'log' => @log, 'mgmt' => mgmt)
        data_links << link
      end
    end

    @log.info "[ADHOC NODE] Started node #{node_name}"
    inventory

    [node_cfg, data_links]
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
    validate_dnat_ports!
    validate_profiles_ready!
    self.class.acquire_lock!(@relative_path) unless @standalone
  
    @log.info "Starting Lab: #{@relative_path}"
    attached = persistent_controller_up?
    synchronize_lab_operation do
      @log.info "Starting Nodes:"
      # The lab ALWAYS runs its own in-lab controller (it is created and
      # destroyed with the lab); ctl-ctrl is a separate persistent node.
      @nodes.each(&:run)

      @log.info "Starting Links:"
      # When the persistent controller is up, additionally wire it onto the
      # lab's mgmt plane as an extra OOB host (its own reserved mgmt IP) --
      # WITHOUT taking over the lab's controller node.
      attach_controller_oob! if attached
      @links.each do |l|
        nodes = (@oob_proxy && l.include?(@oob_endpoint)) ? @nodes + [@oob_proxy] : @nodes
        Link.new('nodes' => nodes, 'links' => l, 'log' => @log, 'mgmt' => @mgmt)
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

    # Deploy this lab's dnsmasq zone into the (attached) controller now that the
    # lab is actually starting. `down` removes it. Doing it here (not in
    # `inventory`) keeps the zone tied to lab lifetime, not to lab *viewing*.
    deploy_dnsmasq(@graph.to_dnsmasq(@graph.get_dnsmasq, @name))

    # Copy lab-specific flashcards if they exist
    lab_flashcards    = File.join(File.dirname(@cfg_file), 'flashcards.json')
    public_flashcards = '/srv/ctlabs-server/public/flashcards.json'
    
    if File.file?(lab_flashcards)
      FileUtils.cp(lab_flashcards, public_flashcards)
      @log.info "Loaded flashcards from lab: #{lab_flashcards}"
    end
  end

  def down(web_v_token = nil, web_v_addr = nil)
    begin
      # Validate we own the lock (skipped in standalone/controller mode)
      unless @standalone
        if self.class.running? && self.class.current_name != @relative_path
          raise "Cannot stop '#{@relative_path}': currently running lab is '#{self.class.current_name}'"
        end
      end
  
      @log.info "Stopping Lab: #{@relative_path}"

      # Remove this lab's dnsmasq zone while the in-lab controller is still up
      # (before the node loop stops it): labs reuse node names but get dynamic
      # IPs, so a stale <lab>.conf would resolve a name to another lab's address.
      attached = persistent_controller_up?
      remove_lab_dnsmasq

      # Remove ctl-ctrl's OOB NIC BEFORE stopping nodes (the NIC lives on
      # ctl-ctrl, which outlives the lab).
      detach_controller_oob! if attached

      synchronize_lab_operation do
        @log.info "Stopping Nodes:"
        @nodes.each(&:stop)

        @log.info "Cleaning up link interfaces..."
        cleanup_link_interfaces

        @log.info "Removing DNAT rules..."
        del_dnat
      end

      # Tear down any cloud (GCP) resources this lab created, by label. Best
      # effort: needs a Vault session to mint a GCP token, and never blocks or
      # fails the local teardown (see teardown_cloud!).
      teardown_cloud!(web_v_token, web_v_addr)

      # Clear any unsaved AdHoc cache!
      FileUtils.rm_f("/var/run/ctlabs/#{@relative_path.gsub('/', '_')}.adhoc")
    ensure
      self.class.release_lock! unless @standalone
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

  # Delete the cloud (GCP) resources this lab created, by label (see Cloud).
  # Best-effort: it never blocks or fails the local teardown, and it is skipped
  # entirely when the lab has no GCP auth configured. A GCP token is minted via
  # GcpAuth, which needs a Vault session: the webgui passes its session token,
  # and CLI users can supply VAULT_TOKEN/VAULT_ADDR in the environment.
  #
  # !!! UNVERIFIED !!! - the delete-by-label REST calls are untested (no GCP
  # creds available at implementation time).
  def teardown_cloud!(web_v_token = nil, web_v_addr = nil)
    ctrl = find_node('ansible') || @nodes.find { |n| n.type.to_s == 'controller' }
    return unless ctrl
    tf_cfg = (@cfg['topology'][0]['nodes'][ctrl.name] || {})['terraform']
    return unless tf_cfg.is_a?(Hash) && !tf_cfg.empty?
    return unless (GcpAuth.resolve_auth_cfg(tf_cfg) rescue nil)  # no GCP auth on this lab

    token = web_v_token.to_s
    addr  = web_v_addr.to_s
    if token.empty? && ENV['VAULT_TOKEN'] && !ENV['VAULT_TOKEN'].empty?
      token = ENV['VAULT_TOKEN']
      addr  = ENV['VAULT_ADDR'].to_s
    end
    if token.empty?
      @log.write("[cloud] skipping GCP teardown for #{@name}: no Vault token available", "warn")
      return
    end

    auth_cfg = GcpAuth.resolve_auth_cfg(tf_cfg) || {}
    project  = auth_cfg['project'].to_s.strip
    project  = tf_cfg['project'].to_s.strip if project.empty?
    if project.empty?
      @log.write("[cloud] skipping GCP teardown for #{@name}: no project configured", "warn")
      return
    end

    begin
      access = GcpAuth.fetch_token(tf_cfg, { addr: addr, token: token })
      Cloud.new(project: project, token: access, log: @log).teardown!(@name)
    rescue => e
      @log.write("[cloud] GCP teardown failed for #{@name}: #{e.message}", "error")
    end
  end

  # Node#stop tears down the container/netns side of each node, but host-side
  # veth endpoints can linger: gateway peers, and any veth whose move into the
  # container netns failed. A lingering `<node><nic>` name makes the next `up`
  # fail at `ip link add ... peer ...` ("File exists"), silently leaving the
  # lab unwired. Delete every link endpoint on the host idempotently.
  def cleanup_link_interfaces
    @links.each do |ep1, ep2|
      [ep1, ep2].compact.each do |ep|
        node_name, nic = ep.to_s.split(':', 2)
        next if node_name.to_s.empty? || nic.to_s.empty?
        %x( ip link delete #{node_name}#{nic} 2>/dev/null )
      end
    end
  end

  # Wire the persistent controller (ctl-ctrl) onto the lab's mgmt plane as an
  # extra host, WITHOUT taking over the lab's controller node. The lab keeps
  # its own in-lab controller at its assigned mgmt IP (e.g. 192.168.99.5);
  # ctl-ctrl joins the same mgmt switch on its own reserved address (the last
  # usable host of the mgmt subnet) so the server can run cloud/terraform/host
  # ops from it and exchange persistent data with the lab controller over the
  # management network.
  #
  # A synthetic proxy node (bypassing @nodes, so it never reaches inventory)
  # supplies Link with ctl-ctrl's netns + address so the existing veth/OVS
  # wiring is reused verbatim. The OOB link is appended to @links and the proxy
  # is injected only for that link in the `up` link loop.
  def attach_controller_oob!
    cid = Controller.container_id
    return if cid.to_s.empty?

    sw = mgmt_switch_name
    return unless find_node(sw)

    oob_ip = controller_oob_mgmt_ip
    return if oob_ip.nil?

    nic           = 'eth1'
    # Idempotency: if a previous run left the OOB NIC on ctl-ctrl (e.g. a
    # crashed lab that never detached), clear it before re-wiring.
    %x( ip netns exec #{cid} ip link delete #{nic} 2>/dev/null )
    port          = get_next_switch_port(sw)
    @oob_endpoint = "#{Controller::NAME}:#{nic}"
    @links << [ "#{sw}:eth#{port}", @oob_endpoint ]

    proxy = Node.new(
      'name'     => Controller::NAME,
      'type'     => 'controller',
      'profile'  => 'linux',
      'plane'    => 'mgmt',
      'nics'     => { nic => oob_ip },
      'gw'       => nil,
      'mtu'      => 1460,
      'defaults' => @defaults,
      'log'      => @log
    )
    proxy.instance_variable_set(:@netns, cid)
    @oob_proxy = proxy

    @log.info "[ATTACH] #{Controller::NAME}:#{nic} (#{oob_ip}) on #{sw}:eth#{port}; lab controller '#{controller_node&.name}' stays in-lab"

    configure_controller_dns!
  end

  # Reserved mgmt address for the persistent controller's OOB NIC: the last
  # usable host of the lab's mgmt subnet. Kept off the sequential allocator
  # (auto_assign_mgmt_ip! starts at .20) so it never collides with a lab node.
  def controller_oob_mgmt_ip
    net = (@mgmt || {})['net'].to_s
    net = '192.168.99.0/24' if net.empty?
    require 'ipaddr'
    subnet = IPAddr.new(net)
    last   = subnet.to_range.last.to_i - 1
    "#{IPAddr.new(last, subnet.family)}/#{subnet.prefix}"
  rescue StandardError
    nil
  end

  # While a lab runs, point ctl-ctrl's resolver at the lab controller's own
  # dnsmasq (on the lab mgmt plane) so `docker exec ctl-ctrl` can resolve the
  # lab's mgmt hostnames for data exchange / server-driven ops, plus the lab's
  # external resolvers. ctl-ctrl's own resolver is saved once and restored on
  # detach so a lab's dns never outlives it.
  def configure_controller_dns!
    ctrl   = controller_node
    ctl_ip = ((ctrl&.nics || {})['eth0'] || '').to_s.split('/')[0]
    return if ctl_ip.empty?

    addrs = ((ctrl&.dns || []) + ((@mgmt || {})['dns'] || []))
            .map(&:to_s).reject(&:empty?).uniq

    domain = "mgmt.#{@domain} #{@domain}"
    dns    = "nameserver #{ctl_ip}\n" + addrs.map { |ns| "nameserver #{ns}" }.join("\n")

    %x( docker exec #{Controller::NAME} sh -c 'test -f /etc/resolv.conf.ctlabs.bak || cp /etc/resolv.conf /etc/resolv.conf.ctlabs.bak' )
    %x( docker exec #{Controller::NAME} sh -c '/usr/bin/printf "domain #{domain}\n#{dns}\noptions timeout:1 attempts:1\n" > /etc/resolv.conf' )
    @log.info "[ATTACH] #{Controller::NAME} resolvers: #{ctl_ip}, #{addrs.join(', ')}"
  end

  # Remove the OOB NIC from ctl-ctrl on lab down. The switch-side endpoint dies
  # with its (stopped) container netns, but the ctl-ctrl side lives on (the
  # controller is persistent), so it MUST be deleted explicitly here.
  def detach_controller_oob!
    return unless persistent_controller_up?
    cid = Controller.container_id
    return if cid.to_s.empty?
    @log.info "[DETACH] removing OOB NIC from #{Controller::NAME}"
    %x( ip netns exec #{cid} ip link delete eth1 2>/dev/null )
    %x( ip link delete ctl-ctrleth1 2>/dev/null )
    # Restore the controller's own resolver (saved on attach) so the lab's dns
    # does not leak past its lifecycle.
    %x( docker exec #{Controller::NAME} sh -c 'test -f /etc/resolv.conf.ctlabs.bak && cp /etc/resolv.conf.ctlabs.bak /etc/resolv.conf' )
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
