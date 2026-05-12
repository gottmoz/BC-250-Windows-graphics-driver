param(
  [int]$Iterations = 33,
  [string]$OutDir = 'C:\Users\Public\bc250-batch2',
  [switch]$SmokeMode
)
$ErrorActionPreference = 'Continue'

$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$devcon='C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe'
$maps=@('ati2mtag_Raphael','ati2mtag_Phoenix','ati2mtag_Navi33','ati2mtag_DragonRange','ati2mtag_Navi10','ati2mtag_Navi32','ati2mtag_Mendocino')

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = Join-Path $OutDir 'run.log'
$csv = Join-Path $OutDir 'iterations.csv'
$sum = Join-Path $OutDir 'summary.json'
$crash = Join-Path $OutDir 'crash.log'

function Log([string]$m){ $ts=Get-Date -Format o; "$ts $m" | Tee-Object -FilePath $log -Append }
function Crash([string]$m){ $ts=Get-Date -Format o; "$ts $m" | Tee-Object -FilePath $crash -Append }
function Get-State {
  try {
    $p=Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue
    $inf=($p|? KeyName -match 'DriverInfPath').Data
    $code=[int](($p|? KeyName -match 'ProblemCode').Data)
    [pscustomobject]@{Inf=$inf;Code=$code}
  } catch {
    Crash ("Get-State exception: " + $_.Exception.Message)
    [pscustomobject]@{Inf='';Code=-1}
  }
}
function Run-Step([string]$name,[scriptblock]$sb,[int]$timeoutSec=25){
  Log ("RECOVER {0} begin" -f $name)
  $job=Start-Job -ScriptBlock $sb -ArgumentList $inst,$devcon
  if(-not (Wait-Job $job -Timeout $timeoutSec)){
    Stop-Job $job -Force | Out-Null
    Remove-Job $job -Force | Out-Null
    Log ("RECOVER {0} timeout" -f $name)
    Crash ("RECOVER {0} timeout" -f $name)
    return $false
  }
  try { Receive-Job $job | Out-Null } catch { Crash ("RECOVER {0} receive exception: {1}" -f $name,$_.Exception.Message) }
  Remove-Job $job -Force | Out-Null
  Log ("RECOVER {0} end" -f $name)
  return $true
}

$step1 = {
  param($inst,$devcon)
  pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
  pnputil /delete-driver oem9.inf /uninstall /force | Out-Null
  pnputil /delete-driver oem21.inf /uninstall /force | Out-Null
  pnputil /scan-devices | Out-Null
  & $devcon update C:\Windows\INF\display.inf 'PCI\VEN_1002&DEV_13FE' | Out-Null
  pnputil /restart-device "$inst" | Out-Null
  Start-Sleep -Seconds 2
}
$step2 = {
  param($inst,$devcon)
  & $devcon disable "$inst" | Out-Null
  Start-Sleep -Seconds 2
  & $devcon enable "$inst" | Out-Null
  pnputil /scan-devices | Out-Null
  Start-Sleep -Seconds 2
}
$step3 = {
  param($inst,$devcon)
  & $devcon remove "$inst" | Out-Null
  Start-Sleep -Seconds 2
  pnputil /scan-devices | Out-Null
  Start-Sleep -Seconds 2
  & $devcon update C:\Windows\INF\display.inf 'PCI\VEN_1002&DEV_13FE' | Out-Null
  pnputil /restart-device "$inst" | Out-Null
  Start-Sleep -Seconds 2
}

function Recover-Ladder {
  Log 'RECOVER ladder begin'
  [void](Run-Step 'step1' $step1 30)
  $s=Get-State
  if($s.Inf -eq 'display.inf' -and $s.Code -eq 0){ Log 'RECOVER step1 success'; return 'step1' }
  [void](Run-Step 'step2' $step2 20)
  $s=Get-State
  if($s.Inf -eq 'display.inf' -and $s.Code -eq 0){ Log 'RECOVER step2 success'; return 'step2' }
  [void](Run-Step 'step3' $step3 30)
  $s=Get-State
  if($s.Inf -eq 'display.inf' -and $s.Code -eq 0){ Log 'RECOVER step3 success'; return 'step3' }
  Log ("RECOVER failed final INF={0} CODE={1}" -f $s.Inf,$s.Code)
  Crash ("RECOVER failed final INF={0} CODE={1}" -f $s.Inf,$s.Code)
  return 'failed'
}

$rows = New-Object System.Collections.Generic.List[object]
if($SmokeMode){ Log "BATCH2 smoke start iterations=$Iterations" } else { Log "BATCH2 start iterations=$Iterations" }

try {
  for($i=1; $i -le $Iterations; $i++){
    $map=$maps[($i-1)%$maps.Count]
    $pre=Get-State
    $preRec='none'
    if($pre.Inf -ne 'display.inf' -or $pre.Code -ne 0){ $preRec=Recover-Ladder }

    $start=Get-Date
    Log ("ITER {0} map={1} start" -f $i,$map)
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $resLine=$null; $rollLine=$null; $iterExit='n/a'; $iterTimedOut=$false

    $job = Start-Job -ScriptBlock {
      param($map)
      powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\bc250-safe-iterate.ps1 -map $map
      exit $LASTEXITCODE
    } -ArgumentList $map

    if(-not (Wait-Job $job -Timeout 180)){
      $iterTimedOut=$true
      Stop-Job $job -Force | Out-Null
      Remove-Job $job -Force | Out-Null
      Log ("ITER {0} timeout >180s" -f $i)
      Crash ("ITER {0} timeout >180s map={1}" -f $i,$map)
    } else {
      try {
        $out = Receive-Job $job
        $iterExit = $job.ChildJobs[0].JobStateInfo.State
        foreach($ln in $out){
          Log ("ITER {0} {1}" -f $i,$ln)
          if($ln -like 'ITER * RESULT *'){ $resLine = $ln }
          if($ln -like 'ITER * ROLLBACK *'){ $rollLine = $ln }
        }
      } catch {
        Crash ("ITER {0} receive exception: {1}" -f $i,$_.Exception.Message)
      } finally {
        Remove-Job $job -Force | Out-Null
      }
    }

    $sw.Stop()
    $post=Get-State
    $postRec='none'
    if($post.Inf -ne 'display.inf' -or $post.Code -ne 0){ $postRec=Recover-Ladder; $post=Get-State }

    $rows.Add([pscustomobject]@{
      iteration=$i; map=$map; started_at=$start.ToString('o'); seconds=[math]::Round($sw.Elapsed.TotalSeconds,1)
      pre_inf=$pre.Inf; pre_code=$pre.Code; pre_recovery=$preRec
      result_line=($resLine -join ' '); rollback_line=($rollLine -join ' ')
      iter_state=$iterExit; iter_timedout=$iterTimedOut
      post_inf=$post.Inf; post_code=$post.Code; post_recovery=$postRec
      stable_baseline=([bool]($post.Inf -eq 'display.inf' -and $post.Code -eq 0))
    })

    if($SmokeMode -and $i -ge $Iterations){ break }
    Start-Sleep -Seconds 2
  }
} catch {
  Crash ("FATAL loop exception: " + $_.Exception.Message)
  Crash ("FATAL loop stack: " + $_.ScriptStackTrace)
}

try {
  $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
  $summary=[pscustomobject]@{
    generated_at=(Get-Date).ToString('o'); iterations=$rows.Count
    result_code43_count=($rows | ? { $_.result_line -match 'CODE=43' }).Count
    rollback_code0_count=($rows | ? { $_.rollback_line -match 'CODE=0' }).Count
    rollback_code43_count=($rows | ? { $_.rollback_line -match 'CODE=43' }).Count
    stable_baseline_count=($rows | ? { $_.stable_baseline }).Count
    pre_recovery_used=($rows | ? { $_.pre_recovery -ne 'none' }).Count
    post_recovery_used=($rows | ? { $_.post_recovery -ne 'none' }).Count
    recovery_failed_count=($rows | ? { $_.pre_recovery -eq 'failed' -or $_.post_recovery -eq 'failed' }).Count
    avg_seconds= if($rows.Count -gt 0){ [math]::Round((($rows | Measure-Object -Property seconds -Average).Average),1) } else { 0 }
  }
  $summary | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $sum
} catch {
  Crash ("EXPORT exception: " + $_.Exception.Message)
}

if($SmokeMode){ Log 'BATCH2 smoke end' } else { Log 'BATCH2 end' }
