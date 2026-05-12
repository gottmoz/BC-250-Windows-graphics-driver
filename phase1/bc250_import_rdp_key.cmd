$ts=Get-Date -Format yyyyMMdd-HHmmss
$bak="C:\Users\Public\RDP-Tcp_backup_$ts.reg"
reg export "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" "$bak" /y
reg import "C:\Users\Public\rdp-tcp-baseline.reg"
sc stop TermService
timeout /t 3 /nobreak >nul
sc start TermService
timeout /t 4 /nobreak >nul
sc start UmRdpService
netstat -ano -p tcp | findstr :3389
qwinsta
