$ErrorActionPreference='Continue'
$ts=Get-Date -Format 'yyyyMMdd-HHmmss'
$log="C:\Users\Public\bc250_rdp_repair_$ts.log"
function W([string]$m){ $m | Tee-Object -FilePath $log -Append }
function DumpState([string]$label){
  W "--- STATE: $label ---"
  try { Get-Service TermService,SessionEnv,UmRdpService | Format-Table -Auto Name,Status,StartType | Out-String | Tee-Object -FilePath $log -Append } catch {}
  try { reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections | Tee-Object -FilePath $log -Append } catch {}
  try { reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fDenyTSConnections | Tee-Object -FilePath $log -Append } catch {}
  try { reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v fEnableWinStation | Tee-Object -FilePath $log -Append } catch {}
  try { reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber | Tee-Object -FilePath $log -Append } catch {}
  try { reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication | Tee-Object -FilePath $log -Append } catch {}
  try { reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v SecurityLayer | Tee-Object -FilePath $log -Append } catch {}
  try { reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v SSLCertificateSHA1Hash | Tee-Object -FilePath $log -Append } catch {}
  try { cmd /c "netstat -ano -p tcp | findstr :3389" 2>&1 | Tee-Object -FilePath $log -Append } catch {}
  try { cmd /c "qwinsta" 2>&1 | Tee-Object -FilePath $log -Append } catch {}
}

W "=== BC250 RDP Repair $ts ==="
DumpState 'before'

W '--- Apply RDP policy/registry baseline ---'
try {
  New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Force | Out-Null
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'fDenyTSConnections' -Type DWord -Value 0
} catch { W "Policy write error: $($_.Exception.Message)" }

try {
  Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Type DWord -Value 0
} catch { W "TerminalServer write error: $($_.Exception.Message)" }

$rdp='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
try {
  Set-ItemProperty -Path $rdp -Name 'fEnableWinStation' -Type DWord -Value 1
  Set-ItemProperty -Path $rdp -Name 'PortNumber' -Type DWord -Value 3389
  Set-ItemProperty -Path $rdp -Name 'UserAuthentication' -Type DWord -Value 0
  Set-ItemProperty -Path $rdp -Name 'SecurityLayer' -Type DWord -Value 0
  Set-ItemProperty -Path $rdp -Name 'LanAdapter' -Type DWord -Value 0
} catch { W "RDP-Tcp write error: $($_.Exception.Message)" }

W '--- Remove stale RDP cert binding (forces regeneration) ---'
try { Remove-ItemProperty -Path $rdp -Name 'SSLCertificateSHA1Hash' -ErrorAction SilentlyContinue } catch {}
try { Remove-ItemProperty -Path $rdp -Name 'SSLCertificateSHA1HashType' -ErrorAction SilentlyContinue } catch {}

W '--- Firewall rules ---'
try { Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' | Out-Null } catch { W "Firewall rule error: $($_.Exception.Message)" }

W '--- Service restart sequence ---'
try { Set-Service -Name SessionEnv -StartupType Automatic } catch {}
try { Set-Service -Name TermService -StartupType Automatic } catch {}
try { Set-Service -Name UmRdpService -StartupType Automatic } catch {}

try { Stop-Service -Name UmRdpService -Force -ErrorAction SilentlyContinue } catch {}
try { Stop-Service -Name TermService -Force -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 2
try { Start-Service -Name SessionEnv -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 2
try { Start-Service -Name TermService -ErrorAction Stop } catch { W "Start TermService error: $($_.Exception.Message)" }
Start-Sleep -Seconds 4
try { Start-Service -Name UmRdpService -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 2

W '--- WMI SetAllowTSConnections ---'
try {
  $tsObj = Get-CimInstance -Namespace 'root/cimv2/TerminalServices' -ClassName 'Win32_TerminalServiceSetting' -ErrorAction Stop
  $res = Invoke-CimMethod -InputObject $tsObj -MethodName 'SetAllowTSConnections' -Arguments @{AllowTSConnections=1;ModifyFirewallException=1}
  W ("SetAllowTSConnections ReturnValue=" + $res.ReturnValue)
} catch { W "SetAllowTSConnections error: $($_.Exception.Message)" }

DumpState 'after'
W '=== END ==='
Write-Output $log
