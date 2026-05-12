Write-Output '=== BCDEDIT CURRENT ==='
bcdedit /enum {current}
Write-Output '=== BCDEDIT DEBUG SETTINGS ==='
bcdedit /dbgsettings
Write-Output '=== NET ADAPTERS ==='
Get-NetAdapter | Sort-Object Status,Name | Format-Table -AutoSize Name,InterfaceDescription,Status,MacAddress,LinkSpeed
Write-Output '=== NET IP CONFIG ==='
Get-NetIPConfiguration | Format-List InterfaceAlias,InterfaceDescription,IPv4Address,IPv4DefaultGateway,DNSServer
Write-Output '=== NET IP INTERFACE ==='
Get-NetIPInterface -AddressFamily IPv4 | Sort-Object InterfaceMetric | Format-Table -AutoSize InterfaceAlias,InterfaceIndex,AddressFamily,ConnectionState,NlMtu,InterfaceMetric,Dhcp
Write-Output '=== ROUTES TOP ==='
Get-NetRoute -AddressFamily IPv4 | Sort-Object RouteMetric,InterfaceMetric,DestinationPrefix | Select-Object -First 100 DestinationPrefix,NextHop,RouteMetric,InterfaceMetric,ifIndex | Format-Table -AutoSize
