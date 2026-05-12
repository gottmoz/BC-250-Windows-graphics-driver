Write-Output '=== LOCAL 3389 TEST ==='
Test-NetConnection 127.0.0.1 -Port 3389 | Select-Object ComputerName,RemotePort,TcpTestSucceeded
Test-NetConnection localhost -Port 3389 | Select-Object ComputerName,RemotePort,TcpTestSucceeded
Test-NetConnection 192.168.50.189 -Port 3389 | Select-Object ComputerName,RemotePort,TcpTestSucceeded
Write-Output '=== NETSTAT ==='
cmd /c netstat -an | findstr 3389
