$ErrorActionPreference='Continue'
$ts=Get-Date -Format 'yyyyMMdd-HHmmss'
$log="C:\Users\Public\bc250_wu_rdp_fix_$ts.log"
function W($m){ $m | Tee-Object -FilePath $log -Append }
W "=== Windows Update RDP Fix $ts ==="

try {
  $session = New-Object -ComObject Microsoft.Update.Session
  $searcher = $session.CreateUpdateSearcher()
  W 'Searching updates...'
  $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
  W ("Updates found: " + $result.Updates.Count)

  if($result.Updates.Count -eq 0){
    W 'No updates available.'
    Write-Output $log
    exit 0
  }

  $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
  for($i=0; $i -lt $result.Updates.Count; $i++){
    $u = $result.Updates.Item($i)
    W ("["+$i+"] " + $u.Title)
    $title = $u.Title
    if($title -match 'Cumulative Update for Windows 10' -or $title -match 'Servicing Stack Update' -or $title -match 'Security Update for Windows 10'){
      [void]$toInstall.Add($u)
      W ('  -> selected')
    }
  }

  if($toInstall.Count -eq 0){
    W 'No targeted updates matched, selecting all found updates.'
    for($i=0; $i -lt $result.Updates.Count; $i++){ [void]$toInstall.Add($result.Updates.Item($i)) }
  }

  W ("Selected updates: " + $toInstall.Count)

  $downloader = $session.CreateUpdateDownloader()
  $downloader.Updates = $toInstall
  W 'Downloading selected updates...'
  $dres = $downloader.Download()
  W ("Download result code: " + $dres.ResultCode)

  $installer = $session.CreateUpdateInstaller()
  $installer.Updates = $toInstall
  W 'Installing selected updates...'
  $ires = $installer.Install()
  W ("Install result code: " + $ires.ResultCode)
  W ("Reboot required: " + $ires.RebootRequired)

  for($i=0; $i -lt $toInstall.Count; $i++){
    $u = $toInstall.Item($i)
    $ur = $ires.GetUpdateResult($i)
    W ("Result["+$i+"] HResult=" + ('0x{0:X8}' -f ($ur.HResult -band 0xFFFFFFFF)) + " Code=" + $ur.ResultCode + " :: " + $u.Title)
  }

} catch {
  W ("ERROR: " + $_.Exception.Message)
}

W '=== END ==='
Write-Output $log
