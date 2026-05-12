$ErrorActionPreference='Continue'
$ts=Get-Date -Format 'yyyyMMdd-HHmmss'
$log="C:\Users\Public\bc250_repair_upgrade_$ts.log"
function W([string]$m){ $line = "[{0}] {1}" -f (Get-Date -Format 's'),$m; $line | Tee-Object -FilePath $log -Append }

W "=== BC250 Repair Upgrade Start ==="
$iso='C:\Users\Public\Win10_22H2_EnglishInternational_x64.iso'
if(!(Test-Path $iso)){ W "ERROR: ISO missing at $iso"; exit 2 }

try {
  $img=Get-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue
  if(-not $img -or -not $img.Attached){
    W 'Mounting ISO...'
    Mount-DiskImage -ImagePath $iso -StorageType ISO -Access ReadOnly -ErrorAction Stop | Out-Null
    Start-Sleep -Seconds 2
  } else { W 'ISO already mounted.' }
} catch { W ("ERROR mounting ISO: " + $_.Exception.Message); exit 3 }

$img=Get-DiskImage -ImagePath $iso
$device=$img.DevicePath
W ("DiskImage DevicePath: " + $device)

$drive=$null
try {
  $cd = Get-CimInstance Win32_CDROMDrive | Where-Object { $_.DeviceID -eq $device } | Select-Object -First 1
  if($cd -and $cd.Drive){ $drive=$cd.Drive }
} catch {}

if(-not $drive){
  $cands = Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.DriveLetter } | Sort-Object DriveLetter
  foreach($v in $cands){
    $d=($v.DriveLetter + ':')
    if(Test-Path (Join-Path $d 'setup.exe')){ $drive=$d; break }
  }
}

if(-not $drive){ W 'ERROR: Could not resolve mounted drive letter.'; exit 4 }
$setup=Join-Path $drive 'setup.exe'
W ("Resolved setup path: " + $setup)
if(!(Test-Path $setup)){ W ("ERROR: setup.exe not found at " + $setup); exit 5 }

$scanLog="C:\Users\Public\BC250_SetupLogs_scan_$ts.zip"
$scanArgs="/auto upgrade /quiet /eula accept /compat scanonly /dynamicupdate disable /copylogs `"$scanLog`""
W ("Running compat scan: " + $scanArgs)
$scanProc=Start-Process -FilePath $setup -ArgumentList $scanArgs -PassThru -Wait
W ("Compat scan exit code: " + $scanProc.ExitCode)
if($scanProc.ExitCode -ne 0){
  W 'Compat scan failed; aborting before upgrade.'
  exit $scanProc.ExitCode
}

$fullLog="C:\Users\Public\BC250_SetupLogs_upgrade_$ts.zip"
$fullArgs="/auto upgrade /quiet /eula accept /dynamicupdate disable /showoobe none /compat ignorewarning /noreboot /copylogs `"$fullLog`""
W ("Running repair upgrade: " + $fullArgs)
$fullProc=Start-Process -FilePath $setup -ArgumentList $fullArgs -PassThru -Wait
W ("Repair upgrade exit code: " + $fullProc.ExitCode)

$act='C:\$WINDOWS.~BT\Sources\Panther\setupact.log'
$err='C:\$WINDOWS.~BT\Sources\Panther\setuperr.log'
if(Test-Path $err){ W 'Tail setuperr.log:'; Get-Content -Path $err -Tail 120 | Tee-Object -FilePath $log -Append }
if(Test-Path $act){ W 'Tail setupact.log:'; Get-Content -Path $act -Tail 120 | Tee-Object -FilePath $log -Append }

W '=== BC250 Repair Upgrade End ==='
exit $fullProc.ExitCode
