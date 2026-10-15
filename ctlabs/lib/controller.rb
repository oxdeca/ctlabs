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

  private

  def standalone_lab
    Lab.new(cfg: TOPOLOGY, relative_path: 'controller/topology.yml', log: @log, standalone: true)
  end

  def write_topology
    FileUtils.mkdir_p(STATE_DIR)
    FileUtils.mkdir_p(VAULT_DATA, mode: 0o700)
    File.write(TOPOLOGY, topology_yaml)
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
  def topology_yaml
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
