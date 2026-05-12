$d=Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\VEN_1002&DEV_13FE*' } | Select-Object -First 1
if($d){
  $svc=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Service' -ea SilentlyContinue).Data
  $pc=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ea SilentlyContinue).Data
  $ps=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemStatus' -ea SilentlyContinue).Data
  'ID='+$d.InstanceId
  'STATUS='+$d.Status
  'SERVICE='+$svc
  'PROBLEM='+$pc
  'PSTATUS=0x{0:X8}' -f [uint32]$ps
}else{'NO_BC250=1'}
$b=Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -eq 'Microsoft Basic Display Adapter' } | Select-Object -First 1
if($b){'BASIC=1';'BASIC_STATUS='+$b.Status}else{'BASIC=0'}
