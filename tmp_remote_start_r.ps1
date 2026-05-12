$runLog='C:\Dev\BC250-windowsDriverTest\r_trace_bg.log'
$flag='C:\Dev\BC250-windowsDriverTest\r_trace_done.flag'
if(Test-Path $runLog){ Remove-Item $runLog -Force }
if(Test-Path $flag){ Remove-Item $flag -Force }
$cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Dev\BC250-windowsDriverTest\R-Series-PostStartTrace-Run.ps1 *> $runLog; echo DONE > $flag"
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmd -WindowStyle Hidden -PassThru
"PID=$($p.Id)"
"LOG=$runLog"
"FLAG=$flag"
