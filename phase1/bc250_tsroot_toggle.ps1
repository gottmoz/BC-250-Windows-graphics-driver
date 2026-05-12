$log='C:\Users\Public\bc250_tsroot_toggle.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
$k='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
W '=== TS root toggle ==='
W '--- before ---'
Get-ItemProperty -Path $k | Select-Object fDenyTSConnections,TSUserEnabled,StartRCM,updateRDStatus | Format-List | Out-String | Tee-Object -FilePath $log -Append
Set-ItemProperty -Path $k -Name 'fDenyTSConnections' -Type DWord -Value 0
Set-ItemProperty -Path $k -Name 'TSUserEnabled' -Type DWord -Value 1
Set-ItemProperty -Path $k -Name 'StartRCM' -Type DWord -Value 1
New-ItemProperty -Path $k -Name 'updateRDStatus' -PropertyType DWord -Value 1 -Force | Out-Null
W '--- restart services ---'
try { Stop-Service -Name TermService -Force -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 2
try { Start-Service -Name TermService -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 4
W '--- after ---'
Get-ItemProperty -Path $k | Select-Object fDenyTSConnections,TSUserEnabled,StartRCM,updateRDStatus | Format-List | Out-String | Tee-Object -FilePath $log -Append
Get-Service TermService,SessionEnv,UmRdpService | Format-Table -Auto Name,Status,StartType | Out-String | Tee-Object -FilePath $log -Append
cmd /c "netstat -ano -p tcp | findstr :3389" 2>&1 | Tee-Object -FilePath $log -Append
cmd /c "qwinsta" 2>&1 | Tee-Object -FilePath $log -Append
W '=== END ==='
