Get-PnpDevice -Class Display | Select-Object Status,FriendlyName,Problem,InstanceId | Format-List
Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'DISPLAY' } | Select-Object DeviceName,InfName,DriverVersion,Manufacturer | Format-List
