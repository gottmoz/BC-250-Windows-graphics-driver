$ErrorActionPreference='SilentlyContinue'
$log='C:\Users\Public\bc250_rdp_errors.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Out-File -FilePath $log -Encoding utf8 -Append; $m}
W '=== RDP Error Scan ==='
$logs=@(
 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational',
 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational',
 'System'
)
foreach($ln in $logs){
  W "--- $ln (Errors/Warnings last 48h) ---"
  try {
    Get-WinEvent -FilterHashtable @{LogName=$ln; StartTime=(Get-Date).AddHours(-48)} |
      Where-Object { $_.LevelDisplayName -in @('Error','Warning') } |
      Select-Object -First 120 TimeCreated,Id,ProviderName,LevelDisplayName,Message |
      Format-List | Out-String | Out-File -FilePath $log -Encoding utf8 -Append
  } catch {
    W "FAILED: $ln"
  }
}
W '=== END ==='
Write-Output $log
