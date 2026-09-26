# Run by Packer's winrm provisioner before sysprep -- bakes ctlabs's Windows
# guest-side agent into the image: OpenSSH Server + a boot-time task that
# re-applies network config from the qemu_init.sh-injected ISO every boot.

$ErrorActionPreference = "Stop"

# --- Disable & Kill SConfig ---
if (Get-Command Set-SConfig -ErrorAction SilentlyContinue) {
    Set-SConfig -AutoLaunch $false
}
Get-Process -Name "sconfig", "cmd" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*sconfig*" } | Stop-Process -Force -ErrorAction SilentlyContinue

# --- OpenSSH Server ---
$taskName = "ctlabs-install-openssh"
$logPath  = "C:\Windows\Temp\ctlabs-openssh-install.log"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 *> '$logPath'`""
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

do {
    Start-Sleep -Seconds 2
    $info = Get-ScheduledTaskInfo -TaskName $taskName
} while ($info.LastTaskResult -eq 267009) # SCHED_S_TASK_RUNNING

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
if ($info.LastTaskResult -ne 0) {
    $detail = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { "(no log at $logPath)" }
    throw "OpenSSH install via scheduled task failed with code $($info.LastTaskResult): $detail"
}

Set-Service -Name sshd -StartupType Automatic
New-NetFirewallRule -Name sshd -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null

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
Register-ScheduledTask -TaskName "ctlabs-net-agent" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

# --- parity with the c9/c10 images ---
Set-TimeZone -Id "Eastern Standard Time" | Out-Null
