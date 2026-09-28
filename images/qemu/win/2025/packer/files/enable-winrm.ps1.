# Stop immediately if any command fails.
# This helps Packer fail fast instead of continuing with a broken WinRM setup.
$ErrorActionPreference = "Stop"

# Windows sometimes marks the network as Public during first boot.
# WinRM is harder to enable on Public networks, so we switch Public profiles to Private.
Get-NetConnectionProfile |
  Where-Object { $_.NetworkCategory -eq "Public" } |
  ForEach-Object {
    Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
  }

# Enable PowerShell remoting.
# -Force avoids interactive prompts.
# -SkipNetworkProfileCheck allows setup even if Windows still thinks the network is Public.
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Initialize WinRM with default listener/configuration.
winrm quickconfig -quiet

# Allow unencrypted WinRM traffic.
# This is acceptable for temporary image-build automation only.
# Harden this before using the image in production.
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# Enable Basic authentication for Packer's WinRM communicator.
# This must match the Packer template settings:
#   winrm_use_ssl  = false
#   winrm_insecure = true
winrm set winrm/config/service/auth '@{Basic="true"}'

# Increase the WinRM timeout so longer Packer provisioning steps do not fail too early.
winrm set winrm/config '@{MaxTimeoutms="1800000"}'

# Open Windows Firewall for WinRM HTTP on port 5985.
# Packer forwards a localhost port on the build host to 5985 inside the VM.
New-NetFirewallRule `
  -DisplayName "WinRM-HTTP-In" `
  -Name "WinRM-HTTP-In" `
  -Protocol TCP `
  -LocalPort 5985 `
  -Action Allow `
  -Direction Inbound `
  -ErrorAction SilentlyContinue

# Make sure WinRM starts automatically after reboot.
Set-Service -Name WinRM -StartupType Automatic

# Restart WinRM so all configuration changes take effect.
Restart-Service -Name WinRM

Write-Output "WinRM configured for Packer."
