$ids = @(
 'UMB\UMB\1&841921D&0&TS_USB_HUB_ENUMERATOR',
 'PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
)
foreach($id in $ids){
  "=== $id ==="
  $d = Get-PnpDevice -InstanceId $id -ErrorAction SilentlyContinue
  if($d){
    $d | Select-Object Status,Class,FriendlyName,InstanceId | Format-List
    $pc = Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue
    $ps = Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_ProblemStatus' -ErrorAction SilentlyContinue
    if($pc){ "ProblemCode=$($pc.Data)" }
    if($ps){ "ProblemStatus=0x{0:X8}" -f ([uint32]$ps.Data) }
  } else {
    'NOT_FOUND'
  }
  ''
}

$umb='UMB\UMB\1&841921D&0&TS_USB_HUB_ENUMERATOR'
pnputil /disable-device "$umb"
Start-Sleep -Seconds 1
pnputil /enable-device "$umb"
Start-Sleep -Seconds 2

'=== AFTER ==='
Get-PnpDevice -InstanceId $umb | Select-Object Status,Class,FriendlyName,InstanceId | Format-List
$pc = Get-PnpDeviceProperty -InstanceId $umb -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue
$ps = Get-PnpDeviceProperty -InstanceId $umb -KeyName 'DEVPKEY_Device_ProblemStatus' -ErrorAction SilentlyContinue
if($pc){ "ProblemCode=$($pc.Data)" }
if($ps){ "ProblemStatus=0x{0:X8}" -f ([uint32]$ps.Data) }
