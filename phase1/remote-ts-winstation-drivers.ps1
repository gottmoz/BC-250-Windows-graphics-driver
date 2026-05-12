$ts=Get-WmiObject -Namespace root\cimv2\TerminalServices -Class Win32_TerminalServiceSetting
$r=$ts.GetWinstationDriverNames()
$r | Format-List *
