$log='C:\Users\Public\bc250_port3389_listener_test.log'
"START $(Get-Date -Format s)" | Out-File -FilePath $log -Encoding utf8 -Append
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any,3389)
$listener.Start()
"LISTENING" | Out-File -FilePath $log -Encoding utf8 -Append
Start-Sleep -Seconds 35
$listener.Stop()
"STOP $(Get-Date -Format s)" | Out-File -FilePath $log -Encoding utf8 -Append
