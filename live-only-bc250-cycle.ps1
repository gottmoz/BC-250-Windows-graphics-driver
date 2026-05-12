Write-Output '=== live-only test start ==='
Write-Output ('start=' + (Get-Date -Format o))
$repo='C:\Dev\BC250-windowsDriverTest'
$start=Get-Date
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\remote-iter-fast.ps1
$iterExit=$LASTEXITCODE
Write-Output "remote_iter_exit=$iterExit"
Write-Output '=== active capture ==='
Get-PnpDevice -Class Display -PresentOnly | Format-List Status,FriendlyName,Problem,Service,InstanceId
Get-PnpDeviceProperty -InstanceId (Get-PnpDevice -Class Display -PresentOnly | Select-Object -First 1).InstanceId -KeyName DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_Service,DEVPKEY_Device_ProblemCode,DEVPKEY_Device_ProblemStatus | Select-Object KeyName,Data | Format-Table -AutoSize
C:\Users\Public\kmt_enum.exe
C:\Users\Public\dxgi_enum.exe
Write-Output '=== recent events after bind ==='
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$start} -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -match 'Kernel-PnP|Service Control|Display|DxgKrnl|DriverFrameworks' -or $_.Message -match 'amdbc250|BC-250|display|dxgkrnl|BasicDisplay|VEN_1002' } | Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message | Format-List | Out-String -Width 220
Write-Output '=== restore display.inf ==='
sc.exe config amdbc250kmd start= disabled
$drivers = pnputil /enum-drivers
$current=$null; $orig=$null
foreach($line in $drivers){
  if($line -match '^Published Name:\s+(\S+)'){ $current=$matches[1]; $orig=$null }
  elseif($line -match '^Original Name:\s+(\S+)'){ $orig=$matches[1] }
  elseif($line.Trim() -eq ''){ if($orig -ieq 'amdbc250.inf' -and $current){ pnputil /delete-driver $current /uninstall /force }; $current=$null; $orig=$null }
}
if($orig -ieq 'amdbc250.inf' -and $current){ pnputil /delete-driver $current /uninstall /force }
& 'C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe' update C:\Windows\INF\display.inf PCI\VEN_1002`&DEV_13FE
Write-Output ('restore_devcon_exit=' + $LASTEXITCODE)
sc.exe config amdbc250kmd start= disabled
Start-Sleep -Seconds 2
Write-Output '=== final safe state ==='
Get-PnpDevice -Class Display -PresentOnly | Format-List Status,FriendlyName,Problem,Service,InstanceId
Get-PnpDeviceProperty -InstanceId (Get-PnpDevice -Class Display -PresentOnly | Select-Object -First 1).InstanceId -KeyName DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_Service,DEVPKEY_Device_ProblemCode,DEVPKEY_Device_ProblemStatus | Select-Object KeyName,Data | Format-Table -AutoSize
sc.exe qc amdbc250kmd
