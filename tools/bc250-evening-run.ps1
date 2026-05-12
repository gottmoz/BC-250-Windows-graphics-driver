$ErrorActionPreference = 'Continue'
$log = 'C:\Users\Public\bc250-evening-run.log'
$maps = @('ati2mtag_Raphael','ati2mtag_Phoenix','ati2mtag_Navi33','ati2mtag_DragonRange','ati2mtag_Navi10','ati2mtag_Navi32','ati2mtag_Mendocino')
$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$devcon='C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe'
$endTime = (Get-Date).Date.AddDays(1).AddHours(7)
function Log([string]$m){ $ts = Get-Date -Format o; "$ts $m" | Tee-Object -FilePath $log -Append }
function Get-State { $p = Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue; $inf = ($p | ? KeyName -match 'DriverInfPath').Data; $code=[int](($p | ? KeyName -match 'ProblemCode').Data); [pscustomobject]@{Inf=$inf;Code=$code} }
function Recover-Baseline {
  Log 'RECOVER begin'; pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null; pnputil /delete-driver oem9.inf /uninstall /force | Out-Null; pnputil /delete-driver oem21.inf /uninstall /force | Out-Null; pnputil /scan-devices | Out-Null; & $devcon remove "$inst" | Out-Null; Start-Sleep 2; pnputil /scan-devices | Out-Null; Start-Sleep 2; & $devcon update C:\Windows\INF\display.inf 'PCI\VEN_1002&DEV_13FE' | Out-Null; pnputil /restart-device "$inst" | Out-Null; Start-Sleep 2; $s=Get-State; Log ("RECOVER end INF={0} CODE={1}" -f $s.Inf,$s.Code)
}
Log 'EVENING_RUN start'; $iter=0
while((Get-Date) -lt $endTime){
  $iter++; $map=$maps[($iter-1)%$maps.Count]; $pre=Get-State; if($pre.Inf -ne 'display.inf' -or $pre.Code -ne 0){ Recover-Baseline }
  Log ("ITER {0} map={1} begin" -f $iter,$map); $sw=[Diagnostics.Stopwatch]::StartNew()
  try { powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\bc250-safe-iterate.ps1 -map $map 2>&1 | % { Log ("ITER {0} {1}" -f $iter,$_)} } catch { Log ("ITER {0} ERROR {1}" -f $iter,$_.Exception.Message) }
  $sw.Stop(); Log ("ITER {0} seconds={1}" -f $iter,[Math]::Round($sw.Elapsed.TotalSeconds,1)); $post=Get-State; if($post.Inf -ne 'display.inf' -or $post.Code -ne 0){ Log ("ITER {0} post-baseline drift INF={1} CODE={2}" -f $iter,$post.Inf,$post.Code); Recover-Baseline }
  if(($iter % 6) -eq 0){ Log ("ITER {0} instrumented custom cycle begin" -f $iter); try { powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\live-only-bc250-cycle.ps1 2>&1 | % { Log ("CYCLE {0} {1}" -f $iter,$_)} } catch { Log ("CYCLE {0} ERROR {1}" -f $iter,$_.Exception.Message) }; $post2=Get-State; if($post2.Inf -ne 'display.inf' -or $post2.Code -ne 0){ Recover-Baseline } }
  Start-Sleep 3
}
Log 'EVENING_RUN end'
