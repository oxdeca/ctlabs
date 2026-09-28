$ErrorActionPreference = "Stop"

Get-NetConnectionProfile |
  Where-Object { $_.NetworkCategory -eq "Public" } |
  ForEach-Object {
    Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
  }

Enable-PSRemoting -Force -SkipNetworkProfileCheck

winrm quickconfig -quiet

winrm set winrm/config/service '@{AllowUnencrypted="true"}'

winrm set winrm/config/service/auth '@{Basic="true"}'

winrm set winrm/config '@{MaxTimeoutms="1800000"}'

New-NetFirewallRule `
  -DisplayName "WinRM-HTTP-In" `
  -Name "WinRM-HTTP-In" `
  -Protocol TCP `
  -LocalPort 5985 `
  -Action Allow `
  -Direction Inbound `
  -ErrorAction SilentlyContinue

Set-Service -Name WinRM -StartupType Automatic

Restart-Service -Name WinRM

Write-Output "WinRM configured for Packer."
