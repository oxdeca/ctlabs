#!/bin/bash

ip link add mgmt type vrf table 40
ip link set mgmt up

ip link set ens3 master mgmt up

mount /dev/cdrom /mnt
bash /mnt/ctlabs_net_setup.sh
umount /mnt

exit 0
