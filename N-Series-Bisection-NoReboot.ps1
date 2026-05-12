param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("n_series_bisection_{0}.log" -f $ts)
$work = Join-Path $ProjectRoot ("n_series_{0}" -f $ts)
New-Item -ItemType Directory -Path $work -Force | Out-Null

$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$cl = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe"
$link = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe"
$sig = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
$kit = "C:\Program Files (x86)\Windows Kits\10"
$incKm = Join-Path $kit "Include\10.0.19041.0\km"
$incShared = Join-Path $kit "Include\10.0.19041.0\shared"
$incCrt = Join-Path $kit "Include\10.0.19041.0\km\crt"
$lib = Join-Path $kit "Lib\10.0.19041.0\km\x64"
$objDir = Join-Path $ProjectRoot "build\Release\x64\amdbc250kmd"
$pkg = Join-Path $ProjectRoot "build\Release\x64\package\amdbc250kmd.sys"

function L([string]$m) {
    ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) | Tee-Object -FilePath $log -Append
}

function HashOf([string]$p) {
    if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash }
    return "MISSING"
}

function M([string]$p, [string]$mk) {
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

$kmdObj = Join-Path $objDir "amdbc250_kmd.obj"
$hwObj = Join-Path $objDir "amdbc250_hw_init.obj"
$fwObj = Join-Path $objDir "amdbc250_fw_loader.obj"
L ("OBJ_KMD={0}|EXISTS={1}|H={2}" -f $kmdObj, (Test-Path $kmdObj), (HashOf $kmdObj))
L ("OBJ_HW={0}|EXISTS={1}|H={2}" -f $hwObj, (Test-Path $hwObj), (HashOf $hwObj))
L ("OBJ_FW={0}|EXISTS={1}|H={2}" -f $fwObj, (Test-Path $fwObj), (HashOf $fwObj))

$baseC = Join-Path $work "n_base.c"
$baseObj = Join-Path $work "n_base.obj"
$baseCode = @"
typedef long NTSTATUS;
typedef void* PVOID;
#define STATUS_SUCCESS ((NTSTATUS)0x00000000L)
NTSTATUS DriverEntry(PVOID DriverObject, PVOID RegistryPath){(void)DriverObject;(void)RegistryPath;return STATUS_SUCCESS;}
"@
Set-Content -LiteralPath $baseC -Value $baseCode -Encoding ASCII
& $cl /nologo /W3 /WX- /O1 /Oi /GS- /TC /c $baseC /Fo$baseObj *>> $log
L ("BASE_CL_EXIT={0}" -f $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { throw "Base stub compile failed" }

$cases = @(
    @{ Name = "N0_BASE"; Objs = @($baseObj) },
    @{ Name = "N1_KMD_ONLY"; Objs = @($kmdObj) },
    @{ Name = "N2_HW_ONLY"; Objs = @($baseObj, $hwObj) },
    @{ Name = "N3_FW_ONLY"; Objs = @($baseObj, $fwObj) },
    @{ Name = "N4_HW_FW"; Objs = @($baseObj, $hwObj, $fwObj) },
    @{ Name = "N5_KMD_HW"; Objs = @($kmdObj, $hwObj) },
    @{ Name = "N6_KMD_FW"; Objs = @($kmdObj, $fwObj) },
    @{ Name = "N7_FULL"; Objs = @($kmdObj, $hwObj, $fwObj) }
)

foreach ($c in $cases) {
    $name = $c.Name
    $marker = "N_SERIES_${name}_$ts"

    $markerC = Join-Path $work ("mk_{0}.c" -f $name)
    $markerObj = Join-Path $work ("mk_{0}.obj" -f $name)
    $markerCode = "__declspec(selectany) const char ${name}_MARKER[] = `"$marker`";"
    Set-Content -LiteralPath $markerC -Value $markerCode -Encoding ASCII
    & $cl /nologo /TC /c $markerC /Fo$markerObj *>> $log
    L ("{0}|MARKER_CL_EXIT={1}" -f $name, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { continue }

    $aSys = Join-Path $work ("{0}.sys" -f $name)
    Remove-Item -LiteralPath $aSys -Force -ErrorAction SilentlyContinue

    $objs = @($c.Objs + $markerObj)
    $missing = $objs | Where-Object { -not (Test-Path $_) }
    if ($missing.Count -gt 0) {
        L ("{0}|SKIP_MISSING_OBJS={1}" -f $name, ($missing -join ";"))
        continue
    }

    & $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$aSys" "/LIBPATH:$lib" $objs ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib *>> $log
    L ("{0}|LINK_EXIT={1}" -f $name, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $aSys)) { continue }

    $aPre = HashOf $aSys
    $hasM = M $aSys $marker
    L ("{0}|A_PRE={1}|MARKER={2}" -f $name, $aPre, $hasM)
    if (-not $hasM) {
        L ("{0}|SKIP_NO_MARKER=1" -f $name)
        continue
    }

    & $sig sign /fd sha256 /f C:\bc250new.pfx /p bc250 $aSys *>> $log
    L ("{0}|SIGN_EXIT={1}" -f $name, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { continue }

    $aPost = HashOf $aSys
    $svc = ("nser_{0}_{1}" -f $name.ToLower(), $ts)
    $cSys = "C:\Windows\System32\drivers\$svc.sys"
    Copy-Item -LiteralPath $aSys -Destination $cSys -Force
    $cHash = HashOf $cSys
    $eq = ($aPost -eq $cHash)
    L ("{0}|A_POST={1}|C_HASH={2}|A_EQ_C={3}|B_HASH={4}" -f $name, $aPost, $cHash, $eq, (HashOf $pkg))
    if (-not $eq) {
        L ("{0}|SKIP_HASH_MISMATCH=1" -f $name)
        continue
    }

    Remove-ServiceSafe $svc
    sc.exe create $svc type= kernel start= demand error= normal binPath= ("\SystemRoot\System32\drivers\$svc.sys") DisplayName= ("BC250 $svc") *>> $log
    sc.exe start $svc *>> $log
    $startExit = $LASTEXITCODE
    L ("{0}|SC_START_EXIT={1}" -f $name, $startExit)
    Start-Sleep -Seconds 2
    sc.exe query $svc *>> $log

    Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = (Get-Date).AddMinutes(-5) } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match "Service Control Manager|Kernel-PnP" -or $_.Message -match $svc } |
        Select-Object -First 8 TimeCreated, Id, ProviderName, Message |
        Format-List * |
        Out-String -Width 4096 |
        Add-Content $log

    sc.exe stop $svc *>> $log
    sc.exe delete $svc *>> $log
    Remove-Item -LiteralPath $cSys -Force -ErrorAction SilentlyContinue
}

L "N_SERIES_DONE=1"
Get-Content $log -Tail 360
