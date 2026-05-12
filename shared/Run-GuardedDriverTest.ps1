param(
    [int]$TimeoutSeconds = 60,
    [switch]$ForceRebootBind,
    [int]$RebootCountdownSeconds = 60,
    [switch]$AllowBaselineBypass,
    [switch]$NoRebootRecovery
)

$ErrorActionPreference = "Continue"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$logPath = Join-Path $repoRoot "guarded-test.log"
$venDevId = "PCI\VEN_1002&DEV_13FE"
$infPath = Join-Path $repoRoot "build\Release\x64\package\amdbc250.inf"
$devconPath = "C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Add-Content -Path $logPath -Value $line
    Write-Host $line
}

function Write-RecentDriverWatchdogEvidence {
    param([int]$LookbackMinutes = 20)

    $start = (Get-Date).AddMinutes(-1 * [Math]::Abs($LookbackMinutes))
    Write-Log "Collecting recent LiveKernel watchdog evidence since $($start.ToString('yyyy-MM-dd HH:mm:ss'))."
    try {
        Get-WinEvent -FilterHashtable @{ LogName = "Application"; StartTime = $start } -ErrorAction Stop |
            Where-Object {
                $_.ProviderName -eq "Windows Error Reporting" -and
                $_.Message -match "LiveKernelEvent" -and
                $_.Message -match "P1:\s*193"
            } |
            Select-Object TimeCreated, Id, ProviderName, Message |
            Format-List | Out-String -Width 4096 | Add-Content -Path $logPath
    } catch {
        Write-Log "WARNING: Failed to collect LiveKernel evidence: $($_.Exception.Message)"
    }
}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsElevated)) {
    Write-Log "Current process is not elevated. Relaunching guarded test as administrator."
    $argList = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", "`"$PSCommandPath`""
        "-TimeoutSeconds", $TimeoutSeconds
        "-RebootCountdownSeconds", $RebootCountdownSeconds
    )

    if ($ForceRebootBind) {
        $argList += "-ForceRebootBind"
    }
    if ($AllowBaselineBypass) {
        $argList += "-AllowBaselineBypass"
    }
    if ($NoRebootRecovery) {
        $argList += "-NoRebootRecovery"
    }

    try {
        $elevated = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList ($argList -join " ") -Wait -PassThru
        exit $elevated.ExitCode
    } catch {
        Write-Log "ERROR: Elevation required to install/update drivers. Relaunch failed: $($_.Exception.Message)"
        exit 740
    }
}

function Get-SigntoolPath {
    foreach ($candidate in @(
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe",
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe",
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22000.0\x64\signtool.exe",
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

function Test-DriverPackageSignature {
    param([string]$ResolvedInfPath)

    if (-not (Test-Path -LiteralPath $ResolvedInfPath)) {
        Write-Log "ERROR: Driver INF not found: $ResolvedInfPath"
        return $false
    }

    $packageDir = Split-Path -Parent $ResolvedInfPath
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($ResolvedInfPath)
    $catPath = Join-Path $packageDir "$baseName.cat"
    $sysPath = Join-Path $packageDir "amdbc250kmd.sys"

    if (-not (Test-Path -LiteralPath $catPath)) {
        Write-Log "ERROR: Catalog file missing: $catPath"
        return $false
    }
    if (-not (Test-Path -LiteralPath $sysPath)) {
        Write-Log "ERROR: Driver binary missing: $sysPath"
        return $false
    }

    $catSig = Get-AuthenticodeSignature -FilePath $catPath
    $sysSig = Get-AuthenticodeSignature -FilePath $sysPath
    Write-Log "Catalog signature status: $($catSig.Status)"
    Write-Log "Driver signature status: $($sysSig.Status)"

    if ($catSig.Status -ne "Valid" -or $sysSig.Status -ne "Valid") {
        Write-Log "ERROR: Signature gate failed (catalog or driver is not Valid)."
        return $false
    }

    $signtoolPath = Get-SigntoolPath
    if ($signtoolPath) {
        & $signtoolPath verify /kp /v $catPath *>> $logPath
        if ($LASTEXITCODE -ne 0) {
            Write-Log "WARNING: signtool /kp verification failed with exit code $LASTEXITCODE. Checking /pa for test-signing."
            & $signtoolPath verify /pa /v $catPath *>> $logPath
            if ($LASTEXITCODE -ne 0) {
                Write-Log "ERROR: signtool verification failed for both /kp and /pa."
                return $false
            }
            Write-Log "signtool /pa verification passed (test-signing path)."
        } else {
            Write-Log "signtool /kp verification passed."
        }
    } else {
        Write-Log "WARNING: signtool.exe not found; relied on Authenticode status only."
    }

    return $true
}

function Get-BC250Device {
    $device = Get-PnpDevice -Class Display -PresentOnly |
        Where-Object { $_.InstanceId -like "*VEN_1002&DEV_13FE*" } |
        Select-Object -First 1
    return $device
}

function Get-BC250StatusText {
    param([string]$InstanceId)
    if (-not $InstanceId) {
        return ""
    }
    return (pnputil /enum-devices /instanceid $InstanceId) -join "`n"
}

function Test-ExpectedSafeBasicDisplayState {
    param([string]$InstanceId)

    $statusText = Get-BC250StatusText -InstanceId $InstanceId
    if ($statusText -match "Driver Name:\s+display\.inf") {
        if ($statusText -match "Problem Code:\s+31" -and
            $statusText -match "Problem Status:\s+0xC01E0438") {
            return $true
        }
        if ($statusText -match "Problem Code:\s+43") {
            return $true
        }
    }

    return $false
}

function Ensure-BaselineDisplayReady {
    param([string]$InstanceId)

    $statusText = Get-BC250StatusText -InstanceId $InstanceId
    if ($statusText -match "Status:\s+Started") {
        Write-Log "Baseline display adapter is already Started."
        return $true
    }

    if (Test-ExpectedSafeBasicDisplayState -InstanceId $InstanceId) {
        Write-Log "Baseline is expected safe state: display.inf with CM_PROB_FAILED_ADD / STATUS_GRAPHICS_NOT_POST_DEVICE_DRIVER."
        return $true
    }

    Write-Log "Baseline display adapter is not Started. Attempting baseline recovery before bind."
    $recoverScript = Join-Path $repoRoot "Recover-DisplayBaseline.ps1"
    if (-not (Test-Path -LiteralPath $recoverScript)) {
        Write-Log "ERROR: Recovery script missing: $recoverScript"
        return $false
    }

    powershell -NoProfile -ExecutionPolicy Bypass -File $recoverScript *>> $logPath
    Start-Sleep -Seconds 2

    $statusText = Get-BC250StatusText -InstanceId $InstanceId
    if ($statusText -match "Status:\s+Started") {
        Write-Log "Baseline recovery succeeded. Adapter reports Started."
        return $true
    }

    Write-Log "ERROR: Baseline recovery did not reach Started state. Aborting this bind attempt."
    pnputil /enum-devices /instanceid $InstanceId /drivers *>> $logPath
    return $false
}

function Remove-LegacyBc250State {
    Write-Log "Cleaning legacy BC250 driver state before bind."

    $driverEnum = pnputil /enum-drivers
    $publishedName = $null
    $bc250Published = @()

    foreach ($line in $driverEnum) {
        if ($line -match '^\s*Published Name:\s*(\S+)\s*$') {
            $publishedName = $Matches[1]
            continue
        }
        if ($line -match '^\s*Original Name:\s*(\S+)\s*$') {
            $originalName = $Matches[1]
            if ($originalName -ieq 'amdbc250.inf' -and $publishedName) {
                $bc250Published += $publishedName
            }
            continue
        }
    }

    $bc250Published = $bc250Published | Select-Object -Unique
    foreach ($pub in $bc250Published) {
        Write-Log "Removing stale package: $pub"
        pnputil /delete-driver $pub /uninstall /force *>> $logPath
    }

    sc.exe stop amdbc250kmd *>> $logPath
    sc.exe delete amdbc250kmd *>> $logPath
}

function Invoke-NoRebootFallback {
    param(
        [string]$InstanceId,
        [string]$HardwareId
    )

    Write-Log "No-reboot fallback: forcing display.inf bind and restart."
    & $devconPath update C:\Windows\INF\display.inf $HardwareId *>> $logPath
    Write-Log "No-reboot fallback devcon exit code: $LASTEXITCODE"

    pnputil /scan-devices *>> $logPath
    Write-Log "No-reboot fallback scan exit code: $LASTEXITCODE"

    if ($InstanceId) {
        pnputil /restart-device $InstanceId *>> $logPath
        Write-Log "No-reboot fallback restart exit code: $LASTEXITCODE"
    }

    Start-Sleep -Seconds 2
    if ($InstanceId) {
        pnputil /enum-devices /instanceid $InstanceId /drivers *>> $logPath
        $status = (pnputil /enum-devices /instanceid $InstanceId) -join "`n"
        if ($status -match "Status:\s+Started") {
            return $true
        }
        if (Test-ExpectedSafeBasicDisplayState -InstanceId $InstanceId) {
            Write-Log "No-reboot fallback reached expected safe BasicDisplay non-POST state."
            return $true
        }
        return $false
    }
    return $false
}

function Write-PreFallbackDebug {
    param(
        [string]$InstanceId,
        [string]$ServiceName
    )

    Write-Log "PRE-FALLBACK DEBUG: begin"
    "=== pre-fallback pnputil device ===" *>> $logPath
    pnputil /enum-devices /instanceid $InstanceId /drivers *>> $logPath
    "=== pre-fallback pnp properties ===" *>> $logPath
    Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName `
        DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_Service,DEVPKEY_Device_ProblemCode,DEVPKEY_Device_ProblemStatus `
        -ErrorAction SilentlyContinue | Select-Object KeyName,Data | Format-Table -AutoSize *>> $logPath
    "=== pre-fallback service query ===" *>> $logPath
    if ($ServiceName) {
        sc.exe query $ServiceName *>> $logPath
        sc.exe qc $ServiceName *>> $logPath
    }
    "=== pre-fallback recent system events XML ===" *>> $logPath
    $eventStart = (Get-Date).AddMinutes(-5)
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$eventStart} -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match 'Kernel-PnP|Service Control Manager|Display|DxgKrnl|CodeIntegrity' -or $_.Message -match 'amdbc250|BC-250|VEN_1002|display|graphics|failed to load' } |
        Select-Object -Last 20 |
        ForEach-Object { $_.ToXml() } *>> $logPath
    foreach ($ciLog in @('Microsoft-Windows-CodeIntegrity/Operational','Microsoft-Windows-Kernel-PnP/Configuration')) {
        "=== pre-fallback recent $ciLog ===" *>> $logPath
        Get-WinEvent -FilterHashtable @{LogName=$ciLog; StartTime=$eventStart} -ErrorAction SilentlyContinue |
            Select-Object -Last 16 |
            ForEach-Object { $_.ToXml() } *>> $logPath
    }
    Write-Log "PRE-FALLBACK DEBUG: end"
}

function Confirm-RebootBind {
    param(
        [int]$CountdownSeconds = 60,
        [switch]$RebootMode
    )

    if ($CountdownSeconds -lt 5) {
        $CountdownSeconds = 5
    }

    Write-Host ""
    if ($RebootMode) {
        Write-Host "Reboot bind requested."
        Write-Log "Reboot bind confirmation started (countdown ${CountdownSeconds}s)."
    } else {
        Write-Host "Guarded BC250 bind requested."
        Write-Log "Guarded bind confirmation started (countdown ${CountdownSeconds}s)."
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        if ($RebootMode) {
            $message = "BC250 test will continue with reboot-bind in $CountdownSeconds seconds.`n`nIf screen goes black, try Win+Ctrl+Shift+B to reset graphics.`n`nClick Cancel to abort this test run."
            $title = "BC250 Reboot Countdown"
        } else {
            $message = "BC250 guarded bind starts in $CountdownSeconds seconds.`n`nIf screen goes black, try Win+Ctrl+Shift+B to reset graphics.`n`nClick Cancel to abort this test run."
            $title = "BC250 Test Countdown"
        }
        $buttons = 1 + 48 + 4096  # OK/Cancel + Warning icon + System modal
        $popupResult = $shell.Popup($message, $CountdownSeconds, $title, $buttons)
        if ($popupResult -eq 2) {
            Write-Host "Test canceled from desktop dialog."
            Write-Log "Guarded bind canceled by desktop dialog."
            return $false
        }
        Write-Host "Countdown completed (or OK selected). Proceeding with driver bind."
        Write-Log "Guarded bind confirmed by dialog timeout/OK."
        return $true
    } catch {
    Write-Host "Desktop popup unavailable. Falling back to terminal countdown."
    Write-Log "Desktop popup unavailable; using terminal countdown fallback."
    }

    $supportsKeyboard = $true
    try {
        $null = [Console]::KeyAvailable
    } catch {
        $supportsKeyboard = $false
    }

    for ($remaining = $CountdownSeconds; $remaining -ge 1; $remaining--) {
        if ($supportsKeyboard) {
            try {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -in @("S", "Escape", "C", "X")) {
                        Write-Host "Test canceled by user input."
                        Write-Log "Guarded bind canceled via keyboard input."
                        return $false
                    }
                }
            } catch {
                $supportsKeyboard = $false
            }
        }
        if ($RebootMode) {
            Write-Host ("Reboot-bind in {0}s... press S to cancel test." -f $remaining)
        } else {
            Write-Host ("Driver bind starts in {0}s... press S to cancel test." -f $remaining)
        }
        Start-Sleep -Seconds 1
    }

    return $true
}

if (-not (Test-Path -LiteralPath $devconPath)) {
    Write-Log "ERROR: devcon.exe not found at $devconPath"
    exit 1
}

Write-Log "Starting guarded driver test."
Write-Log "Recovery tip: if screen turns black, try Win+Ctrl+Shift+B to reset graphics."
if ($NoRebootRecovery -and $ForceRebootBind) {
    Write-Log "WARNING: -NoRebootRecovery is set; ignoring reboot bind and using non-reboot devcon update."
}
cmd.exe /c "shutdown /a >nul 2>&1"
Write-Log "Signature gate check for package: $infPath"
if (-not (Test-DriverPackageSignature -ResolvedInfPath $infPath)) {
    Write-Log "Aborting test before driver bind."
    exit 3
}

$device = Get-BC250Device
if (-not $device) {
    Write-Log "ERROR: Could not locate BC250 display device (VEN_1002&DEV_13FE)."
    exit 4
}
$instanceId = $device.InstanceId
$hwId = $venDevId

Write-Log "Target instance: $instanceId"
$baselineReady = Ensure-BaselineDisplayReady -InstanceId $instanceId
if (-not $baselineReady) {
    if ($AllowBaselineBypass) {
        Write-Log "WARNING: Baseline display not Started. Continuing due to -AllowBaselineBypass."
    } else {
        exit 6
    }
}

Remove-LegacyBc250State
$watchdogArmed = $false
if ($NoRebootRecovery) {
    Write-Log "No-reboot mode enabled: rollback watchdog will not be armed."
} else {
Write-Log "Arming rollback watchdog for $TimeoutSeconds seconds."
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "Arm-DriverRollbackWatchdog.ps1") -TimeoutSeconds $TimeoutSeconds -DeviceMatch $hwId -RebootCountdownSeconds $RebootCountdownSeconds -AllowAutoRebootAfterFallback *>> $logPath
if ($LASTEXITCODE -ne 0) {
        Write-Log "ERROR: Failed to arm rollback watchdog (exit $LASTEXITCODE). Aborting before bind."
        exit 5
    }
    $watchdogArmed = $true
}

$shouldProceed = Confirm-RebootBind -CountdownSeconds $RebootCountdownSeconds -RebootMode:$ForceRebootBind
if (-not $shouldProceed) {
    if ($watchdogArmed) {
        Write-Log "Guarded bind cancelled before driver update. Cancelling rollback watchdog."
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "Cancel-DriverRollbackWatchdog.ps1") *>> $logPath
    } else {
        Write-Log "Guarded bind cancelled before driver update."
    }
    exit 0
}
$useRebootBind = [bool]$ForceRebootBind -and (-not $NoRebootRecovery)

$devconArgs = @("update", $infPath, $hwId)
if ($useRebootBind) {
    $devconArgs = @("/r", "update", $infPath, $hwId)
}

Write-Log "Applying BC250 driver with devcon: $($devconArgs -join ' ')"
& $devconPath @devconArgs *>> $logPath
$devconExit = $LASTEXITCODE
Write-Log "devcon exit code: $devconExit"

Start-Sleep -Seconds 20

$deviceAfter = Get-BC250Device
if ($deviceAfter) {
    $instanceId = $deviceAfter.InstanceId
}

Write-Log "Collecting device status for $instanceId"
pnputil /enum-devices /instanceid $instanceId /drivers *>> $logPath
$statusText = (pnputil /enum-devices /instanceid $instanceId) -join "`n"

if ($statusText -match "Status:\s+Started") {
    if ($watchdogArmed) {
        Write-Log "Device reports Started. Cancelling rollback watchdog."
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "Cancel-DriverRollbackWatchdog.ps1") *>> $logPath
    } else {
        Write-Log "Device reports Started."
    }
} else {
    if ($watchdogArmed) {
        Write-Log "Device not in Started state. Watchdog remains armed for rollback and emergency reboot recovery."
    } else {
        Write-Log "Device not in Started state. Running immediate no-reboot fallback."
        $activeService = $null
        try {
            $activeService = (Get-PnpDeviceProperty -InstanceId $instanceId -KeyName DEVPKEY_Device_Service -ErrorAction SilentlyContinue).Data
        } catch {
            $activeService = $null
        }
        Write-PreFallbackDebug -InstanceId $instanceId -ServiceName $activeService
        $fallbackStarted = Invoke-NoRebootFallback -InstanceId $instanceId -HardwareId $hwId
        if ($fallbackStarted) {
            Write-Log "No-reboot fallback recovered device to Started."
        } else {
            Write-Log "No-reboot fallback did not recover device to Started."
        }
    }
}

Write-RecentDriverWatchdogEvidence -LookbackMinutes 30
Write-Log "Guarded driver test complete."
$finalStatusText = (pnputil /enum-devices /instanceid $instanceId) -join "`n"
if ($finalStatusText -match "Status:\s+Started") {
    exit $devconExit
}
if ($devconExit -eq 0) {
    exit 7
}
exit $devconExit
