#!/bin/bash

# ctlabs-net.service is Type=oneshot + RemainAfterExit=true, so this script
# runs exactly once per boot and systemd never retries it. It used to end in a
# bare "exit 0", which meant any failure inside the generated
# ctlabs_net_setup.sh was reported as status=0/SUCCESS - the guest then booted
# with no SSH key in any user's home and looked perfectly healthy. Propagate the
# real exit status instead; the key install inside the generated script exits
# non-zero on failure.

# Tolerate a pre-existing VRF (re-provisioning an existing disk).
ip link add mgmt type vrf table 99 2>/dev/null || true
ip link set mgmt up 2>/dev/null || true

mount /dev/cdrom /mnt || { echo "ctlabs: failed to mount /dev/cdrom" >&2; exit 1; }
bash /mnt/ctlabs_net_setup.sh
rc=$?
umount /mnt
exit $rc
