$ErrorActionPreference = "SilentlyContinue"

Write-Output "1. Cleaning WinSxS Component Store..."
Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase

Write-Output "2. Clearing Temp files & Windows Update Cache..."
Stop-Service -Name wuauserv -Force
Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force

# Safely delete temp files while preserving Packer's active wrapper scripts
Get-ChildItem -Path "C:\Windows\Temp\*" -Exclude "packer-*" | Remove-Item -Recurse -Force
Remove-Item -Path "C:\Users\*\AppData\Local\Temp\*" -Recurse -Force

Write-Output "3. Disabling Hibernation..."
powercfg /hibernate off

Write-Output "4. Trimming NTFS Volume..."
Optimize-Volume -DriveLetter C -ReTrim

Write-Output "5. Zeroing unallocated space..."
$path = "C:\zero.tmp"
$stream = [System.IO.File]::Create($path)
$chunk = New-Object byte[] 1048576 # 1MB chunk
try {
    while ($true) {
        $stream.Write($chunk, 0, $chunk.Length)
    }
} catch {
    # Disk full exception expected
} finally {
    $stream.Close()
    Remove-Item $path -Force
}
