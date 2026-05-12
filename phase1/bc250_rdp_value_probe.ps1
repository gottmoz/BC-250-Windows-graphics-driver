$k='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
Get-ItemProperty -Path $k | Select-Object fLogonDisabled,UserAuthentication,SecurityLayer,PortNumber,fEnableWinStation,SelectTransport,SelectNetworkDetect | Format-List
