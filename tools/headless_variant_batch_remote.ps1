$root='C:\Dev\BC250-windowsDriverTest'
$src=Join-Path $root 'amdbc250_kmd.c'
$backup=Join-Path $root 'amdbc250_kmd.c.autobatch.bak'
$log=Join-Path $root 'tools\headless_variant_batch.log'
$msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
$inf2cat='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x86\Inf2Cat.exe'
$sig='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
$pkg=Join-Path $root 'build\Release\x64\package'
$kmdproj=Join-Path $root 'amdbc250kmd.vcxproj'
$inf=Join-Path $root 'amdbc250.inf'
$cert = @(
  Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue
  Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue
) | Where-Object { $_.HasPrivateKey -and $_.Subject -match 'BC250' } | Sort-Object NotAfter -Descending | Select-Object -First 1

function L($m){ "$(Get-Date -Format o) $m" | Tee-Object -FilePath $log -Append }

Copy-Item -LiteralPath $src -Destination $backup -Force
L 'START headless variant batch'

$variants=@(
  @{name='V1_base'; headless='1'; skip='1'; v12=$true},
  @{name='V2_hwinit_on'; headless='1'; skip='0'; v12=$true},
  @{name='V3_display_on'; headless='0'; skip='1'; v12=$true},
  @{name='V4_hwinit_display_on'; headless='0'; skip='0'; v12=$true},
  @{name='V5_wddm13_hwskip'; headless='1'; skip='1'; v12=$false},
  @{name='V6_wddm13_hwinit'; headless='1'; skip='0'; v12=$false}
)

foreach($v in $variants){
  try {
    L "BEGIN $($v.name)"
    $txt=Get-Content -Raw -LiteralPath $backup
    $txt=[regex]::Replace($txt,'#define\s+AMDBC250_HEADLESS_RENDER_ONLY\s+\d+','#define AMDBC250_HEADLESS_RENDER_ONLY '+$v.headless)
    $txt=[regex]::Replace($txt,'#define\s+AMDBC250_SKIP_HW_INIT\s+\d+','#define AMDBC250_SKIP_HW_INIT '+$v.skip)

    if($v.v12){
      $txt=$txt -replace 'DriverInitData\.Version = DXGKDDI_INTERFACE_VERSION_WDDM1_3;','DriverInitData.Version = DXGKDDI_INTERFACE_VERSION_WDDM1_2;'
      $txt=$txt -replace 'pCaps->WDDMVersion = DXGKDDI_WDDMv1_3;','pCaps->WDDMVersion = DXGKDDI_WDDMv1_2;'
      $txt=$txt -replace 'pWddmCaps->WDDMVersion = DXGKDDI_WDDMv1_3;','pWddmCaps->WDDMVersion = DXGKDDI_WDDMv1_2;'
    } else {
      $txt=$txt -replace 'DriverInitData\.Version = DXGKDDI_INTERFACE_VERSION_WDDM1_2;','DriverInitData.Version = DXGKDDI_INTERFACE_VERSION_WDDM1_3;'
      $txt=$txt -replace 'pCaps->WDDMVersion = DXGKDDI_WDDMv1_2;','pCaps->WDDMVersion = DXGKDDI_WDDMv1_3;'
      $txt=$txt -replace 'pWddmCaps->WDDMVersion = DXGKDDI_WDDMv1_2;','pWddmCaps->WDDMVersion = DXGKDDI_WDDMv1_3;'
    }

    Set-Content -LiteralPath $src -Value $txt -Encoding ASCII

    & $msbuild $kmdproj /t:Build /p:Configuration=Release /p:Platform=x64 /m /v:m | Out-Null
    if($LASTEXITCODE -ne 0){ L "FAIL $($v.name) build=$LASTEXITCODE"; continue }

    Copy-Item -LiteralPath $inf -Destination (Join-Path $pkg 'amdbc250.inf') -Force
    Copy-Item -LiteralPath (Join-Path $root 'build\Release\x64\amdbc250kmd.sys') -Destination (Join-Path $pkg 'amdbc250kmd.sys') -Force
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
    } else {
      L "RESULT $($v.name) no_411_event_found"
    }
  } catch {
    L "EXCEPTION $($v.name) $($_.Exception.Message)"
  }
}

Copy-Item -LiteralPath $backup -Destination $src -Force
L 'END headless variant batch'
