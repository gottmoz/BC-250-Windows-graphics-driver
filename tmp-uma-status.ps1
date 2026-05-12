$d = Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match 'UMA|Bus Enumerator|PCI Device' -or $_.Class -in 'System','Display' }
$d | Select-Object Status,Class,FriendlyName,InstanceId | Sort-Object Class,FriendlyName | Format-Table -AutoSize
''
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddHours(-6)} |
  Where-Object {
    $_.ProviderName -match 'Kernel-PnP|Display|Service Control Manager' -and
    $_.Message -match 'UMA|Enumerator|amdbc250|failed to load|PCI\\VEN_1002'
  } |
  Select-Object -First 40 TimeCreated,Id,ProviderName,Message |
  Format-List
