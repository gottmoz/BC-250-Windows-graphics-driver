# Install-Driver.ps1
# Installs the AMD BC-250 reference driver package.

param(
    [string]$DriverPath = ".\amdbc250.inf"
)

Write-Host "Starting AMD BC-250 driver installation..."

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$candidatePaths = @(
    $DriverPath,
    (Join-Path $scriptRoot "amdbc250.inf"),
    (Join-Path $scriptRoot "..\inf\amdbc250.inf")
)

$resolvedDriverPath = $null
foreach ($candidate in $candidatePaths) {
    if (Test-Path -LiteralPath $candidate) {
        $resolvedDriverPath = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}

if (-not $resolvedDriverPath) {
    Write-Error "INF file not found. Provide a valid path using -DriverPath."
    exit 1
}

$testSigningStatus = bcdedit /enum {current} | Select-String "testsigning"
if ($testSigningStatus -notlike "*Yes*") {
    Write-Warning "Test Signing is not enabled. Unsigned driver loading may fail."
    Write-Warning "Enable with: bcdedit /set testsigning on (then reboot)."
}

Write-Host "Adding driver package: $resolvedDriverPath"
pnputil /add-driver $resolvedDriverPath /install

if ($LASTEXITCODE -eq 0) {
    Write-Host "Driver installed successfully."
} else {
    Write-Error "Driver installation failed with code: $LASTEXITCODE"
}
