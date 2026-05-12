$ErrorActionPreference='Continue'
$ts=Get-Date -Format 'yyyyMMdd-HHmmss'
$log="C:\Users\Public\bc250_diag_rdp_debug_$ts.log"
function W($m){ $m | Tee-Object -FilePath $log -Append }
W "=== BC250 Diag $ts ==="
W "--- WHOAMI ---"
whoami | Tee-Object -FilePath $log -Append
whoami /groups | Tee-Object -FilePath $log -Append
W "--- BCD CURRENT ---"
cmd /c "bcdedit /enum {current}" 2>&1 | Tee-Object -FilePath $log -Append
W "--- BCD DBGSETTINGS ---"
cmd /c "bcdedit /dbgsettings" 2>&1 | Tee-Object -FilePath $log -Append
W "--- NET ADAPTERS (incl hidden) ---"
Get-NetAdapter -IncludeHidden | Sort-Object ifIndex | Format-Table -Auto Name,InterfaceDescription,Status,MacAddress | Out-String | Tee-Object -FilePath $log -Append
W "--- NET IP ---"
Get-NetIPAddress -AddressFamily IPv4 | Sort-Object InterfaceIndex | Format-Table -Auto InterfaceAlias,IPAddress,PrefixLength | Out-String | Tee-Object -FilePath $log -Append
W "--- SERVICES ---"
Get-Service TermService,UmRdpService,SessionEnv | Format-Table -Auto Name,Status,StartType | Out-String | Tee-Object -FilePath $log -Append
W "--- RDP LISTENER ---"
cmd /c "netstat -ano | findstr :3389" 2>&1 | Tee-Object -FilePath $log -Append
W "--- QWINSTA ---"
cmd /c "qwinsta" 2>&1 | Tee-Object -FilePath $log -Append
W "--- RDP REG ---"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections 2>&1 | Tee-Object -FilePath $log -Append
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber 2>&1 | Tee-Object -FilePath $log -Append
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication 2>&1 | Tee-Object -FilePath $log -Append
W "--- FIREWALL RDP RULES ---"
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Select-Object DisplayName,Enabled,Profile,Direction,Action | Format-Table -Auto | Out-String | Tee-Object -FilePath $log -Append
W "--- BC250 TASKS ---"
try {
  $csv = schtasks /Query /FO CSV /V 2>$null | ConvertFrom-Csv
  $csv | Where-Object { $_.TaskName -like '\\BC250*' } | Select-Object TaskName,Status,'Schedule Type','Next Run Time','Last Run Time','Task To Run','Run As User' | Format-Table -Auto | Out-String | Tee-Object -FilePath $log -Append
} catch {
  W $_
}
W "=== END ==="
Write-Output $log
