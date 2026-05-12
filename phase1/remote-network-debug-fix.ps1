Write-Output '=== BEFORE ==='
bcdedit /enum "{current}"
bcdedit /dbgsettings
Write-Output '=== APPLY ==='
bcdedit /debug off
bcdedit /bootdebug off
Write-Output '=== AFTER ==='
bcdedit /enum "{current}"
bcdedit /dbgsettings
Write-Output '=== ADAPTER SNAPSHOT ==='
Get-NetAdapter | Sort-Object Status,Name | Format-Table -AutoSize Name,InterfaceDescription,Status,MacAddress,LinkSpeed
