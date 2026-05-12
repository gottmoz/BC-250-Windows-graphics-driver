<# 
BC-250 Windows Graphics Driver log collector

Usage:
  Open PowerShell as Administrator.
  Run:
    Set-ExecutionPolicy -Scope Process Bypass
    .\collect-bc250-logs.ps1 -TestStage T2 -Commit abcdef1 -Result code43

Output:
  Creates a zip file on the Desktop with system, driver, PnP, DxDiag, and Event Viewer logs.

Notes:
  This script does not modify drivers.
#>

param(
    [string]$TestStage = "unknown",
    [string]$Commit = "unknown",
    [string]$Result = "unknown",
    [string]$OutputRoot = "$env:USERPROFILE\Desktop"
)

$ErrorActionPreference = "Continue"

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$safeCommit = ($Commit -replace '[^a-zA-Z0-9._-]', '_')
$safeStage = ($TestStage -replace '[^a-zA-Z0-9._-]', '_')
$safeResult = ($Result -replace '[^a-zA-Z0-9._-]', '_')

$outDir = Join-Path $OutputRoot "BC250Logs_${timestamp}_${safeCommit}_${safeStage}_${safeResult}"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

function Run-Cmd {
    param(
        [string]$Name,
        [scriptblock]$Command
    )
    $path = Join-Path $outDir $Name
    try {
        & $Command | Out-File -FilePath $path -Encoding utf8 -Width 300
    } catch {
        "ERROR: $($_.Exception.Message)" | Out-File -FilePath $path -Encoding utf8
    }
}

"BC-250 Windows Graphics Driver Log Bundle" | Out-File (Join-Path $outDir "README.txt") -Encoding utf8
"Timestamp: $timestamp" | Out-File (Join-Path $outDir "README.txt") -Encoding utf8 -Append
"Commit: $Commit" | Out-File (Join-Path $outDir "README.txt") -Encoding utf8 -Append
"TestStage: $TestStage" | Out-File (Join-Path $outDir "README.txt") -Encoding utf8 -Append
"Result: $Result" | Out-File (Join-Path $outDir "README.txt") -Encoding utf8 -Append

Run-Cmd "systeminfo.txt" { systeminfo }
Run-Cmd "computerinfo.txt" { Get-ComputerInfo }
Run-Cmd "pnp-display.txt" { Get-PnpDevice -Class Display | Format-List * }
Run-Cmd "pnp-all-problem-devices.txt" { Get-PnpDevice | Where-Object { $_.Status -ne "OK" } | Format-List * }
Run-Cmd "video-controller.txt" { Get-CimInstance Win32_VideoController | Format-List * }
Run-Cmd "pnputil-display-devices.txt" { pnputil /enum-devices /class Display }
Run-Cmd "pnputil-drivers.txt" { pnputil /enum-drivers }
Run-Cmd "driverquery.txt" { driverquery /v }
Run-Cmd "bcdedit.txt" { bcdedit /enum all }

try {
    dxdiag /t (Join-Path $outDir "dxdiag.txt")
} catch {
    "ERROR running dxdiag: $($_.Exception.Message)" | Out-File (Join-Path $outDir "dxdiag-error.txt") -Encoding utf8
}

try {
    Copy-Item "C:\Windows\INF\setupapi.dev.log" (Join-Path $outDir "setupapi.dev.log") -Force
} catch {
    "ERROR copying setupapi.dev.log: $($_.Exception.Message)" | Out-File (Join-Path $outDir "setupapi-copy-error.txt") -Encoding utf8
}

$logs = @(
    @{ Name = "System"; File = "System.evtx" },
    @{ Name = "Application"; File = "Application.evtx" },
    @{ Name = "Microsoft-Windows-Kernel-PnP/Configuration"; File = "Kernel-PnP-Configuration.evtx" },
    @{ Name = "Microsoft-Windows-DriverFrameworks-UserMode/Operational"; File = "DriverFrameworks-UserMode-Operational.evtx" }
)

foreach ($log in $logs) {
    try {
        wevtutil epl $log.Name (Join-Path $outDir $log.File)
    } catch {
        "ERROR exporting $($log.Name): $($_.Exception.Message)" | Out-File (Join-Path $outDir "$($log.File).error.txt") -Encoding utf8
    }
}

Run-Cmd "recent-system-driver-events.txt" {
    Get-WinEvent -LogName System -MaxEvents 300 |
        Where-Object {
            $_.ProviderName -match "Kernel-PnP|Display|amdkmdag|amdwddmg|dxgkrnl|WHEA|BugCheck|Service Control Manager"
        } |
        Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
        Format-List *
}

Run-Cmd "recent-application-events.txt" {
    Get-WinEvent -LogName Application -MaxEvents 200 |
        Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
        Format-List *
}

$zipPath = "$outDir.zip"
try {
    Compress-Archive -Path $outDir -DestinationPath $zipPath -Force
    Write-Host "Created log bundle: $zipPath"
} catch {
    Write-Host "Failed to create zip: $($_.Exception.Message)"
    Write-Host "Logs are still available at: $outDir"
}
