$log='C:\Users\Public\bc250_disable_tasks.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== Disable BC250 tasks ==='
$tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like 'BC250*' -or $_.TaskPath -like '\\BC250*' }
if(-not $tasks){ W 'No BC250 tasks found.' }
foreach($t in $tasks){
  W ("Task: " + $t.TaskPath + $t.TaskName + " state=" + $t.State)
  try { Stop-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue } catch {}
  try { Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Continue | Out-Null; W 'Disabled.' } catch { W ("Disable failed: " + $_.Exception.Message) }
}
W '--- Post state ---'
Get-ScheduledTask | Where-Object { $_.TaskName -like 'BC250*' -or $_.TaskPath -like '\\BC250*' } | Select-Object TaskPath,TaskName,State | Format-Table -Auto | Out-String | Tee-Object -FilePath $log -Append
W '=== END ==='
