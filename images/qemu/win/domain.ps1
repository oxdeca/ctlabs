#
# Windows PowerShell script for AD DS Deployment
#
# https://dev.to/ekurtovic/automating-active-directory-deployment-on-windows-server-2022-using-powershell-script-3b2p

# Change hostname first


# Promote to ADDC

Import-Module ADDSDeployment
Install-ADDSForest `
-CreateDnsDelegation:$false `
-DatabasePath "C:\Windows\NTDS" `
-DomainMode "WinThreshold" `
-DomainName "ctlabs.internal" `
-DomainNetbiosName "CTLABS" `
-ForestMode "WinThreshold" `
-InstallDns:$true `
-LogPath "C:\Windows\NTDS" `
-NoRebootOnCompletion:$false `
-SysvolPath "C:\Windows\SYSVOL" `
-Force:$true
