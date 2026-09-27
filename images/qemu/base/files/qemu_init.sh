#!/bin/bash

# import environment password to container
export $(cat /proc/1/environ | tr '\0' '\n' | grep QEMU)

DISK1="/media/vda.qcow2"
ENABLE_KVM=
QEMU_IMG=${QEMU_IMG:-qemu-img.qcow2}
QEMU_MEM=${QEMU_MEM:-768M}
QEMU_CPU=${QEMU_CPU:-4} # Changed default to 4 to better demonstrate symmetry

# --- NUMA CONFIGURATION ---
# Set to 2 to enable a 2-node NUMA topology. Set to 0 to disable.
QEMU_NUMA_NODES=${QEMU_NUMA_NODES:-0} 

# If NUMA is enabled, default sockets to NUMA nodes so the guest OS maps them correctly
if [ "$QEMU_NUMA_NODES" -ge 2 ]; then
  QEMU_CPU_SOCKETS=${QEMU_CPU_SOCKETS:-$QEMU_NUMA_NODES}
else
  QEMU_CPU_SOCKETS=${QEMU_CPU_SOCKETS:-1}
fi

QEMU_CPU_THREADS=${QEMU_CPU_THREADS:-2}

# Calculate cores per socket based on desired QEMU_CPU
QEMU_CPU_CORES=$((QEMU_CPU / (QEMU_CPU_SOCKETS * QEMU_CPU_THREADS)))
# Ensure cores is at least 1
[ "$QEMU_CPU_CORES" -lt 1 ] && QEMU_CPU_CORES=1

# CRITICAL FIX: Calculate the ACTUAL total vCPUs that will be spawned.
# We use THIS number to divide CPUs symmetrically across NUMA nodes, 
# preventing unassigned CPUs from defaulting to Node 0.
ACTUAL_VCPUS=$((QEMU_CPU_SOCKETS * 1 * QEMU_CPU_CORES * QEMU_CPU_THREADS))

QEMU_VGA=${QEMU_VGA:-none}
QEMU_VNC=${QEMU_VNC:-false}

FILE="/root/.ssh/authorized_keys"
TIMEOUT=120  # Wait max 2 minutes
SECONDS=0    # Bash builtin timer

echo "Waiting for $FILE..." >&2

until [ -f "$FILE" ] && [ -r "$FILE" ]; do
    if [ $SECONDS -ge $TIMEOUT ]; then
        echo "Error: Timeout waiting for $FILE after ${TIMEOUT}s" >&2
        exit 1
    fi
    sleep 1
done

echo "File found, copying key..." >&2
mkdir -p /mnt/ssh
cp /root/.ssh/authorized_keys /mnt/ssh/

gen_mac() {
  local premac="52:54:00:"
  echo ${premac}$(openssl rand -hex 3 | gawk '{gsub(/.{2}/,"&:")}1' | sed 's@.$@@')
}

# Linux-guest net setup. Windows images override this entirely (see
# /root/qemu_init.d/, sourced below) since the guest-side setup is
# completely different (PowerShell/netsh, no bash/VRF) -- keeping that out
# of this shared script avoids piling OS-conditional branches in here as
# more guest-specific features (AD-DC, firewall, ...) show up.
create_net_setup_script() {
  local eth0_nic=enp0s1
  local eth0_ip=$( ip -br addr ls eth0 | awk '{print $3}' )
  local eth0_gw=$( ip -br route ls default vrf mgmt | awk '{print $3}' )
  local eth1_nic=enp0s2
  local eth1_ip=$( ip -br addr ls eth1 | awk '{print $3}' )
  local eth1_gw=$( ip -br route ls default | awk '{print $3}' )
cat > /mnt/ctlabs_net_setup.sh << EOF
#!/bin/bash

hostnamectl set-hostname ${HOSTNAME}

if [ ! -d "/root/.ssh" ]; then
  mkdir -vp /root/.ssh
fi
cp /mnt/ssh/authorized_keys /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# ens3
ip addr add ${eth0_ip} dev ${eth0_nic}
ip link set ${eth0_nic} master mgmt mtu 1460 up
ip route add default via ${eth0_gw} vrf mgmt

# ens4
ip addr add ${eth1_ip} dev ${eth1_nic}
ip link set ${eth1_nic} mtu 1460 up
ip route add default via ${eth1_gw}

echo '$(cat /etc/resolv.conf)' > /etc/resolv.conf
EOF
}

# Per-image extensions (Windows net setup, AD-DC, extra firewall rules,
# etc.) live in /root/qemu_init.d/*.sh, baked in by each image's own
# Dockerfile via COPY. Sourced after the definitions above so an extension
# can override any function here (e.g. redefine create_net_setup_script)
# without forking this shared script.
for _ext in /root/qemu_init.d/*.sh; do
  [ -e "$_ext" ] || continue
  source "$_ext"
done
unset _ext

qemu_base_cmd() {
  local qemu_vga=""
  local qemu_numa=""
  local qemu_vnc=""
  local qemu_machine_extra=",graphics=off"

  if [ "$QEMU_VGA" != "none" ]; then
    qemu_vga="-vga $QEMU_VGA"
  fi
  if [ "$QEMU_VNC" == "true" ]; then
    qemu_vga="-vga std"
    qemu_vnc="-vnc :0"
    # graphics=off disables the video adapter at the machine level
    # regardless of -vga/-vnc -- drop it when VNC output is wanted.
    qemu_machine_extra=""
  fi

  if [ "$QEMU_NUMA_NODES" -ge 2 ]; then
    # Divide the ACTUAL spawned vCPUs evenly among the NUMA nodes for perfect symmetry
    local cpus_per_node=$((ACTUAL_VCPUS / QEMU_NUMA_NODES))
    
    # 1. Convert total QEMU_MEM to Megabytes for safe, explicit division
    local mem_mb=0
    if [[ "$QEMU_MEM" =~ ^([0-9]+)[Gg]$ ]]; then
      mem_mb=$((${BASH_REMATCH[1]} * 1024))
    elif [[ "$QEMU_MEM" =~ ^([0-9]+)[Mm]$ ]]; then
      mem_mb=${BASH_REMATCH[1]}
    else
      mem_mb=1024 # Fallback to 1G if parsing fails
    fi
    
    local mem_per_node_mb=$((mem_mb / QEMU_NUMA_NODES))
    
    # 2. Generate explicit memory-backend-ram objects and link them to NUMA nodes
    for ((i=0; i<QEMU_NUMA_NODES; i++)); do
      local start_cpu=$((i * cpus_per_node))
      local end_cpu=$((start_cpu + cpus_per_node - 1))
      
      # Assign any remaining CPUs to the last node if division isn't perfectly even
      if [ $i -eq $((QEMU_NUMA_NODES - 1)) ]; then
        end_cpu=$((ACTUAL_VCPUS - 1))
      fi
      
      local memdev_id="ram-node${i}"
      
      # Define the memory backend for this node
      qemu_numa+="-object memory-backend-ram,id=${memdev_id},size=${mem_per_node_mb}M "
      
      # Link the NUMA node to the memory backend
      if [ $start_cpu -eq $end_cpu ]; then
        qemu_numa+="-numa node,nodeid=${i},cpus=${start_cpu},memdev=${memdev_id} "
      else
        qemu_numa+="-numa node,nodeid=${i},cpus=${start_cpu}-${end_cpu},memdev=${memdev_id} "
      fi
    done
    
    # Add default distance between node 0 and 1
    qemu_numa+="-numa dist,src=0,dst=1,val=20 "
  fi

  QEMU_BASE_CMD=(
    "qemu-system-x86_64 -nodefaults -display none ${qemu_vga} ${qemu_vnc} -m ${QEMU_MEM} -serial mon:stdio"
    "-smp sockets=${QEMU_CPU_SOCKETS},dies=1,cores=${QEMU_CPU_CORES},threads=${QEMU_CPU_THREADS}"
    # hv_passthrough hung Windows guests solid right after SeaBIOS handed
    # off to the boot disk (confirmed 2026-09-27: identical command, only
    # this flag + graphics=off differed from a proven-working boot) --
    # the exact Hyper-V CPUID leaf set it passes through doesn't match
    # what Windows' boot-time HAL expects closely enough. These four are
    # the specific enlightenments Windows actually wants; harmless no-ops
    # for Linux guests (they only matter to a Hyper-V-aware kernel).
    "-cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time,kvm=on,l3-cache=on,migratable=no"
    "-machine type=q35,smm=on,graphics=off,vmport=off,dump-guest-core=off,accel=kvm ${qemu_numa}"
    "${ENABLE_KVM} -device qemu-xhci,id=xhci -device usb-tablet"
    "-global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1"
    "-device virtio-balloon-pci,free-page-reporting=on,id=ballon0,bus=pcie.0,addr=0x5"
  )
}

qemu_add_disk() {
  local id="$1"
  local path="$2"
  local addr="${3:-0xa}"
  local bootx="${5:-}"

  QEMU_DISKS+=(
    "-object iothread,id=io${id}"
    "-drive file=${path},id=disk${id},format=qcow2,cache=none,aio=native,discard=unmap,detect-zeroes=unmap,if=none"
    # Use ACTUAL_VCPUS for num_queues to match the true vCPU count
    "-device virtio-scsi-pci,id=bus${id},bus=pcie.0,addr=${addr},iothread=io${id},num_queues=${ACTUAL_VCPUS}"
    "-device scsi-hd,drive=disk${id},bus=bus${id}.0,channel=0,scsi-id=0,lun=0,rotation_rate=1${bootx:+,bootx=${bootx}}"
  )
}

qemu_add_nic() {
  local nic="$1"
  local br="$2"
  local script="${3:-no}"
  local queues="${4:-${QEMU_CPU_CORES}}"
  # Optional explicit MAC so callers can generate it ahead of time and
  # reuse the same value elsewhere (e.g. a guest-side net-setup script that
  # needs to identify the NIC by MAC) instead of only knowing it after the
  # fact from this function's own gen_mac() call.
  local mac="${5:-$(gen_mac)}"
  local cmd=""

  if [[ "$script" != "no" ]]; then
    cmd=",script=${script}-up,downscript=${script}-down"
  fi

  QEMU_NICS+=(
    "-nic tap,ifname=${nic},br=${br}${cmd},model=virtio-net-pci,mac=${mac},queues=${queues}"
  )
}

qemu_add_iso() {
  local path="$1"

  QEMU_ISOS+=(
    "-drive file=${path},media=cdrom"
  )
}

qemu_start() {
  qemu_base_cmd

  local cmd=(
    "${QEMU_BASE_CMD[@]}"
    "${QEMU_DISKS[@]}"
    "${QEMU_NICS[@]}"
    "${QEMU_ISOS[@]}"
  )

  tmux send-keys -t qemu "$(printf "%s " "${cmd[@]}")" ENTER
}

#
# MAIN
#

# loop while nic eth0 isn't ready
while :; do
  ip -br link ls eth0
  if [ $? -eq 0 ]; then
    break
  fi
  sleep 1
done
sleep 2

if [ -n "${DISK1}" ]; then
  qemu-img create -f qcow2 ${DISK1} 500M
fi

if [ -c /dev/kvm ]; then
  ENABLE_KVM="--enable-kvm"
fi

# Generated ahead of create_net_setup_script (not inside qemu_add_nic) so
# a guest-side net-setup script (e.g. Windows, which must match NICs by
# MAC rather than assumed enumeration order) can embed the same value that
# actually ends up on the -nic line below.
ENS0_MAC=$(gen_mac)
ENS1_MAC=$(gen_mac)

create_net_setup_script
mkisofs -r -o /tmp/${HOSTNAME}.iso /mnt/

# start tmux session
tmux new -d -s qemu

qemu_add_disk 1 "/media/${QEMU_IMG}" "0xa" "3"
qemu_add_disk 2 "/media/vda.qcow2"   "0xb"

qemu_add_nic ens0 br0 "no"          "$QEMU_CPU_CORES" "$ENS0_MAC"
qemu_add_nic ens1 br1 "/root/if"    "$QEMU_CPU_CORES" "$ENS1_MAC"
qemu_add_iso "/tmp/${HOSTNAME}.iso"

qemu_start
