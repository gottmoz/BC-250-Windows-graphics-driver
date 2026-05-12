$dir = 'C:\Dev\BC250-windowsDriverTest\n9rver_build_20260508_221619'
$runner = 'C:\Dev\BC250-windowsDriverTest\P0-N9C-PnpBind-Hashed-NoReboot.ps1'
$list = @('R13_VER_0x4002.sys','R20_VER_0x5023.sys','R21_VER_0x6003.sys','R27_VER_0xC004.sys')
foreach ($n in $list) {
  Write-Host ('=== RUN ' + $n + ' ===')
  & $runner -N9Dir $dir -N9SysName $n
  Start-Sleep -Seconds 2
}
