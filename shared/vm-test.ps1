param(
    [Parameter(Mandatory = $true)][string]$InfPath,
    [string]$HardwareId = "PCI\\VEN_1002&DEV_13FE"
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$m) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $m"
}

if (-not (Test-Path -LiteralPath $InfPath)) {
    throw "INF not found: $InfPath"
}

Write-Step "Staging package with pnputil."
pnputil /add-driver $InfPath /install
if ($LASTEXITCODE -ne 0) {
    throw "pnputil failed with $LASTEXITCODE"
}

Write-Step "Enumerating target hardware status."
pnputil /enum-devices /instanceid $HardwareId
Write-Step "VM smoke test done. Do not set start=boot on untested drivers."
