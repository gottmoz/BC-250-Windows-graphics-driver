$log='C:\Dev\BC250-windowsDriverTest\r_trace_bg.log'
$flag='C:\Dev\BC250-windowsDriverTest\r_trace_done.flag'
for($i=1;$i -le 20;$i++){
  Start-Sleep -Seconds 20
  $proc=Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in @('MSBuild','link','cl','cmd','powershell') }
  $hasFlag=Test-Path $flag
  "TICK=$i FLAG=$hasFlag PROCS=$($proc.Count)"
  if(Test-Path $log){
    Get-Content $log -Tail 25
  }
  if($hasFlag){ break }
}
