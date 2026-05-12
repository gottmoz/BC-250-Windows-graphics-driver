$log='C:\Users\Public\bc250_termservice_bindwatch.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Out-File -FilePath $log -Encoding utf8 -Append; $m}
W '=== TermService Bind Watch ==='
W ('Start time ' + (Get-Date -Format s))
sc.exe stop TermService | Out-Null
Start-Sleep -Seconds 2
sc.exe start TermService | Out-Null
for($i=0;$i -lt 25;$i++){
  $ts=(Get-Date -Format 'HH:mm:ss.fff')
  $line=(cmd /c "netstat -ano -p tcp | findstr :3389")
  if([string]::IsNullOrWhiteSpace($line)){ W ("$ts :: no3389") } else { W ("$ts :: $line") }
  Start-Sleep -Milliseconds 500
}
W '--- service status ---'
sc.exe queryex TermService | Out-File -FilePath $log -Encoding utf8 -Append
W '--- qwinsta ---'
(cmd /c qwinsta) | Out-File -FilePath $log -Encoding utf8 -Append
W '=== END ==='
