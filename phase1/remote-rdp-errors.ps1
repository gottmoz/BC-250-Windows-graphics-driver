$start=(Get-Date).AddDays(-2)
Write-Output '=== RCM WARN/ERR ==='
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'; StartTime=$start} -ErrorAction SilentlyContinue |
  Where-Object { $_.LevelDisplayName -in @('Error','Warning') } |
  Select-Object TimeCreated,Id,LevelDisplayName,Message -First 200 | Format-List
Write-Output '=== LSM WARN/ERR ==='
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'; StartTime=$start} -ErrorAction SilentlyContinue |
  Where-Object { $_.LevelDisplayName -in @('Error','Warning') } |
  Select-Object TimeCreated,Id,LevelDisplayName,Message -First 200 | Format-List
Write-Output '=== SYSTEM WARN/ERR RDP ==='
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$start} -ErrorAction SilentlyContinue |
  Where-Object { $_.LevelDisplayName -in @('Error','Warning') -and $_.Message -match 'Remote Desktop|TermService|RDP|3389|terminal' } |
  Select-Object TimeCreated,Id,ProviderName,LevelDisplayName,Message -First 200 | Format-List
