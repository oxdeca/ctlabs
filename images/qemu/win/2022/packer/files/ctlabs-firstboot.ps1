# Run by Packer's winrm provisioner before sysprep -- bakes ctlabs's Windows
# guest-side agent into the image: OpenSSH Server + a boot-time task that
# re-applies network config from the qemu_init.sh-injected ISO every boot.
# Windows has no systemd/ctlabs-net.service equivalent, so a Scheduled Task
# at every startup fills that role (see images/qemu/base/files/qemu_init.sh's
# ctlabs_net_setup.ps1 emission -- this agent is what actually runs it).
#
# DRAFT / UNVALIDATED (2026-09-25): drive discovery and the "run at every
# boot, no drive letter assumed" logic below have not been run against a
# real guest.

$ErrorActionPreference = "Stop"

# --- OpenSSH Server ---
# NOT a direct Add-WindowsCapability call -- confirmed 2026-09-26 (both on
# h3 and independently on a second host, same error): DISM-backed cmdlets
# like this one fail with "Access is denied" (COMException) when invoked
# directly inside a WinRM/PSRemoting session -- a known double-hop-style
# restriction, not something wrong with the capability name or privileges.
# Standard fix: run it via a scheduled task (SYSTEM, triggered locally),
# which gets a full token WinRM's remote session doesn't provide.
$taskName = "ctlabs-install-openssh"
$logPath  = "C:\Windows\Temp\ctlabs-openssh-install.log"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 *> '$logPath'`""
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

do {
    Start-Sleep -Seconds 2
    $info = Get-ScheduledTaskInfo -TaskName $taskName
} while ($info.LastTaskResult -eq 267009) # SCHED_S_TASK_RUNNING

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
if ($info.LastTaskResult -ne 0) {
    # Confirmed 2026-09-26: a bare LastTaskResult code (e.g. "1") is useless
    # on its own -- capture the actual DISM/PowerShell error text the task
    # produced so the next failure (if any) is diagnosable without another
    # full rebuild cycle.
    $detail = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { "(no log at $logPath)" }
    throw "OpenSSH install via scheduled task failed with code $($info.LastTaskResult): $detail"
}

Set-Service -Name sshd -StartupType Automatic
New-NetFirewallRule -Name sshd -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

# --- root user, for Ansible SSH-key parity with the Linux hosts ---
# Password is thrown away -- login is key-only via
# administrators_authorized_keys, which OpenSSH applies to any member of
# the local Administrators group regardless of username, so root just
# needs to exist and be in that group (see qemu_init.d/10-net-setup.sh,
# which deploys the actual key on every boot).
if (-not (Get-LocalUser -Name "root" -ErrorAction SilentlyContinue)) {
    $rootPassword = ConvertTo-SecureString (([System.Guid]::NewGuid().ToString()) + "!Aa1") -AsPlainText -Force
    New-LocalUser -Name "root" -Password $rootPassword -PasswordNeverExpires -AccountNeverExpires -UserMayNotChangePassword | Out-Null
    Add-LocalGroupMember -Group "Administrators" -Member "root"
}

# --- RDP + ctlabs user, Desktop Experience only ---
# core and dtop run this exact same script (the variant only changes
# which image autounattend.xml installs, see win2022.pkr.hcl/build.sh) --
# gate on the actual installation type rather than needing a separate
# Packer variable threaded through, so this stays correctly scoped even
# if that ever changes. HKLM...CurrentVersion's InstallationType is
# "Server" for Desktop Experience, "Server Core" for Core -- same
# registry value Get-ComputerInfo reads, checked directly here to skip
# its slow full-system inventory.
$installType = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name InstallationType).InstallationType
if ($installType -eq "Server") {
    # Enable Remote Desktop
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

    # ctlabs local admin user -- fixed/known password by request, matching
    # the rest of ctlabs' lab-credential convention (e.g. the Linux
    # images' own "root:secret"), not a secure production credential.
    # Being in Administrators also means it automatically picks up SSH
    # key access via administrators_authorized_keys, same as root.
    if (-not (Get-LocalUser -Name "ctlabs" -ErrorAction SilentlyContinue)) {
        $ctlabsPassword = ConvertTo-SecureString "secret123!" -AsPlainText -Force
        New-LocalUser -Name "ctlabs" -Password $ctlabsPassword -PasswordNeverExpires -AccountNeverExpires | Out-Null
        Add-LocalGroupMember -Group "Administrators" -Member "ctlabs"
    }
}

# --- boot-time net-setup agent ---
New-Item -ItemType Directory -Path "C:\ProgramData\ctlabs" -Force | Out-Null
$agentPath = "C:\ProgramData\ctlabs\ctlabs-net-agent.ps1"

@'
# Finds and runs ctlabs_net_setup.ps1 off whichever optical drive the lab
# host injected this boot. qemu_init.sh bakes a fresh ISO with fresh IPs on
# every container start, so this can't assume a fixed drive letter the way
# a one-shot FirstLogonCommand could.
Get-Volume | Where-Object { $_.DriveType -eq "CD-ROM" -and $_.DriveLetter } | ForEach-Object {
    $script = "$($_.DriveLetter):\ctlabs_net_setup.ps1"
    if (Test-Path $script) {
        & $script
    }
}
'@ | Set-Content -Path $agentPath -Encoding UTF8

$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$agentPath`""
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "ctlabs-net-agent" -Action $action -Trigger $trigger -Principal $principal -Force

# --- parity with the c9/c10 images ---
Set-TimeZone -Id "Eastern Standard Time"
