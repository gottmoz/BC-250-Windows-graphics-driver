$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$start=(Get-Date).AddMinutes(-20)
Write-Output '=== DEVICE ==='
pnputil /enum-devices /instanceid "$inst" /drivers
Get-PnpDevice -InstanceId $inst | Select-Object Status,FriendlyName,Problem,Present | Format-List
Get-PnpDeviceProperty -InstanceId $inst -KeyName 'DEVPKEY_Device_DriverInfPath','DEVPKEY_Device_Service','DEVPKEY_Device_ProblemCode','DEVPKEY_Device_ProblemStatus' | Select-Object KeyName,Data | Format-Table -AutoSize
Write-Output '=== SETUPAPI TAIL ==='
Select-String -Path C:\Windows\INF\setupapi.dev.log -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|0xC0000059|amdbc250|13FE' -Context 0,4 | Select-Object -Last 120
Write-Output '=== KERNEL-PNP 219 XML ==='
Get-WinEvent -FilterHashtable @{LogName='System'; Id=219; ProviderName='Microsoft-Windows-Kernel-PnP'; StartTime=$start} -ErrorAction SilentlyContinue |
  Where-Object { $_.Message -match 'amdbc250|13FE' } |
  Select-Object -First 20 |
  ForEach-Object { $_.ToXml() }
Write-Output '=== SYSTEM EVENTS ==='
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$start} -ErrorAction SilentlyContinue |
  Where-Object { ($_.ProviderName -eq 'Microsoft-Windows-Kernel-PnP' -and $_.Id -in 219,400,410,411) -or $_.ProviderName -eq 'Service Control Manager' } |
  Select-Object TimeCreated,ProviderName,Id,Message -First 160 | Format-List
