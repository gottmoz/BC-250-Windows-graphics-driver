$ErrorActionPreference='Continue'
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Type DWord
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 0 -Type DWord
Set-Service -Name TermService -StartupType Automatic
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
Restart-Service -Name TermService -Force
Start-Sleep -Seconds 5
$port=(Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'PortNumber').PortNumber
$diag='C:\BC250_Driver\rdp_startup_fix_status.txt'
"$(Get-Date -Format s) port=$port" | Out-File -LiteralPath $diag -Encoding ascii
cmd /c netstat -an | findstr ":$port" | Out-File -LiteralPath $diag -Append -Encoding ascii
cmd /c qwinsta | Out-File -LiteralPath $diag -Append -Encoding ascii
