Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' |
  Select-Object fEnableWinStation,PortNumber,UserAuthentication,SecurityLayer,LanAdapter,MinEncryptionLevel,SSLCertificateSHA1Hash,SecurityLayer
