$dir = 'C:\Dev\BC250-windowsDriverTest\n9def_build_20260508_214329'
$runner = 'C:\Dev\BC250-windowsDriverTest\P0-N9C-PnpBind-Hashed-NoReboot.ps1'
$list = @('N9D_DXGK_EMPTY.sys','N9E_DXGK_MINCALLBACK.sys','N9F_DOD_MIN.sys')
foreach ($n in $list) {
    Write-Host ('=== RUN ' + $n + ' ===')
    & $runner -N9Dir $dir -N9SysName $n
    Start-Sleep -Seconds 2
}
