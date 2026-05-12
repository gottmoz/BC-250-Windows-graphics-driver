$ErrorActionPreference='Stop'
$log='C:\Users\Public\rdp_file_patch_'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log'
function W($m){ $m | Tee-Object -FilePath $log -Append }

W ('START=' + (Get-Date -Format s))

$map = @{
  'C:\Windows\System32\termsrv.dll'   = 'C:\Windows\WinSxS\amd64_microsoft-windows-t..teconnectionmanager_31bf3856ad364e35_10.0.19041.3271_none_03668b4c0974010b\termsrv.dll'
  'C:\Windows\System32\rdpcorets.dll' = 'C:\Windows\WinSxS\amd64_microsoft-windows-r..s-regkeys-component_31bf3856ad364e35_10.0.19041.3324_none_a4455e71bd0c005b\rdpcorets.dll'
  'C:\Windows\System32\rdpinit.exe'   = 'C:\Windows\WinSxS\amd64_microsoft-windows-t..lications-clientsku_31bf3856ad364e35_10.0.19041.1682_none_93780fe2fb732500\rdpinit.exe'
  'C:\Windows\System32\rdpshell.exe'  = 'C:\Windows\WinSxS\amd64_microsoft-windows-t..lications-clientsku_31bf3856ad364e35_10.0.19041.1682_none_93780fe2fb732500\rdpshell.exe'
  'C:\Windows\System32\rdpclip.exe'   = 'C:\Windows\WinSxS\amd64_microsoft-windows-t..lipboardredirection_31bf3856ad364e35_10.0.19041.2075_none_76b29cf8c04245d9\rdpclip.exe'
  'C:\Windows\System32\rdpendp.dll'   = 'C:\Windows\WinSxS\amd64_microsoft-windows-t..ices-rdpsounddriver_31bf3856ad364e35_10.0.19041.746_none_18c2980b58d44ec1\rdpendp.dll'
  'C:\Windows\System32\umrdp.dll'     = 'C:\Windows\WinSxS\amd64_microsoft-windows-t..ices-portredirector_31bf3856ad364e35_10.0.19041.1806_none_d627d6535aaaeadc\umrdp.dll'
}

foreach($kv in $map.GetEnumerator()){
  if(-not (Test-Path $kv.Value)){ W ('MISSING_SRC ' + $kv.Key + ' <= ' + $kv.Value); throw 'Missing source file(s)' }
}

$backupRoot='C:\Users\Public\rdp_file_backup'
New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null

W 'Stopping RDP services'
Stop-Service UmRdpService -Force -ErrorAction SilentlyContinue
Stop-Service TermService -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

foreach($dst in $map.Keys){
  $name=[IO.Path]::GetFileName($dst)
  $bak=Join-Path $backupRoot ($name + '.bak')
  if(-not (Test-Path $bak)){ Copy-Item -LiteralPath $dst -Destination $bak -Force }

  & takeown.exe /f $dst | Out-Null
  & icacls.exe $dst /grant '*S-1-5-32-544:F' /c | Out-Null

  $src=$map[$dst]
  Copy-Item -LiteralPath $src -Destination $dst -Force
  $vi=(Get-Item $dst).VersionInfo.FileVersion
  W ('PATCHED ' + $dst + ' => ' + $vi)
}

W 'Starting RDP services'
Start-Service TermService -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4
Start-Service UmRdpService -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$ok = (Test-NetConnection localhost -Port 3389 -WarningAction SilentlyContinue -InformationLevel Quiet)
W ('LISTEN3389=' + $ok)

if(-not $ok){
  W 'No listener; rolling back patched files'
  Stop-Service UmRdpService -Force -ErrorAction SilentlyContinue
  Stop-Service TermService -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2

  foreach($dst in $map.Keys){
    $name=[IO.Path]::GetFileName($dst)
    $bak=Join-Path $backupRoot ($name + '.bak')
    if(Test-Path $bak){
      & takeown.exe /f $dst | Out-Null
      & icacls.exe $dst /grant '*S-1-5-32-544:F' /c | Out-Null
      Copy-Item -LiteralPath $bak -Destination $dst -Force
      W ('RESTORED ' + $dst)
    }
  }

  Start-Service TermService -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 4
  Start-Service UmRdpService -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2

  $ok2 = (Test-NetConnection localhost -Port 3389 -WarningAction SilentlyContinue -InformationLevel Quiet)
  W ('POST_ROLLBACK_LISTEN3389=' + $ok2)
}

W 'Final state:'
Get-Service TermService,UmRdpService | ForEach-Object { W ('SERVICE ' + $_.Name + '=' + $_.Status) }
cmd /c "qwinsta" | Tee-Object -FilePath $log -Append | Out-Null
cmd /c "netstat -ano -p tcp | findstr :3389" | Tee-Object -FilePath $log -Append | Out-Null
W ('END=' + (Get-Date -Format s))
Write-Output $log
