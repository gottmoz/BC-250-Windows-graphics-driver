$inst='PCI\VEN_1002&DEV_13FE'
Get-PnpDevice -Class Display -PresentOnly | Select-Object Status,Class,FriendlyName,InstanceId | Format-Table -AutoSize
''
Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like "$inst*" } | Select-Object Status,Class,FriendlyName,InstanceId | Format-List
''
$dev = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like "$inst*" } | Select-Object -First 1
if ($dev) {
  'Service=' + (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue).Data
  'ProblemCode=' + (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue).Data
  $ps=(Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_ProblemStatus' -ErrorAction SilentlyContinue).Data
  if($ps -ne $null){ 'ProblemStatus=0x{0:X8}' -f ([uint32]$ps) }
}
