$dir = 'C:\Dev\BC250-windowsDriverTest\n9s_shape_build_20260508_223139'
$runner = 'C:\Dev\BC250-windowsDriverTest\P0-N9C-PnpBind-Hashed-NoReboot.ps1'
$list = @(
 'S0_EMPTY_V4002.sys',
 'S1_LIFECYCLE_V4002.sys',
 'S2_LIFE_PWR_IO_V4002.sys',
 'S3_PLUS_QAI_V4002.sys',
 'S4_DODLIKE_V4002.sys',
 'S5_FULLDISP_V4002.sys',
 'S3_PLUS_QAI_VC004.sys',
 'S4_DODLIKE_VC004.sys'
)
foreach ($n in $list) {
  Write-Host ('=== RUN ' + $n + ' ===')
  & $runner -N9Dir $dir -N9SysName $n
  Start-Sleep -Seconds 2
}
