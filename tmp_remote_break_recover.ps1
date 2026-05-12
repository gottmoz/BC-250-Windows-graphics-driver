Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in @('cmd','powershell','MSBuild','link','cl','inf2cat','signtool') } | Stop-Process -Force -ErrorAction SilentlyContinue
sc.exe config amdbc250kmd start= disabled | Out-Host
$inst=Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\VEN_1002&DEV_13FE*' } | Select-Object -First 1
if($inst){
  pnputil /disable-device "$($inst.InstanceId)" | Out-Host
  pnputil /remove-device "$($inst.InstanceId)" | Out-Host
}
pnputil /scan-devices | Out-Host
Start-Sleep -Seconds 5
$d=Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\VEN_1002&DEV_13FE*' } | Select-Object -First 1
if($d){
  $svc=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Service' -ea SilentlyContinue).Data
  $pc=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ea SilentlyContinue).Data
  Write-Output ('POST_ID='+$d.InstanceId)
  Write-Output ('POST_STATUS='+$d.Status)
  Write-Output ('POST_SERVICE='+$svc)
  Write-Output ('POST_PROBLEM='+$pc)
} else { 'POST_NO_DEV=1' }
