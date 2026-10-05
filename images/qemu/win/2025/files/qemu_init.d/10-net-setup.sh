create_net_setup_script() {
  local eth0_ip=$( ip -br addr ls eth0 | awk '{print $3}' )
  local eth1_ip=$( ip -br addr ls eth1 | awk '{print $3}' )
  local eth1_gw=$( ip -br route ls default | awk '{print $3}' )
  local dns_servers=($(awk '/^nameserver/{print $2}' /etc/resolv.conf))

  local mac0_win=$( echo "${ENS0_MAC}" | tr '[:lower:]' '[:upper:]' | tr ':' '-' )
  local mac1_win=$( echo "${ENS1_MAC}" | tr '[:lower:]' '[:upper:]' | tr ':' '-' )

  local short_hostname="${HOSTNAME%%.*}"

  local dns_ps_list=""
  for ns in "${dns_servers[@]}"; do
    dns_ps_list+="'${ns}',"
  done
  dns_ps_list="${dns_ps_list%,}"

  local mgmt_dns_ps_list=""
  for ns in "${dns_servers[@]}"; do
    if [[ ! "$ns" =~ ^10\. ]] && [[ ! "$ns" =~ ^192\.168\. ]] && [[ ! "$ns" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
      mgmt_dns_ps_list+="'${ns}',"
    fi
  done
  mgmt_dns_ps_list="${mgmt_dns_ps_list%,}"

  mkdir -p /mnt/ssh
  # ctlabs injects the lab public key into this container before qemu starts;
  # prefer the login user's home (see qemu_init.sh) and fall back to root's.
  _ctlabs_ssh_user="${CTLABS_SSH_USER:-ansible}"
  if id -u "$_ctlabs_ssh_user" >/dev/null 2>&1; then
    _ctlabs_auth="/home/${_ctlabs_ssh_user}/.ssh/authorized_keys"
  else
    _ctlabs_auth="/root/.ssh/authorized_keys"
  fi
  # Loud on failure but non-fatal: the rest of this script still has to
  # configure the network, and a guest with no key is still better than one
  # that never got configured. Grep the qemu journal for this line.
  cp "$_ctlabs_auth" /mnt/ssh/authorized_keys || \
    echo "ERROR: failed to copy $_ctlabs_auth to /mnt/ssh/authorized_keys - guest will have no SSH key" >&2

cat > /mnt/ctlabs_net_setup.ps1 << EOF
if ((Get-CimInstance Win32_ComputerSystem).Name -ne "${short_hostname}") {
    Rename-Computer -NewName "${short_hostname}" -Force -Restart
    exit
}

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

Enable-NetFirewallRule -Name "FPS-ICMP4-ERQ-In" -ErrorAction SilentlyContinue
Enable-NetFirewallRule -Name "FPS-ICMP6-ERQ-In" -ErrorAction SilentlyContinue

\$sshdConfig = "C:\ProgramData\ssh\sshd_config"
if (Test-Path \$sshdConfig) {
    \$lines = Get-Content \$sshdConfig | Where-Object { \$_ -notmatch '^\s*ListenAddress\s' }
    Set-Content -Path \$sshdConfig -Value \$lines -Encoding ASCII
}

if ((Get-Service -Name sshd -ErrorAction SilentlyContinue).Status -ne "Running") {
    Start-Service -Name sshd -ErrorAction SilentlyContinue
}

\$keySrc = Join-Path \$PSScriptRoot "ssh\authorized_keys"
if (Test-Path \$keySrc) {
    \$sshDir   = "C:\ProgramData\ssh"
    \$authKeys = "\$sshDir\administrators_authorized_keys"
    New-Item -ItemType Directory -Path \$sshDir -Force -ErrorAction SilentlyContinue | Out-Null
    Copy-Item -Path \$keySrc -Destination \$authKeys -Force
    icacls.exe "\$authKeys" /inheritance:r /grant "SYSTEM:(F)" /grant "BUILTIN\Administrators:(F)" | Out-Null
}
EOF
}
