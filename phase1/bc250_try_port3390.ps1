$k='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
Set-ItemProperty -Path $k -Name PortNumber -Type DWord -Value 3390
Stop-Service TermService -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service TermService -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4
cmd /c "netstat -ano -p tcp | findstr :3390"
cmd /c "netstat -ano -p udp | findstr :3390"
cmd /c qwinsta
