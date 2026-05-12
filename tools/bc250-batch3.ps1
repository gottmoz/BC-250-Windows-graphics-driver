param(
  [int]$Iterations = 20,
  [string]$OutDir = 'C:\Users\Public\bc250-batch3'
)
$ErrorActionPreference = 'Continue'
$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$maps=@('ati2mtag_Raphael','ati2mtag_Phoenix','ati2mtag_Navi33','ati2mtag_DragonRange','ati2mtag_Navi10','ati2mtag_Navi32','ati2mtag_Mendocino')
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log=Join-Path $OutDir 'run.log'; $csv=Join-Path $OutDir 'iterations.csv'; $sum=Join-Path $OutDir 'summary.json'
function Log($m){"$((Get-Date).ToString('o')) $m"|Tee-Object -FilePath $log -Append}
function State(){ $p=Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_ProblemCode -ea SilentlyContinue; [pscustomobject]@{Inf=($p|? KeyName -match 'DriverInfPath').Data; Code=[int](($p|? KeyName -match 'ProblemCode').Data)} }
$rows=@(); Log "BATCH3 start iterations=$Iterations"
for($i=1;$i -le $Iterations;$i++){
  $map=$maps[($i-1)%$maps.Count]
  $pre=State
  Log "ITER $i map=$map start pre=$($pre.Inf)/$($pre.Code)"
  $sw=[Diagnostics.Stopwatch]::StartNew(); $timedOut=$false; $res=''; $roll=''
  $job=Start-Job -ScriptBlock { param($m) powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\bc250-safe-iterate.ps1 -map $m 2>&1 } -ArgumentList $map
  if(-not (Wait-Job $job -Timeout 120)){
    $timedOut=$true; Stop-Job $job -Force|Out-Null; Remove-Job $job -Force|Out-Null; Log "ITER $i timeout>120s"
  } else {
    $out=Receive-Job $job; Remove-Job $job -Force|Out-Null
    foreach($ln in $out){ Log "ITER $i $ln"; if($ln -like 'ITER * RESULT *'){$res=$ln}; if($ln -like 'ITER * ROLLBACK *'){$roll=$ln} }
  }
  $sw.Stop(); $post=State
  $rows += [pscustomobject]@{iteration=$i;map=$map;seconds=[math]::Round($sw.Elapsed.TotalSeconds,1);timed_out=$timedOut;result_line=$res;rollback_line=$roll;post_inf=$post.Inf;post_code=$post.Code;stable_baseline=($post.Inf -eq 'display.inf' -and $post.Code -eq 0)}
  if(-not $rows[-1].stable_baseline){ Log "ITER $i baseline_not_stable STOP_BATCH"; break }
  Start-Sleep -Seconds 2
}
$rows|Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
$summary=[pscustomobject]@{generated_at=(Get-Date).ToString('o');iterations=$rows.Count;timeouts=($rows|? timed_out).Count;code43_results=($rows|? {$_.result_line -match 'CODE=43'}).Count;rollback_code0=($rows|? {$_.rollback_line -match 'CODE=0'}).Count;stable_count=($rows|? stable_baseline).Count;avg_seconds=if($rows.Count){[math]::Round((($rows|measure seconds -Average).Average),1)}else{0}}
$summary|ConvertTo-Json -Depth 4|Set-Content -Encoding UTF8 -Path $sum
Log 'BATCH3 end'
