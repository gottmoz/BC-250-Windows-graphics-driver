$keys=@('HKLM:\SYSTEM\CurrentControlSet\Services\TermService','HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters')
foreach($k in $keys){
  "=== $k ==="
  try { (Get-Acl $k).Access | Select-Object IdentityReference,RegistryRights,AccessControlType,IsInherited | Format-Table -Auto }
  catch { $_.Exception.Message }
}
