$ErrorActionPreference='Stop'
$src='C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF'
$base='C:\Users\Public\bc250-map-tests'
$inf2cat='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x86\Inf2Cat.exe'
$sig='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
$devcon='C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe'
$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$cert=Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.HasPrivateKey -and $_.Subject -match 'BC250' } | Sort-Object NotAfter -Descending | Select-Object -First 1
if(-not $cert){ throw 'No BC250 cert' }

function Run-One([string]$map){
  Write-Output "=== ITER $map START $(Get-Date -Format o) ==="
  $work=Join-Path $base $map
  if(Test-Path $work){ Remove-Item -Recurse -Force $work }
  New-Item -ItemType Directory -Path $work | Out-Null
  Copy-Item -Path (Join-Path $src '*') -Destination $work -Recurse -Force
  $inf=Join-Path $work "u0397406_bc250_$map.inf"
  Copy-Item -LiteralPath (Join-Path $work 'u0397406.inf') -Destination $inf -Force
  $cat="u0397406_bc250_$map.cat"
  $txt=Get-Content -LiteralPath $inf -Raw
  $txt=[regex]::Replace($txt,'(?m)^CatalogFile\s*=\s*.+$','CatalogFile='+$cat)
  $inject1="%AMD13FE.1% = $map, PCI\\VEN_1002&DEV_13FE"
  $inject2="%AMD13FE.2% = $map, PCI\\VEN_1002&DEV_13FE&SUBSYS_00001022"
  $txt=$txt -replace '(?m)^\[ATI\.Mfg\.NTamd64\.10\.0\.1\.\.16299\]$',"`$0`r`n$inject1`r`n$inject2"
  $txt=$txt -replace '(?m)^\[ATI\.Mfg\.NTamd64\.10\.0\.1\]$',"`$0`r`n$inject1`r`n$inject2"
  if($txt -notmatch '(?m)^AMD13FE\.1\s*='){
    $s1 = 'AMD13FE.1 = "AMD BC-250 Graphics Adapter (' + $map + ')"'
    $s2 = 'AMD13FE.2 = "AMD BC-250 Graphics Adapter (' + $map + ' SUBSYS)"'
    $txt=$txt -replace '(?m)^\[Strings\]$', ("`$0`r`n" + $s1 + "`r`n" + $s2)
  }
  Set-Content -LiteralPath $inf -Value $txt -Encoding ASCII

  & $inf2cat /driver:$work /os:10_X64 | Out-Null
  if($LASTEXITCODE -ne 0){ Write-Output "ITER $map INF2CAT_FAIL=$LASTEXITCODE"; return }
  & $sig sign /fd SHA256 /sha1 $cert.Thumbprint /s My (Join-Path $work $cat) | Out-Null
  if($LASTEXITCODE -ne 0){ Write-Output "ITER $map SIGN_FAIL=$LASTEXITCODE"; return }
  & $sig verify /pa /v (Join-Path $work $cat) | Out-Null
  if($LASTEXITCODE -ne 0){ Write-Output "ITER $map VERIFY_FAIL=$LASTEXITCODE"; return }

  pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
  pnputil /delete-driver oem9.inf /uninstall /force | Out-Null
  pnputil /add-driver $inf /install | Out-Null
  & $devcon update $inf 'PCI\VEN_1002&DEV_13FE' | Out-Null

  $d=Get-PnpDevice -Class Display -PresentOnly
  $pci=$d | Where-Object { $_.InstanceId -like 'PCI\VEN_1002&DEV_13FE*' } | Select-Object -First 1
  $root=$d | Where-Object { $_.InstanceId -like 'ROOT\DISPLAY*' } | Select-Object -First 1
  $pInf=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath -ErrorAction SilentlyContinue).Data
  $pSvc=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_Service -ErrorAction SilentlyContinue).Data
  $pCode=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue).Data
  Write-Output ("ITER {0} RESULT PCI_Status={1} PCI_Problem={2} INF={3} SVC={4}" -f $map,$pci.Status,$pci.Problem,$pInf,$pSvc)
  if($root){ Write-Output ("ITER {0} ROOTDISPLAY Problem={1} Service={2}" -f $map,$root.Problem,$root.Service) }

  # rollback
  & $devcon update C:\Windows\INF\display.inf 'PCI\VEN_1002&DEV_13FE' | Out-Null
  pnputil /scan-devices | Out-Null
  pnputil /restart-device "$inst" | Out-Null
  pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
  $post=Get-PnpDevice -InstanceId $inst -ErrorAction SilentlyContinue
  $postInf=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath -ErrorAction SilentlyContinue).Data
  $postCode=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue).Data
  Write-Output ("ITER {0} ROLLBACK PCI_Status={1} PCI_Problem={2} INF={3}" -f $map,$post.Status,$post.Problem,$postInf)
  Write-Output "=== ITER $map END $(Get-Date -Format o) ==="
}

foreach($m in @('ati2mtag_Navi14','ati2mtag_Navi21','ati2mtag_Legacy')){ Run-One $m }
