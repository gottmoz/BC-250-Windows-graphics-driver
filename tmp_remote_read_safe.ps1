Get-ChildItem C:\Dev\BC250-windowsDriverTest -Filter 'safe_iter*' | Sort-Object LastWriteTime -Descending | Select-Object -First 5 FullName,LastWriteTime,Length | Format-Table -AutoSize
$l=Get-ChildItem C:\Dev\BC250-windowsDriverTest -Filter 'safe_iter*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($l){
  'LATEST='+$l.FullName
  Get-Content $l.FullName -Tail 200
}
