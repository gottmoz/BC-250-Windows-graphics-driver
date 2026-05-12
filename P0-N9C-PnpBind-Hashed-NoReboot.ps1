param(
    [string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest",
    [string]$N9Dir = "",
    [string]$N9SysName = "N9C_ENTRYONLY_DXGK_MIN.sys"
)

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("p0_n9c_pnp_bind_hashed_{0}.log" -f $ts)
$work = Join-Path $ProjectRoot ("p0_pkg_{0}" -f $ts)
New-Item -ItemType Directory -Path $work -Force | Out-Null

function L([string]$m) {
    ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) | Tee-Object -FilePath $log -Append
}

function HashSafe([string]$p) {
    if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash }
    return "MISSING"
}

function Read-BcParams([string]$serviceName) {
    if ([string]::IsNullOrWhiteSpace($serviceName)) { return }
    $paramsPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName\Parameters"
    if (-not (Test-Path $paramsPath)) {
        L ("PARAM_PATH_MISSING={0}" -f $paramsPath)
        return
    }
    try {
        $p = Get-ItemProperty -Path $paramsPath -ErrorAction Stop
        $props = $p.PSObject.Properties |
            Where-Object {
                $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' -and
                ($_.Name -like 'Bc250*' -or $_.Name -like 'Abi*' -or $_.Name -like 'Sample*')
            } |
            Sort-Object Name
        foreach ($prop in $props) {
            $n = $prop.Name
            $v = $prop.Value
            if ($v -is [int] -or $v -is [uint32] -or $v -is [long]) {
                L ("PARAM_{0}=0x{1:X8}" -f $n, ([uint32]$v))
            }
            else {
                L ("PARAM_{0}={1}" -f $n, $v)
            }
        }
    }
    catch {
        L ("PARAM_READ_ERR={0}" -f $_.Exception.Message)
    }
}

function Find-LatestDir([string]$base, [string]$pattern) {
    $d = Get-ChildItem -Path $base -Directory -Filter $pattern -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -ne $d) { return $d.FullName }
    return ""
}

function Find-Tool([string[]]$patterns) {
    foreach ($pat in $patterns) {
        $tool = Get-ChildItem -Path $pat -File -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($null -ne $tool) { return $tool.FullName }
    }
    return ""
}

L "LOG=$log"
L "NO_REBOOT=1"

if ([string]::IsNullOrWhiteSpace($N9Dir)) {
    $N9Dir = Find-LatestDir -base $ProjectRoot -pattern "n9_entryonly_*"
}
if ([string]::IsNullOrWhiteSpace($N9Dir)) {
    L "ERR_N9_DIR_NOT_FOUND=1"
    exit 2
}

$n9Sys = Join-Path $N9Dir $N9SysName
$infSrc = Join-Path $ProjectRoot "amdbc250.inf"
$umdSrc = Join-Path $ProjectRoot "amdbc250umd.dll"

if (-not (Test-Path $n9Sys)) {
    L ("ERR_N9_SYS_NOT_FOUND={0}" -f $n9Sys)
    exit 3
}
if (-not (Test-Path $infSrc)) {
    L ("ERR_INF_NOT_FOUND={0}" -f $infSrc)
    exit 4
}

$infDst = Join-Path $work "amdbc250.inf"
$sysDst = Join-Path $work "amdbc250kmd.sys"
$umdDst = Join-Path $work "amdbc250umd.dll"

Copy-Item -LiteralPath $infSrc -Destination $infDst -Force
Copy-Item -LiteralPath $n9Sys -Destination $sysDst -Force

$driverVerDate = Get-Date -Format "MM/dd/yyyy"
$driverVerTime = Get-Date -Format "HH.mm.ss"
$infText = Get-Content -LiteralPath $infDst -Raw
$infText = [Regex]::Replace($infText, '(?im)^DriverVer\s*=.*$', ("DriverVer={0},{1}" -f $driverVerDate, $driverVerTime))
Set-Content -LiteralPath $infDst -Value $infText -Encoding ASCII
L ("INF_DRIVERVER={0},{1}" -f $driverVerDate, $driverVerTime)
if (-not (Test-Path $umdSrc)) {
    $foundUmd = Get-ChildItem -Path $ProjectRoot -Recurse -Filter "amdbc250umd.dll" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($foundUmd) { $umdSrc = $foundUmd.FullName }
}

if (Test-Path $umdSrc) {
    Copy-Item -LiteralPath $umdSrc -Destination $umdDst -Force
    L ("UMD_COPIED=1|UMD_SRC={0}" -f $umdSrc)
}
else {
    L "UMD_MISSING=1"
}

$certPfx = "C:\bc250new.pfx"
$certPass = "bc250"

$inf2cat = Find-Tool -patterns @(
    "C:\Program Files (x86)\Windows Kits\10\bin\*\x86\Inf2Cat.exe",
    "C:\Program Files (x86)\Windows Kits\10\bin\*\x86\inf2cat.exe",
    "C:\Program Files (x86)\Windows Kits\10\bin\x86\Inf2Cat.exe",
    "C:\Program Files (x86)\Windows Kits\10\bin\x86\inf2cat.exe",
    "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\Inf2Cat.exe",
    "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\inf2cat.exe"
)
$signtool = Find-Tool -patterns @(
    "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe"
)

L ("TOOL_INF2CAT={0}" -f $inf2cat)
L ("TOOL_SIGNTOOL={0}" -f $signtool)

if ([string]::IsNullOrWhiteSpace($inf2cat) -or -not (Test-Path $inf2cat)) {
    L "ERR_INF2CAT_NOT_FOUND=1"
    exit 5
}
if ([string]::IsNullOrWhiteSpace($signtool) -or -not (Test-Path $signtool)) {
    L "ERR_SIGNTOOL_NOT_FOUND=1"
    exit 6
}
if (-not (Test-Path $certPfx)) {
    L ("ERR_CERT_NOT_FOUND={0}" -f $certPfx)
    exit 7
}

$hashA = HashSafe $n9Sys
$hashBPre = HashSafe $sysDst
L ("A_SRC={0}" -f $n9Sys)
L ("A_HASH={0}" -f $hashA)
L ("B_PRE_PATH={0}" -f $sysDst)
L ("B_PRE_HASH={0}" -f $hashBPre)
L ("A_EQ_B_PRE={0}" -f ($hashA -eq $hashBPre))

& $inf2cat /driver:$work /os:10_RS5_X64,10_19H1_X64,10_20H1_X64 *>> $log
L ("INF2CAT_EXIT={0}" -f $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) {
    & $inf2cat /driver:$work /os:10_X64 *>> $log
    L ("INF2CAT_FALLBACK_EXIT={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) {
        L "ERR_INF2CAT_FAILED=1"
        exit 8
    }
}

$cat = Join-Path $work "amdbc250.cat"
if (-not (Test-Path $cat)) {
    $cat = Get-ChildItem -Path $work -Filter "*.cat" -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $cat) {
    L "ERR_CAT_NOT_FOUND=1"
    exit 9
}

& $signtool sign /fd sha256 /f $certPfx /p $certPass $sysDst *>> $log
L ("SIGN_SYS_EXIT={0}" -f $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { exit 10 }

& $signtool sign /fd sha256 /f $certPfx /p $certPass $cat *>> $log
L ("SIGN_CAT_EXIT={0}" -f $LASTEXITCODE)
if ($LASTEXITCODE -ne 0) { exit 11 }

$hashB = HashSafe $sysDst
L ("B_POST_HASH={0}" -f $hashB)

$startTime = Get-Date
$instance = (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\VEN_1002&DEV_13FE*' } | Select-Object -First 1)
$serviceName = "amdbc250kmd"
if ($instance) {
    L ("INSTANCE_ID={0}" -f $instance.InstanceId)
    L ("INSTANCE_STATUS_PRE={0}" -f $instance.Status)
    $servicePre = Get-PnpDeviceProperty -InstanceId $instance.InstanceId -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue
    if ($servicePre -and -not [string]::IsNullOrWhiteSpace($servicePre.Data)) {
        $serviceName = [string]$servicePre.Data
    }
    L ("SERVICE_PRE={0}" -f $serviceName)
}
else {
    L "INSTANCE_NOT_FOUND_PRE=1"
}

# Remove stale breadcrumbs so each run reads fresh DriverEntry writes.
$paramsPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName\Parameters"
try {
    if (Test-Path $paramsPath) {
        Remove-Item -Path $paramsPath -Recurse -Force -ErrorAction Stop
        L ("PARAM_PATH_CLEARED={0}" -f $paramsPath)
    }
}
catch {
    L ("PARAM_CLEAR_ERR={0}" -f $_.Exception.Message)
}

pnputil /add-driver "$infDst" /install *>> $log
$pnpexit = $LASTEXITCODE
L ("PNPUTIL_EXIT={0}" -f $pnpexit)

Start-Sleep -Seconds 4

if ($instance) {
    pnputil /enum-devices /instanceid "$($instance.InstanceId)" /drivers *>> $log
    $problemCode = Get-PnpDeviceProperty -InstanceId $instance.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue
    $problemStatus = Get-PnpDeviceProperty -InstanceId $instance.InstanceId -KeyName 'DEVPKEY_Device_ProblemStatus' -ErrorAction SilentlyContinue
    $service = Get-PnpDeviceProperty -InstanceId $instance.InstanceId -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue
    if ($problemCode) { L ("PROBLEM_CODE={0}" -f $problemCode.Data) }
    if ($problemStatus) { L ("PROBLEM_STATUS=0x{0:X8}" -f ([uint32]$problemStatus.Data)) }
    if ($service -and -not [string]::IsNullOrWhiteSpace($service.Data)) {
        $serviceName = [string]$service.Data
        L ("SERVICE={0}" -f $serviceName)
    }
}

Read-BcParams -serviceName $serviceName

$fr = Get-ChildItem -Path "$env:windir\System32\DriverStore\FileRepository" -Directory -Filter "amdbc250.inf_*" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($fr) {
    $cSys = Join-Path $fr.FullName "amdbc250kmd.sys"
    $hashC = HashSafe $cSys
    L ("C_PATH={0}" -f $cSys)
    L ("C_HASH={0}" -f $hashC)
    L ("A_EQ_C={0}" -f ($hashA -eq $hashC))
    L ("B_EQ_C={0}" -f ($hashB -eq $hashC))
}
else {
    L "C_PATH_NOT_FOUND=1"
}

Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $startTime.AddMinutes(-1) } -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProviderName -match 'Kernel-PnP|Service Control Manager|Display' -or
        $_.Id -in 219,411,400,410,7000,7001
    } |
    Select-Object -First 80 TimeCreated, Id, ProviderName, Message |
    Format-List * |
    Out-String -Width 4096 |
    Add-Content $log

L "P0_DONE=1"
Get-Content -Path $log -Tail 220
