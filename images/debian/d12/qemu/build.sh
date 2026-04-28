#!/bin/bash

IMG_NAME=ctlabs/d12/qemu
IMG_VERS=0.4.1

MNTDIR=/media/ctlabs_d12_qemu
QIMG_NAME=debian-12-nocloud-amd64.qcow2
QIMG_SIZE=20G
QIMG_URL=https://cloud.debian.org/images/cloud/bookworm/latest/${QIMG_NAME}

create_qemu_img() {
  if [ ! -e ${QIMG_NAME} ]; then
    curl -sLo ${QIMG_NAME} ${QIMG_URL}
    qemu-img resize ${QIMG_NAME} ${QIMG_SIZE}
  fi

  modprobe nbd
  mkdir -vp ${MNTDIR}                && sleep 1
  qemu-nbd -c /dev/nbd0 ${QIMG_NAME} && sleep 1
  growpart /dev/nbd0 1
  resize2fs /dev/nbd0p1
  mount /dev/nbd0p1 ${MNTDIR}

  echo '' > ${MNTDIR}/etc/network/interfaces
  install -m 0644 files/99-ctlabs.sh           ${MNTDIR}/etc/profile.d/
  install -m 0640 files/ctlabs-net.service     ${MNTDIR}/etc/systemd/system/
  install -m 0750 files/ctlabs-exec            ${MNTDIR}/usr/bin/
  install -m 0640 files/ssh.service            ${MNTDIR}/etc/systemd/system/
  install -m 0750 files/ctlabs_run_setup.sh    ${MNTDIR}/root/
  install -m 0644 files/bashrc.kali            ${MNTDIR}/etc/

  chroot ${MNTDIR} /usr/bin/systemctl enable ctlabs-net.service ssh.service
  chroot ${MNTDIR} /usr/bin/systemctl disable systemd-networkd.service
  chroot ${MNTDIR} /usr/bin/systemctl mask    systemd-networkd.service
  chroot ${MNTDIR} /bin/sh -c 'rm /etc/resolv.conf'
  chroot ${MNTDIR} /bin/sh -c 'echo "nameserver 1.1.1.2" > /etc/resolv.conf'
  chroot ${MNTDIR} /bin/sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
  chroot ${MNTDIR} /bin/sh -c 'mknod /dev/null c 1 3 && chmod 0666 /dev/null'
  chroot ${MNTDIR} /bin/sh -c 'apt update && apt -y remove man-db'
  chroot ${MNTDIR} /bin/sh -c 'apt -y install openssh-server lvm2 fdisk nfs-kernel-server locales'
  chroot ${MNTDIR} /bin/sh -c 'apt -y install cloud-utils sshpass xterm gnupg fonts-noto-color-emoji'
  chroot ${MNTDIR} /bin/sh -c 'mv /bin/resize /usr/local/bin/ && apt -y remove xterm && apt -y clean && apt -y autoclean && apt -y autoremove'
  chroot ${MNTDIR} /bin/sh -c 'sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config'
  chroot ${MNTDIR} /bin/sh -c 'echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && locale-gen'
  chroot ${MNTDIR} /bin/sh -c 'echo "LANG=en_US.UTF-8" > /etc/default/locale'

  umount ${MNTDIR}
  qemu-nbd -d /dev/nbd0
}

create_qemu_img
docker build --rm -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest .
rm ${QIMG_NAME}
