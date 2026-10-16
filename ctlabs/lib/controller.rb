# -----------------------------------------------------------------------------
# File        : ctlabs/lib/controller.rb
# Description : Persistent control plane (decoupled controller).
#
#               Starts a long-lived controller container plus its OWN minimal
#               mgmt plane (controller + switch + router + egress), built from
#               the existing node types -- no bespoke network. The plane nodes
#               use ctl-* names so they never collide with a workload lab's
#               sw0/ro0/natgw (role lookup via Lab#mgmt_switch/#nat_gateway).
#               The controller is NOT a user lab: it lives outside the single-lab
#               lock and is never listed as a lab. Workload labs attach to it
#               (per-lab OOB veth onto their mgmt switch) -- see design-guide.md
#               sec.12.9.
#
# Usage: ctlabs.rb --controller=up|down|status
# -----------------------------------------------------------------------------

require 'fileutils'

class Controller
  # NOTE: the container/node name feeds the host-side veth name as
  # "<name><nic>" (see link.rb), so it MUST be short: "<name>eth0" has to fit
  # Linux's 15-char IFNAMSIZ. "ctl-ctrl"+"eth0" = 11 is safe; a long name like
  # "ctlabs-controller" silently fails veth creation (20 chars) and the plane
  # never wires up.
  NAME      = 'ctl-ctrl'
  STATE_DIR = '/var/run/ctlabs/controller'
  TOPOLOGY  = File.join(STATE_DIR, 'topology.yml')

  # Persistent host-backed storage for the controller. Vault's file storage
  # (`/opt/vault/data`, provisioned by the ctlabs_vault role) would otherwise
  # live in the container's writable layer and die with `controller down`
  # (`docker rm -f`). `down`/`up` no longer discards Vault's init/unseal state
  # or secrets. (Terraform state and ansible content already persist via the
  # repo bind-mounts in the controller profile.)
  DATA_DIR   = '/var/lib/ctlabs/controller'
  VAULT_DATA = File.join(DATA_DIR, 'vault')

  # Host-backed overlay for WebUI edits to the (otherwise code-generated) control
  # plane: extra exposed services, extra control-plane nodes, and the
  # controller's own play/terraform config. Merged onto the base topology on
  # every `up` and on every render, so it survives `controller down`/`up` (and a
  # reboot, unlike STATE_DIR which lives on tmpfs). Base nodes/services are
  # locked; only entries stored here are user-removable.
  OVERLAYS = File.join(DATA_DIR, 'overrides.yml')

  # Node types that actually start a container on the control plane, i.e. have a
  # terminal and can own services. `gateway` (ctl-natgw) is a host bridge.
  PLANE_CONTAINER_TYPES = %w[host router switch controller].freeze

  # Node types allowed to own host DNAT forwards (mirrors Lab.metadata's list).
  DNAT_NODE_TYPES = %w[host controller router server gateway].freeze

  # A running controller container is the source of truth for "is it up".
  def self.running?
    out = %x( docker inspect -f '{{.State.Running}}' #{NAME} 2>/dev/null ).strip
    out == 'true'
  end

  # Full container id. Lab#attach_controller! uses this as the netns handle
  # (ip netns exec <id> ...) to wire the per-lab OOB veth into the controller.
  def self.container_id
    %x( docker inspect -f '{{.Id}}' #{NAME} 2>/dev/null ).strip
  end

  # Any ctl-* plane containers, running or not (anchored so a lab's sw0 never
  # matches ctl-sw0). Used to detect partial state so `down` can still clean up
  # after a crash even when the controller container itself is gone.
  def self.plane_containers
    %x( docker ps -a --format '{{.Names}}' --filter name='^ctl-' 2>/dev/null )
      .lines.map(&:strip).reject(&:empty?)
  end

  # Describe the controller's own mgmt-plane nodes for the webgui "Control-Plane"
  # card. The controller is global (not a lab), so there is no Lab.metadata for
  # it; the effective topology (base + overlays) is the source of truth. Returns
  # the configured container-backed nodes even when the controller is down, so
  # the UI can edit the plane; `running` is per-node (a stopped/exited container
  # shows red, not hidden). The edge `ctl-natgw` is a HOST bridge (like a lab's
  # `natgw`), not a container, so it has no terminal and is filtered out.
  def self.plane_nodes
    cfg = effective_topology
    return [] unless cfg.is_a?(Hash)

    running = running_node_names

    nodes = []
    Array(cfg['topology']).each do |vm|
      next unless vm.is_a?(Hash)
      (vm['planes'] || {}).each do |plane, pcfg|
        next unless pcfg.is_a?(Hash)
        (pcfg['nodes'] || {}).each do |name, ncfg|
          ncfg = {} unless ncfg.is_a?(Hash)
          type = (ncfg['type'] || 'host').to_s
          next unless PLANE_CONTAINER_TYPES.include?(type)
          nodes << {
            name:     name,
            type:     type,
            profile:  ncfg['profile'],
            plane:    plane,
            running:  running.include?(name),
            removable: overlay_node?(name)
          }
        end
      end
    end
    nodes
  end

  # Names of `ctl-*` containers that are up right now.
  def self.running_node_names
    %x( docker ps --format '{{.Names}}' --filter name='^ctl-' 2>/dev/null )
      .lines.map(&:strip).reject(&:empty?)
  end

  # Host port-forwards owned by the controller (base + overlay `dnat:`
  # declarations), for the webgui "Exposed Services" card. Mirrors the shape of
  # Lab.metadata's :exposed_ports so the same DNAT styling can be reused. Base
  # forwards are fixed (declared in #base_topology_yaml) and shown read-only;
  # overlay forwards are user-removable. Known services get a friendly label +
  # a browser URL.
  def self.exposed_ports
    cfg = effective_topology
    return [] unless cfg.is_a?(Hash)

    vip = %x( ip route get 1.1.1.1 | head -n1 | awk '{print $7}' ).strip
    base = base_service_keys

    rows = []
    Array(cfg['topology']).each do |vm|
      next unless vm.is_a?(Hash)
      (vm['planes'] || {}).each do |_plane, pcfg|
        next unless pcfg.is_a?(Hash)
        (pcfg['nodes'] || {}).each do |name, ncfg|
          next unless ncfg.is_a?(Hash) && DNAT_NODE_TYPES.include?((ncfg['type'] || 'host').to_s)
          dnat = ncfg['dnat']
          next unless dnat.is_a?(Array)
          rip = (ncfg['nics'] || {})['eth0']&.split('/')&.first
          dnat.each do |r|
            next unless r.is_a?(Array) && r.size >= 2
            ext   = r[0].to_i
            int   = r[1].to_i
            proto = (r[2] || 'tcp').to_s
            service = case int
                      when 8200 then 'Vault'
                      when 53   then 'DNS (dnsmasq)'
                      end
            rows << {
              node:          name,
              proto:         proto,
              service:       service,
              external_port: "#{vip}:#{ext}",
              internal_port: "#{rip || 'N/A'}:#{int}",
              raw_ext:       ext,
              raw_int:       int,
              # Same rule the topology map uses for its "Web Interface" link
              # (see graph.rb).
              url:           vip.to_s.empty? ? nil : "https://#{vip}:#{ext}",
              removable:     !base.include?("#{name}/#{ext}/#{proto}")
            }
          end
        end
      end
    end
    rows
  end

  # ---------------------------------------------------------------------------
  # Overlay store (base + user edits)
  # ---------------------------------------------------------------------------

  # Normalize a dnat entry (array form from the base YAML, hash form from the
  # overlay file) to a comparable [ext, int, proto] triple.
  def self.dnat_rule(r)
    if r.is_a?(Hash)
      [r['ext'].to_i, r['int'].to_i, (r['proto'] || 'tcp').to_s]
    else
      [r[0].to_i, r[1].to_i, (r[2] || 'tcp').to_s]
    end
  end

  def self.overlays
    return {} unless File.file?(OVERLAYS)
    data = YAML.load_file(OVERLAYS)
    data.is_a?(Hash) ? data : {}
  rescue StandardError
    {}
  end

  def self.save_overlays(data)
    FileUtils.mkdir_p(DATA_DIR)
    File.write(OVERLAYS, data.to_yaml)
  end

  # The immutable, code-generated base topology as a Hash.
  def self.base_topology
    YAML.safe_load(base_topology_yaml, aliases: true)
  end

  # Base topology with the overlay merged on. The mgmt plane is the only plane
  # the UI edits; extra nodes are always added there.
  def self.effective_topology
    topo   = base_topology
    vm     = Array(topo['topology']).first
    planes = (vm && vm['planes']) || {}
    mgmt   = planes['mgmt'] ||= {}
    nodes  = mgmt['nodes'] ||= {}

    ov = overlays

    # 1. Extra exposed services -> append to the target node's dnat list.
    (ov['services'] || {}).each do |name, rules|
      node = nodes[name]
      next unless node.is_a?(Hash) && rules.is_a?(Array)
      node['dnat'] ||= []
      rules.each do |r|
        rule = dnat_rule(r)
        node['dnat'] << rule unless node['dnat'].any? { |x| dnat_rule(x) == rule }
      end
    end

    # 2. Extra control-plane nodes (never shadow a base node).
    (ov['nodes'] || {}).each do |name, cfg|
      nodes[name] = cfg if cfg.is_a?(Hash) && !nodes.key?(name)
    end

    # 3. Controller (ctl-ctrl) automation config.
    ctrl = nodes[NAME]
    if ctrl.is_a?(Hash)
      ctrl['play']      = ov['play']      if ov['play'].is_a?(Hash)
      ctrl['terraform'] = ov['terraform'] if ov['terraform'].is_a?(Hash)
    end

    topo
  end

  # Set of "node/ext/proto" keys declared in the BASE topology, so the UI can
  # tell locked built-in services from user-added ones.
  def self.base_service_keys
    keys = []
    vm   = Array(base_topology['topology']).first || {}
    ((vm['planes'] || {})['mgmt'] || {})['nodes']&.each do |name, ncfg|
      next unless ncfg.is_a?(Hash) && ncfg['dnat'].is_a?(Array)
      ncfg['dnat'].each { |r| keys << "#{name}/#{dnat_rule(r)[0]}/#{dnat_rule(r)[2]}" }
    end
    keys
  end

  def self.overlay_node?(name)
    cfg = overlays['nodes']
    cfg.is_a?(Hash) && cfg.key?(name)
  end

  # ---------------------------------------------------------------------------
  # Overlay mutations (called from the WebUI)
  # ---------------------------------------------------------------------------

  def self.reserved_range
    defined?(Lab::RESERVED_DNAT_RANGE) ? Lab::RESERVED_DNAT_RANGE : (8400..8499)
  end

  # Add an exposed service to a control-plane node. Enforces the reserved host
  # port range (the controller owns 8400-8499) + uniqueness.
  def self.add_service(node_name, ext, int, proto = 'tcp')
    ext   = ext.to_i
    int   = int.to_i
    proto = proto.to_s.downcase
    proto = 'tcp' unless %w[tcp udp].include?(proto)

    raise 'External port must be 1-65535' unless ext.between?(1, 65535)
    raise 'Internal port must be 1-65535' unless int.between?(1, 65535)
    raise "External port #{ext} must be within the controller range #{reserved_range}" unless reserved_range.include?(ext)

    nodes = effective_topology.dig('topology', 0, 'planes', 'mgmt', 'nodes') || {}
    node  = nodes[node_name]
    raise "Node '#{node_name}' is not a control-plane node" unless node.is_a?(Hash)

    existing = Array(node['dnat']).map { |r| dnat_rule(r) }
    raise "Port #{ext}/#{proto} is already exposed" if existing.any? { |r| r[0] == ext && r[2] == proto }

    ov = overlays
    ov['services'] ||= {}
    ov['services'][node_name] ||= []
    ov['services'][node_name] << { 'ext' => ext, 'int' => int, 'proto' => proto }
    save_overlays(ov)
    { node: node_name, ext: ext, int: int, proto: proto }
  end

  # Remove an OVERLAY service. A base (built-in) service is not stored in the
  # overlay, so this returns false and the UI keeps it locked.
  def self.remove_service(node_name, ext, proto = 'tcp')
    ext   = ext.to_i
    proto = proto.to_s.downcase
    ov    = overlays
    rules = ov.dig('services', node_name)
    return false unless rules.is_a?(Array)

    before = rules.size
    rules.reject! { |r| dnat_rule(r)[0] == ext && dnat_rule(r)[2] == proto }
    return false if rules.size == before

    ov['services'].delete(node_name) if rules.empty?
    ov.delete('services') if ov['services'].is_a?(Hash) && ov['services'].empty?
    save_overlays(ov)
    true
  end

  # Add an extra control-plane node (mgmt plane). Applied on the next
  # `controller up` — a running plane is not hot-modified.
  def self.add_node(name, cfg = {})
    name = name.to_s.strip
    raise 'Node name is required' if name.empty?
    raise "Invalid node name '#{name}' (use lowercase letters, digits, dashes)" unless name =~ /\A[a-z0-9][a-z0-9-]*\z/
    raise "Node name '#{name}' is reserved by the base topology" if base_topology.dig('topology', 0, 'planes', 'mgmt', 'nodes')&.key?(name)

    ov = overlays
    ov['nodes'] ||= {}
    raise "Node '#{name}' already exists" if ov['nodes'].key?(name)

    node = { 'type' => (cfg['type'] || 'host').to_s, 'gw' => '192.168.98.1' }
    node['kind'] = cfg['kind'].to_s if cfg['kind'] && !cfg['kind'].to_s.strip.empty?
    node['ipv4'] = cfg['ipv4'].to_s if cfg['ipv4'] && !cfg['ipv4'].to_s.strip.empty?
    ov['nodes'][name] = node
    save_overlays(ov)
    node
  end

  # Remove an overlay node (and any services attached to it). Base nodes are
  # locked. Returns false if nothing was removed.
  def self.remove_node(name)
    name = name.to_s
    ov   = overlays
    removed = false

    if ov['nodes'].is_a?(Hash) && ov['nodes'].key?(name)
      ov['nodes'].delete(name)
      ov.delete('nodes') if ov['nodes'].empty?
      removed = true
    end
    if ov['services'].is_a?(Hash) && ov['services'].key?(name)
      ov['services'].delete(name)
      ov.delete('services') if ov['services'].empty?
      removed = true
    end

    save_overlays(ov) if removed
    removed
  end

  # --- Controller (ctl-ctrl) automation config, stored in the overlay --------

  def self.controller_play
    overlays['play'].is_a?(Hash) ? overlays['play'] : {}
  end

  def self.update_controller_play(cfg)
    ov = overlays
    cfg.is_a?(Hash) && !cfg.empty? ? ov['play'] = cfg : ov.delete('play')
    save_overlays(ov)
    ov['play']
  end

  def self.controller_terraform
    overlays['terraform'].is_a?(Hash) ? overlays['terraform'] : {}
  end

  def self.update_controller_terraform(cfg)
    ov = overlays
    cfg.is_a?(Hash) && !cfg.empty? ? ov['terraform'] = cfg : ov.delete('terraform')
    save_overlays(ov)
    ov['terraform']
  end

  def initialize(log: nil)
    @log = log || LabLog.null
  end

  # Bring up the controller container + its mgmt plane. Standalone mode means
  # Lab#up skips the lab lock and the public-config write.
  def up(web_v_token = nil, web_v_addr = nil)
    if self.class.running?
      puts "✅ Controller already running (#{NAME})"
      return
    end
    write_topology
    lab = standalone_lab
    validate_reserved_ports!(lab)
    lab.up(web_v_token, web_v_addr)
    expose_services!
    @log.info "Controller up (#{NAME})"
    puts "✓ Controller up (#{NAME})"
  end

  # Stop the controller. Lab#down is standalone, so it stops the plane nodes
  # (ctl-sw0/ctl-ro0/ctl-natgw). The controller itself is persistent (no --rm),
  # so we force-remove it explicitly -- otherwise a stopped container with the
  # same name would block the next `up`.
  def down
    if !self.class.running? && self.class.plane_containers.empty?
      puts "❌ Controller is not running."
      return
    end
    standalone_lab.down
    %x( docker rm -f #{NAME} 2>/dev/null )
    @log.info "Controller down (#{NAME})"
    puts "✓ Controller down (#{NAME})"
  end

  def status
    if self.class.running?
      puts "✅ Controller is running (#{NAME})"
    else
      puts "❌ Controller is not running."
    end
  end

  # Public: a standalone Lab view of the controller for automation runs. Writes
  # the merged (base + overlay) topology first, so WebUI edits to the
  # controller's play/terraform config take effect without a full `controller
  # up`. Used by the WebUI control-plane tab to run/stop the controller's own
  # playbook + terraform.
  def lab
    write_topology
    standalone_lab
  end

  private

  def standalone_lab
    Lab.new(cfg: TOPOLOGY, relative_path: 'controller/topology.yml', log: @log, standalone: true)
  end

  def write_topology
    FileUtils.mkdir_p(STATE_DIR)
    FileUtils.mkdir_p(VAULT_DATA, mode: 0o700)
    File.write(TOPOLOGY, self.class.effective_topology.to_yaml)
  end

  # The controller is standalone, so Lab#validate_dnat_ports! deliberately skips
  # the reserved-range check. Enforce the inverse here: any host port the
  # controller itself forwards MUST live in RESERVED_DNAT_RANGE, so the block
  # stays the single source of truth for "controller owns these host ports".
  # The controller image's dnsmasq binds only loopback (`interface=lo` in
  # /etc/dnsmasq.conf), but the controller DNAT forwards `8453 -> ctl-ctrl:53`
  # on the mgmt IP. Drop in a listen directive for the mgmt NIC so dnsmasq
  # answers on 192.168.98.5 too, then restart it. Vault already binds
  # 0.0.0.0 (its HCL uses the default-route IPv4), so only dnsmasq needs this.
  def expose_services!
    script = 'printf "interface=eth0\n" > /etc/dnsmasq.d/00-listen.conf ' \
             '&& systemctl restart dnsmasq'
    out = %x( docker exec #{NAME} bash -c '#{script}' 2>&1 )
    @log.write "#{__method__}(): #{out.strip}", "debug"
  end

  def validate_reserved_ports!(lab)
    lab.nodes.each do |node|
      next unless node.dnat.is_a?(Array)
      node.dnat.each do |r|
        ext = r[0].to_i
        next if ext <= 0
        next if Lab::RESERVED_DNAT_RANGE.include?(ext)
        raise "Controller DNAT port #{ext} (node '#{node.name}') is outside " \
              "the reserved range #{Lab::RESERVED_DNAT_RANGE}"
      end
    end
  end

  # Minimal mgmt plane. `persistent: true` drops --rm on the controller so it
  # survives; the plane nodes give it mgmt reachability + internet egress.
  #
  # CRITICAL: the controller COEXISTS with a running lab on the same host, so
  # its node/bridge names (`ctl-*`) and subnets (mgmt 192.168.98.0/24, edge
  # 192.168.14.0/29) must NOT collide with the lab defaults (lab mgmt
  # 192.168.99.0/24, lab edge 192.168.15.0/29). `natgw` is a HOST bridge, so a
  # shared 192.168.15.1 would be a hard IP collision.
  def self.base_topology_yaml
    <<~YAML
      ---
      name: ctlabs-controller
      desc: persistent ctlabs control plane (mgmt only)
      topology:
      - hv: ctlabs-controller-vm1
        provider: local
        planes:
          mgmt:
            vrfid: 98
            net: 192.168.98.0/24
            gw: 192.168.98.1
            # External resolvers for the controller's own mgmt plane. Without
            # this the image's resolv.conf is only `nameserver 127.0.0.1` (its
            # own dnsmasq), so the controller cannot resolve anything external
            # -- which breaks `terraform init`/registry + any role that fetches
            # over the network. Egress goes via the controller's own natgw.
            dns: [1.1.1.1, 8.8.8.8]
            nodes:
              ctl-ctrl:
                type: controller
                persistent: true
                gw: 192.168.98.1
                # Host-backed Vault storage (persists across controller
                # recreate). Ansible (ctlabs_vault) chowns this dir to the
                # vault service user at provisioning time.
                vols:
                - "#{VAULT_DATA}:/opt/vault/data"
                nics:
                  eth0: 192.168.98.5/24
                # Controller-owned host port forwards (host binds 8400-8499,
                # enforced by Controller#validate_reserved_ports!). Moved up
                # from per-lab: one stable endpoint for Vault (8200) and
                # dnsmasq (53) regardless of which lab is attached.
                dnat:
                - [8443, 8200, tcp]
                - [8453, 53, 'tcp']
                - [8453, 53, 'udp']
              ctl-sw0:
                profile: ovs
                type: switch
                ipv4: 192.168.98.10/24
                gw: 192.168.98.1
              ctl-ro0:
                profile: frr
                type: router
                gw: 192.168.14.1
                nics:
                  eth0: 192.168.98.1/24
                  eth1: 192.168.14.2/29
          edge:
            nodes:
              ctl-natgw:
                type: gateway
                ipv4: 192.168.14.1/29
                snat: true
                dnat:
                  mgmt: ctl-ro0:eth1
        links:
        - [ "ctl-ro0:eth1", "ctl-natgw:eth1" ]
    YAML
  end
end
