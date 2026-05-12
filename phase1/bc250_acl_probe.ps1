$keys=@(
 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server',
 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations',
 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
)
foreach($k in $keys){
  "=== $k ==="
  try { (Get-Acl $k).Access | Select-Object IdentityReference,RegistryRights,AccessControlType,IsInherited | Format-Table -Auto }
  catch { $_.Exception.Message }
}
