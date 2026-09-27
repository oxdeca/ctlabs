# Windows override of qemu_init.sh's create_net_setup_script(). Windows
# guests have no bash/VRF, so instead of the Linux ctlabs_net_setup.sh a
# boot-time scheduled task (baked into the image, see
# images/qemu/windows/2022/packer/files/ctlabs-firstboot.ps1) runs
# ctlabs_net_setup.ps1 generated here.
#
# NICs are matched by MAC address (ENS0_MAC/ENS1_MAC, generated in
# qemu_init.sh's MAIN and passed to qemu_add_nic before this script's
# .ps1 is written) rather than by an assumed "Ethernet"/"Ethernet 2"
# enumeration order -- that assumption doesn't reliably hold, since
# Windows can enumerate virtio-net adapters in either order.
#
# Only the data NIC (ens1) gets a default gateway. Mirrors the Linux
# twin's design, where the mgmt route lives in an isolated `vrf mgmt`
# routing table rather than the main one -- Windows has no VRF equivalent,
# so the simplest safe analogue is: exactly one default gateway, on the
# data interface, and none on mgmt.
create_net_setup_script() {
  local eth0_ip=$( ip -br addr ls eth0 | awk '{print $3}' )
  local eth1_ip=$( ip -br addr ls eth1 | awk '{print $3}' )
  local eth1_gw=$( ip -br route ls default | awk '{print $3}' )
  local dns_servers=($(awk '/^nameserver/{print $2}' /etc/resolv.conf))

  local mac0_win=$( echo "${ENS0_MAC}" | tr '[:lower:]' '[:upper:]' | tr ':' '-' )
  local mac1_win=$( echo "${ENS1_MAC}" | tr '[:lower:]' '[:upper:]' | tr ':' '-' )

  # Windows computer names can't contain dots -- $HOSTNAME here may be an
  # FQDN (e.g. win1.ctlabs.internal), so Rename-Computer needs just the
  # short label or it silently fails to apply.
  local short_hostname="${HOSTNAME%%.*}"

  local dns_ps_list=""
  for ns in "${dns_servers[@]}"; do
    dns_ps_list+="'${ns}',"
  done
  dns_ps_list="${dns_ps_list%,}"

  # Stage the authorized_keys the container already refreshes into
  # /mnt/ssh/ every boot (same file the Linux twin picks up) so
  # ctlabs_net_setup.ps1 below can deploy it into OpenSSH's expected
  # location -- there's no other mechanism that gets it onto the guest.
  mkdir -p /mnt/ssh
  cp /root/.ssh/authorized_keys /mnt/ssh/authorized_keys

cat > /mnt/ctlabs_net_setup.ps1 << EOF
# mgmt (ens0) -- no default gateway, direct-attached subnet only
\$nic0 = Get-NetAdapter | Where-Object { \$_.MacAddress -eq "${mac0_win}" }
if (\$nic0) {
    Remove-NetIPAddress -InterfaceAlias \$nic0.Name -Confirm:\$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceAlias \$nic0.Name -Confirm:\$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias \$nic0.Name -IPAddress "${eth0_ip%/*}" -PrefixLength 24 -ErrorAction SilentlyContinue
    Set-DnsClientServerAddress -InterfaceAlias \$nic0.Name -ServerAddresses @(${dns_ps_list}) -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias \$nic0.Name -Dhcp Disabled
    netsh interface ipv4 set subinterface "\$(\$nic0.Name)" mtu=1460 store=persistent
}

# data (ens1) -- default gateway lives here
\$nic1 = Get-NetAdapter | Where-Object { \$_.MacAddress -eq "${mac1_win}" }
if (\$nic1) {
    Remove-NetIPAddress -InterfaceAlias \$nic1.Name -Confirm:\$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceAlias \$nic1.Name -Confirm:\$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias \$nic1.Name -IPAddress "${eth1_ip%/*}" -PrefixLength 24 -DefaultGateway "${eth1_gw}" -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias \$nic1.Name -Dhcp Disabled
    netsh interface ipv4 set subinterface "\$(\$nic1.Name)" mtu=1460 store=persistent
}

# Allow inbound ping (helps basic reachability checks from the mgmt side)
Enable-NetFirewallRule -Name "FPS-ICMP4-ERQ-In" -ErrorAction SilentlyContinue
Enable-NetFirewallRule -Name "FPS-ICMP6-ERQ-In" -ErrorAction SilentlyContinue

# OpenSSH admin key -- administrators_authorized_keys requires this exact
# ACL (SYSTEM + local Administrators only, inheritance stripped) or sshd
# silently refuses to use it. Path is relative to this script's own
# location (\$PSScriptRoot), not a fixed drive letter -- the boot-time
# agent that invokes this script finds it by scanning all CD-ROM volumes,
# so the letter isn't guaranteed to be D:.
\$keySrc = Join-Path \$PSScriptRoot "ssh\authorized_keys"
if (Test-Path \$keySrc) {
    \$sshDir   = "C:\ProgramData\ssh"
    \$authKeys = "\$sshDir\administrators_authorized_keys"
    New-Item -ItemType Directory -Path \$sshDir -Force -ErrorAction SilentlyContinue | Out-Null
    Copy-Item -Path \$keySrc -Destination \$authKeys -Force
    icacls.exe "\$authKeys" /inheritance:r /grant "SYSTEM:(F)" /grant "BUILTIN\Administrators:(F)" | Out-Null
}

if ((Get-CimInstance Win32_ComputerSystem).Name -ne "${short_hostname}") {
    Rename-Computer -NewName "${short_hostname}" -Force -Restart
}
EOF
}
