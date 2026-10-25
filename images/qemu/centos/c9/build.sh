#!/bin/bash

IMG_NAME=ctlabs/qemu/c9
IMG_VERS=0.1.4

BASE_IMAGES_DIR=${BASE_IMAGES_DIR:-/media/ctlabs-images/qemu}
MNTDIR=/media/ctlabs_c9_qemu
QIMG_NAME=CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2
QIMG_URL=https://cloud.centos.org/centos/9-stream/x86_64/images/${QIMG_NAME}
QIMG_SIZE=40G

create_qemu_img() {
  if [ ! -e ${QIMG_NAME} ]; then
    curl -sLo ${QIMG_NAME} ${QIMG_URL}
    qemu-img resize ${QIMG_NAME} ${QIMG_SIZE}
  fi

  modprobe nbd
  mkdir -vp ${MNTDIR}                && sleep 1
  qemu-nbd -c /dev/nbd0 ${QIMG_NAME} && sleep 1
  growpart    /dev/nbd0 4
  
  # Only generate new UUIDs for XFS partitions p3 (/boot) and p4 (/)
  # Leave p1 (EFI) completely untouched so its original UUID and boot files remain valid!
  xfs_admin -U generate /dev/nbd0p3
  xfs_admin -U generate /dev/nbd0p4
  
  UUID_P3=$(blkid -s UUID -o value /dev/nbd0p3)
  UUID_P4=$(blkid -s UUID -o value /dev/nbd0p4)
  
  # Mount partitions hierarchically
  mount       /dev/nbd0p4 ${MNTDIR}
  mkdir -p    ${MNTDIR}/boot
  mkdir -p    ${MNTDIR}/boot/efi
  mount       /dev/nbd0p3 ${MNTDIR}/boot
  
  xfs_growfs  /dev/nbd0p4

  # Fetch old UUIDs from fstab before modifying
  OLD_ROOT_UUID=$(grep '[[:space:]]/[[:space:]]'     ${MNTDIR}/etc/fstab | awk '{print $1}' | tr -d 'UUID=')
  OLD_BOOT_UUID=$(grep '[[:space:]]/boot[[:space:]]' ${MNTDIR}/etc/fstab | awk '{print $1}' | tr -d 'UUID=')

  # Update /etc/fstab with the new UUIDs for root and boot
  [ -n "$OLD_ROOT_UUID" ] && sed -i "s/${OLD_ROOT_UUID}/$UUID_P4/g" ${MNTDIR}/etc/fstab
  [ -n "$OLD_BOOT_UUID" ] && sed -i "s/${OLD_BOOT_UUID}/$UUID_P3/g" ${MNTDIR}/etc/fstab

  # Update Boot Specification configs to match the new root UUID
  if [ -n "$OLD_ROOT_UUID" ]; then
      find ${MNTDIR}/boot -type f \( -name "*.conf" -o -name "grub.cfg" \) -exec sed -i "s/${OLD_ROOT_UUID}/${UUID_P4}/g" {} +
      [ -f ${MNTDIR}/etc/default/grub ] && sed -i "s/${OLD_ROOT_UUID}/${UUID_P4}/g" ${MNTDIR}/etc/default/grub
  fi

  # Bind-mount pseudo-filesystems for chroot dracut execution
  mount --bind /dev  ${MNTDIR}/dev
  mount --bind /proc ${MNTDIR}/proc
  mount --bind /sys  ${MNTDIR}/sys

  chroot ${MNTDIR} /bin/sh -c 'dracut --regenerate-all --force'

  # Clean up bind mounts
  umount ${MNTDIR}/sys
  umount ${MNTDIR}/proc
  umount ${MNTDIR}/dev

  install -m 0750 files/ctlabs_run_setup.sh    ${MNTDIR}/root/
  install -m 0750 files/ctlabs-exec            ${MNTDIR}/usr/bin/
  install -m 0644 files/bashrc-kali.sh         ${MNTDIR}/etc/profile.d/
  install -m 0644 files/99-ctlabs.sh           ${MNTDIR}/etc/profile.d/
  install -m 0640 files/ctlabs-net.service     ${MNTDIR}/etc/systemd/system/
  install -m 0640 files/sshd.service           ${MNTDIR}/etc/systemd/system/

  chroot ${MNTDIR} /usr/bin/systemctl enable ctlabs-net.service sshd.service
  chroot ${MNTDIR} /usr/bin/systemctl disable NetworkManager systemd-network-generator
  chroot ${MNTDIR} /usr/bin/systemctl mask    NetworkManager systemd-network-generator
  chroot ${MNTDIR} /bin/sh -c 'echo "nameserver 1.1.1.2" > /etc/resolv.conf'
  chroot ${MNTDIR} /bin/sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
  chroot ${MNTDIR} /bin/sh -c 'mknod /dev/null c 1 3 && chmod 0666 /dev/null'

  chroot ${MNTDIR} /bin/sh -c 'useradd -U -s /bin/bash -d /home/ansible -m ansible && echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible'
  chroot ${MNTDIR} /bin/sh -c 'sed -ri "s@^(SELINUX)=enforcing@\1=permissive@" /etc/selinux/config'
  chroot ${MNTDIR} /bin/sh -c 'dnf -y remove man-db cloud-init && dnf -y install epel-release epel-next-release'
  chroot ${MNTDIR} /bin/sh -c 'dnf -y install htop lvm2 nfs-utils numactl xterm-resize sshpass nc'
  chroot ${MNTDIR} /bin/sh -c 'dnf -y install vim-enhanced glibc-langpack-en google-noto-color-emoji-fonts'
  chroot ${MNTDIR} /bin/sh -c 'ln -sfv /usr/share/zoneinfo/America/Toronto /etc/localtime'
  chroot ${MNTDIR} /bin/sh -c 'echo "LANG=en_US.UTF-8" > /etc/locale.conf'
  chroot ${MNTDIR} /bin/sh -c 'echo "root:" | chpasswd'

  # Unmount partitions in reverse order
  umount ${MNTDIR}/boot
  umount ${MNTDIR}
  qemu-nbd -d /dev/nbd0
}

create_qemu_img
docker build --rm -t ${IMG_NAME}:${IMG_VERS} -t ${IMG_NAME}:latest .
rm ${QIMG_NAME}
