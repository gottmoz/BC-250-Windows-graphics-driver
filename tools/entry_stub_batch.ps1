$ErrorActionPreference='Continue'
$repo='C:\Dev\BC250-windowsDriverTest'
$kmd=Join-Path $repo 'amdbc250_kmd.c'
$bak=Join-Path $repo 'amdbc250_kmd.c.entrybak'
$log=Join-Path $repo 'entry-stub-batch.log'

function Log([string]$m){
  $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line="[$ts] $m"
  Add-Content -LiteralPath $log -Value $line
  Write-Output $line
}

if (!(Test-Path $bak)) { Copy-Item -LiteralPath $kmd -Destination $bak -Force }
$base = Get-Content -LiteralPath $bak -Raw

$variants = @(
  @{Name='E1_core_only'; Mode='core'},
  @{Name='E2_core_plus_query'; Mode='coreq'},
  @{Name='E3_core_plus_mem'; Mode='coremem'}
)

foreach($v in $variants){
  $txt = $base
  $txt = [regex]::Replace($txt, '(?s)/\*\s*Pin interface negotiation.*?#endif', 'DriverInitData.Version = DXGKDDI_INTERFACE_VERSION_WDDM1_3;')

  $lines = $txt -split "`r?`n"
  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -match '^\s*DriverInitData\.DxgkDdi'){
      if($lines[$i] -notmatch 'DxgkDdiAddDevice|DxgkDdiStartDevice|DxgkDdiStopDevice|DxgkDdiRemoveDevice|DxgkDdiResetDevice|DxgkDdiUnload|DxgkDdiDispatchIoRequest'){
        $lines[$i] = ($lines[$i] -replace '=\s*[^;]+;','= NULL;')
      }
    }
  }

  if($v.Mode -eq 'coreq'){
    for($i=0;$i -lt $lines.Count;$i++){
      if($lines[$i] -match 'DxgkDdiQueryAdapterInfo'){ $lines[$i] = '    DriverInitData.DxgkDdiQueryAdapterInfo           = Bc250DdiQueryAdapterInfo;' }
      if($lines[$i] -match 'DxgkDdiQueryInterface'){ $lines[$i] = '    DriverInitData.DxgkDdiQueryInterface             = Bc250DdiQueryInterface;' }
    }
  }
  if($v.Mode -eq 'coremem'){
    for($i=0;$i -lt $lines.Count;$i++){
      if($lines[$i] -match 'DxgkDdiQueryAdapterInfo'){ $lines[$i] = '    DriverInitData.DxgkDdiQueryAdapterInfo           = Bc250DdiQueryAdapterInfo;' }
      if($lines[$i] -match 'DxgkDdiCreateAllocation'){ $lines[$i] = '    DriverInitData.DxgkDdiCreateAllocation           = Bc250DdiCreateAllocation;' }
      if($lines[$i] -match 'DxgkDdiDestroyAllocation'){ $lines[$i] = '    DriverInitData.DxgkDdiDestroyAllocation          = Bc250DdiDestroyAllocation;' }
      if($lines[$i] -match 'DxgkDdiBuildPagingBuffer'){ $lines[$i] = '    DriverInitData.DxgkDdiBuildPagingBuffer          = Bc250DdiBuildPagingBuffer;' }
      if($lines[$i] -match 'DxgkDdiPatch\s*='){ $lines[$i] = '    DriverInitData.DxgkDdiPatch                      = Bc250DdiPatch;' }
    }
  }

  $txt = [string]::Join("`r`n",$lines)
  Set-Content -LiteralPath $kmd -Value $txt -Encoding ASCII -NoNewline

  Log "ITER_START $($v.Name)"
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $out = powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Public\remote-iter-fast.ps1' 2>&1
  $code = $LASTEXITCODE
  $sw.Stop()
  $sec=[math]::Round($sw.Elapsed.TotalSeconds,1)

  $tmp = Join-Path $repo ("tmp_" + $v.Name + ".log")
  $out | Out-File -LiteralPath $tmp -Encoding ascii
  $marker = (Select-String -Path $tmp -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|problem status: 0xc0000059|0xC00000E5|GUARD_EXIT=|Status:\s+Started' | Select-Object -Last 1).Line
  Log "ITER_END $($v.Name) exit=$code seconds=$sec marker=$marker"

  if($sec -gt 180){ Log "ITER_ABORT $($v.Name) exceeded 180s"; break }
}

Copy-Item -LiteralPath $bak -Destination $kmd -Force
Log 'ENTRY-STUB batch done; source restored from backup.'
