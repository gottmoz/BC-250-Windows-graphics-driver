$log='C:\Users\Public\bc250_rdp_deepdiag.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== RDP DEEP DIAG ==='
W '--- SC QC TERMSERVICE ---'
sc.exe qc TermService | Tee-Object -FilePath $log -Append
W '--- SC QUERYEX TERMSERVICE ---'
sc.exe queryex TermService | Tee-Object -FilePath $log -Append
$pid=(Get-CimInstance Win32_Service -Filter "Name='TermService'").ProcessId
W "TermService PID: $pid"
W '--- TASKLIST SVC ---'
cmd /c "tasklist /svc /fi \"pid eq $pid\"" 2>&1 | Tee-Object -FilePath $log -Append
W '--- NETSTAT FOR PID ---'
cmd /c "netstat -ano | findstr \" $pid\"" 2>&1 | Tee-Object -FilePath $log -Append
W '--- RDP-Tcp key dump ---'
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /s 2>&1 | Tee-Object -FilePath $log -Append
W '--- TERM LOGS (System) ---'
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='TermService'; StartTime=(Get-Date).AddDays(-2)} -MaxEvents 120 | Select-Object TimeCreated,Id,LevelDisplayName,Message | Format-List | Out-String | Tee-Object -FilePath $log -Append
W '--- TERM LSM LOGS ---'
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'; StartTime=(Get-Date).AddDays(-2)} -MaxEvents 120 | Select-Object TimeCreated,Id,LevelDisplayName,Message | Format-List | Out-String | Tee-Object -FilePath $log -Append
W '--- REMOTECONNECTIONMANAGER LOGS ---'
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'; StartTime=(Get-Date).AddDays(-2)} -MaxEvents 120 | Select-Object TimeCreated,Id,LevelDisplayName,Message | Format-List | Out-String | Tee-Object -FilePath $log -Append
W '=== END ==='
