Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in @('cmd','powershell','MSBuild','link','cl','inf2cat','signtool') } | Select-Object ProcessName,Id,CPU,StartTime,Path | Sort-Object StartTime | Format-Table -AutoSize
$log='C:\Dev\BC250-windowsDriverTest\r_trace_bg.log'
if(Test-Path $log){
  Get-Item $log | Select-Object FullName,Length,LastWriteTime | Format-List
  Get-Content $log -Tail 80
} else {
  'NO_LOG'
}
