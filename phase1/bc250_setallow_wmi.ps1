$log='C:\Users\Public\bc250_setallow_wmi.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== WMI SetAllowTSConnections ==='
try {
  $o = Get-WmiObject -Namespace 'root\cimv2\TerminalServices' -Class 'Win32_TerminalServiceSetting' -ErrorAction Stop
  W ('Object found: ' + $o.__CLASS)
  $r1 = $o.SetAllowTSConnections(1)
  W ('SetAllowTSConnections(1) returned: ' + $r1.ReturnValue)
  try {
    $r2 = $o.SetAllowTSConnections(1,1)
    W ('SetAllowTSConnections(1,1) returned: ' + $r2.ReturnValue)
  } catch { W ('SetAllowTSConnections(1,1) error: ' + $_.Exception.Message) }
} catch { W ('Get-WmiObject error: ' + $_.Exception.Message) }
Get-Service TermService | Format-List Status,StartType | Out-String | Tee-Object -FilePath $log -Append
cmd /c "netstat -ano -p tcp | findstr :3389" 2>&1 | Tee-Object -FilePath $log -Append
cmd /c "qwinsta" 2>&1 | Tee-Object -FilePath $log -Append
W '=== END ==='
