$ErrorActionPreference='Continue'
$repo='C:\Dev\BC250-windowsDriverTest'
$kmd=Join-Path $repo 'amdbc250_kmd.c'
$bak=Join-Path $repo 'amdbc250_kmd.c.kmdodbak'
$log=Join-Path $repo 'kmdod-profile-batch-v2.log'

function Log([string]$m){$ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss';$line="[$ts] $m";Add-Content -LiteralPath $log -Value $line;Write-Output $line}
if(!(Test-Path $bak)){Copy-Item -LiteralPath $kmd -Destination $bak -Force}
$base=Get-Content -LiteralPath $bak -Raw

$profiles=@(
 @{Name='Q1_kmdod_min'; Keep=@('DxgkDdiAddDevice','DxgkDdiStartDevice','DxgkDdiStopDevice','DxgkDdiRemoveDevice','DxgkDdiDispatchIoRequest','DxgkDdiResetDevice','DxgkDdiUnload','DxgkDdiSetPowerState','DxgkDdiQueryChildRelations','DxgkDdiQueryChildStatus','DxgkDdiQueryDeviceDescriptor','DxgkDdiSetPalette','DxgkDdiSetPointerPosition','DxgkDdiSetPointerShape','DxgkDdiIsSupportedVidPn','DxgkDdiSetVidPnSourceAddress','DxgkDdiRecommendFunctionalVidPn','DxgkDdiEnumVidPnCofuncModality','DxgkDdiSetVidPnSourceVisibility','DxgkDdiCommitVidPn','DxgkDdiUpdateActiveVidPnPresentPath','DxgkDdiRecommendMonitorModes','DxgkDdiGetScanLine','DxgkDdiQueryVidPnHWCapability')},
 @{Name='Q2_plus_query'; Keep=@('DxgkDdiAddDevice','DxgkDdiStartDevice','DxgkDdiStopDevice','DxgkDdiRemoveDevice','DxgkDdiDispatchIoRequest','DxgkDdiResetDevice','DxgkDdiUnload','DxgkDdiSetPowerState','DxgkDdiQueryChildRelations','DxgkDdiQueryChildStatus','DxgkDdiQueryDeviceDescriptor','DxgkDdiSetPalette','DxgkDdiSetPointerPosition','DxgkDdiSetPointerShape','DxgkDdiIsSupportedVidPn','DxgkDdiSetVidPnSourceAddress','DxgkDdiRecommendFunctionalVidPn','DxgkDdiEnumVidPnCofuncModality','DxgkDdiSetVidPnSourceVisibility','DxgkDdiCommitVidPn','DxgkDdiUpdateActiveVidPnPresentPath','DxgkDdiRecommendMonitorModes','DxgkDdiGetScanLine','DxgkDdiQueryVidPnHWCapability','DxgkDdiQueryAdapterInfo','DxgkDdiQueryInterface')},
 @{Name='Q3_plus_mem'; Keep=@('DxgkDdiAddDevice','DxgkDdiStartDevice','DxgkDdiStopDevice','DxgkDdiRemoveDevice','DxgkDdiDispatchIoRequest','DxgkDdiResetDevice','DxgkDdiUnload','DxgkDdiSetPowerState','DxgkDdiQueryChildRelations','DxgkDdiQueryChildStatus','DxgkDdiQueryDeviceDescriptor','DxgkDdiSetPalette','DxgkDdiSetPointerPosition','DxgkDdiSetPointerShape','DxgkDdiIsSupportedVidPn','DxgkDdiSetVidPnSourceAddress','DxgkDdiRecommendFunctionalVidPn','DxgkDdiEnumVidPnCofuncModality','DxgkDdiSetVidPnSourceVisibility','DxgkDdiCommitVidPn','DxgkDdiUpdateActiveVidPnPresentPath','DxgkDdiRecommendMonitorModes','DxgkDdiGetScanLine','DxgkDdiQueryVidPnHWCapability','DxgkDdiQueryAdapterInfo','DxgkDdiQueryInterface','DxgkDdiCreateDevice','DxgkDdiDestroyDevice','DxgkDdiCreateContext','DxgkDdiDestroyContext','DxgkDdiCreateAllocation','DxgkDdiDestroyAllocation','DxgkDdiOpenAllocation','DxgkDdiCloseAllocation','DxgkDdiBuildPagingBuffer','DxgkDdiPatch')},
 @{Name='Q4_plus_render'; Keep=@('DxgkDdiAddDevice','DxgkDdiStartDevice','DxgkDdiStopDevice','DxgkDdiRemoveDevice','DxgkDdiDispatchIoRequest','DxgkDdiResetDevice','DxgkDdiUnload','DxgkDdiSetPowerState','DxgkDdiQueryChildRelations','DxgkDdiQueryChildStatus','DxgkDdiQueryDeviceDescriptor','DxgkDdiSetPalette','DxgkDdiSetPointerPosition','DxgkDdiSetPointerShape','DxgkDdiIsSupportedVidPn','DxgkDdiSetVidPnSourceAddress','DxgkDdiRecommendFunctionalVidPn','DxgkDdiEnumVidPnCofuncModality','DxgkDdiSetVidPnSourceVisibility','DxgkDdiCommitVidPn','DxgkDdiUpdateActiveVidPnPresentPath','DxgkDdiRecommendMonitorModes','DxgkDdiGetScanLine','DxgkDdiQueryVidPnHWCapability','DxgkDdiQueryAdapterInfo','DxgkDdiQueryInterface','DxgkDdiCreateDevice','DxgkDdiDestroyDevice','DxgkDdiCreateContext','DxgkDdiDestroyContext','DxgkDdiCreateAllocation','DxgkDdiDestroyAllocation','DxgkDdiOpenAllocation','DxgkDdiCloseAllocation','DxgkDdiBuildPagingBuffer','DxgkDdiPatch','DxgkDdiSubmitCommand','DxgkDdiQueryCurrentFence','DxgkDdiPresent','DxgkDdiRender')}
)

foreach($p in $profiles){
  $txt=$base
  $lines=$txt -split "`r?`n"

  $start=-1; $end=-1
  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -match '/\* Core device lifecycle callbacks \*/'){ $start=$i }
    if($lines[$i] -match '/\* Register with Dxgkrnl \*/'){ $end=$i; break }
  }
  if($start -lt 0 -or $end -lt 0){ Log "ITER_SKIP $($p.Name) could not locate DriverEntry callback block"; continue }

  for($i=$start; $i -lt $end; $i++){
    if($lines[$i] -match '^\s*DriverInitData\.(DxgkDdi\w+)\s*=\s*(.+);\s*$'){
      $cb=$Matches[1]
      if($p.Keep -contains $cb){
        # keep existing assignment
      } else {
        $lines[$i] = "    DriverInitData.$cb".PadRight(52) + " = NULL;"
      }
    }
  }

  $txt=[string]::Join("`r`n",$lines)
  Set-Content -LiteralPath $kmd -Value $txt -Encoding ASCII -NoNewline

  Log "ITER_START $($p.Name)"
  $sw=[Diagnostics.Stopwatch]::StartNew(); $out=powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Public\remote-iter-fast.ps1' 2>&1; $code=$LASTEXITCODE; $sw.Stop(); $sec=[math]::Round($sw.Elapsed.TotalSeconds,1)
  $tmp=Join-Path $repo ("tmp_"+$p.Name+".log"); $out|Out-File -LiteralPath $tmp -Encoding ascii
  $marker=(Select-String -Path $tmp -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|problem status: 0xc0000059|0xC00000E5|GUARD_EXIT=|KMD build failed'|Select-Object -Last 1).Line
  Log "ITER_END $($p.Name) exit=$code seconds=$sec marker=$marker"
  if($sec -gt 180){Log "ITER_ABORT $($p.Name) exceeded 180s";break}
}

Copy-Item -LiteralPath $bak -Destination $kmd -Force
Log 'KMDOD profile v2 batch done; source restored.'
