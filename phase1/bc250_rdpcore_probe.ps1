$logs=@(
 'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational',
 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin',
 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational',
 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
)
$log='C:\Users\Public\bc250_rdpcore_probe.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== RDP Core Probe ==='
foreach($ln in $logs){
  W "--- $ln (last 200) ---"
  try {
    Get-WinEvent -LogName $ln -MaxEvents 200 |
      Select-Object TimeCreated,Id,LevelDisplayName,ProviderName,Message |
      Format-List | Out-String | Tee-Object -FilePath $log -Append
  } catch {
    W "FAILED: $ln"
    W $_.Exception.Message
  }
}
W '=== END ==='
