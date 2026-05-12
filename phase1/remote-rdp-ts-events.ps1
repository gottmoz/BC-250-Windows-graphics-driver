$start=(Get-Date).AddHours(-4)
Write-Output '=== LSM OPERATIONAL ==='
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'; StartTime=$start} -ErrorAction SilentlyContinue |
  Select-Object TimeCreated,Id,LevelDisplayName,Message -First 120 | Format-List
Write-Output '=== RCM OPERATIONAL ==='
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'; StartTime=$start} -ErrorAction SilentlyContinue |
  Select-Object TimeCreated,Id,LevelDisplayName,Message -First 120 | Format-List
Write-Output '=== SYSTEM TERM/UMRDP ==='
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$start} -ErrorAction SilentlyContinue |
  Where-Object { $_.ProviderName -match 'TermService|TerminalServices|Service Control Manager' -and $_.Message -match 'TermService|UmRdpService|Remote Desktop|3389|listener' } |
  Select-Object TimeCreated,Id,ProviderName,LevelDisplayName,Message -First 120 | Format-List
