Write-Output '=== SC QC ==='
cmd /c sc qc TermService
cmd /c sc qc UmRdpService
cmd /c sc queryex TermService
cmd /c sc queryex UmRdpService
Write-Output '=== EVENTLOG SERVICE FAIL ==='
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddMinutes(-30)} -ErrorAction SilentlyContinue |
  Where-Object { $_.ProviderName -eq 'Service Control Manager' -and ($_.Id -in 7000,7001,7009,7011,7023,7031,7034) -and $_.Message -match 'UmRdpService|TermService|Remote Desktop' } |
  Select-Object TimeCreated,Id,Message | Format-List
