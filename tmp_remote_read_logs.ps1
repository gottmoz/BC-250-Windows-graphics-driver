$dir='C:\Dev\BC250-windowsDriverTest'
Get-ChildItem $dir -Filter '*n9c_pnp_bind_hashed_*.log' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5 FullName,LastWriteTime,Length | Format-Table -AutoSize
$l=Get-ChildItem $dir -Filter '*n9c_pnp_bind_hashed_*.log' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($l){
  'LATEST='+$l.FullName
  Get-Content $l.FullName -Tail 120
}
