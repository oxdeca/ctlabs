#!/bin/bash

ip link add mgmt type vrf table 40
ip link set mgmt up

ip addr add 169.254.40.2/30 dev ens3
ip link set ens3 master mgmt up

ip vrf exec mgmt sshpass -p 'secret' scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@169.254.40.1:/mnt/ctlabs_net_setup.sh /root/
bash /root/ctlabs_net_setup.sh

exit 0
