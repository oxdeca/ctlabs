$ErrorActionPreference = "Stop"

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
} while ($info.LastTaskResult -eq 267009)

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
if ($info.LastTaskResult -ne 0) {
    $detail = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { "(no log at $logPath)" }
    throw "OpenSSH install via scheduled task failed with code $($info.LastTaskResult): $detail"
}

Set-Service -Name sshd -StartupType Manual
New-NetFirewallRule -Name sshd -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null

if (-not (Get-LocalUser -Name "root" -ErrorAction SilentlyContinue)) {
    $rootPassword = ConvertTo-SecureString (([System.Guid]::NewGuid().ToString()) + "!Aa1") -AsPlainText -Force
    New-LocalUser -Name "root" -Password $rootPassword -PasswordNeverExpires -AccountNeverExpires -UserMayNotChangePassword | Out-Null
    Add-LocalGroupMember -Group "Administrators" -Member "root"
}
if (-not (Get-LocalUser -Name "ansible" -ErrorAction SilentlyContinue)) {
    $ansiblePassword = ConvertTo-SecureString (([System.Guid]::NewGuid().ToString()) + "!Aa1") -AsPlainText -Force
    New-LocalUser -Name "ansible" -Password $ansiblePassword -PasswordNeverExpires -AccountNeverExpires -UserMayNotChangePassword | Out-Null
    Add-LocalGroupMember -Group "Administrators" -Member "ansible"
}
if (-not (Get-LocalUser -Name "ctlabs" -ErrorAction SilentlyContinue)) {
    $ctlabsPassword = ConvertTo-SecureString "secret123!" -AsPlainText -Force
    New-LocalUser -Name "ctlabs" -Password $ctlabsPassword -PasswordNeverExpires -AccountNeverExpires -UserMayNotChangePassword | Out-Null
    Add-LocalGroupMember -Group "Administrators" -Member "ctlabs"
}

$installType = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name InstallationType).InstallationType
if ($installType -eq "Server") {
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
}

New-Item -ItemType Directory -Path "C:\ProgramData\ctlabs" -Force | Out-Null
$agentPath = "C:\ProgramData\ctlabs\ctlabs-net-agent.ps1"

@'
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

Set-TimeZone -Id "Eastern Standard Time"

function Optimize-Assemblies {
    param (
        [string]$assemblyFilter = "Microsoft.PowerShell.",
        [string]$activity = "Native Image Installation"
    )

    try {
        $ngenPath = [System.IO.Path]::Combine([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory(), "ngen.exe")

        if (-Not (Test-Path $ngenPath)) {
            Write-Host "Ngen.exe not found at $ngenPath. Make sure .NET Framework is installed."
            return
        }

        $assemblies = [AppDomain]::CurrentDomain.GetAssemblies()
        $filteredAssemblies = $assemblies | Where-Object { $_.FullName -ilike "$assemblyFilter*" }

        if ($filteredAssemblies.Count -eq 0) {
            Write-Host "No matching assemblies found for optimization."
            return
        }

        foreach ($assembly in $filteredAssemblies) {
            $name = [System.IO.Path]::GetFileName($assembly.Location)
            Write-Progress -Activity $activity -Status "Optimizing $name"
            Start-Process -FilePath $ngenPath -ArgumentList "install `"$($assembly.Location)`"" -Wait -WindowStyle Hidden
        }

        Write-Host "Optimization complete."
    } catch {
        Write-Host "An error occurred: $_"
    }
}

Optimize-Assemblies -assemblyFilter "Microsoft.PowerShell."
