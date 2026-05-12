$ErrorActionPreference='Continue'
$log='C:\Users\Public\wu_install_kb5082200_'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log'
function W($m){$m|Tee-Object -FilePath $log -Append}
W ('START=' + (Get-Date -Format s))
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
W ('FOUND=' + $result.Updates.Count)
$toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
for($i=0; $i -lt $result.Updates.Count; $i++){
  $u=$result.Updates.Item($i)
  W ('CANDIDATE=' + $u.Title)
  if($u.Title -like '*KB5082200*'){ [void]$toInstall.Add($u); W 'SELECTED=KB5082200' }
}
if($toInstall.Count -eq 0){ W 'NO_TARGET_UPDATE'; W ('END=' + (Get-Date -Format s)); exit 0 }
$downloader = $session.CreateUpdateDownloader(); $downloader.Updates = $toInstall
W 'DOWNLOAD_START'
$dr = $downloader.Download()
W ('DOWNLOAD_RESULT=' + $dr.ResultCode + ' HResult=' + ('0x{0:X8}' -f ($dr.HResult -band 0xffffffff)))
$installer = $session.CreateUpdateInstaller(); $installer.Updates = $toInstall
W 'INSTALL_START'
$ir = $installer.Install()
W ('INSTALL_RESULT=' + $ir.ResultCode + ' HResult=' + ('0x{0:X8}' -f ($ir.HResult -band 0xffffffff)) + ' REBOOT=' + $ir.RebootRequired)
for($i=0; $i -lt $toInstall.Count; $i++){
  $res = $ir.GetUpdateResult($i)
  $title = $toInstall.Item($i).Title
  W ('UPDATE_RESULT=' + $title + ' => RC=' + $res.ResultCode + ' HR=' + ('0x{0:X8}' -f ($res.HResult -band 0xffffffff)))
}
W ('END=' + (Get-Date -Format s))
