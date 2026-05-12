$log='C:\Users\Public\bc250_all_rdp_errors.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== All RDP/Terminal Error Scan ==='
$logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.LogName -match 'TerminalServices|Rdp|RemoteDesktop|TS|RDS' } | Select-Object -ExpandProperty LogName
$logs = $logs | Sort-Object -Unique
foreach($ln in $logs){
  W "--- $ln ---"
  try {
    $ev = Get-WinEvent -FilterHashtable @{LogName=$ln; StartTime=(Get-Date).AddDays(-2)} -ErrorAction Stop |
      Where-Object { $_.LevelDisplayName -in @('Error','Warning') }
    if($ev){
      $ev | Select-Object -First 40 TimeCreated,Id,LevelDisplayName,ProviderName,Message |
        Format-List | Out-String | Tee-Object -FilePath $log -Append
    } else { W 'No warnings/errors.' }
  } catch { W ("FAILED: " + $_.Exception.Message) }
}
W '=== END ==='
