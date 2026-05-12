$log='C:\Users\Public\bc250_termservice_process_probe.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== TermService Process Probe ==='
$svc=Get-CimInstance Win32_Service -Filter "Name='TermService'"
$pid=$svc.ProcessId
W ("TermService PID: " + $pid)
W ("State: " + $svc.State)
W '--- tasklist /svc ---'
cmd /c "tasklist /svc /fi \"pid eq $pid\"" 2>&1 | Tee-Object -FilePath $log -Append
W '--- modules (termsrv/rdp) ---'
cmd /c "tasklist /m /fi \"pid eq $pid\"" 2>&1 | findstr /I "termsrv rdp" | Tee-Object -FilePath $log -Append
W '--- TCP by owning process ---'
Get-NetTCPConnection -OwningProcess $pid -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State | Format-Table -Auto | Out-String | Tee-Object -FilePath $log -Append
W '--- UDP endpoints by owning process ---'
Get-NetUDPEndpoint -OwningProcess $pid -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort | Format-Table -Auto | Out-String | Tee-Object -FilePath $log -Append
W '=== END ==='
