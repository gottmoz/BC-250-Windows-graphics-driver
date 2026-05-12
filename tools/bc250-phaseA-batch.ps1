param(
  [int]$Iterations = 24,
  [string]$OutDir = 'C:\Users\Public\bc250-phaseA-batch'
)

$ErrorActionPreference = 'Continue'
$inst = 'PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$devcon = 'C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe'
$iterScript = 'C:\Users\Public\bc250-safe-iterate.ps1'

$maps = @('ati2mtag_Raphael','ati2mtag_Phoenix','ati2mtag_Navi33','ati2mtag_DragonRange','ati2mtag_Navi10')
$variants = @('svc_demand','svc_auto','bind_then_restart','disable_enable_cycle','root_display_cleanup','rescan_first')

$expectedSeconds = 80
$midpointSeconds = 40
$hardTimeoutSeconds = 170

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = Join-Path $OutDir 'run.log'
$csv = Join-Path $OutDir 'iterations.csv'
$summary = Join-Path $OutDir 'summary.json'

function Log([string]$m) {
  "$((Get-Date).ToString('o')) $m" | Tee-Object -FilePath $log -Append
}

function Get-State {
  $p = Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue
  [pscustomobject]@{
    Inf  = ($p | Where-Object KeyName -match 'DriverInfPath').Data
    Code = [int](($p | Where-Object KeyName -match 'ProblemCode').Data)
  }
}

function Recover-Baseline {
  Log 'RECOVER begin'
  pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
  pnputil /delete-driver oem9.inf /uninstall /force | Out-Null
  pnputil /delete-driver oem21.inf /uninstall /force | Out-Null
  pnputil /scan-devices | Out-Null
  & $devcon remove "$inst" | Out-Null
  Start-Sleep -Seconds 2
  pnputil /scan-devices | Out-Null
  Start-Sleep -Seconds 2
  & $devcon update C:\Windows\INF\display.inf 'PCI\VEN_1002&DEV_13FE' | Out-Null
  pnputil /restart-device "$inst" | Out-Null
  Start-Sleep -Seconds 2
  $s = Get-State
  Log ("RECOVER end INF={0} CODE={1}" -f $s.Inf,$s.Code)
}

function Apply-Variant([string]$variant) {
  Log ("VARIANT apply={0}" -f $variant)
  switch($variant) {
    'svc_demand' {
      sc.exe config amduw23g start= demand | Out-Null
      sc.exe stop amduw23g | Out-Null
    }
    'svc_auto' {
      sc.exe config amduw23g start= auto | Out-Null
      sc.exe start amduw23g | Out-Null
    }
    'bind_then_restart' {
      pnputil /restart-device "$inst" | Out-Null
      Start-Sleep -Seconds 2
    }
    'disable_enable_cycle' {
      & $devcon disable "$inst" | Out-Null
      Start-Sleep -Seconds 1
      & $devcon enable "$inst" | Out-Null
      Start-Sleep -Seconds 1
    }
    'root_display_cleanup' {
      pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
      Start-Sleep -Seconds 1
    }
    'rescan_first' {
      pnputil /scan-devices | Out-Null
      Start-Sleep -Seconds 1
    }
  }
}

$rows = @()
$tested = New-Object 'System.Collections.Generic.HashSet[string]'
Log ("PHASEA_BATCH start iterations={0} expected={1}s midpoint={2}s timeout={3}s" -f $Iterations,$expectedSeconds,$midpointSeconds,$hardTimeoutSeconds)

for($i=1; $i -le $Iterations; $i++) {
  $map = $maps[($i - 1) % $maps.Count]
  $variant = $variants[($i - 1) % $variants.Count]
  $combo = "$map|$variant"
  if($tested.Contains($combo)) {
    $variant = $variants[($i + 1) % $variants.Count]
    $combo = "$map|$variant"
  }
  [void]$tested.Add($combo)

  $iterId = "{0:yyyyMMdd-HHmmss}-I{1:D3}" -f (Get-Date), $i
  $pre = Get-State
  if($pre.Inf -ne 'display.inf') { Recover-Baseline }

  Apply-Variant $variant
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $timedOut = $false
  $midState = ''
  $resLine = ''
  $rollLine = ''

  Log ("ITER {0} begin id={1} map={2} variant={3}" -f $i,$iterId,$map,$variant)
  $job = Start-Job -ScriptBlock {
    param($m,$iterScriptPath)
    powershell -NoProfile -ExecutionPolicy Bypass -File $iterScriptPath -map $m 2>&1
  } -ArgumentList $map,$iterScript

  Start-Sleep -Seconds $midpointSeconds
  $midState = (Get-Job -Id $job.Id -ErrorAction SilentlyContinue).State
  Log ("ITER {0} midpoint state={1}" -f $i,$midState)

  if(-not (Wait-Job $job -Timeout ($hardTimeoutSeconds - $midpointSeconds))) {
    $timedOut = $true
    Stop-Job $job -Force | Out-Null
    Remove-Job $job -Force | Out-Null
    Log ("ITER {0} timeout" -f $i)
  } else {
    $out = Receive-Job $job
    Remove-Job $job -Force | Out-Null
    foreach($ln in $out) {
      Log ("ITER {0} {1}" -f $i,$ln)
      if($ln -like 'ITER * RESULT *') { $resLine = $ln }
      if($ln -like 'ITER * ROLLBACK *') { $rollLine = $ln }
    }
  }

  $sw.Stop()
  $post = Get-State
  if($post.Inf -ne 'display.inf') { Recover-Baseline; $post = Get-State }

  $rows += [pscustomobject]@{
    iteration = $i
    iter_id = $iterId
    map = $map
    variant = $variant
    combo = $combo
    seconds = [math]::Round($sw.Elapsed.TotalSeconds,1)
    midpoint_state = $midState
    timed_out = $timedOut
    result_line = $resLine
    rollback_line = $rollLine
    post_inf = $post.Inf
    post_code = $post.Code
    stable_baseline = ($post.Inf -eq 'display.inf')
  }
}

$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
$sum = [pscustomobject]@{
  generated_at = (Get-Date).ToString('o')
  iterations = $rows.Count
  unique_combos = ($rows | Select-Object -ExpandProperty combo -Unique).Count
  code43_results = ($rows | Where-Object { $_.result_line -match 'CODE=43' }).Count
  rollback_code0 = ($rows | Where-Object { $_.rollback_line -match 'CODE=0' }).Count
  timeouts = ($rows | Where-Object timed_out).Count
  midpoint_failed = ($rows | Where-Object { $_.midpoint_state -in @('Failed','Stopped') }).Count
  avg_seconds = if($rows.Count){ [math]::Round((($rows | Measure-Object seconds -Average).Average),1) } else { 0 }
}
$sum | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $summary

Log 'PHASEA_BATCH end'
