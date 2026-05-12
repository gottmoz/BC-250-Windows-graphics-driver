$ErrorActionPreference = 'Continue'
$ProjectRoot = 'C:\Dev\BC250-windowsDriverTest'
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("i1_qseg3_commitlimit_{0}.log" -f $ts)
$out = Join-Path $ProjectRoot ("i1_qseg3_commitlimit_{0}" -f $ts)
New-Item -ItemType Directory -Path $out -Force | Out-Null

function L([string]$m) {
  $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m
  $line | Tee-Object -FilePath $log -Append
}
function HashSafe([string]$p) { if(Test-Path $p){ (Get-FileHash $p -Algorithm SHA256).Hash } else { 'MISSING' } }

L "LOG=$log"
L "PROFILE=I1_QSEG3_COMMITLIMIT_SIZE"
L "CHANGE=Only QUERYSEGMENT3 CommitLimit=Size"

$msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
$link='C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe'
$kmLib='C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64'
$objDir=Join-Path $ProjectRoot 'build\Release\x64\amdbc250kmd'
$sys=Join-Path $out 'I1_QSEG3_COMMITLIMIT.sys'

L 'BUILD_KMD_START'
& $msbuild (Join-Path $ProjectRoot 'amdbc250kmd.vcxproj') /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
L ("BUILD_KMD_EXIT={0}" -f $LASTEXITCODE)
if($LASTEXITCODE -ne 0){ Get-Content $log -Tail 160; exit 10 }

$objs=@('amdbc250_kmd.obj','amdbc250_hw_init.obj','amdbc250_fw_loader.obj') | ForEach-Object { Join-Path $objDir $_ } | Where-Object { Test-Path $_ }
foreach($o in $objs){ L ("OBJ=$o|HASH=$(HashSafe $o)") }
if($objs.Count -lt 2){ L "ERR_MISSING_OBJS=$($objs.Count)"; Get-Content $log -Tail 160; exit 11 }

L 'LINK_START'
& $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$sys" "/LIBPATH:$kmLib" $objs ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib *>> $log
L ("LINK_EXIT={0}" -f $LASTEXITCODE)
if($LASTEXITCODE -ne 0 -or -not (Test-Path $sys)){ Get-Content $log -Tail 160; exit 12 }
L ("SYS=$sys")
L ("SYS_HASH=$(HashSafe $sys)")

L 'PNP_BIND_START'
& (Join-Path $ProjectRoot 'P0-N9C-PnpBind-Hashed-NoReboot.ps1') -ProjectRoot $ProjectRoot -N9Dir $out -N9SysName 'I1_QSEG3_COMMITLIMIT.sys' *>> $log
L ("PNP_BIND_EXIT={0}" -f $LASTEXITCODE)

$d=Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\VEN_1002&DEV_13FE*' } | Select-Object -First 1
if($d){
  $svc=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue).Data
  $pc=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue).Data
  $ps=(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_ProblemStatus' -ErrorAction SilentlyContinue).Data
  L ("POST_BIND_STATUS=$($d.Status)|SERVICE=$svc|PROBLEM=$pc|PSTATUS=0x{0:X8}" -f [uint32]$ps)
}

L 'RECOVERY_REBOOT_START'
& (Join-Path $ProjectRoot 'tmp_remote_recover_basic.ps1') *>> $log
L ("RECOVERY_EXIT={0}" -f $LASTEXITCODE)
Get-Content $log -Tail 260
