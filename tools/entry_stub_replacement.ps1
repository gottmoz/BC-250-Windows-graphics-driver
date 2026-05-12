$repo='C:\Dev\BC250-windowsDriverTest'
$kmd=Join-Path $repo 'amdbc250_kmd.c'
$bak=Join-Path $repo 'amdbc250_kmd.c.entrybak'
$log=Join-Path $repo 'entry-stub-batch.log'
function Log([string]$m){$ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss';$line="[$ts] $m";Add-Content -LiteralPath $log -Value $line;Write-Output $line}
$txt=Get-Content -LiteralPath $bak -Raw
$txt=[regex]::Replace($txt,'(?s)/\*\s*Pin interface negotiation.*?#endif','DriverInitData.Version = DXGKDDI_INTERFACE_VERSION_WDDM1_3;')
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
Log 'ITER_START E3b_core_query_no_mem'
$sw=[Diagnostics.Stopwatch]::StartNew();$out=powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Public\remote-iter-fast.ps1' 2>&1;$code=$LASTEXITCODE;$sw.Stop();$sec=[math]::Round($sw.Elapsed.TotalSeconds,1)
$tmp=Join-Path $repo 'tmp_E3b_core_query_no_mem.log';$out|Out-File -LiteralPath $tmp -Encoding ascii
$marker=(Select-String -Path $tmp -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|problem status: 0xc0000059|0xC00000E5|GUARD_EXIT=|Status:\s+Started'|Select-Object -Last 1).Line
Log "ITER_END E3b_core_query_no_mem exit=$code seconds=$sec marker=$marker"
Copy-Item -LiteralPath $bak -Destination $kmd -Force
Log 'Restored from entry backup.'
