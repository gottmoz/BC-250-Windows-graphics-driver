$ErrorActionPreference = 'Continue'
$log = 'C:\Users\Public\bc250-evening-run.log'
$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$devcon='C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe'
$endTime = (Get-Date).Date.AddDays(1).AddHours(7)
$expectedSeconds = 65
$midCheckSeconds = [Math]::Max(20, [int]($expectedSeconds/2))
$hardTimeoutSeconds = [Math]::Max(100, [int]($expectedSeconds*2))

$maps = @('ati2mtag_Raphael','ati2mtag_Phoenix','ati2mtag_Navi33','ati2mtag_DragonRange','ati2mtag_Navi10','ati2mtag_Navi32','ati2mtag_Mendocino','ati2mtag_Navi31','ati2mtag_Navi24','ati2mtag_Navi23')
$variants = @(
  'baseline',
  'svc_demand',
  'svc_auto_start',
  'remove_root_display',
  'rescan_before',
  'disable_enable_before'
)

function Log([string]$m){ "$((Get-Date).ToString('o')) $m" | Tee-Object -FilePath $log -Append }
function Get-State {
  $p = Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue
  [pscustomobject]@{ Inf=($p|? KeyName -match 'DriverInfPath').Data; Code=[int](($p|? KeyName -match 'ProblemCode').Data) }
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
  $s=Get-State
  Log ("RECOVER end INF={0} CODE={1}" -f $s.Inf,$s.Code)
}

function Apply-Variant([string]$variant){
  Log ("VARIANT apply={0}" -f $variant)
  switch($variant){
    'baseline' { }
    'svc_demand' {
      sc.exe stop "AMD Crash Defender Service" | Out-Null
      sc.exe stop "AMD External Events Utility" | Out-Null
      sc.exe config "AMD Crash Defender Service" start= demand | Out-Null
      sc.exe config "AMD External Events Utility" start= demand | Out-Null
    }
    'svc_auto_start' {
      sc.exe config amduw23g start= auto | Out-Null
      sc.exe start amduw23g | Out-Null
    }
    'remove_root_display' {
      pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
    }
    'rescan_before' {
      pnputil /scan-devices | Out-Null
      Start-Sleep -Seconds 1
    }
    'disable_enable_before' {
      & $devcon disable "$inst" | Out-Null
      Start-Sleep -Seconds 1
      & $devcon enable "$inst" | Out-Null
      Start-Sleep -Seconds 1
    }
  }
}

function Run-OneWithWatchdog([int]$iter,[string]$map,[string]$variant){
  $attempt=0
  while($attempt -lt 3){
    $attempt++
    $pre=Get-State
    if($pre.Inf -ne 'display.inf' -or $pre.Code -ne 0){ Recover-Baseline }

    Apply-Variant $variant
    Log ("ITER {0} map={1} variant={2} attempt={3} begin expected={4}s midpoint={5}s timeout={6}s" -f $iter,$map,$variant,$attempt,$expectedSeconds,$midCheckSeconds,$hardTimeoutSeconds)

    $job=Start-Job -ScriptBlock { param($m) powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\bc250-safe-iterate.ps1 -map $m 2>&1 } -ArgumentList $map
    Start-Sleep -Seconds $midCheckSeconds
    $midState=(Get-Job -Id $job.Id -ErrorAction SilentlyContinue).State
    Log ("ITER {0} midpoint state={1}" -f $iter,$midState)

    if($midState -eq 'Failed' -or $midState -eq 'Stopped'){
      Stop-Job $job -Force | Out-Null
      Remove-Job $job -Force | Out-Null
      Log ("ITER {0} midpoint_fail -> recover+restart" -f $iter)
      Recover-Baseline
      continue
    }

    if(-not (Wait-Job $job -Timeout ($hardTimeoutSeconds - $midCheckSeconds))){
      Stop-Job $job -Force | Out-Null
      Remove-Job $job -Force | Out-Null
      Log ("ITER {0} timeout -> recover+restart" -f $iter)
      Recover-Baseline
      continue
    }

    $out=Receive-Job $job
    Remove-Job $job -Force | Out-Null
    foreach($ln in $out){ Log ("ITER {0} {1}" -f $iter,$ln) }

    $post=Get-State
    if($post.Inf -eq 'display.inf' -and $post.Code -eq 0){
      Log ("ITER {0} done stable" -f $iter)
      return $true
    }

    Log ("ITER {0} post-baseline drift INF={1} CODE={2} -> recover+restart" -f $iter,$post.Inf,$post.Code)
    Recover-Baseline
  }

  Log ("ITER {0} failed after retries" -f $iter)
  return $false
}

# build unique combination queue, then repeat with +pass index if runtime exceeds queue
$combos = @()
foreach($m in $maps){ foreach($v in $variants){ $combos += [pscustomobject]@{Map=$m;Variant=$v} } }

Log 'EVENING_RUN start'
$iter=0
$idx=0
$pass=1
while((Get-Date) -lt $endTime){
  $iter++
  if($idx -ge $combos.Count){ $idx=0; $pass++ }
  $c=$combos[$idx]
  $idx++
  $variantTag = if($pass -gt 1){ "$($c.Variant)-p$pass" } else { $c.Variant }
  [void](Run-OneWithWatchdog -iter $iter -map $c.Map -variant $c.Variant)
  Log ("ITER {0} combo_done map={1} variant={2}" -f $iter,$c.Map,$variantTag)
  Start-Sleep -Seconds 2
}
Log 'EVENING_RUN end'
