param(
  [int]$Iterations = 30,
  [string]$OutRoot = 'C:\Users\Public\bc250-phaseA-longrun',
  [int]$ExpectedPerIterSec = 72
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $OutRoot $runId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$log = Join-Path $runDir 'longrun.log'

function Log([string]$m) {
  "$((Get-Date).ToString('o')) $m" | Tee-Object -FilePath $log -Append
}

function Start-Batch([string]$batchDir) {
  if(Test-Path $batchDir) {
    Remove-Item (Join-Path $batchDir '*') -Force -ErrorAction SilentlyContinue
  } else {
    New-Item -ItemType Directory -Force -Path $batchDir | Out-Null
  }
  Start-Job -ScriptBlock {
    param($iters)
    powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\bc250-phaseA-batch.ps1 -Iterations $iters
  } -ArgumentList $Iterations
}

function Get-IterCount([string]$csvPath) {
  if(-not (Test-Path $csvPath)) { return 0 }
  try { return (Import-Csv $csvPath).Count } catch { return 0 }
}

$batchDir = 'C:\Users\Public\bc250-phaseA-batch'
$csvPath = Join-Path $batchDir 'iterations.csv'
$summaryPath = Join-Path $batchDir 'summary.json'
$runTailPath = Join-Path $batchDir 'run.log'

$expectedTotalSec = [Math]::Max(600, $Iterations * $ExpectedPerIterSec)
$halfSec = [int]($expectedTotalSec / 2)
$hardTimeoutSec = [int]($expectedTotalSec * 2)
$minHalfIters = [Math]::Max(1, [int]([Math]::Floor($Iterations / 2)))

Log ("LONGRUN start run_id={0} iterations={1} expected_total={2}s half={3}s timeout={4}s" -f $runId,$Iterations,$expectedTotalSec,$halfSec,$hardTimeoutSec)

$job = Start-Batch -batchDir $batchDir
Log ("LONGRUN batch_job_started id={0}" -f $job.Id)

Start-Sleep -Seconds $halfSec
$halfCount = Get-IterCount -csvPath $csvPath
$jobState = (Get-Job -Id $job.Id -ErrorAction SilentlyContinue).State
Log ("HALF_CHECK iter_count={0} min_required={1} job_state={2}" -f $halfCount,$minHalfIters,$jobState)

if($halfCount -lt $minHalfIters -and $jobState -eq 'Running') {
  Log 'HALF_CHECK stall_detected -> restart_once'
  Stop-Job -Id $job.Id -Force -ErrorAction SilentlyContinue | Out-Null
  Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue | Out-Null
  $job = Start-Batch -batchDir $batchDir
  Log ("LONGRUN restarted batch_job id={0}" -f $job.Id)
}

if(-not (Wait-Job -Id $job.Id -Timeout $hardTimeoutSec)) {
  Log 'FINAL_CHECK timeout waiting for batch completion'
  Stop-Job -Id $job.Id -Force -ErrorAction SilentlyContinue | Out-Null
  Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue | Out-Null
  exit 2
}

$out = Receive-Job -Id $job.Id -ErrorAction SilentlyContinue
Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue | Out-Null
foreach($ln in $out) { Log ("BATCH_OUT {0}" -f $ln) }

$finalCount = Get-IterCount -csvPath $csvPath
Log ("FINAL_CHECK iter_count={0}" -f $finalCount)
if(Test-Path $summaryPath) {
  $summary = Get-Content $summaryPath -Raw
  Log ("FINAL_SUMMARY {0}" -f $summary.Replace("`r"," ").Replace("`n"," "))
} else {
  Log 'FINAL_CHECK summary_missing'
}

if(Test-Path $runTailPath) {
  Log 'FINAL_TAIL_BEGIN'
  Get-Content $runTailPath -Tail 20 | ForEach-Object { Log ("RUNLOG {0}" -f $_) }
  Log 'FINAL_TAIL_END'
}

Copy-Item -Path $csvPath -Destination (Join-Path $runDir 'iterations.csv') -Force -ErrorAction SilentlyContinue
Copy-Item -Path $summaryPath -Destination (Join-Path $runDir 'summary.json') -Force -ErrorAction SilentlyContinue
Copy-Item -Path $runTailPath -Destination (Join-Path $runDir 'run.log') -Force -ErrorAction SilentlyContinue

Log 'LONGRUN end'
