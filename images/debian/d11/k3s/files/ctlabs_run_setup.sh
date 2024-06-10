#!/bin/bash

mount -t 9p -o trans=virtio setup /mnt

cd /mnt
bash ./ctlabs_net_setup.sh
cd -

umount /mnt

exit 0
