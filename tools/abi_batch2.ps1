$ErrorActionPreference='Continue'
$repo='C:\Dev\BC250-windowsDriverTest'
$kmd=Join-Path $repo 'amdbc250_kmd.c'
$bak=Join-Path $repo 'amdbc250_kmd.c.abibak2'
$log=Join-Path $repo 'abi-batch2-run.log'
function Log([string]$m){$ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss';$line="[$ts] $m";Add-Content -LiteralPath $log -Value $line;Write-Output $line}
if (!(Test-Path $bak)) { Copy-Item -LiteralPath $kmd -Destination $bak -Force }
$base = Get-Content -LiteralPath $bak -Raw
$variants = @(
  @{Name='B1_sdkver_coremin'; Ver='DriverInitData.Version = DXGKDDI_INTERFACE_VERSION;'; Q='NULL'; C='NULL'; P='NULL'; R='NULL'},
  @{Name='B2_wddm13_coremin'; Ver='DriverInitData.Version = DXGKDDI_INTERFACE_VERSION_WDDM1_3;'; Q='NULL'; C='NULL'; P='NULL'; R='NULL'},
  @{Name='B3_wddm20_coremin'; Ver='DriverInitData.Version = DXGKDDI_INTERFACE_VERSION_WDDM2_0;'; Q='NULL'; C='NULL'; P='NULL'; R='NULL'},
  @{Name='B4_wddm13_qi_only'; Ver='DriverInitData.Version = DXGKDDI_INTERFACE_VERSION_WDDM1_3;'; Q='Bc250DdiQueryInterface'; C='NULL'; P='NULL'; R='NULL'},
  @{Name='B5_wddm13_qi_ci'; Ver='DriverInitData.Version = DXGKDDI_INTERFACE_VERSION_WDDM1_3;'; Q='Bc250DdiQueryInterface'; C='Bc250DdiControlInterrupt'; P='NULL'; R='NULL'}
)
Log "ABI2 batch start; variants=$($variants.Count)"
foreach($v in $variants){
  $txt=$base
  $txt=[regex]::Replace($txt,'(?s)/\*\s*Pin interface negotiation.*?#endif',$v.Ver)
  $txt=[regex]::Replace($txt,'(?m)^(\s*DriverInitData\.DxgkDdiQueryInterface\s*=\s*).+?;\s*$',('$1'+$v.Q+';'))
  $txt=[regex]::Replace($txt,'(?m)^(\s*DriverInitData\.DxgkDdiControlInterrupt\s*=\s*).+?;\s*$',('$1'+$v.C+';'))
  $txt=[regex]::Replace($txt,'(?m)^(\s*DriverInitData\.DxgkDdiPreemptCommand\s*=\s*).+?;\s*$',('$1'+$v.P+';'))
  $txt=[regex]::Replace($txt,'(?m)^(\s*DriverInitData\.DxgkDdiRenderKm\s*=\s*).+?;\s*$',('$1'+$v.R+';'))
  $txt=$txt.Replace('    DriverInitData.DxgkDdiCreateDevice               = Bc250DdiCreateDevice;','    DriverInitData.DxgkDdiCreateDevice               = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiDestroyDevice              = Bc250DdiDestroyDevice;','    DriverInitData.DxgkDdiDestroyDevice              = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiCreateContext              = Bc250DdiCreateContext;','    DriverInitData.DxgkDdiCreateContext              = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiDestroyContext             = Bc250DdiDestroyContext;','    DriverInitData.DxgkDdiDestroyContext             = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiCreateAllocation           = Bc250DdiCreateAllocation;','    DriverInitData.DxgkDdiCreateAllocation           = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiDestroyAllocation          = Bc250DdiDestroyAllocation;','    DriverInitData.DxgkDdiDestroyAllocation          = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiOpenAllocation             = Bc250DdiOpenAllocation;','    DriverInitData.DxgkDdiOpenAllocation             = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiCloseAllocation            = Bc250DdiCloseAllocation;','    DriverInitData.DxgkDdiCloseAllocation            = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiBuildPagingBuffer          = Bc250DdiBuildPagingBuffer;','    DriverInitData.DxgkDdiBuildPagingBuffer          = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiPatch                      = Bc250DdiPatch;','    DriverInitData.DxgkDdiPatch                      = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiSubmitCommand              = Bc250DdiSubmitCommand;','    DriverInitData.DxgkDdiSubmitCommand              = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiQueryCurrentFence          = Bc250DdiQueryCurrentFence;','    DriverInitData.DxgkDdiQueryCurrentFence          = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiPresent                    = Bc250DdiPresent;','    DriverInitData.DxgkDdiPresent                    = NULL;')
  $txt=$txt.Replace('    DriverInitData.DxgkDdiRender                     = Bc250DdiRender;','    DriverInitData.DxgkDdiRender                     = NULL;')
  Set-Content -LiteralPath $kmd -Value $txt -Encoding ASCII -NoNewline
  Log "ITER_START $($v.Name)"
  $sw=[Diagnostics.Stopwatch]::StartNew(); $out=powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Public\remote-iter-fast.ps1' 2>&1; $code=$LASTEXITCODE; $sw.Stop(); $sec=[math]::Round($sw.Elapsed.TotalSeconds,1)
  $tmp=Join-Path $repo ("tmp_"+$v.Name+".log"); $out|Out-File -LiteralPath $tmp -Encoding ascii
  $marker=(Select-String -Path $tmp -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|problem status: 0xc0000059|0xC00000E5|GUARD_EXIT=|KMD build failed'|Select-Object -Last 1).Line
  Log "ITER_END $($v.Name) exit=$code seconds=$sec marker=$marker"
  if($sec -gt 180){ Log "ITER_ABORT $($v.Name) exceeded 180s"; break }
}
Copy-Item -LiteralPath $bak -Destination $kmd -Force
Log 'ABI2 batch done; source restored from backup.'
