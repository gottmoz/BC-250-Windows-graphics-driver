$root='C:\Dev\BC250-windowsDriverTest'
$ts='20260508_202739'
$paths=@(
  "$root\build\Release\x64\amdbc250kmd.sys",
  "$root\build\Release\x64\package\amdbc250kmd.sys",
  "$root\build\Release\x64\amdbc250kmd\amdbc250kmd.sys"
)
foreach($p in $paths){
  if(Test-Path $p){
    $h=(Get-FileHash $p -Algorithm SHA256).Hash
    $b=[IO.File]::ReadAllBytes($p)
    $a=[Text.Encoding]::ASCII.GetString($b)
    $m=$a.Contains('L2F_SINGLE_COMPILE_UNIT_20260508_20260508_202739')
    Write-Output ("PATH={0}`nHASH={1}`nMARKER={2}`n" -f $p,$h,$m)
  } else {
    Write-Output ("PATH={0}`nMISSING=1`n" -f $p)
  }
}
