# Windows override of qemu_init.sh's create_net_setup_script(). Windows
# guests have no bash/VRF, so instead of the Linux ctlabs_net_setup.sh a
# boot-time scheduled task (baked into the image, see
# images/qemu/win/2022/packer/files/ctlabs-firstboot.ps1) runs
# ctlabs_net_setup.ps1 generated here.
#
# NICs are matched by MAC address (ENS0_MAC/ENS1_MAC, generated in
# qemu_init.sh's MAIN and passed to qemu_add_nic before this script's
# .ps1 is written) rather than by an assumed "Ethernet"/"Ethernet 2"
# enumeration order -- that assumption doesn't reliably hold, since
# Windows can enumerate virtio-net adapters in either order. Once matched,
# they're renamed to eth0 (mgmt) / eth1 (data) for parity with the
# container-side interface names.
#
# Only the data NIC (ens1) gets a default gateway. Windows has no VRF
# equivalent to the Linux hosts' `vrf mgmt` isolation, so mgmt/data
# separation here is approximated with strong-host mode (no cross-interface
# send/receive) on both. sshd is currently listening on both interfaces
# (see the disabled mgmt-only ListenAddress block below) -- OpenSSH wasn't
# listening at all as of 2026-09-27, root cause not yet found, so the
# mgmt-only restriction is on hold until that's sorted out first.
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

  # mgmt only gets external resolvers -- the RFC1918/internal ones (e.g.
  # 192.168.10.11) live on the data network, which mgmt can no longer
  # reach once strong-host mode is applied below. Matches the existing
  # convention elsewhere (see labs/net/*.yml: the mgmt plane's own `dns`
  # list is external-only, distinct from the host-wide list).
  local mgmt_dns_ps_list=""
  for ns in "${dns_servers[@]}"; do
    if [[ ! "$ns" =~ ^10\. ]] && [[ ! "$ns" =~ ^192\.168\. ]] && [[ ! "$ns" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
      mgmt_dns_ps_list+="'${ns}',"
    fi
  done
  mgmt_dns_ps_list="${mgmt_dns_ps_list%,}"

  # Stage the authorized_keys the container already refreshes into
  # /mnt/ssh/ every boot (same file the Linux twin picks up) so
  # ctlabs_net_setup.ps1 below can deploy it into OpenSSH's expected
  # location -- there's no other mechanism that gets it onto the guest.
  mkdir -p /mnt/ssh
  cp /root/.ssh/authorized_keys /mnt/ssh/authorized_keys

cat > /mnt/ctlabs_net_setup.ps1 << EOF
# mgmt (ens0) -- renamed eth0, no default gateway, direct-attached subnet
# only, strong-host mode so it can't be used to reach the data side
\$nic0 = Get-NetAdapter | Where-Object { \$_.MacAddress -eq "${mac0_win}" }
if (\$nic0) {
    Rename-NetAdapter -InputObject \$nic0 -NewName "eth0" -ErrorAction SilentlyContinue
    Remove-NetIPAddress -InterfaceAlias "eth0" -Confirm:\$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceAlias "eth0" -Confirm:\$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias "eth0" -IPAddress "${eth0_ip%/*}" -PrefixLength 24 -ErrorAction SilentlyContinue
$( [ -n "$mgmt_dns_ps_list" ] && echo "    Set-DnsClientServerAddress -InterfaceAlias \"eth0\" -ServerAddresses @(${mgmt_dns_ps_list}) -ErrorAction SilentlyContinue" )
    Set-NetIPInterface -InterfaceAlias "eth0" -Dhcp Disabled -WeakHostSend Disabled -WeakHostReceive Disabled -Forwarding Disabled -ErrorAction SilentlyContinue
    netsh interface ipv4 set subinterface "eth0" mtu=1460 store=persistent
}

# data (ens1) -- renamed eth1, default gateway lives here
\$nic1 = Get-NetAdapter | Where-Object { \$_.MacAddress -eq "${mac1_win}" }
if (\$nic1) {
    Rename-NetAdapter -InputObject \$nic1 -NewName "eth1" -ErrorAction SilentlyContinue
    Remove-NetIPAddress -InterfaceAlias "eth1" -Confirm:\$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceAlias "eth1" -Confirm:\$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias "eth1" -IPAddress "${eth1_ip%/*}" -PrefixLength 24 -DefaultGateway "${eth1_gw}" -ErrorAction SilentlyContinue
    Set-DnsClientServerAddress -InterfaceAlias "eth1" -ServerAddresses @(${dns_ps_list}) -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceAlias "eth1" -Dhcp Disabled -WeakHostSend Disabled -WeakHostReceive Disabled -Forwarding Disabled -ErrorAction SilentlyContinue
    netsh interface ipv4 set subinterface "eth1" mtu=1460 store=persistent
}

# Allow inbound ping (helps basic reachability checks from the mgmt side)
Enable-NetFirewallRule -Name "FPS-ICMP4-ERQ-In" -ErrorAction SilentlyContinue
Enable-NetFirewallRule -Name "FPS-ICMP6-ERQ-In" -ErrorAction SilentlyContinue

# mgmt-only ListenAddress binding is DISABLED 2026-09-27 -- root-caused:
# sshd's Automatic start at boot races the IP actually being assigned
# (this net-setup script, which assigns it, runs from a boot-time
# scheduled task -- there's no guarantee it wins that race against sshd's
# own service start). A stale ListenAddress pinned to a specific IP means
# sshd fails to bind and just stays stopped, since Windows doesn't retry a
# failed Automatic-start service. Listening on both interfaces for now
# avoids the race entirely (0.0.0.0 doesn't need any specific IP to exist
# yet). Still strip any ListenAddress line left over from before this fix
# so it doesn't keep failing on boxes that already hit the race once.
\$sshdConfig = "C:\ProgramData\ssh\sshd_config"
if (Test-Path \$sshdConfig) {
    \$lines = Get-Content \$sshdConfig | Where-Object { \$_ -notmatch '^\s*ListenAddress\s' }
    Set-Content -Path \$sshdConfig -Value \$lines -Encoding ASCII
}

# Self-heal: if sshd's own Automatic-start lost the boot-order race and
# ended up Stopped, start it here instead of waiting for a full reboot --
# this script (which just finished configuring the network) is guaranteed
# to run after the IP is actually up.
if ((Get-Service -Name sshd -ErrorAction SilentlyContinue).Status -ne "Running") {
    Start-Service -Name sshd -ErrorAction SilentlyContinue
}

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
