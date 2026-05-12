# Uninstall-Driver.ps1
# Uninstalls the AMD BC-250 reference driver package.

param(
    [string]$DriverInfName = "amdbc250.inf"
)

Write-Host "Starting AMD BC-250 driver removal..."

Write-Host "Removing driver package: $DriverInfName"
pnputil /delete-driver $DriverInfName /uninstall /force

if ($LASTEXITCODE -eq 0) {
    Write-Host "Driver removed successfully."
    exit 0
}

Write-Warning "Direct removal failed (code $LASTEXITCODE). Trying published OEM package..."

$publishedInf = $null
$enumLines = pnputil /enum-drivers
for ($i = 0; $i -lt $enumLines.Count; $i++) {
    if ($enumLines[$i] -match "Original Name\\s*:\\s*$([Regex]::Escape($DriverInfName))") {
        for ($j = [Math]::Max(0, $i - 6); $j -le $i; $j++) {
            if ($enumLines[$j] -match "Published Name\\s*:\\s*(oem\\d+\\.inf)") {
                $publishedInf = $Matches[1]
                break
            }
        }
    }
    if ($publishedInf) { break }
}

if (-not $publishedInf) {
    Write-Error "Could not find a published OEM INF mapped to $DriverInfName."
    exit 1
}

Write-Host "Removing published package: $publishedInf"
pnputil /delete-driver $publishedInf /uninstall /force

if ($LASTEXITCODE -eq 0) {
    Write-Host "Driver removed successfully."
} else {
    Write-Error "Driver removal failed with code: $LASTEXITCODE"
}
