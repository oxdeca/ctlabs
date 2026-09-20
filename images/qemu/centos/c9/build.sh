#!/bin/bash

IMG_NAME=ctlabs/c9/qemu
IMG_VERS=0.1.1

MNTDIR=/media/ctlabs_c9_qemu
QIMG_SIZE=20G
QIMG_NAME=CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2
QIMG_URL=https://cloud.centos.org/centos/9-stream/x86_64/images/${QIMG_NAME}

create_qemu_img() {
  if [ ! -e ${QIMG_NAME} ]; then
    curl -sLo ${QIMG_NAME} ${QIMG_URL}
    qemu-img resize ${QIMG_NAME} ${QIMG_SIZE}
  fi

  modprobe nbd
  mkdir -vp ${MNTDIR}                && sleep 1
  qemu-nbd -c /dev/nbd0 ${QIMG_NAME} && sleep 1
  growpart    /dev/nbd0 4
  mount       /dev/nbd0p4 ${MNTDIR}
  xfs_growfs  /dev/nbd0p4

  install -m 0750 files/ctlabs_run_setup.sh    ${MNTDIR}/root/
  install -m 0750 files/ctlabs-exec            ${MNTDIR}/usr/bin/
  install -m 0644 files/bashrc-kali.sh         ${MNTDIR}/etc/profile.d/
  install -m 0644 files/99-ctlabs.sh           ${MNTDIR}/etc/profile.d/
  install -m 0640 files/ctlabs-net.service     ${MNTDIR}/etc/systemd/system/
  install -m 0640 files/sshd.service           ${MNTDIR}/etc/systemd/system/
  install -m 0640 files/tmux.conf              ${MNTDIR}/etc/

  chroot ${MNTDIR} /usr/bin/systemctl enable ctlabs-net.service sshd.service
  chroot ${MNTDIR} /usr/bin/systemctl disable NetworkManager systemd-network-generator
  chroot ${MNTDIR} /usr/bin/systemctl mask    NetworkManager systemd-network-generator
  chroot ${MNTDIR} /bin/sh -c 'echo "nameserver 1.1.1.2" > /etc/resolv.conf'
  chroot ${MNTDIR} /bin/sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
  chroot ${MNTDIR} /bin/sh -c 'mknod /dev/null c 1 3 && chmod 0666 /dev/null'
  
  chroot ${MNTDIR} /bin/sh -c 'sed -ri "s@^(SELINUX)=enforcing@\1=permissive@" /etc/selinux/config'
  chroot ${MNTDIR} /bin/sh -c 'dnf -y remove man-db cloud-init && dnf -y install epel-release epel-next-release'
  chroot ${MNTDIR} /bin/sh -c 'dnf -y install htop lvm2 nfs-utils numactl xterm-resize sshpass nc'
  chroot ${MNTDIR} /bin/sh -c 'dnf -y install vim-enhanced glibc-langpack-en google-noto-color-emoji-fonts'
  chroot ${MNTDIR} /bin/sh -c 'sed -ri "s@^#(PermitRootLogin) .*@\1 yes@" /etc/ssh/sshd_config'
  chroot ${MNTDIR} /bin/sh -c 'ln -sfv /usr/share/zoneinfo/America/Toronto /etc/localtime'
  chroot ${MNTDIR} /bin/sh -c 'echo 'LANG=en_US.UTF-8' > /etc/locale.conf'
  chroot ${MNTDIR} /bin/sh -c 'echo "root:" | chpasswd'

  umount ${MNTDIR}
  qemu-nbd -d /dev/nbd0
}

create_qemu_img
docker build --rm -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest .
rm ${QIMG_NAME}
