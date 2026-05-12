$ErrorActionPreference='Stop'
$out='C:\Dev\BC250-windowsDriverTest\safe_iter_$(Get-Date -Format yyyyMMdd_HHmmss).log'
"START=$(Get-Date -Format s)" | Out-File -FilePath $out -Encoding ascii

# 1) Run one known profile test (P2)
& 'C:\Dev\BC250-windowsDriverTest\P0-N9C-PnpBind-Hashed-NoReboot.ps1' -ProjectRoot 'C:\Dev\BC250-windowsDriverTest' -N9Dir 'C:\Dev\BC250-windowsDriverTest\p_P2_20260509_134816' -N9SysName 'P_P2.sys' *>> $out

# 2) Snapshot state after bind
"POST_BIND" | Add-Content $out
$d=Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | ? InstanceId -like 'PCI\VEN_1002&DEV_13FE*' | select -First 1
if($d){
  $svc=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Service' -ea SilentlyContinue).Data
  $pc=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ea SilentlyContinue).Data
  $ps=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemStatus' -ea SilentlyContinue).Data
  "STATUS=$($d.Status) SERVICE=$svc PROBLEM=$pc PSTATUS=0x{0:X8}" -f [uint32]$ps | Add-Content $out
}

# 3) Immediate no-reboot rollback to BasicDisplay
"ROLLBACK_START" | Add-Content $out
sc.exe config amdbc250kmd start= disabled | Out-Null
if($d){
  pnputil /disable-device "$($d.InstanceId)" *>> $out
  pnputil /remove-device "$($d.InstanceId)" *>> $out
}
pnputil /scan-devices *>> $out
Start-Sleep -Seconds 6
$d2=Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | ? InstanceId -like 'PCI\VEN_1002&DEV_13FE*' | select -First 1
if($d2){
  $svc2=(Get-PnpDeviceProperty -InstanceId $d2.InstanceId -KeyName 'DEVPKEY_Device_Service' -ea SilentlyContinue).Data
  $pc2=(Get-PnpDeviceProperty -InstanceId $d2.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ea SilentlyContinue).Data
  "POST_ROLLBACK STATUS=$($d2.Status) SERVICE=$svc2 PROBLEM=$pc2" | Add-Content $out
}
$b=Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | ? FriendlyName -eq 'Microsoft Basic Display Adapter' | select -First 1
if($b){"BASIC_OK=1 BASIC_STATUS=$($b.Status)" | Add-Content $out}else{"BASIC_OK=0"|Add-Content $out}
"END=$(Get-Date -Format s)" | Add-Content $out
Write-Output $out
