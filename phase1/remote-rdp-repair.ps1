$ErrorActionPreference='Continue'
Write-Output '=== ENABLE RDP CORE ==='
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Type DWord
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 0 -Type DWord

Write-Output '=== SERVICE ==='
Set-Service -Name TermService -StartupType Automatic
Start-Service -Name TermService
Get-Service -Name TermService | Format-List Name,Status,StartType

Write-Output '=== FIREWALL ==='
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Select-Object DisplayName,Enabled,Profile,Direction,Action | Format-Table -AutoSize

Write-Output '=== LISTENER ==='
$port=(Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'PortNumber').PortNumber
"PortNumber=$port"
Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,State,OwningProcess | Format-Table -AutoSize

Write-Output '=== RDP USERS GROUP ==='
cmd /c "net localgroup \"Remote Desktop Users\""

Write-Output '=== IP SNAPSHOT ==='
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.254*' } | Select-Object InterfaceAlias,IPAddress,PrefixLength | Format-Table -AutoSize
