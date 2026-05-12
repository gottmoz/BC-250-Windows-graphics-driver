$d=Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\VEN_1002&DEV_13FE*' } | Select-Object -First 1
if($d){
  $svc=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue).Data
  $pc=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue).Data
  $ps=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemStatus' -ErrorAction SilentlyContinue).Data
  Write-Output ('ID='+$d.InstanceId)
  Write-Output ('CLASS='+$d.Class)
  Write-Output ('STATUS='+$d.Status)
  Write-Output ('SERVICE='+$svc)
  Write-Output ('PROBLEM='+$pc)
  Write-Output ('PSTATUS=0x{0:X8}' -f [uint32]$ps)
} else {
  'NO_BC250_DEV=1'
}
$b=Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -eq 'Microsoft Basic Display Adapter' } | Select-Object -First 1
if($b){
  'BASIC_OK=1'
  'BASIC_ID='+$b.InstanceId
  'BASIC_STATUS='+$b.Status
} else {
  'BASIC_OK=0'
}
