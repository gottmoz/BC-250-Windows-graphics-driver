param(
    [Parameter(Mandatory = $true)][string]$DriverService,
    [Parameter(Mandatory = $true)][string]$InstallCommand,
    [int]$RebootDelaySeconds = 60
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run as Administrator."
    }
}

function Write-Step([string]$m) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $m"
}

Assert-Admin
Write-Step "Creating restore point."
Checkpoint-Computer -Description "pre-driver" -RestorePointType MODIFY_SETTINGS | Out-Null

Write-Step "Setting '$DriverService' start=demand."
sc.exe config $DriverService start= demand | Out-Null

Write-Step "Executing install command."
Invoke-Expression $InstallCommand

Write-Step "Enabling safeboot minimal."
bcdedit /set {current} safeboot minimal | Out-Null

Write-Step "Rebooting in $RebootDelaySeconds seconds."
shutdown /r /t $RebootDelaySeconds
Write-Step "After reconnect run: bcdedit /deletevalue {current} safeboot ; shutdown /r /t 0"
