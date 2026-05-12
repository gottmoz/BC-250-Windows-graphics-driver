$ErrorActionPreference='Continue'
$repo='C:\Dev\BC250-windowsDriverTest'
$kmd=Join-Path $repo 'amdbc250_kmd.c'
$bak=Join-Path $repo 'amdbc250_kmd.c.versionbak'
$log=Join-Path $repo 'init-version-batch.log'
$runner='C:\Users\Public\remote-iter-fast.ps1'

function Log([string]$m){
  $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line="[$ts] $m"
  Add-Content -LiteralPath $log -Value $line
  Write-Output $line
}

function Set-VersionExpr([string]$text,[string]$expr){
  $txt=$text
  $newLine="DriverInitData.Version = $expr;"

  $block='(?s)#if defined\(DXGKDDI_INTERFACE_VERSION_WDDM2_0\)\s*DriverInitData\.Version\s*=\s*DXGKDDI_INTERFACE_VERSION_WDDM2_0;\s*#else\s*DriverInitData\.Version\s*=\s*DXGKDDI_INTERFACE_VERSION_WDDM1_3;\s*#endif'
  $replaced=[regex]::Replace($txt,$block,$newLine,1)
  if($replaced -ne $txt){ return $replaced }

  $single='DriverInitData\.Version\s*=\s*[^;]+;'
  return [regex]::Replace($txt,$single,$newLine,1)
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
    Log "ITER_TIMEOUT $name exceeded 180s; stopping and retrying once"
    Stop-Job -Id $job.Id -Force | Out-Null
    Remove-Job -Id $job.Id -Force | Out-Null

    $sw2=[Diagnostics.Stopwatch]::StartNew()
    $out2=powershell -NoProfile -ExecutionPolicy Bypass -File $runner 2>&1
    $code2=$LASTEXITCODE
    $sw2.Stop()
    $tmp2=Join-Path $repo ("tmp_"+$name+"_retry.log")
    $out2 | Out-File -LiteralPath $tmp2 -Encoding ascii
    $marker2=(Select-String -Path $tmp2 -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|problem status: 0xc0000059|0xC00000E5|0xC01E0438|GUARD_EXIT=|KMD build failed|DxgkInitialize failed' | Select-Object -Last 1).Line
    if(-not $marker2){ $marker2='(no marker found)' }
    Log "ITER_END $name retry exit=$code2 seconds=$([math]::Round($sw2.Elapsed.TotalSeconds,1)) marker=$marker2"
    return
  }

  $out=Receive-Job -Id $job.Id
  $tmp=Join-Path $repo ("tmp_"+$name+".log")
  $out | Out-File -LiteralPath $tmp -Encoding ascii

  $exitCode=0
  $exitMarker=(Select-String -Path $tmp -Pattern 'GUARD_EXIT=([0-9-]+)' | Select-Object -Last 1)
  if($exitMarker){
    $exitCode=[int]$exitMarker.Matches[0].Groups[1].Value
  }

  $sw.Stop()
  Remove-Job -Id $job.Id -Force | Out-Null
  $sec=[math]::Round($sw.Elapsed.TotalSeconds,1)
  $marker=(Select-String -Path $tmp -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|problem status: 0xc0000059|0xC00000E5|0xC01E0438|GUARD_EXIT=|KMD build failed|DxgkInitialize failed' | Select-Object -Last 1).Line
  if(-not $marker){ $marker='(no marker found)' }
  Log "ITER_END $name exit=$exitCode seconds=$sec marker=$marker"
}

if(!(Test-Path $runner)){ throw "Runner missing: $runner" }
if(!(Test-Path $bak)){ Copy-Item -LiteralPath $kmd -Destination $bak -Force }
$base=Get-Content -LiteralPath $bak -Raw

$variants=@(
  @{Name='VM1_wddm1_3'; Expr='DXGKDDI_INTERFACE_VERSION_WDDM1_3'},
  @{Name='VM2_wddm2_0'; Expr='DXGKDDI_INTERFACE_VERSION_WDDM2_0'},
  @{Name='VM3_wddm2_1'; Expr='DXGKDDI_INTERFACE_VERSION_WDDM2_1'},
  @{Name='VM4_wddm2_2'; Expr='DXGKDDI_INTERFACE_VERSION_WDDM2_2'},
  @{Name='VM5_wddm2_3'; Expr='DXGKDDI_INTERFACE_VERSION_WDDM2_3'},
  @{Name='VM6_win8'; Expr='DXGKDDI_INTERFACE_VERSION_WIN8'},
  @{Name='VM7_literal_0x4002'; Expr='0x4002'},
  @{Name='VM8_literal_0x5023'; Expr='0x5023'}
)

foreach($v in $variants){
  $txt=Set-VersionExpr -text $base -expr $v.Expr
  Set-Content -LiteralPath $kmd -Value $txt -Encoding ASCII -NoNewline
  Run-Iteration -name $v.Name
}

Copy-Item -LiteralPath $bak -Destination $kmd -Force
Log 'Version matrix batch done; source restored.'
