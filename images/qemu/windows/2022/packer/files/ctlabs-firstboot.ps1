# Run by Packer's winrm provisioner before sysprep -- bakes ctlabs's Windows
# guest-side agent into the image: OpenSSH Server + a boot-time task that
# re-applies network config from the qemu_init.sh-injected ISO every boot.
# Windows has no systemd/ctlabs-net.service equivalent, so a Scheduled Task
# at every startup fills that role (see images/qemu/base/files/qemu_init.sh's
# ctlabs_net_setup.ps1 emission -- this agent is what actually runs it).
#
# DRAFT / UNVALIDATED (2026-09-25): OpenSSH capability name, drive discovery,
# and the "run at every boot, no drive letter assumed" logic below have not
# been run against a real guest.

$ErrorActionPreference = "Stop"

# --- OpenSSH Server ---
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
New-NetFirewallRule -Name sshd -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

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
