$ErrorActionPreference='Continue'
$repo='C:\Dev\BC250-windowsDriverTest'
$kmd=Join-Path $repo 'amdbc250_kmd.c'
$bak=Join-Path $repo 'amdbc250_kmd.c.initbak'
$log=Join-Path $repo 'init-contract-batch.log'

function Log([string]$m){
  $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line="[$ts] $m"
  Add-Content -LiteralPath $log -Value $line
  Write-Output $line
}

if(!(Test-Path $bak)){
  Copy-Item -LiteralPath $kmd -Destination $bak -Force
}
$base=Get-Content -LiteralPath $bak -Raw

$kmdodMinKeep=@(
  'DxgkDdiAddDevice','DxgkDdiStartDevice','DxgkDdiStopDevice','DxgkDdiRemoveDevice',
  'DxgkDdiDispatchIoRequest','DxgkDdiResetDevice','DxgkDdiUnload','DxgkDdiSetPowerState',
  'DxgkDdiQueryChildRelations','DxgkDdiQueryChildStatus','DxgkDdiQueryDeviceDescriptor',
  'DxgkDdiSetPalette','DxgkDdiSetPointerPosition','DxgkDdiSetPointerShape','DxgkDdiIsSupportedVidPn',
  'DxgkDdiSetVidPnSourceAddress','DxgkDdiRecommendFunctionalVidPn','DxgkDdiEnumVidPnCofuncModality',
  'DxgkDdiSetVidPnSourceVisibility','DxgkDdiCommitVidPn','DxgkDdiUpdateActiveVidPnPresentPath',
  'DxgkDdiRecommendMonitorModes','DxgkDdiGetScanLine','DxgkDdiQueryVidPnHWCapability'
)

$variants=@(
  @{
    Name='R1_v13_qiqa_intr_on'
    Version='DXGKDDI_INTERFACE_VERSION_WDDM1_3'
    Keep=$kmdodMinKeep + @('DxgkDdiQueryAdapterInfo','DxgkDdiQueryInterface','DxgkDdiInterruptRoutine','DxgkDdiDpcRoutine')
  },
  @{
    Name='R2_v13_qiqa_intr_off'
    Version='DXGKDDI_INTERFACE_VERSION_WDDM1_3'
    Keep=$kmdodMinKeep + @('DxgkDdiQueryAdapterInfo','DxgkDdiQueryInterface')
  },
  @{
    Name='R3_v13_qiqa_off_intr_off'
    Version='DXGKDDI_INTERFACE_VERSION_WDDM1_3'
    Keep=$kmdodMinKeep
  },
  @{
    Name='R4_v20_qiqa_intr_off'
    Version='DXGKDDI_INTERFACE_VERSION_WDDM2_0'
    Keep=$kmdodMinKeep + @('DxgkDdiQueryAdapterInfo','DxgkDdiQueryInterface')
  },
  @{
    Name='R5_sdkdefault_qiqa_intr_off'
    Version='DXGKDDI_INTERFACE_VERSION'
    Keep=$kmdodMinKeep + @('DxgkDdiQueryAdapterInfo','DxgkDdiQueryInterface')
  },
  @{
    Name='R6_v20_qiqa_off_intr_off'
    Version='DXGKDDI_INTERFACE_VERSION_WDDM2_0'
    Keep=$kmdodMinKeep
  }
)

foreach($v in $variants){
  $txt=$base
  $lines=$txt -split "`r?`n"

  $start=-1; $end=-1
  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -match '/\* Core device lifecycle callbacks \*/'){ $start=$i }
    if($lines[$i] -match '/\* Register with Dxgkrnl \*/'){ $end=$i; break }
  }
  if($start -lt 0 -or $end -lt 0){
    Log "ITER_SKIP $($v.Name) could not locate DriverEntry block"
    continue
  }

  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -match '^\s*DriverInitData\.Version\s*='){
      $lines[$i] = "    DriverInitData.Version = $($v.Version);"
    }
  }

  for($i=$start; $i -lt $end; $i++){
    if($lines[$i] -match '^\s*DriverInitData\.(DxgkDdi\w+)\s*=\s*(.+);\s*$'){
      $cb=$Matches[1]
      if($v.Keep -contains $cb){
        # keep original callback assignment
      } else {
        $lines[$i] = "    DriverInitData.$cb".PadRight(52) + " = NULL;"
      }
    }
  }

  $txt=[string]::Join("`r`n",$lines)
  Set-Content -LiteralPath $kmd -Value $txt -Encoding ASCII -NoNewline

  Log "ITER_START $($v.Name) version=$($v.Version)"
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $out=powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Public\remote-iter-fast.ps1' 2>&1
  $code=$LASTEXITCODE
  $sw.Stop()
  $sec=[math]::Round($sw.Elapsed.TotalSeconds,1)
  $tmp=Join-Path $repo ("tmp_"+$v.Name+".log")
  $out | Out-File -LiteralPath $tmp -Encoding ascii

  $marker=(Select-String -Path $tmp -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|problem status: 0xc0000059|0xC00000E5|GUARD_EXIT=|KMD build failed|DxgkInitialize failed' | Select-Object -Last 1).Line
  if(-not $marker){ $marker='(no marker found)' }
  Log "ITER_END $($v.Name) exit=$code seconds=$sec marker=$marker"

  if($sec -gt 180){
    Log "ITER_ABORT $($v.Name) exceeded 180s"
    break
  }
}

Copy-Item -LiteralPath $bak -Destination $kmd -Force
Log 'Init-contract batch done; source restored.'
