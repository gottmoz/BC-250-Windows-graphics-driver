$log='C:\Users\Public\bc250_termservice_process_probe3.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== TermService Process Probe ==='
$svc=Get-CimInstance Win32_Service -Filter "Name='TermService'"
$tpid=[int]$svc.ProcessId
W ("TermService PID: " + $tpid)
W ("State: " + $svc.State)
W '--- tasklist /svc ---'
$cmd1 = 'tasklist /svc /fi "pid eq ' + $tpid + '"'
cmd /c $cmd1 2>&1 | Tee-Object -FilePath $log -Append
W '--- tasklist /m ---'
$cmd2 = 'tasklist /m /fi "pid eq ' + $tpid + '"'
cmd /c $cmd2 2>&1 | Tee-Object -FilePath $log -Append
W '--- TCP by owning process ---'
Get-NetTCPConnection -OwningProcess $tpid -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State | Format-Table -Auto | Out-String | Tee-Object -FilePath $log -Append
W '--- UDP endpoints by owning process ---'
Get-NetUDPEndpoint -OwningProcess $tpid -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort | Format-Table -Auto | Out-String | Tee-Object -FilePath $log -Append
W '=== END ==='
