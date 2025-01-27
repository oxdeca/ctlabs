#!/bin/bash

SCRIPT_DIR="/oem"
ISO_FILE="/tmp/${HOSTNAME}.iso"

gen_mac() {
  local premac="52:54:00:"
  echo ${premac}$(openssl rand -hex 3 | awk '{gsub(/.{2}/,"&:")}1' | sed 's@.$@@')
}

create_net_setup_script() {
  local premac="52:54:00:12:34:"
  local eth1_ip=$( ip -br addr ls eth1     | awk '{print $3}' )
  local eth1_gw=$( ip -br route ls default | awk '{print $3}' )
  local eth2_ip=$( ip -br addr ls eth2     | awk '{print $3}' )
  local eth2_gw=$( ip -br route ls default | awk '{print $3}' )
  local nic="Ethernet"
  local nic_ip=${eth1_ip}
  local nic_gw=${eth1_gw}
  if [ "${VNC}" == "1" ]; then
    nic_ip=${eth2_ip}
    nic_gw=${eth2_gw}
  fi

cat > ${SCRIPT_DIR}/ctlabs.ps1 << EOF
# powershell script to setup ethernet devices

# disable interfaces
netsh interface set interface "${nic}" disable

# enable interfaces we need
netsh interface set interface "${nic}" enable

# set mtu=1460
netsh interface ipv4 set subinterface "${nic}" mtu=1460 store=persistent

# set ip
netsh interface ipv4 set address name="${nic}" static ${nic_ip} 255.255.255.0 ${nic_gw}

# dns
netsh interface ipv4 add dnsserver name="${nic}" address=1.1.1.1 index=1
netsh interface ipv4 add dnsserver name="${nic}" address=8.8.8.8 index=2
EOF

}

if [ ! -d ${SCRIPT_DIR} ]; then
  mkdir -vp ${SCRIPT_DIR}
fi
create_net_setup_script
mkisofs -r -o ${ISO_FILE} ${SCRIPT_DIR}

if [ "${VNC}" == "1" ]; then
  NET_OPTS="-nic tap,ifname=ens2,br=net2,script=/root/if-up,downscript=/root/if-down,mac=$(gen_mac) -drive file=${ISO_FILE},media=cdrom"
else
  NET_OPTS="-nic tap,ifname=ens1,br=net1,script=/root/if-up,downscript=/root/if-down,mac=$(gen_mac) -drive file=${ISO_FILE},media=cdrom"
fi
