Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
  Select-Object ProductName,EditionID,CurrentBuild,DisplayVersion,ReleaseId | Format-List
