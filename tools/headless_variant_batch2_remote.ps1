$root='C:\Dev\BC250-windowsDriverTest'
$src=Join-Path $root 'amdbc250_kmd.c'
$bak=Join-Path $root 'amdbc250_kmd.c.simplebatch.bak'
$log=Join-Path $root 'tools\headless_variant_batch2.log'
$msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
$inf2cat='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x86\Inf2Cat.exe'
$sig='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
$pkg=Join-Path $root 'build\Release\x64\package'
$proj=Join-Path $root 'amdbc250kmd.vcxproj'
$inf=Join-Path $root 'amdbc250.inf'
$cert = @(
  Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue
  Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue
) | Where-Object { $_.HasPrivateKey -and $_.Subject -match 'BC250' } | Sort-Object NotAfter -Descending | Select-Object -First 1
function L($m){ "$(Get-Date -Format o) $m" | Tee-Object -FilePath $log -Append }
Copy-Item $src $bak -Force
L 'START simple batch2'
$variants=@(
  @{name='B1_h1_s1';h='1';s='1'},
  @{name='B2_h1_s0';h='1';s='0'},
  @{name='B3_h0_s1';h='0';s='1'},
  @{name='B4_h0_s0';h='0';s='0'}
)
foreach($v in $variants){
  L "BEGIN $($v.name)"
  Copy-Item $bak $src -Force
  $txt=Get-Content -Raw $src
  $txt=[regex]::Replace($txt,'#define\s+AMDBC250_HEADLESS_RENDER_ONLY\s+\d+','#define AMDBC250_HEADLESS_RENDER_ONLY '+$v.h)
  $txt=[regex]::Replace($txt,'#define\s+AMDBC250_SKIP_HW_INIT\s+\d+','#define AMDBC250_SKIP_HW_INIT '+$v.s)
  Set-Content -LiteralPath $src -Value $txt -Encoding ASCII

  & $msbuild $proj /t:Build /p:Configuration=Release /p:Platform=x64 /m /v:m | Out-Null
  if($LASTEXITCODE -ne 0){ L "FAIL $($v.name) build=$LASTEXITCODE"; continue }

  Copy-Item $inf (Join-Path $pkg 'amdbc250.inf') -Force
  Copy-Item (Join-Path $root 'build\Release\x64\amdbc250kmd.sys') (Join-Path $pkg 'amdbc250kmd.sys') -Force
  & $inf2cat /driver:$pkg /os:10_X64 | Out-Null
  if($LASTEXITCODE -ne 0){ L "FAIL $($v.name) inf2cat=$LASTEXITCODE"; continue }
  & $sig sign /fd SHA256 /sha1 $cert.Thumbprint /s My (Join-Path $pkg 'amdbc250.cat') | Out-Null
  & $sig sign /fd SHA256 /sha1 $cert.Thumbprint /s My (Join-Path $pkg 'amdbc250kmd.sys') | Out-Null

  powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Run-GuardedDriverTest.ps1') -TimeoutSeconds 35 -NoRebootRecovery -AllowBaselineBypass | Out-Null
  $ev=Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Kernel-PnP/Configuration'; StartTime=(Get-Date).AddMinutes(-3)} -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -eq 411 -and $_.Message -match 'VEN_1002&DEV_13FE' } | Select-Object -First 1
  if($ev){
    $msg=$ev.Message -replace "`r`n",' | '
    L "RESULT $($v.name) $msg"
  } else { L "RESULT $($v.name) no_411" }
}
Copy-Item $bak $src -Force
L 'END simple batch2'
