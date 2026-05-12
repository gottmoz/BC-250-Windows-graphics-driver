$ErrorActionPreference='Continue'
$inst = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\VEN_1002&DEV_13FE*' } | Select-Object -First 1
if($inst){
  Write-Output ('TARGET='+$inst.InstanceId)
  pnputil /disable-device "$($inst.InstanceId)"
}
sc.exe config amdbc250kmd start= disabled | Out-Host

$all = pnputil /enum-drivers | Out-String
$blocks = ($all -split "`r?`n`r?`n") | Where-Object { $_ -match 'amdbc250\.inf' -or $_ -match 'Provider Name:\s*BC250' }
foreach($b in $blocks){
  $m = [regex]::Match($b,'Published Name:\s*(oem\d+\.inf)')
  if($m.Success){
    $oem = $m.Groups[1].Value
    Write-Output ('REMOVE_DRIVER='+$oem)
    pnputil /delete-driver $oem /uninstall /force
  }
}

if($inst){ pnputil /remove-device "$($inst.InstanceId)" }
pnputil /scan-devices
Write-Output 'RECOVERY_DONE=1'
shutdown /r /t 10
