$log='C:\Users\Public\bc250_rdp_cert_fix.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== RDP Cert Fix ==='
W '--- Existing certs in LocalMachine\\Remote Desktop ---'
try {
  $certs = Get-ChildItem -Path 'Cert:\LocalMachine\Remote Desktop' -ErrorAction Stop
  if($certs){ $certs | Select-Object Subject,Thumbprint,NotBefore,NotAfter | Format-Table -Auto | Out-String | Tee-Object -FilePath $log -Append }
  else { W 'No certs found.' }
} catch { W ("Read cert store error: " + $_.Exception.Message) }

W '--- Remove certs in LocalMachine\\Remote Desktop ---'
try {
  Get-ChildItem -Path 'Cert:\LocalMachine\Remote Desktop' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  W 'Removed cert(s) if present.'
} catch { W ("Remove cert error: " + $_.Exception.Message) }

W '--- restart TermService ---'
try { Stop-Service TermService -Force -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 2
try { Start-Service TermService -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 4

W '--- Post status ---'
Get-Service TermService,UmRdpService,SessionEnv | Format-Table -Auto Name,Status,StartType | Out-String | Tee-Object -FilePath $log -Append
cmd /c "netstat -ano -p tcp | findstr :3389" 2>&1 | Tee-Object -FilePath $log -Append
cmd /c "qwinsta" 2>&1 | Tee-Object -FilePath $log -Append
W '=== END ==='
