$ts=Get-WmiObject -Namespace root\cimv2\TerminalServices -Class Win32_TerminalServiceSetting -ErrorAction SilentlyContinue
if($null -eq $ts){ 'NO_TS_OBJ'; exit }
$ts | Get-Member -MemberType Method | Select-Object Name,Definition | Format-Table -AutoSize
