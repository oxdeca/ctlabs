#!/bin/bash

IMG="debian-11-nocloud-amd64.qcow2"
DISK1="/media/vda.qcow2"
ENABLE_KVM=

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

# start tmux session
tmux new -d -s qemu

tmux send-keys -t qemu "qemu-system-x86_64 -nodefaults -display none -m 1G -serial mon:stdio -smp 2     \
                         -boot c -drive file=/media/${IMG} ${ENABLE_KVM}                                \
                         -drive file=/media/vda.qcow2 -vga virtio                                       \
                         -virtfs local,path=/mnt,mount_tag=setup,readonly=on,security_model=passthrough \
                         -nic tap,ifname=ens0,br=net0,script=no,downscript=no                           \
                         -nic tap,ifname=ens1,br=net1,script=/root/if-up,downscript=/root/if-down" ENTER

