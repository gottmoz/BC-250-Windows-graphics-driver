$logs = @(
 'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_222510.log',
 'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_222518.log',
 'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_222526.log',
 'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_222534.log'
)
foreach($l in $logs){
  "=== $l ==="
  Select-String -Path $l -Pattern 'A_SRC=|PROBLEM_STATUS=|PARAM_Bc250InitVersion=|PARAM_Bc250DxgkStatus=|B_EQ_C=|PNPUTIL_EXIT=' | ForEach-Object { $_.Line }
}
