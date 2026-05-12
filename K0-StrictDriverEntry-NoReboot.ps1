param(
    [string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest"
)

$ErrorActionPreference = "Continue"
$PackageDir = Join-Path $ProjectRoot "build\Release\x64\package"
$ObjDir = Join-Path $ProjectRoot "build\Release\x64\amdbc250kmd"
$Log = Join-Path $ProjectRoot ("k0_strict_driverentry_noreboot_{0}.log" -f (Get-Date -Format yyyyMMdd_HHmmss))

function Write-K0Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $Message
    Write-Host $line
    Add-Content -Path $Log -Value $line
}

function Get-Bc250InstanceId {
    $device = Get-PnpDevice -Class Display |
        Where-Object { $_.InstanceId -like "*VEN_1002&DEV_13FE*" } |
        Select-Object -First 1
    if ($device) { return $device.InstanceId }
    return $null
}

function Dump-Bc250Device {
    param([string]$Tag)
    Write-K0Log $Tag
    $instanceId = Get-Bc250InstanceId
    if ($instanceId) {
        pnputil /enum-devices /instanceid $instanceId /drivers *>> $Log
    }
    return $instanceId
}

function Remove-Bc250Packages {
    $driverEnum = pnputil /enum-drivers
    $publishedName = $null
    $packages = @()

    foreach ($line in $driverEnum) {
        if ($line -match '^\s*Published Name\s*:\s*(oem\d+\.inf)') {
            $publishedName = $Matches[1]
            continue
        }
        if ($line -match '^\s*Original Name\s*:\s*amdbc250\.inf' -and $publishedName) {
            $packages += $publishedName
        }
    }

    $packages | Select-Object -Unique | ForEach-Object {
        Write-K0Log "Delete package $_"
        pnputil /delete-driver $_ /uninstall /force *>> $Log
    }
}

Set-Location $ProjectRoot
Write-K0Log "LOG=$Log"
Write-K0Log "NO_REBOOT=1"

Write-K0Log "Source marker check"
Select-String -Path (Join-Path $ProjectRoot "amdbc250_kmd.c") `
    -Pattern "AMDBC250_K0_STRICT_DRIVERENTRY|AMDBC250_BUILD_MARKER|AMDBC250_UMA_FLAGS_PROFILE|AMDBC250_REPORTED_VRAM_MB_OVERRIDE" |
    ForEach-Object { $_.Line } | Tee-Object -FilePath $Log -Append

Remove-Item -Recurse -Force $ObjDir -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $PackageDir "amdbc250kmd.sys"), (Join-Path $PackageDir "amdbc250.cat") -ErrorAction SilentlyContinue

$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
Write-K0Log "Build KMD clean"
& $msbuild (Join-Path $ProjectRoot "amdbc250kmd.vcxproj") /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $Log
Write-K0Log "KMD_EXIT=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) {
    Get-Content $Log -Tail 160
    exit 1
}

Write-K0Log "Build UMD"
& $msbuild (Join-Path $ProjectRoot "amdbc250umd.vcxproj") /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $Log
Write-K0Log "UMD_EXIT=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) {
    Get-Content $Log -Tail 160
    exit 2
}

$vsDevCmd = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
$envOutput = cmd /c "`"$vsDevCmd`" -arch=x64 & set" 2>&1
$envOutput | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*=' } | ForEach-Object {
    $parts = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($parts[0], $parts[1], 'Process')
}

$objects = @(
    (Join-Path $ObjDir "amdbc250_kmd.obj"),
    (Join-Path $ObjDir "amdbc250_hw_init.obj"),
    (Join-Path $ObjDir "amdbc250_fw_loader.obj")
) | Where-Object { Test-Path $_ }

$libPath = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64"
Write-K0Log "Explicit link"
& link.exe /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE `
    "/out:$(Join-Path $PackageDir "amdbc250kmd.sys")" "/LIBPATH:$libPath" `
    $objects ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib *>> $Log
Write-K0Log "LINK_EXIT=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $PackageDir "amdbc250kmd.sys"))) {
    Get-Content $Log -Tail 160
    exit 3
}

Copy-Item (Join-Path $ProjectRoot "build\Release\x64\amdbc250umd.dll") (Join-Path $PackageDir "amdbc250umd.dll") -Force
Copy-Item (Join-Path $ProjectRoot "amdbc250.inf") (Join-Path $PackageDir "amdbc250.inf") -Force

Write-K0Log "Binary marker check"
$bytes = [IO.File]::ReadAllBytes((Join-Path $PackageDir "amdbc250kmd.sys"))
$ascii = [Text.Encoding]::ASCII.GetString($bytes)
$markerPresent = $ascii.Contains("K0_STRICT_DRIVERENTRY_REVALIDATE_20260508_1648")
Write-K0Log "MARKER_PRESENT=$markerPresent"
if (-not $markerPresent) {
    Get-Content $Log -Tail 160
    exit 10
}

$hash = (Get-FileHash (Join-Path $PackageDir "amdbc250kmd.sys") -Algorithm SHA256).Hash
Write-K0Log "SYS_HASH=$hash"

$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
$inf2cat = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x86\inf2cat.exe"
Remove-Item (Join-Path $PackageDir "amdbc250.cat") -ErrorAction SilentlyContinue
& $inf2cat /driver:$PackageDir /os:10_X64 *>> $Log
Write-K0Log "INF2CAT_EXIT=$LASTEXITCODE"
& $signtool sign /fd sha256 /f C:\bc250new.pfx /p bc250 (Join-Path $PackageDir "amdbc250kmd.sys") *>> $Log
Write-K0Log "SIGN_SYS_EXIT=$LASTEXITCODE"
& $signtool sign /fd sha256 /f C:\bc250new.pfx /p bc250 (Join-Path $PackageDir "amdbc250.cat") *>> $Log
Write-K0Log "SIGN_CAT_EXIT=$LASTEXITCODE"
& $signtool verify /pa /v (Join-Path $PackageDir "amdbc250.cat") *>> $Log
Write-K0Log "VERIFY_CAT_EXIT=$LASTEXITCODE"

Get-Item (Join-Path $PackageDir "amdbc250kmd.sys"), (Join-Path $PackageDir "amdbc250.cat"), (Join-Path $PackageDir "amdbc250.inf") |
    ForEach-Object { "PKG|$($_.Name)|$($_.Length)|$($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" } |
    Tee-Object -FilePath $Log -Append

$instanceId = Dump-Bc250Device "Pre-install"
Remove-Bc250Packages

Write-K0Log "Install no-reboot K0"
pnputil /add-driver (Join-Path $PackageDir "amdbc250.inf") /install *>> $Log
Write-K0Log "PNPUTIL_INSTALL_EXIT=$LASTEXITCODE"
Start-Sleep -Seconds 3

$instanceId = Dump-Bc250Device "Post-install"
if ($instanceId) {
    pnputil /restart-device $instanceId *>> $Log
    Write-K0Log "RESTART_EXIT=$LASTEXITCODE"
}
Start-Sleep -Seconds 15

$instanceId = Dump-Bc250Device "Post-restart"
Write-K0Log "Service check"
sc.exe qc amdbc250kmd *>> $Log
sc.exe query amdbc250kmd *>> $Log

Write-K0Log "Recent events"
Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = (Get-Date).AddMinutes(-10) } -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match "Kernel-PnP|Service Control Manager|Display" -or $_.Message -match "amdbc250|13FE" } |
    Select-Object TimeCreated, Id, ProviderName, Message -First 35 |
    Format-List * |
    Out-String -Width 4096 |
    Add-Content $Log

Write-K0Log "Rollback to BasicDisplay"
Remove-Bc250Packages
pnputil /scan-devices *>> $Log
if ($instanceId) {
    pnputil /restart-device $instanceId *>> $Log
}
Dump-Bc250Device "Final" | Out-Null

Get-Content $Log -Tail 220
