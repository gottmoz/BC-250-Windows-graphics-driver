param(
    [string]$HardwareId = "PCI\\VEN_1002&DEV_13FE",
    [string]$DevconPath = "C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe"
)

$ErrorActionPreference = "Continue"

function Write-Step([string]$m) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $m"
}

Write-Step "Disabling non-Microsoft display miniport service if present."
sc.exe config amdbc250kmd start= disabled | Out-Null
sc.exe stop amdbc250kmd | Out-Null

Write-Step "Removing BC250 driver packages from DriverStore."
$drivers = pnputil /enum-drivers
$pub = $null
foreach ($line in $drivers) {
    if ($line -match '^\s*Published Name:\s*(\S+)\s*$') { $pub = $Matches[1]; continue }
    if ($line -match '^\s*Original Name:\s*(\S+)\s*$') {
        if ($Matches[1] -ieq "amdbc250.inf" -and $pub) {
            pnputil /delete-driver $pub /uninstall /force | Out-Null
        }
    }
}

if (Test-Path -LiteralPath $DevconPath) {
    Write-Step "Binding Microsoft Basic Display adapter."
    & $DevconPath update C:\Windows\INF\display.inf $HardwareId | Out-Null
}

Write-Step "Restarting now."
shutdown /r /t 0
