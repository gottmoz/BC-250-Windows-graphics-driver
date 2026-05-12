$logs = @(
'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_223207.log',
'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_223215.log',
'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_223223.log',
'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_223230.log',
'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_223238.log',
'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_223246.log',
'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_223254.log',
'C:\Dev\BC250-windowsDriverTest\p0_n9c_pnp_bind_hashed_20260508_223301.log'
)
foreach($l in $logs){
  "=== $l ==="
  Select-String -Path $l -Pattern 'A_SRC=|PROBLEM_STATUS=|PARAM_Bc250ShapeId=|PARAM_Bc250InitStructKind=|PARAM_Bc250InitVersion=|PARAM_Bc250CallbackCount=|PARAM_Bc250CallbacksMask=|PARAM_Bc250FirstNonNullOffset=|PARAM_Bc250LastNonNullOffset=|PARAM_Bc250DxgkStatus=|B_EQ_C=' | ForEach-Object { $_.Line }
}
