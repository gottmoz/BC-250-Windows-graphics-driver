$root='C:\Dev\BC250-windowsDriverTest\build\Release\x64'
Get-ChildItem $root -File | Select-Object Name,Length,LastWriteTime | Sort-Object LastWriteTime -Descending | Format-Table -AutoSize
$targets=@(
  "$root\amdbc250kmd_fw.sys",
  "$root\package\amdbc250kmd.sys",
  "$root\l2f_manual_20260508_202924.sys"
)
foreach($t in $targets){
 if(Test-Path $t){
  $h=(Get-FileHash $t -Algorithm SHA256).Hash
  Write-Output "`nFILE=$t`nHASH=$h"
 }
}
