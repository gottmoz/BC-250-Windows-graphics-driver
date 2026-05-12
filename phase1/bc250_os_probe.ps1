$cv='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Get-ItemProperty -Path $cv | Select-Object ProductName,EditionID,DisplayVersion,CurrentBuild,CurrentBuildNumber,UBR | Format-List
