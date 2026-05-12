$log='C:\Users\Public\bc250_kdnet_to_realtek.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== KDNET -> Realtek recover ==='
W '--- BEFORE ---'
Get-NetAdapter -IncludeHidden | Sort-Object ifIndex | Format-Table -Auto Name,InterfaceDescription,Status,MacAddress | Out-String | Tee-Object -FilePath $log -Append
W '--- Disable Kernel Debug adapter(s) ---'
$kd = Get-NetAdapter -IncludeHidden | Where-Object { $_.InterfaceDescription -like '*Kernel Debug Network Adapter*' }
foreach($k in $kd){
  W "Disabling: $($k.Name) / $($k.InterfaceDescription)"
  Disable-NetAdapter -Name $k.Name -Confirm:$false -ErrorAction Continue | Out-Null
}
W '--- PnP scan devices ---'
cmd /c "pnputil /scan-devices" 2>&1 | Tee-Object -FilePath $log -Append
W '--- Enable Realtek ---'
$rt = Get-NetAdapter -IncludeHidden | Where-Object { $_.InterfaceDescription -like 'Realtek*' }
foreach($r in $rt){
  W "Enabling: $($r.Name) / $($r.InterfaceDescription) status=$($r.Status)"
  Enable-NetAdapter -Name $r.Name -Confirm:$false -ErrorAction Continue | Out-Null
}
Start-Sleep -Seconds 3
W '--- AFTER ---'
Get-NetAdapter -IncludeHidden | Sort-Object ifIndex | Format-Table -Auto Name,InterfaceDescription,Status,MacAddress | Out-String | Tee-Object -FilePath $log -Append
Get-NetIPAddress -AddressFamily IPv4 | Sort-Object InterfaceIndex | Format-Table -Auto InterfaceAlias,IPAddress,PrefixLength | Out-String | Tee-Object -FilePath $log -Append
W '=== END ==='
