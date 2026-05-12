$ErrorActionPreference='Continue'
Write-Output '=== PRE DISPLAY ==='
Get-PnpDevice -Class Display | Select-Object Status,FriendlyName,Problem,InstanceId | Format-List
Write-Output '=== ROLLBACK BASIC DISPLAY ==='
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class NewDev {
  [DllImport("newdev.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool UpdateDriverForPlugAndPlayDevices(
      IntPtr hwndParent,
      string HardwareId,
      string FullInfPath,
      uint InstallFlags,
      out bool bRebootRequired);
}
"@
$reboot=$false
$ok=[NewDev]::UpdateDriverForPlugAndPlayDevices([IntPtr]::Zero,'PCI\\CC_0300','C:\Windows\INF\display.inf',0x1,[ref]$reboot)
$err=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Output "rollback_ok=$ok"
Write-Output "last_error=$err"
Write-Output "reboot_required=$reboot"
Write-Output '=== POST DISPLAY ==='
Get-PnpDevice -Class Display | Select-Object Status,FriendlyName,Problem,InstanceId | Format-List
Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'DISPLAY' } | Select-Object DeviceName,InfName,DriverVersion,Manufacturer | Format-List
