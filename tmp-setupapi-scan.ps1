$log='C:\Windows\INF\setupapi.dev.log'
$pat='c0000059|CM_PROB_FAILED_DRIVER_ENTRY|amdbc250kmd|PCI\\VEN_1002&DEV_13FE'
Select-String -Path $log -Pattern $pat -CaseSensitive:$false | Select-Object -Last 80 | ForEach-Object { $_.Line }
