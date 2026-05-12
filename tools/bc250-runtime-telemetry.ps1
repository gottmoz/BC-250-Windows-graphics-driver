param([string]$map='ati2mtag_Navi10',[switch]$DisableAmdServices)
$ErrorActionPreference='Stop'
$src='C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF'
$work='C:\Users\Public\bc250-runtime-'+$map
$inf2cat='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x86\Inf2Cat.exe'
$sig='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
$devcon='C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe'
$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$cert=Get-ChildItem Cert:\CurrentUser\My | ? { $_.HasPrivateKey -and $_.Subject -match 'BC250' } | Sort-Object NotAfter -Descending | Select-Object -First 1
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
& $sig sign /fd SHA256 /sha1 $cert.Thumbprint /s My (Join-Path $work 'u0397406.cat') | Out-Null
& $sig verify /pa /v (Join-Path $work 'u0397406.cat') | Out-Null
pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
pnputil /delete-driver oem9.inf /uninstall /force | Out-Null
pnputil /add-driver $inf /install | Out-Null
if($DisableAmdServices){
  foreach($s in @('AMD Crash Defender Service','AMD External Events Utility')){
    sc.exe stop "$s" | Out-Null
    sc.exe config "$s" start= demand | Out-Null
  }
}
$start=Get-Date
& $devcon update $inf 'PCI\VEN_1002&DEV_13FE' | Out-Null
Start-Sleep -Seconds 20
$pci=Get-PnpDevice -InstanceId $inst -ea SilentlyContinue
$pInf=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath -ea SilentlyContinue).Data
$pSvc=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_Service -ea SilentlyContinue).Data
$pCode=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_ProblemCode -ea SilentlyContinue).Data
Write-Output ("ITER {0} RESULT TS={1} PCI={2}/{3} INF={4} SVC={5} CODE={6}" -f $map,(Get-Date -Format o),$pci.Status,$pci.Problem,$pInf,$pSvc,$pCode)
$ev=Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$start.AddSeconds(-5)} -ea SilentlyContinue |
  ? { $_.ProviderName -in @('Display','amduw23g','amdkmdag','Microsoft-Windows-Kernel-PnP','Service Control Manager') -or $_.Message -match 'amduw23g|amdkmdag|13FE|display' } |
  Select-Object -First 25 TimeCreated,ProviderName,Id,LevelDisplayName,Message
foreach($e in $ev){
  $m=($e.Message -replace "`r?`n",' ')
  if($m.Length -gt 220){ $m=$m.Substring(0,220) }
  Write-Output ("ITER {0} EVENT {1:o} {2} ID={3} {4}" -f $map,$e.TimeCreated,$e.ProviderName,$e.Id,$m)
}
& $devcon update C:\Windows\INF\display.inf 'PCI\VEN_1002&DEV_13FE' | Out-Null
pnputil /scan-devices | Out-Null
pnputil /restart-device "$inst" | Out-Null
pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
$post=Get-PnpDevice -InstanceId $inst -ea SilentlyContinue
$postInf=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath -ea SilentlyContinue).Data
$postCode=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_ProblemCode -ea SilentlyContinue).Data
Write-Output ("ITER {0} ROLLBACK TS={1} PCI={2}/{3} INF={4} CODE={5}" -f $map,(Get-Date -Format o),$post.Status,$post.Problem,$postInf,$postCode)

