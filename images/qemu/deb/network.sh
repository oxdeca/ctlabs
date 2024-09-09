#!/bin/bash

SCRIPT_DIR="/mnt"
ISO_FILE="/tmp/${HOSTNAME}.iso"

gen_mac() {
  local premac="52:54:00:"
  echo ${premac}$(openssl rand -hex 3 | awk '{gsub(/.{2}/,"&:")}1' | sed 's@.$@@')
}

create_net_setup_script() {
  local eth0_ip=$( ip -br addr ls eth0 | awk '{print $3}' )
  local eth0_gw=$( ip -br route ls default vrf mgmt | awk '{print $3}' )
  local eth1_ip=$( ip -br addr ls eth1 | awk '{print $3}' )
  local eth1_gw=$( ip -br route ls default | awk '{print $3}' )
  local eth2_ip=$( ip -br addr ls eth2 | awk '{print $3}' )
  local eth2_gw=$( ip -br route ls default | awk '{print $3}' )
  local nic1="enp0s2"
  local nic2="enp0s3"
  local nic2_ip=${eth1_ip}
  local nic2_gw=${eth1_gw}
  if [ "${VNC}" == "1" ]; then
    nic2_ip=${eth2_ip}
    nic2_gw=${eth2_gw}
  fi

cat > ${SCRIPT_DIR}/ctlabs_net_setup.sh << EOF
#!/bin/bash

hostnamectl set-hostname ${HOSTNAME}
ip link add mgmt type vrf table 40
ip link set mgmt up

# ens3
ip addr add ${eth0_ip} dev ${nic1}
ip link set ${nic1} master mgmt mtu 1460 up
ip route add default via ${eth0_gw} vrf mgmt

# ens4
ip addr add ${nic2_ip} dev ${nic2}
ip link set ${nic2} mtu 1460 up
ip route add default via ${nic2_gw}

echo '$(cat /etc/resolv.conf)' > /etc/resolv.conf
EOF

}

#
# MAIN
#

create_net_setup_script
mkisofs -r -o ${ISO_FILE} ${SCRIPT_DIR}

if [ "${VNC}" == "1" ]; then
  NET_OPTS=" -nic tap,ifname=ens0,br=net0,script=no,downscript=no,mac=$(gen_mac) -nic tap,ifname=ens2,br=net2,script=/root/if-up,downscript=/root/if-down,mac=$(gen_mac) -drive file=${ISO_FILE},media=cdrom"
else
  NET_OPTS=" -nic tap,ifname=ens0,br=net0,script=no,downscript=no,mac=$(gen_mac) -nic tap,ifname=ens1,br=net1,script=/root/if-up,downscript=/root/if-down,mac=$(gen_mac) -drive file=${ISO_FILE},media=cdrom"
fi

