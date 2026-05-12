$ErrorActionPreference='Continue'
Write-Output '=== WMI RDP RESET ==='
$ts=Get-WmiObject -Namespace root\cimv2\TerminalServices -Class Win32_TerminalServiceSetting -ErrorAction SilentlyContinue
if($null -eq $ts){ Write-Output 'Win32_TerminalServiceSetting not found' }
else {
  Write-Output ('SetAllowTSConnections=' + ($ts.SetAllowTSConnections(1,1).ReturnValue))
  Write-Output ('SetUserAuthenticationRequired=' + ($ts.SetUserAuthenticationRequired(0).ReturnValue))
  Write-Output ('SetSecurityLayer=' + ($ts.SetSecurityLayer(0).ReturnValue))
}
Restart-Service TermService -Force
Start-Sleep -Seconds 3
Write-Output '=== LOCAL TEST ==='
Test-NetConnection 127.0.0.1 -Port 3389 | Select-Object ComputerName,RemotePort,TcpTestSucceeded
cmd /c netstat -an | findstr 3389
cmd /c qwinsta
