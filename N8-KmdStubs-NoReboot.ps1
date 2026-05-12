param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("n8_kmd_stubs_{0}.log" -f $ts)
$work = Join-Path $ProjectRoot ("n8_kmd_stubs_{0}" -f $ts)
New-Item -ItemType Directory -Path $work -Force | Out-Null

$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$cl = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe"
$link = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe"
$dumpbin = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
$kmLib = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64"
$incKm = "C:\Program Files (x86)\Windows Kits\10\Include\10.0.19041.0\km"
$incShared = "C:\Program Files (x86)\Windows Kits\10\Include\10.0.19041.0\shared"
$objDir = Join-Path $ProjectRoot "build\Release\x64\amdbc250kmd"
$kmdObj = Join-Path $objDir "amdbc250_kmd.obj"
$pkgSys = Join-Path $ProjectRoot "build\Release\x64\package\amdbc250kmd.sys"

function L([string]$m) {
    ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) | Tee-Object -FilePath $log -Append
}

function HashOf([string]$p) {
    if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash }
    return "MISSING"
}

function HasMarker([string]$p, [string]$mk) {
    if (-not (Test-Path $p)) { return $false }
    try {
        $a = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($p))
        return $a.Contains($mk)
    }
    catch { return $false }
}

function Remove-ServiceSafe([string]$n) {
    sc.exe stop $n *>> $log
    sc.exe delete $n *>> $log
}

L "LOG=$log"
L "NO_REBOOT=1"

& $msbuild (Join-Path $ProjectRoot "amdbc250kmd.vcxproj") /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
L ("FULL_BUILD_EXIT={0}" -f $LASTEXITCODE)
L ("KMD_OBJ={0}|EXISTS={1}|H={2}" -f $kmdObj, (Test-Path $kmdObj), (HashOf $kmdObj))
if (-not (Test-Path $kmdObj)) { throw "kmd obj missing" }

$marker = "N8_KMD_STUBS_$ts"
$stubC = Join-Path $work "n8_kmd_deps_stubs.c"
$stubObj = Join-Path $work "n8_kmd_deps_stubs.obj"
$mkC = Join-Path $work "n8_marker.c"
$mkObj = Join-Path $work "n8_marker.obj"

$stubCode = @"
typedef long NTSTATUS;
typedef void* PAMDBC250_DEVICE_EXTENSION;
#define STATUS_SUCCESS ((NTSTATUS)0x00000000L)
NTSTATUS Bc250HwInitialize(PAMDBC250_DEVICE_EXTENSION DevExt){(void)DevExt; return STATUS_SUCCESS;}
void Bc250HwShutdown(PAMDBC250_DEVICE_EXTENSION DevExt){(void)DevExt;}
NTSTATUS Bc250HwReset(PAMDBC250_DEVICE_EXTENSION DevExt){(void)DevExt; return STATUS_SUCCESS;}
"@
Set-Content -LiteralPath $stubC -Value $stubCode -Encoding ASCII

$markerCode = "__declspec(selectany) const char N8_MARKER[] = `"$marker`";"
Set-Content -LiteralPath $mkC -Value $markerCode -Encoding ASCII

& $cl /nologo /W3 /WX- /TC /c $stubC /Fo$stubObj *>> $log
L ("STUB_CL_EXIT={0}" -f $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { throw "stub compile failed" }

& $cl /nologo /W3 /WX- /TC /c $mkC /Fo$mkObj *>> $log
L ("MARKER_CL_EXIT={0}" -f $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { throw "marker compile failed" }

$n8aSys = Join-Path $work "N8A_KMD_STUBS.sys"
& $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$n8aSys" "/LIBPATH:$kmLib" $kmdObj $stubObj $mkObj ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib *>> $log
L ("N8A_LINK_EXIT={0}" -f $LASTEXITCODE)
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $n8aSys)) {
    L "N8A_LINK_FAILED=1"
    Get-Content $log -Tail 220
    exit 0
}

$aPre = HashOf $n8aSys
$hasM = HasMarker $n8aSys $marker
L ("N8A_A_PRE={0}|MARKER={1}" -f $aPre, $hasM)
if (-not $hasM) { throw "marker missing in N8A" }

& $signtool sign /fd sha256 /f C:\bc250new.pfx /p bc250 $n8aSys *>> $log
L ("N8A_SIGN_EXIT={0}" -f $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { throw "sign failed" }

$aPost = HashOf $n8aSys
$svc = ("n8a_kmdstubs_{0}" -f $ts).ToLower()
$cSys = "C:\Windows\System32\drivers\$svc.sys"
Copy-Item -LiteralPath $n8aSys -Destination $cSys -Force
$cHash = HashOf $cSys
$eq = ($aPost -eq $cHash)
L ("N8A_A_POST={0}|C_HASH={1}|A_EQ_C={2}|B_HASH={3}" -f $aPost, $cHash, $eq, (HashOf $pkgSys))
if (-not $eq) { throw "A/C hash mismatch" }

Remove-ServiceSafe $svc
sc.exe create $svc type= kernel start= demand error= normal binPath= ("\SystemRoot\System32\drivers\$svc.sys") DisplayName= ("BC250 $svc") *>> $log
sc.exe start $svc *>> $log
L ("N8A_SC_START_EXIT={0}" -f $LASTEXITCODE)
Start-Sleep -Seconds 2
sc.exe query $svc *>> $log

$n8Imp = Join-Path $work "N8A_imports.txt"
$n8Hdr = Join-Path $work "N8A_headers.txt"
$n8Sym = Join-Path $work "N8A_symbols.txt"
if (Test-Path $dumpbin) {
    & $dumpbin /imports $n8aSys *> $n8Imp
    & $dumpbin /headers $n8aSys *> $n8Hdr
    & $dumpbin /symbols $n8aSys *> $n8Sym
    L "N8A_DUMPBIN_DONE=1"
}

Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = (Get-Date).AddMinutes(-5) } -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match "Service Control Manager|Kernel-PnP" -or $_.Message -match $svc } |
    Select-Object -First 12 TimeCreated, Id, ProviderName, Message |
    Format-List * |
    Out-String -Width 4096 |
    Add-Content $log

sc.exe stop $svc *>> $log
sc.exe delete $svc *>> $log
Remove-Item -LiteralPath $cSys -Force -ErrorAction SilentlyContinue

L "N8_DONE=1"
Get-Content $log -Tail 320
