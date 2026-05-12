$ErrorActionPreference='Continue'
$all = pnputil /enum-drivers
$blocks = ($all -split "Published Name:") | Where-Object { $_ -match 'Original Name:\s+amdbc250\.inf' }
$names = @()
foreach($b in $blocks){
  if($b -match '^(\s*oem\d+\.inf)'){ $names += $matches[1].Trim() }
}
$names = $names | Sort-Object -Unique
Write-Output ('FOUND=' + ($names -join ','))
foreach($n in $names){
  Write-Output ('DELETE=' + $n)
  pnputil /delete-driver $n /uninstall /force
}
pnputil /remove-device "PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041"
pnputil /scan-devices
Start-Sleep -Seconds 3
Get-PnpDevice -Class Display | Select-Object Status,FriendlyName,Problem,InstanceId | Format-List
Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'DISPLAY' } | Select-Object DeviceName,InfName,DriverVersion,Manufacturer | Format-List
