param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("m0c_full_kmd_manual_link_gate_{0}.log" -f $ts)
$src = Join-Path $ProjectRoot "amdbc250_kmd.c"
$srcBak = "$src.bak_$ts"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$link = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
$kmLib = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64"
$objDir = Join-Path $ProjectRoot "build\Release\x64\amdbc250kmd"
$packageSys = Join-Path $ProjectRoot "build\Release\x64\package\amdbc250kmd.sys"
$aSys = Join-Path $ProjectRoot ("build\Release\x64\m0c_fullkmd_{0}.sys" -f $ts)
$marker = "AMDBC250_FULL_KMD_M0C_20260508_$ts"

function L([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m
    $line | Tee-Object -FilePath $log -Append
}

function HashSafe([string]$p) {
    if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash }
    return "MISSING"
}

function HasMarker([string]$p, [string]$mk) {
    if (-not (Test-Path $p)) { return $false }
    try {
        $ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($p))
        return $ascii.Contains($mk)
    }
    catch { return $false }
}

function Remove-ServiceSafe([string]$n) {
    sc.exe stop $n *>> $log
    sc.exe delete $n *>> $log
}

L "LOG=$log"
L "MARKER=$marker"
L "NO_REBOOT=1"

Copy-Item -LiteralPath $src -Destination $srcBak -Force

try {
    Add-Content -LiteralPath $src -Value "`r`n__declspec(selectany) const char g_Amdbc250BuildMarker_M0C[] = `"$marker`";`r`n"
    L "SOURCE_MARKER_APPENDED=1"

    & $msbuild (Join-Path $ProjectRoot "amdbc250kmd.vcxproj") /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
    L ("BUILD_EXIT={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }

    $objs = @(
        (Join-Path $objDir "amdbc250_kmd.obj"),
        (Join-Path $objDir "amdbc250_hw_init.obj"),
        (Join-Path $objDir "amdbc250_fw_loader.obj")
    )

    foreach ($o in $objs) {
        L ("OBJ={0}|EXISTS={1}|HASH={2}" -f $o, (Test-Path $o), (HashSafe $o))
    }

    $missing = $objs | Where-Object { -not (Test-Path $_) }
    if ($missing.Count -gt 0) { throw ("Missing objects: " + ($missing -join ", ")) }

    Remove-Item -LiteralPath $aSys -Force -ErrorAction SilentlyContinue
    & $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE `
        "/OUT:$aSys" "/LIBPATH:$kmLib" `
        $objs ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib *>> $log
    L ("LINK_EXIT={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $aSys)) { throw "Manual full-KMD link failed" }

    $markerA = HasMarker $aSys $marker
    $aHashPreSign = HashSafe $aSys
    $bHash = HashSafe $packageSys
    L ("A_PATH={0}" -f $aSys)
    L ("A_HASH_PRE_SIGN={0}" -f $aHashPreSign)
    L ("A_MARKER={0}" -f $markerA)
    L ("B_PATH={0}" -f $packageSys)
    L ("B_HASH={0}" -f $bHash)
    if (-not $markerA) { throw "A.sys missing marker; not testing stale-risky artifact" }

    & $signtool sign /fd sha256 /f C:\bc250new.pfx /p bc250 $aSys *>> $log
    L ("SIGN_A_EXIT={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { throw "Sign A failed" }
    $aHash = HashSafe $aSys
    L ("A_HASH_POST_SIGN={0}" -f $aHash)

    $svc = ("m0cfullkmd_{0}" -f $ts).ToLower()
    $cPath = "C:\Windows\System32\drivers\$svc.sys"
    Copy-Item -LiteralPath $aSys -Destination $cPath -Force
    $cHash = HashSafe $cPath
    L ("C_PATH={0}" -f $cPath)
    L ("C_HASH={0}" -f $cHash)
    L ("A_EQ_C={0}" -f ($aHash -eq $cHash))
    if ($aHash -ne $cHash) { throw "Hash mismatch between A and C" }

    Remove-ServiceSafe $svc
    sc.exe create $svc type= kernel start= demand error= normal binPath= ("\SystemRoot\System32\drivers\$svc.sys") DisplayName= ("BC250 $svc") *>> $log
    sc.exe start $svc *>> $log
    L ("SC_START_EXIT={0}" -f $LASTEXITCODE)
    Start-Sleep -Seconds 2
    sc.exe query $svc *>> $log

    Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = (Get-Date).AddMinutes(-10) } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match "Service Control Manager|Kernel-PnP|Display" -or $_.Message -match $svc -or $_.Message -match "amdbc250" } |
        Select-Object TimeCreated, Id, ProviderName, Message -First 40 |
        Format-List * |
        Out-String -Width 4096 |
        Add-Content $log

    sc.exe stop $svc *>> $log
    sc.exe delete $svc *>> $log
    Remove-Item -LiteralPath $cPath -Force -ErrorAction SilentlyContinue
    L "M0C_DONE=1"
}
finally {
    if (Test-Path $srcBak) {
        Copy-Item -LiteralPath $srcBak -Destination $src -Force
        Remove-Item -LiteralPath $srcBak -Force -ErrorAction SilentlyContinue
    }
    L "SOURCE_RESTORED=1"
}

Get-Content $log -Tail 320
