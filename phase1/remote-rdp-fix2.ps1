$ErrorActionPreference='Continue'
Write-Output '=== START UMRDP + RESTART TERMSERVICE ==='
Set-Service UmRdpService -StartupType Automatic
Start-Service UmRdpService
Restart-Service TermService -Force
Start-Sleep -Seconds 3
Write-Output '=== SERVICES ==='
Get-Service TermService,SessionEnv,UmRdpService | Format-Table -AutoSize Name,Status,StartType
Write-Output '=== QWINSTA ==='
cmd /c qwinsta
Write-Output '=== NETSTAT 3389 ==='
cmd /c netstat -ano | findstr ":3389"
