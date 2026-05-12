$ErrorActionPreference='Continue'
$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'

Write-Output '=== PRE STATE ==='
Get-PnpDevice -Class Display | Select-Object Status,FriendlyName,Problem,InstanceId | Format-List
Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'DISPLAY' } | Select-Object DeviceName,InfName,DriverVersion,Manufacturer | Format-List

Write-Output '=== DISABLE BC250 SERVICES ==='
$svcNames = @('amdbc250kmd')
foreach($svc in $svcNames){
  sc.exe stop $svc | Out-Host
  sc.exe config $svc start= disabled | Out-Host
}

Write-Output '=== DISABLE/REMOVE DEVICE INSTANCE ==='
pnputil /disable-device "$inst" | Out-Host
pnputil /remove-device "$inst" | Out-Host

Write-Output '=== DELETE BC250 DISPLAY DRIVERS FROM DRIVERSTORE ==='
$drvList = pnputil /enum-drivers
$published = @()
$curPub = $null
$curOrig = $null
foreach($line in $drvList){
  if($line -match 'Published Name\s*:\s*(oem\d+\.inf)'){ $curPub=$matches[1] }
  if($line -match 'Original Name\s*:\s*(.+)$'){
    $curOrig=$matches[1].Trim()
    if($curPub -and ($curOrig -ieq 'amdbc250.inf')){ $published += $curPub; $curPub=$null; $curOrig=$null }
  }
}
$published = $published | Sort-Object -Unique
Write-Output ('BC250_OEM_LIST=' + ($published -join ','))
foreach($oem in $published){
  Write-Output ('DELETE=' + $oem)
  pnputil /delete-driver $oem /uninstall /force | Out-Host
}

Write-Output '=== FORCE BASIC DISPLAY BIND ATTEMPT ==='
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
$ok=[NewDev]::UpdateDriverForPlugAndPlayDevices([IntPtr]::Zero,'PCI\\CC_0300','C:\\Windows\\INF\\display.inf',0x1,[ref]$reboot)
$err=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Output "rollback_ok=$ok"
Write-Output "last_error=$err"
Write-Output "reboot_required=$reboot"

Write-Output '=== RESCAN ==='
pnputil /scan-devices | Out-Host
Start-Sleep -Seconds 3

Write-Output '=== POST STATE ==='
Get-PnpDevice -Class Display | Select-Object Status,FriendlyName,Problem,InstanceId | Format-List
Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'DISPLAY' } | Select-Object DeviceName,InfName,DriverVersion,Manufacturer | Format-List

Write-Output '=== REBOOT NOW ==='
shutdown /r /t 0
