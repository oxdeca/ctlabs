#!/bin/bash

IMG="debian-11-nocloud-amd64.qcow2"
DISK1="/media/vda.qcow2"
ENABLE_KVM=
QEMU_MEM=${QEMU_MEM:-256M}

# import environment password to container
export $(cat /proc/1/environ | tr '\0' '\n' | grep QEMU)


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

gen_mac() {
  local premac="52:54:00:"
  echo ${premac}$(openssl rand -hex 3 | awk '{gsub(/.{2}/,"&:")}1' | sed 's@.$@@')
}

create_net_setup_script() {
  local premac="52:54:00:12:34:"
  local eth0_ip=$( ip -br addr ls eth0 | awk '{print $3}' )
  local eth0_gw=$( ip -br route ls default vrf mgmt | awk '{print $3}' )
  local eth1_ip=$( ip -br addr ls eth1 | awk '{print $3}' )
  local eth1_gw=$( ip -br route ls default | awk '{print $3}' )
cat > /mnt/ctlabs_net_setup.sh << EOF
#!/bin/bash

hostnamectl set-hostname ${HOSTNAME}


# ens3
ip addr add ${eth0_ip} dev ens3
ip link set ens3 master mgmt mtu 1460 up
#ip link set ens3 address "${premac}$(openssl rand -hex 1)"
ip route add default via ${eth0_gw} vrf mgmt

# ens4
ip addr add ${eth1_ip} dev ens4
ip link set ens4 mtu 1460 up
#ip link set ens4 address "${premac}$(openssl rand -hex 1)"
ip route add default via ${eth1_gw}

echo '$(cat /etc/resolv.conf)' > /etc/resolv.conf
EOF

}

create_net_setup_script
mkisofs -r -o /tmp/${HOSTNAME}.iso /mnt/

# start tmux session
tmux new -d -s qemu

tmux send-keys -t qemu "qemu-system-x86_64 -nodefaults -display none -m ${QEMU_MEM} -serial mon:stdio                           \
                        -smp 2,sockets=1,dies=1,cores=2,threads=1                                                               \
                        -cpu host,kvm=on,l3-cache=on,+hypervisor,migratable=no                                                  \
                        -machine type=q35,smm=on,graphics=off,vmport=off,dump-guest-core=off,hpet=off,accel=kvm                 \
                        ${ENABLE_KVM} -device qemu-xhci,id=xhci -device usb-tablet                                              \
                        -global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1 -object iothread,id=io2                     \
                        -device virtio-balloon-pci,id=balloon0,bus=pcie.0,addr=0x5                                              \
                        -drive file=/media/${IMG},id=disk1,format=raw,cache=none,aio=native,discard=on,detect-zeroes=on,if=none \
                        -device virtio-scsi-pci,id=disk1b,bus=pcie.0,addr=0xa,iothread=io2                                      \
                        -device scsi-hd,drive=disk1,bus=disk1b.0,channel=0,scsi-id=0,lun=0,rotation_rate=1,bootindex=3          \
                        -drive file=/media/vda.qcow2 -vga virtio                                                                \
                        -drive file=/tmp/${HOSTNAME}.iso,media=cdrom                                                            \
                        -nic tap,ifname=ens0,br=net0,script=no,downscript=no,mac=$(gen_mac)                                     \
                        -nic tap,ifname=ens1,br=net1,script=/root/if-up,downscript=/root/if-down,mac=$(gen_mac)" ENTER


