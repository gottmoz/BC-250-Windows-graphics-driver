$log='C:\Users\Public\bc250_rdp_eventprobe.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== RDP Event Probe ==='
W '--- RCM last 120 ---'
Get-WinEvent -LogName 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational' -MaxEvents 120 |
  Select-Object TimeCreated,Id,LevelDisplayName,Message |
  Format-List | Out-String | Tee-Object -FilePath $log -Append
W '--- LSM last 120 ---'
Get-WinEvent -LogName 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' -MaxEvents 120 |
  Select-Object TimeCreated,Id,LevelDisplayName,Message |
  Format-List | Out-String | Tee-Object -FilePath $log -Append
W '--- System Term-related last 150 ---'
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddHours(-8)} -MaxEvents 1000 |
  Where-Object { $_.ProviderName -match 'Term|Terminal|Service Control Manager|Schannel' -or $_.Message -match 'RDP|TermService|Remote Desktop|3389|listener' } |
  Select-Object -First 150 TimeCreated,Id,ProviderName,LevelDisplayName,Message |
  Format-List | Out-String | Tee-Object -FilePath $log -Append
W '=== END ==='
