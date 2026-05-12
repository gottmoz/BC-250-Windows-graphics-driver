param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("m0_full_kmd_artifact_gate_{0}.log" -f $ts)
$src = Join-Path $ProjectRoot "amdbc250_kmd.c"
$srcBak = "$src.bak_$ts"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
$buildRoot = Join-Path $ProjectRoot "build\Release\x64"
$packageSys = Join-Path $ProjectRoot "build\Release\x64\package\amdbc250kmd.sys"
$marker = "AMDBC250_FULL_KMD_M0_20260508_$ts"

function L([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m
    $line | Tee-Object -FilePath $log -Append
}

function Get-HashSafe([string]$path) {
    if (Test-Path $path) { return (Get-FileHash $path -Algorithm SHA256).Hash }
    return "MISSING"
}

function Has-Marker([string]$path, [string]$mk) {
    if (-not (Test-Path $path)) { return $false }
    try {
        $b = [IO.File]::ReadAllBytes($path)
        $a = [Text.Encoding]::ASCII.GetString($b)
        return $a.Contains($mk)
    }
    catch { return $false }
}

L "LOG=$log"
L "MARKER=$marker"
L "NO_REBOOT=1"

Copy-Item -LiteralPath $src -Destination $srcBak -Force

try {
    Add-Content -LiteralPath $src -Value "`r`n__declspec(selectany) const char g_Amdbc250BuildMarker_M0[] = `"$marker`";`r`n"
    L "SOURCE_MARKER_APPENDED=1"

    $buildStart = Get-Date

    & $msbuild (Join-Path $ProjectRoot "amdbc250kmd.vcxproj") /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
    L ("BUILD_EXIT={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }

    $sysCandidates = Get-ChildItem -Path $buildRoot -Recurse -Filter "*.sys" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $buildStart.AddMinutes(-2) } |
        Sort-Object LastWriteTime -Descending

    L "CANDIDATE_COUNT=$($sysCandidates.Count)"
    foreach ($c in $sysCandidates) {
        L ("CANDIDATE={0}|{1}|{2}|MARKER={3}" -f $c.FullName, $c.Length, $c.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), (Has-Marker $c.FullName $marker))
    }

    $aCandidate = $sysCandidates | Where-Object { $_.FullName -notlike "*\\package\\*" -and (Has-Marker $_.FullName $marker) } | Select-Object -First 1
    if (-not $aCandidate) {
        $aCandidate = $sysCandidates | Where-Object { Has-Marker $_.FullName $marker } | Select-Object -First 1
    }
    if (-not $aCandidate) {
        throw "No freshly built SYS contains marker. Stale artifact risk."
    }

    $aPath = $aCandidate.FullName
    $aHash = Get-HashSafe $aPath
    $bHash = Get-HashSafe $packageSys

    L "A_PATH=$aPath"
    L "A_HASH=$aHash"
    L "B_PATH=$packageSys"
    L "B_HASH=$bHash"

    & $signtool sign /fd sha256 /f C:\bc250new.pfx /p bc250 $aPath *>> $log
    L ("SIGN_A_EXIT={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { throw "Sign A failed" }

    $svc = ("m0kmd_{0}" -f $ts).ToLower()
    $cPath = "C:\Windows\System32\drivers\$svc.sys"
    Copy-Item -LiteralPath $aPath -Destination $cPath -Force
    $cHash = Get-HashSafe $cPath

    L "C_PATH=$cPath"
    L "C_HASH=$cHash"
    L ("A_EQ_C={0}" -f ($aHash -eq $cHash))

    if ($aHash -ne $cHash) {
        throw "Hash mismatch between A and C"
    }

    sc.exe stop $svc *>> $log
    sc.exe delete $svc *>> $log

    sc.exe create $svc type= kernel start= demand error= normal binPath= ("\SystemRoot\System32\drivers\" + $svc + ".sys") DisplayName= ("BC250 " + $svc) *>> $log
    sc.exe start $svc *>> $log
    L ("SC_START_EXIT={0}" -f $LASTEXITCODE)
    Start-Sleep -Seconds 2
    sc.exe query $svc *>> $log

    $evtStart = (Get-Date).AddMinutes(-10)
    Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = $evtStart } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match "Service Control Manager|Kernel-PnP|Display" -or $_.Message -match $svc -or $_.Message -match "amdbc250" } |
        Select-Object TimeCreated, Id, ProviderName, Message -First 40 |
        Format-List * |
        Out-String -Width 4096 |
        Add-Content $log

    sc.exe stop $svc *>> $log
    sc.exe delete $svc *>> $log
    Remove-Item -LiteralPath $cPath -Force -ErrorAction SilentlyContinue

    L "M0_DONE=1"
}
finally {
    if (Test-Path $srcBak) {
        Copy-Item -LiteralPath $srcBak -Destination $src -Force
        Remove-Item -LiteralPath $srcBak -Force -ErrorAction SilentlyContinue
    }
    L "SOURCE_RESTORED=1"
}

Get-Content $log -Tail 320
