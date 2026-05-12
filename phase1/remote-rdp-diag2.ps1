Write-Output '=== TS REG ==='
Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' | Select-Object fDenyTSConnections | Format-List
Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' | Select-Object PortNumber,UserAuthentication,SecurityLayer | Format-List
Write-Output '=== SERVICES ==='
Get-Service TermService,SessionEnv,UmRdpService | Format-Table -AutoSize Name,Status,StartType
Write-Output '=== QWINSTA ==='
cmd /c qwinsta
Write-Output '=== NETSTAT 3389 ==='
cmd /c netstat -ano | findstr ":3389"
Write-Output '=== FIREWALL RULES ==='
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Select-Object DisplayName,Enabled,Profile,Action | Format-Table -AutoSize
