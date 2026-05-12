$ErrorActionPreference='Continue'
$repo='C:\Dev\BC250-windowsDriverTest'
$kmd=Join-Path $repo 'amdbc250_kmd.c'
$bak=Join-Path $repo 'amdbc250_kmd.c.initapibak'
$log=Join-Path $repo 'init-api-ab-batch.log'
$runner='C:\Users\Public\remote-iter-fast.ps1'

function Log([string]$m){
  $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line="[$ts] $m"
  Add-Content -LiteralPath $log -Value $line
  Write-Output $line
}

function Set-VersionSdkDefault([string]$text){
  return [regex]::Replace(
    $text,
    '(?s)#if defined\(DXGKDDI_INTERFACE_VERSION_WDDM2_0\)\s*DriverInitData\.Version\s*=\s*DXGKDDI_INTERFACE_VERSION_WDDM2_0;\s*#else\s*DriverInitData\.Version\s*=\s*DXGKDDI_INTERFACE_VERSION_WDDM1_3;\s*#endif',
    'DriverInitData.Version = DXGKDDI_INTERFACE_VERSION;'
  )
}

function Transform-ToDod([string]$text,[bool]$vsyncOff){
  $txt=$text
  $txt=$txt.Replace('DRIVER_INITIALIZATION_DATA DriverInitData = {0};','KMDDOD_INITIALIZATION_DATA DriverInitData = {0};')
  $txt=Set-VersionSdkDefault $txt
  $txt=$txt.Replace(
    'Status = DxgkInitialize(DriverObject, RegistryPath, &DriverInitData);',
    'Status = DxgkInitializeDisplayOnlyDriver(DriverObject, RegistryPath, &DriverInitData);'
  )

  $dropFields=@(
    'DxgkDdiCreateDevice','DxgkDdiDestroyDevice',
    'DxgkDdiCreateContext','DxgkDdiDestroyContext',
    'DxgkDdiCreateAllocation','DxgkDdiDestroyAllocation',
    'DxgkDdiOpenAllocation','DxgkDdiCloseAllocation',
    'DxgkDdiBuildPagingBuffer','DxgkDdiPatch',
    'DxgkDdiSubmitCommand','DxgkDdiPreemptCommand',
    'DxgkDdiQueryCurrentFence','DxgkDdiPresent',
    'DxgkDdiRender','DxgkDdiRenderKm'
  )
  $vsyncGroup=@('DxgkDdiControlInterrupt','DxgkDdiGetScanLine','DxgkDdiInterruptRoutine','DxgkDdiDpcRoutine')

  $lines=$txt -split "`r?`n"
  $start=-1; $end=-1
  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -match '/\* Core device lifecycle callbacks \*/'){ $start=$i }
    if($lines[$i] -match '/\* Register with Dxgkrnl \*/'){ $end=$i; break }
  }
  if($start -lt 0 -or $end -lt 0){ return $txt }

  $newLines = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $lines.Count;$i++){
    if($i -eq $end){
      $newLines.Add('    DriverInitData.DxgkDdiPresentDisplayOnly                             = NULL;')
      $newLines.Add('    DriverInitData.DxgkDdiStopDeviceAndReleasePostDisplayOwnership       = NULL;')
      $newLines.Add('    DriverInitData.DxgkDdiSystemDisplayEnable                            = NULL;')
      $newLines.Add('    DriverInitData.DxgkDdiSystemDisplayWrite                             = NULL;')
      $newLines.Add('    DriverInitData.DxgkDdiGetChildContainerId                            = NULL;')
      $newLines.Add('    DriverInitData.DxgkDdiSetPowerComponentFState                        = NULL;')
      $newLines.Add('    DriverInitData.DxgkDdiPowerRuntimeControlRequest                      = NULL;')
      $newLines.Add('    DriverInitData.DxgkDdiNotifySurpriseRemoval                          = NULL;')
      $newLines.Add('    DriverInitData.DxgkDdiPowerRuntimeSetDeviceHandle                    = NULL;')
    }

    if($i -ge $start -and $i -lt $end -and $lines[$i] -match '^\s*DriverInitData\.(DxgkDdi\w+)\s*=\s*(.+);\s*$'){
      $cb=$Matches[1]
      if($dropFields -contains $cb){
        $newLines.Add("    /* DOD omit: $cb */")
        continue
      }
      if($vsyncOff -and ($vsyncGroup -contains $cb)){
        $newLines.Add(("    DriverInitData.$cb").PadRight(72) + " = NULL;")
        continue
      }
    }
    $newLines.Add($lines[$i])
  }

  return [string]::Join("`r`n",$newLines)
}

function Run-Iteration([string]$name){
  Log "ITER_START $name"
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $job=Start-Job -ScriptBlock {
    powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Public\remote-iter-fast.ps1'
    exit $LASTEXITCODE
  }

  Start-Sleep -Seconds 60
  $state=(Get-Job -Id $job.Id).State
  Log "HALFTIME_CHECK $name state=$state elapsed=60s"

  $completed=Wait-Job -Id $job.Id -Timeout 120
  if(-not $completed){
    Log "ITER_TIMEOUT $name exceeded 180s; stopping and restarting once"
    Stop-Job -Id $job.Id -Force | Out-Null
    Remove-Job -Id $job.Id -Force | Out-Null

    $sw2=[Diagnostics.Stopwatch]::StartNew()
    $out2=powershell -NoProfile -ExecutionPolicy Bypass -File $runner 2>&1
    $code2=$LASTEXITCODE
    $sw2.Stop()
    $tmp2=Join-Path $repo ("tmp_"+$name+"_retry.log")
    $out2 | Out-File -LiteralPath $tmp2 -Encoding ascii
    $marker2=(Select-String -Path $tmp2 -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|problem status: 0xc0000059|0xC00000E5|GUARD_EXIT=|KMD build failed|DxgkInitialize failed' | Select-Object -Last 1).Line
    if(-not $marker2){ $marker2='(no marker found)' }
    Log "ITER_END $name retry exit=$code2 seconds=$([math]::Round($sw2.Elapsed.TotalSeconds,1)) marker=$marker2"
    return
  }

  $out=Receive-Job -Id $job.Id
  $code=$job.ChildJobs[0].JobStateInfo.Reason
  $exitCode=0
  if($out -is [array]){
    $tmp=Join-Path $repo ("tmp_"+$name+".log")
    $out | Out-File -LiteralPath $tmp -Encoding ascii
  } else {
    $tmp=Join-Path $repo ("tmp_"+$name+".log")
    $out | Out-File -LiteralPath $tmp -Encoding ascii
  }

  # Derive process exit code from captured output marker when available.
  $exitMarker=(Select-String -Path $tmp -Pattern 'GUARD_EXIT=([0-9-]+)' | Select-Object -Last 1)
  if($exitMarker){
    $exitCode=[int]$exitMarker.Matches[0].Groups[1].Value
  }

  $sw.Stop()
  Remove-Job -Id $job.Id -Force | Out-Null
  $sec=[math]::Round($sw.Elapsed.TotalSeconds,1)
  $marker=(Select-String -Path $tmp -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|problem status: 0xc0000059|0xC00000E5|GUARD_EXIT=|KMD build failed|DxgkInitialize failed' | Select-Object -Last 1).Line
  if(-not $marker){ $marker='(no marker found)' }
  Log "ITER_END $name exit=$exitCode seconds=$sec marker=$marker"
}

if(!(Test-Path $runner)){
  throw "Runner missing: $runner"
}
if(!(Test-Path $bak)){
  Copy-Item -LiteralPath $kmd -Destination $bak -Force
}
$base=Get-Content -LiteralPath $bak -Raw

$variants=@(
  @{Name='AB1_dxgk_baseline'; Kind='dxgk'; VsyncOff=$false; SdkVersion=$false},
  @{Name='AB2_dxgk_sdkver'; Kind='dxgk'; VsyncOff=$false; SdkVersion=$true},
  @{Name='AB3_dod_vsync_on'; Kind='dod';  VsyncOff=$false; SdkVersion=$true},
  @{Name='AB4_dod_vsync_off';Kind='dod';  VsyncOff=$true;  SdkVersion=$true}
)

foreach($v in $variants){
  $txt=$base
  if($v.SdkVersion){
    $txt=Set-VersionSdkDefault $txt
  }
  if($v.Kind -eq 'dod'){
    $txt=Transform-ToDod -text $txt -vsyncOff:$v.VsyncOff
  }
  Set-Content -LiteralPath $kmd -Value $txt -Encoding ASCII -NoNewline
  Run-Iteration -name $v.Name
}

Copy-Item -LiteralPath $bak -Destination $kmd -Force
Log 'Init API A/B batch done; source restored.'
