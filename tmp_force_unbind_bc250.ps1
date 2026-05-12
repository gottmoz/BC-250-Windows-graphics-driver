$ErrorActionPreference='Continue'
Write-Output '=== PRE ==='
Get-PnpDevice -Class Display | Select-Object Status,FriendlyName,Problem,InstanceId | Format-List
pnputil /enum-drivers | Select-String -Pattern 'oem61.inf|amdbc250.inf|Provider Name: AMD BC-250 Driver Project' -Context 0,3

Write-Output '=== REMOVE DEVICE INSTANCE ==='
pnputil /remove-device "PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041"
Write-Output '=== DELETE OEM61 ==='
pnputil /delete-driver oem61.inf /uninstall /force
Write-Output '=== RESCAN ==='
pnputil /scan-devices
Start-Sleep -Seconds 3
Write-Output '=== POST ==='
Get-PnpDevice -Class Display | Select-Object Status,FriendlyName,Problem,InstanceId | Format-List
Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'DISPLAY' } | Select-Object DeviceName,InfName,DriverVersion,Manufacturer | Format-List
