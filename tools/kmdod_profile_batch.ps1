$ErrorActionPreference='Continue'
$repo='C:\Dev\BC250-windowsDriverTest'
$kmd=Join-Path $repo 'amdbc250_kmd.c'
$bak=Join-Path $repo 'amdbc250_kmd.c.kmdodbak'
$log=Join-Path $repo 'kmdod-profile-batch.log'

function Log([string]$m){$ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss';$line="[$ts] $m";Add-Content -LiteralPath $log -Value $line;Write-Output $line}
if(!(Test-Path $bak)){Copy-Item -LiteralPath $kmd -Destination $bak -Force}
$base=Get-Content -LiteralPath $bak -Raw

$profiles=@(
 @{Name='P1_kmdod_min'; Display='1'; Query='0'; Mem='0'; Render='0'; Int='0'},
 @{Name='P2_kmdod_plus_query'; Display='1'; Query='1'; Mem='0'; Render='0'; Int='0'},
 @{Name='P3_kmdod_plus_mem'; Display='1'; Query='1'; Mem='1'; Render='0'; Int='0'},
 @{Name='P4_kmdod_plus_render'; Display='1'; Query='1'; Mem='1'; Render='1'; Int='0'}
)

foreach($p in $profiles){
  $txt=$base

  # Start from all callbacks nulled, then enable selected groups.
  $lines=$txt -split "`r?`n"
  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -match '^\s*DriverInitData\.DxgkDdi'){ $lines[$i]=($lines[$i] -replace '=\s*[^;]+;','= NULL;') }
  }

  # Always-required core lifecycle.
  $core=@(
    'DxgkDdiAddDevice                 = Bc250DdiAddDevice;',
    'DxgkDdiStartDevice               = Bc250DdiStartDevice;',
    'DxgkDdiStopDevice                = Bc250DdiStopDevice;',
    'DxgkDdiRemoveDevice               = Bc250DdiRemoveDevice;',
    'DxgkDdiDispatchIoRequest         = Bc250DdiDispatchIoRequest;',
    'DxgkDdiResetDevice                = Bc250DdiResetDevice;',
    'DxgkDdiUnload                     = Bc250DdiUnload;',
    'DxgkDdiSetPowerState              = Bc250DdiSetPowerState;'
  )
  foreach($c in $core){
    $n=$c.Split('=')[0].Trim()
    for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match [regex]::Escape($n)){ $lines[$i]='    DriverInitData.'+$c } }
  }

  if($p.Display -eq '1'){
    $disp=@(
      'DxgkDdiQueryChildRelations        = Bc250DdiQueryChildRelations;',
      'DxgkDdiQueryChildStatus           = Bc250DdiQueryChildStatus;',
      'DxgkDdiQueryDeviceDescriptor      = Bc250DdiQueryDeviceDescriptor;',
      'DxgkDdiSetPalette                 = Bc250DdiSetPalette;',
      'DxgkDdiSetPointerPosition         = Bc250DdiSetPointerPosition;',
      'DxgkDdiSetPointerShape            = Bc250DdiSetPointerShape;',
      'DxgkDdiIsSupportedVidPn           = Bc250DdiIsSupportedVidPn;',
      'DxgkDdiSetVidPnSourceAddress      = Bc250DdiSetVidPnSourceAddress;',
      'DxgkDdiRecommendFunctionalVidPn   = Bc250DdiRecommendFunctionalVidPn;',
      'DxgkDdiEnumVidPnCofuncModality    = Bc250DdiEnumVidPnCofuncModality;',
      'DxgkDdiSetVidPnSourceVisibility   = Bc250DdiSetVidPnSourceVisibility;',
      'DxgkDdiCommitVidPn                = Bc250DdiCommitVidPn;',
      'DxgkDdiUpdateActiveVidPnPresentPath = Bc250DdiUpdateActiveVidPnPresentPath;',
      'DxgkDdiRecommendMonitorModes      = Bc250DdiRecommendMonitorModes;',
      'DxgkDdiGetScanLine                = Bc250DdiGetScanLine;',
      'DxgkDdiQueryVidPnHWCapability     = Bc250DdiQueryVidPnHwCapability;'
    )
    foreach($d in $disp){$n=$d.Split('=')[0].Trim(); for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match [regex]::Escape($n)){ $lines[$i]='    DriverInitData.'+$d } }}
  }

  if($p.Query -eq '1'){
    $q=@(
      'DxgkDdiQueryAdapterInfo           = Bc250DdiQueryAdapterInfo;',
      'DxgkDdiQueryInterface             = Bc250DdiQueryInterface;'
    )
    foreach($d in $q){$n=$d.Split('=')[0].Trim(); for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match [regex]::Escape($n)){ $lines[$i]='    DriverInitData.'+$d } }}
  }

  if($p.Mem -eq '1'){
    $m=@(
      'DxgkDdiCreateDevice               = Bc250DdiCreateDevice;',
      'DxgkDdiDestroyDevice              = Bc250DdiDestroyDevice;',
      'DxgkDdiCreateContext              = Bc250DdiCreateContext;',
      'DxgkDdiDestroyContext             = Bc250DdiDestroyContext;',
      'DxgkDdiCreateAllocation           = Bc250DdiCreateAllocation;',
      'DxgkDdiDestroyAllocation          = Bc250DdiDestroyAllocation;',
      'DxgkDdiOpenAllocation             = Bc250DdiOpenAllocation;',
      'DxgkDdiCloseAllocation            = Bc250DdiCloseAllocation;',
      'DxgkDdiBuildPagingBuffer          = Bc250DdiBuildPagingBuffer;',
      'DxgkDdiPatch                      = Bc250DdiPatch;'
    )
    foreach($d in $m){$n=$d.Split('=')[0].Trim(); for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match [regex]::Escape($n)){ $lines[$i]='    DriverInitData.'+$d } }}
  }

  if($p.Render -eq '1'){
    $r=@(
      'DxgkDdiSubmitCommand              = Bc250DdiSubmitCommand;',
      'DxgkDdiQueryCurrentFence          = Bc250DdiQueryCurrentFence;',
      'DxgkDdiPresent                    = Bc250DdiPresent;',
      'DxgkDdiRender                     = Bc250DdiRender;'
    )
    foreach($d in $r){$n=$d.Split('=')[0].Trim(); for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match [regex]::Escape($n)){ $lines[$i]='    DriverInitData.'+$d } }}
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
Log 'KMDOD profile batch done; source restored.'
