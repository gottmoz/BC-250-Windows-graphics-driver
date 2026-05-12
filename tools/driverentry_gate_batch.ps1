$ErrorActionPreference='Continue'
$repo='C:\Dev\BC250-windowsDriverTest'
$kmd=Join-Path $repo 'amdbc250_kmd.c'
$bak=Join-Path $repo 'amdbc250_kmd.c.driverentrybak'
$log=Join-Path $repo 'driverentry-gate-batch.log'

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

$variants=@(
  @{ Name='GATE1_baseline'; Mode='baseline' },
  @{ Name='GATE2_return_success'; Mode='return_success' },
  @{ Name='GATE3_return_not_supported'; Mode='return_not_supported' }
)

foreach($v in $variants){
  $lines=$base -split "`r?`n"

  $idxReg=-1
  $idxRet=-1
  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -match '/\* Register with Dxgkrnl \*/'){ $idxReg=$i }
    if($idxReg -ge 0 -and $lines[$i] -match '^\s*return\s+Status\s*;\s*$'){ $idxRet=$i; break }
  }

  if($idxReg -lt 0 -or $idxRet -lt 0){
    Log "ITER_SKIP $($v.Name) could not locate DriverEntry register/return block"
    continue
  }

  $newLines=@()
  $newLines += $lines[0..($idxReg-1)]

  switch($v.Mode){
    'baseline' {
      $newLines += $lines[$idxReg..$idxRet]
    }
    'return_success' {
      $newLines += '    /* Register with Dxgkrnl */'
      $newLines += '    KdPrint(("AMDBC250: GATE forcing STATUS_SUCCESS (skip DxgkInitialize)\n"));'
      $newLines += '    return STATUS_SUCCESS;'
    }
    'return_not_supported' {
      $newLines += '    /* Register with Dxgkrnl */'
      $newLines += '    KdPrint(("AMDBC250: GATE forcing STATUS_NOT_SUPPORTED (skip DxgkInitialize)\n"));'
      $newLines += '    return STATUS_NOT_SUPPORTED;'
    }
  }

  $newLines += $lines[($idxRet+1)..($lines.Count-1)]
  $txt=[string]::Join("`r`n",$newLines)
  Set-Content -LiteralPath $kmd -Value $txt -Encoding ASCII -NoNewline

  Log "ITER_START $($v.Name)"
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $out=powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Public\remote-iter-fast.ps1' 2>&1
  $code=$LASTEXITCODE
  $sw.Stop()
  $sec=[math]::Round($sw.Elapsed.TotalSeconds,1)
  $tmp=Join-Path $repo ("tmp_"+$v.Name+".log")
  $out | Out-File -LiteralPath $tmp -Encoding ascii

  $marker=(Select-String -Path $tmp -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|CM_PROB_FAILED_START|problem status:|GUARD_EXIT=|0xC0000059|0xC00000E5|0x00000000|GATE forcing' | Select-Object -Last 2 | ForEach-Object { $_.Line }) -join ' || '
  if(-not $marker){ $marker='(no marker found)' }
  Log "ITER_END $($v.Name) exit=$code seconds=$sec marker=$marker"

  if($sec -gt 180){
    Log "ITER_ABORT $($v.Name) exceeded 180s"
    break
  }
}

Copy-Item -LiteralPath $bak -Destination $kmd -Force
Log 'DriverEntry gate batch done; source restored.'
