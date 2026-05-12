$log='C:\Users\Public\bc250_bind3389_probe.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== bind3389 probe ==='
try {
  $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any,3389)
  $l.Start()
  W 'BIND_OK'
  Start-Sleep -Seconds 3
  $l.Stop()
  W 'STOP_OK'
} catch {
  W ('BIND_FAIL: ' + $_.Exception.GetType().FullName + ' :: ' + $_.Exception.Message)
}
W '=== END ==='
