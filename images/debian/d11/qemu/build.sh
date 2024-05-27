#!/bin/bash

IMG_NAME=ctlabs/d11/qemu
IMG_VERS=0.2

MNTDIR=/media/ctlabs_d11_qemu
QIMG_NAME=debian-11-nocloud-amd64.qcow2
QIMG_URL=https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-nocloud-amd64.qcow2

create_qemu_img() {
  if [ ! -e ${QIMG_NAME} ]; then
    curl -Lo ${QIMG_NAME} ${QIMG_URL}
  fi

  mkdir -vp ${MNTDIR}                && sleep 1
  qemu-nbd -c /dev/nbd0 ${QIMG_NAME} && sleep 1
  mount /dev/nbd0p1 ${MNTDIR}

  echo '' > ${MNTDIR}/etc/network/interfaces
  install -m 0644 files/99-ctlabs.sh           ${MNTDIR}/etc/profile.d/
  install -m 0640 files/ctlabs-net.service     ${MNTDIR}/etc/systemd/system/
  install -m 0640 files/sshd-mgmt.service      ${MNTDIR}/etc/systemd/system/
  install -m 0750 files/ctlabs_run_setup.sh    ${MNTDIR}/root/
  install -m 0644 files/bashrc.kali            ${MNTDIR}/etc/

  chroot ${MNTDIR} /usr/bin/systemctl enable ctlabs-net.service sshd-mgmt.service
  chroot ${MNTDIR} /bin/sh -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'
  chroot ${MNTDIR} /bin/sh -c 'apt update && apt -y install openssh-server'
  chroot ${MNTDIR} /bin/sh -c 'echo "root:secret" | chpasswd && sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config'

  umount ${MNTDIR}
  qemu-nbd -d /dev/nbd0
}

create_qemu_img
docker build --rm -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest .
