$ErrorActionPreference='Continue'
$repo='C:\Dev\BC250-windowsDriverTest'
$kmd=Join-Path $repo 'amdbc250_kmd.c'
$kmdBak=Join-Path $repo 'amdbc250_kmd.c.compileverbak'
$proj=Join-Path $repo 'amdbc250kmd.vcxproj'
$projBak=Join-Path $repo 'amdbc250kmd.vcxproj.compileverbak'
$log=Join-Path $repo 'compile-dxgkver-batch.log'
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

function Apply-CompileDefine([string]$projectText,[string]$expr){
  if([string]::IsNullOrWhiteSpace($expr)){
    return $projectText
  }
  $anchor='        WIN32_LEAN_AND_MEAN=1;'
  $inject=$anchor + "`r`n        DXGKDDI_INTERFACE_VERSION=$expr;"
  return $projectText.Replace($anchor,$inject)
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
if(!(Test-Path $kmdBak)){ Copy-Item -LiteralPath $kmd -Destination $kmdBak -Force }
if(!(Test-Path $projBak)){ Copy-Item -LiteralPath $proj -Destination $projBak -Force }

$baseKmd=Get-Content -LiteralPath $kmdBak -Raw
$baseProj=Get-Content -LiteralPath $projBak -Raw
$baseKmd=Set-VersionSdkDefault $baseKmd

$variants=@(
  @{Name='CV1_compile_default'; Expr=''},
  @{Name='CV2_compile_wddm1_3'; Expr='DXGKDDI_INTERFACE_VERSION_WDDM1_3'},
  @{Name='CV3_compile_wddm2_0'; Expr='DXGKDDI_INTERFACE_VERSION_WDDM2_0'},
  @{Name='CV4_compile_wddm2_1'; Expr='DXGKDDI_INTERFACE_VERSION_WDDM2_1'},
  @{Name='CV5_compile_win8'; Expr='DXGKDDI_INTERFACE_VERSION_WIN8'}
)

foreach($v in $variants){
  $kmdText=$baseKmd
  $projText=Apply-CompileDefine -projectText $baseProj -expr $v.Expr
  Set-Content -LiteralPath $kmd -Value $kmdText -Encoding ASCII -NoNewline
  Set-Content -LiteralPath $proj -Value $projText -Encoding UTF8
  Run-Iteration -name $v.Name
}

Copy-Item -LiteralPath $kmdBak -Destination $kmd -Force
Copy-Item -LiteralPath $projBak -Destination $proj -Force
Log 'Compile DXGK version batch done; source/project restored.'
