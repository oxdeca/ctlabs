#!/bin/bash

# import environment password to container
export $(cat /proc/1/environ | tr '\0' '\n' | grep QEMU)

IMG="debian-11-nocloud-amd64.qcow2"
DISK1="/media/vda.qcow2"
ENABLE_KVM=
QEMU_MEM=${QEMU_MEM:-768M}
QEMU_CPU=${QEMU_CPU:-2}
QEMU_CPU_THREADS=${QEMU_CPU_THREADS:-2}
QEMU_CPU_CORES=${QEMU_CPU_CORES:-$((QEMU_CPU/QEMU_CPU_THREADS))}

gen_mac() {
  local premac="52:54:00:"
  echo ${premac}$(openssl rand -hex 3 | awk '{gsub(/.{2}/,"&:")}1' | sed 's@.$@@')
}

create_net_setup_script() {
  local premac="52:54:00:12:34:"
  local eth0_nic=enp0s1
  local eth0_ip=$( ip -br addr ls eth0 | awk '{print $3}' )
  local eth0_gw=$( ip -br route ls default vrf mgmt | awk '{print $3}' )
  local eth1_nic=enp0s2
  local eth1_ip=$( ip -br addr ls eth1 | awk '{print $3}' )
  local eth1_gw=$( ip -br route ls default | awk '{print $3}' )
cat > /mnt/ctlabs_net_setup.sh << EOF
#!/bin/bash

hostnamectl set-hostname ${HOSTNAME}


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

qemu_base_cmd() {
  QEMU_BASE_CMD=(
    "qemu-system-x86_64 -nodefaults -display none -m ${QEMU_MEM} -serial mon:stdio"
    "-smp sockets=1,dies=1,cores=${QEMU_CPU_CORES},threads=${QEMU_CPU_THREADS}"
    "-cpu host,hv_passthrough,kvm=on,l3-cache=on,migratable=no"
    "-machine type=q35,smm=on,graphics=off,vmport=off,dump-guest-core=off,accel=kvm"
    "${ENABLE_KVM} -device qemu-xhci,id=xhci -device usb-tablet"
    "-global ICH9-LPC.disable_s3=1 -global ICH9-LPX.disable_s4=1"
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
    "-device virtio-scsi-pci,id=bus${id},bus=pcie.0,addr=${addr},iothread=io${id},num_queues=${QEMU_CPU}"
    "-device scsi-hd,drive=disk${id},bus=bus${id}.0,channel=0,scsi-id=0,lun=0,rotation_rate=1${bootx:+,bootx=${bootx}}"
  )
}

qemu_add_nic() {
  local nic="$1"
  local br="$2"
  local script="${3:-no}"
  local queues="${4:-${QEMU_CPU_CORES}}"
  local cmd=""

  if [[ "$script" != "no" ]]; then
    cmd=",script=${script}-up,downscript=${script}-down"
  fi

  QEMU_NICS+=(
    "-nic tap,ifname=${nic},br=${br}${cmd},model=virtio-net-pci,mac=$(gen_mac),queues=${queues}"
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

  local cmd+=(
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

# loop while nic eth1 isn't ready
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

create_net_setup_script
mkisofs -r -o /tmp/${HOSTNAME}.iso /mnt/

# start tmux session
tmux new -d -s qemu

qemu_add_disk 1 "/media/${IMG}"    "0xa" "3"
qemu_add_disk 2 "/media/vda.qcow2" "0xb"

qemu_add_nic ens0 br0
qemu_add_nic ens1 br1 "/root/if"
qemu_add_iso "/tmp/${HOSTNAME}.iso"

qemu_start

