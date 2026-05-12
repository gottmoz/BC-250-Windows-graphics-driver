$ts=Get-WmiObject -Namespace root\cimv2\TerminalServices -Class Win32_TerminalServiceSetting
$ts | Select-Object AllowTSConnections,PolicySourceAllowTSConnections,TerminalServerMode,SingleSession,PolicySourceSingleSession,SessionBrokerDrainMode,EnableDFSS | Format-List
