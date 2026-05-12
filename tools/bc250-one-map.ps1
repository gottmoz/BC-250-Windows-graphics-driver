param([string]$map='ati2mtag_Navi14')
$ErrorActionPreference='Stop'
$src='C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF'
$work='C:\Users\Public\bc250-one-'+$map
$inf2cat='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x86\Inf2Cat.exe'
$sig='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
$devcon='C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe'
$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$cert = @(
  Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue
  Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue
) | Where-Object { $_.HasPrivateKey -and $_.Subject -match 'BC250' } |
  Sort-Object NotAfter -Descending |
  Select-Object -First 1
if(-not $cert){ throw 'No cert' }
if(Test-Path $work){ Remove-Item -Recurse -Force $work }
New-Item -Type Directory -Path $work | Out-Null
Copy-Item -Path (Join-Path $src '*') -Destination $work -Recurse -Force
$inf=Join-Path $work 'u0397406.inf'
$txt=Get-Content -Raw -LiteralPath $inf
$txt=$txt -replace '(?m)^\[ATI\.Mfg\.NTamd64\.10\.0\.1\.\.16299\]$',"`$0`r`n%AMD13FE.1% = $map, PCI\VEN_1002&DEV_13FE`r`n%AMD13FE.2% = $map, PCI\VEN_1002&DEV_13FE&SUBSYS_00001022"
$txt=$txt -replace '(?m)^\[ATI\.Mfg\.NTamd64\.10\.0\.1\]$',"`$0`r`n%AMD13FE.1% = $map, PCI\VEN_1002&DEV_13FE`r`n%AMD13FE.2% = $map, PCI\VEN_1002&DEV_13FE&SUBSYS_00001022"
if($txt -notmatch '(?m)^AMD13FE\.1\s*='){
  $s1 = 'AMD13FE.1 = "AMD BC-250 Graphics Adapter (' + $map + ')"'
  $s2 = 'AMD13FE.2 = "AMD BC-250 Graphics Adapter (' + $map + ' SUBSYS)"'
  $txt=$txt -replace '(?m)^\[Strings\]$', ("`$0`r`n" + $s1 + "`r`n" + $s2)
}
Set-Content -LiteralPath $inf -Value $txt -Encoding ASCII
& $inf2cat /driver:$work /os:10_X64 | Out-Null
if($LASTEXITCODE -ne 0){ Write-Output "ITER $map INF2CAT_FAIL=$LASTEXITCODE"; exit 1 }
& $sig sign /fd SHA256 /sha1 $cert.Thumbprint /s My (Join-Path $work 'u0397406.cat') | Out-Null
if($LASTEXITCODE -ne 0){ Write-Output "ITER $map SIGN_FAIL=$LASTEXITCODE"; exit 1 }
& $sig verify /pa /v (Join-Path $work 'u0397406.cat') | Out-Null
if($LASTEXITCODE -ne 0){ Write-Output "ITER $map VERIFY_FAIL=$LASTEXITCODE"; exit 1 }
pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
pnputil /delete-driver oem9.inf /uninstall /force | Out-Null
pnputil /add-driver $inf /install | Out-Null
& $devcon update $inf 'PCI\VEN_1002&DEV_13FE' | Out-Null
$d=Get-PnpDevice -Class Display -PresentOnly
$pci=$d | ? { $_.InstanceId -like 'PCI\VEN_1002&DEV_13FE*' } | select -first 1
$root=$d | ? { $_.InstanceId -like 'ROOT\DISPLAY*' } | select -first 1
$pInf=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath -ea SilentlyContinue).Data
$pSvc=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_Service -ea SilentlyContinue).Data
$pCode=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_ProblemCode -ea SilentlyContinue).Data
Write-Output ("ITER {0} RESULT PCI={1}/{2} INF={3} SVC={4} CODE={5}" -f $map,$pci.Status,$pci.Problem,$pInf,$pSvc,$pCode)
if($root){ Write-Output ("ITER {0} ROOT={1}/{2} SVC={3}" -f $map,$root.Status,$root.Problem,$root.Service) }
& $devcon update C:\Windows\INF\display.inf 'PCI\VEN_1002&DEV_13FE' | Out-Null
pnputil /scan-devices | Out-Null
pnputil /restart-device "$inst" | Out-Null
pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
$post=Get-PnpDevice -InstanceId $inst -ea SilentlyContinue
$postInf=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath -ea SilentlyContinue).Data
$postCode=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_ProblemCode -ea SilentlyContinue).Data
Write-Output ("ITER {0} ROLLBACK PCI={1}/{2} INF={3} CODE={4}" -f $map,$post.Status,$post.Problem,$postInf,$postCode)

