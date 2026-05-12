param([string]$map='ati2mtag_Navi10')
$ErrorActionPreference='Stop'
$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$devcon='C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe'

function Get-State {
  $p=(Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_ProblemCode -ea SilentlyContinue)
  $inf=($p|? KeyName -match 'DriverInfPath').Data
  $code=[int](($p|? KeyName -match 'ProblemCode').Data)
  [pscustomobject]@{Inf=$inf;Code=$code}
}

function Recover-Baseline {
  pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
  pnputil /delete-driver oem9.inf /uninstall /force | Out-Null
  pnputil /delete-driver oem21.inf /uninstall /force | Out-Null
  pnputil /scan-devices | Out-Null
  & $devcon remove "$inst" | Out-Null
  Start-Sleep -Seconds 2
  pnputil /scan-devices | Out-Null
  Start-Sleep -Seconds 2
  & $devcon update C:\Windows\INF\display.inf 'PCI\VEN_1002&DEV_13FE' | Out-Null
  pnputil /restart-device "$inst" | Out-Null
  Start-Sleep -Seconds 2
}

$ts=Get-Date -Format o
Write-Output "ITER $map START $ts"
$pre=Get-State
if($pre.Inf -ne 'display.inf' -or $pre.Code -ne 0){
  Recover-Baseline
  $post=Get-State
  Write-Output "ITER $map PRE_RECOVER INF=$($post.Inf) CODE=$($post.Code)"
}

powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\bc250-one-map.ps1 -map $map
$end=Get-State
if($end.Inf -ne 'display.inf' -or $end.Code -ne 0){
  Recover-Baseline
  $r=Get-State
  Write-Output "ITER $map POST_RECOVER INF=$($r.Inf) CODE=$($r.Code)"
}
Write-Output "ITER $map END $(Get-Date -Format o)"
