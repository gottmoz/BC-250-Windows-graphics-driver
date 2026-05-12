param(
    [Parameter(Mandatory = $true)][string]$ExtractedDriverRoot,
    [string]$InfRelativePath = "Packages\Drivers\Display\WT6A_INF",
    [string]$OutputTag = "bc250_mod",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ids = @(
    "PCI\VEN_1002&DEV_13FE",
    "PCI\VEN_1002&DEV_143F",
    "PCI\VEN_1002&DEV_13DB",
    "PCI\VEN_1002&DEV_13F9",
    "PCI\VEN_1002&DEV_13FA",
    "PCI\VEN_1002&DEV_13FB",
    "PCI\VEN_1002&DEV_13FC"
)

function Write-Step([string]$Message) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $Message"
}

function Get-LineEnding([string]$Text) {
    if ($Text -match "`r`n") { return "`r`n" }
    return "`n"
}

function Get-InfSectionName([string]$Line) {
    if ($Line -match '^\s*\[([^\]]+)\]\s*$') {
        return $Matches[1]
    }
    return $null
}

function Get-ChildRelativePath([string]$RootPath, [string]$ChildPath) {
    $rootFull = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    $childFull = [System.IO.Path]::GetFullPath($ChildPath)
    if (-not $childFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is not under root: $ChildPath"
    }
    return $childFull.Substring($rootFull.Length).TrimStart('\', '/')
}

function Add-Bc250ModelsToInf([string]$Content) {
    $newline = Get-LineEnding $Content
    $lines = $Content -split "\r?\n", -1
    $output = New-Object System.Collections.Generic.List[string]
    $patchedSections = New-Object System.Collections.Generic.List[string]
    $currentSection = $null
    $sectionLines = New-Object System.Collections.Generic.List[string]

    function Flush-Section {
        if ($null -eq $currentSection) {
            foreach ($line in $sectionLines) { $output.Add($line) }
            $sectionLines.Clear()
            return
        }

        $isModelSection = $false
        foreach ($line in $sectionLines) {
            if ($line -match '^\s*%[^%]+%\s*=\s*ati2mtag_Navi10\s*,\s*PCI\\VEN_1002&DEV_[0-9A-Fa-f]{4}') {
                $isModelSection = $true
                break
            }
        }

        if (-not $isModelSection) {
            foreach ($line in $sectionLines) { $output.Add($line) }
            $sectionLines.Clear()
            return
        }

        $alreadyPatched = $false
        foreach ($line in $sectionLines) {
            if ($line -match 'AMD_BC250') {
                $alreadyPatched = $true
                break
            }
        }

        $inserted = $false
        for ($i = 0; $i -lt $sectionLines.Count; $i++) {
            $output.Add($sectionLines[$i])
            $nextLine = if (($i + 1) -lt $sectionLines.Count) { $sectionLines[$i + 1] } else { $null }

            if (-not $alreadyPatched -and
                -not $inserted -and
                $sectionLines[$i] -match '^\s*%[^%]+%\s*=\s*ati2mtag_Navi10\s*,\s*PCI\\VEN_1002&DEV_[0-9A-Fa-f]{4}' -and
                ($null -eq $nextLine -or $nextLine -notmatch '^\s*%[^%]+%\s*=\s*ati2mtag_Navi10\s*,')) {
                foreach ($id in $ids) {
                    $output.Add("%AMD_BC250% = ati2mtag_Navi10, $id")
                }
                $inserted = $true
                $patchedSections.Add($currentSection)
            }
        }

        $sectionLines.Clear()
    }

    foreach ($line in $lines) {
        $sectionName = Get-InfSectionName $line
        if ($null -ne $sectionName) {
            Flush-Section
            $currentSection = $sectionName
        }
        $sectionLines.Add($line)
    }
    Flush-Section

    $patchedContent = $output -join $newline

    if ($patchedContent -notmatch '(?m)^\s*AMD_BC250\s*=' -or $Force) {
        if ($patchedContent -match '(?ms)(\[Strings\]\s*)') {
            $patchedContent = $patchedContent -replace '(?ms)(\[Strings\]\s*)', "`$1AMD_BC250 = `"AMD BC-250 (Cyan Skillfish)`"$newline"
        } else {
            throw "Could not find [Strings] section."
        }
    }

    [pscustomobject]@{
        Content = $patchedContent
        PatchedSections = @($patchedSections)
    }
}

$driverRoot = (Resolve-Path -LiteralPath $ExtractedDriverRoot).Path
$infRoot = Join-Path $driverRoot $InfRelativePath
if (-not (Test-Path -LiteralPath $infRoot)) {
    throw "INF root not found: $infRoot"
}
if ($OutputTag -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "OutputTag may only contain letters, numbers, dot, underscore, and dash."
}

$targetInf = Get-ChildItem -Path $infRoot -Recurse -Filter "*.inf" |
    Where-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        $text -match 'ati2mtag_Navi10' -and
        $text -match '(?m)^\s*%[^%]+%\s*=\s*ati2mtag_Navi10\s*,\s*PCI\\VEN_1002&DEV_[0-9A-Fa-f]{4}'
    } |
    Sort-Object Name |
    Select-Object -First 1

if (-not $targetInf) {
    throw "No AMD display INF with ati2mtag_Navi10 model entries found under $infRoot"
}

$outRoot = Join-Path $driverRoot "mod_$OutputTag"
$outInfRoot = Join-Path $outRoot $InfRelativePath
if (Test-Path -LiteralPath $outRoot) {
    if (-not $Force) {
        throw "Output already exists: $outRoot. Re-run with -Force to replace it."
    }
    $resolvedOutRoot = (Resolve-Path -LiteralPath $outRoot).Path
    if (-not $resolvedOutRoot.StartsWith($driverRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedOutRoot) -notlike 'mod_*') {
        throw "Refusing to remove unexpected output path: $resolvedOutRoot"
    }
    Remove-Item -LiteralPath $outRoot -Recurse -Force
}

Write-Step "Copying Radeon INF payload: $infRoot -> $outInfRoot"
New-Item -ItemType Directory -Force -Path $outInfRoot | Out-Null
Copy-Item -Path (Join-Path $infRoot "*") -Destination $outInfRoot -Recurse -Force

$relativeInf = Get-ChildRelativePath $infRoot $targetInf.FullName
$outInf = Join-Path $outInfRoot $relativeInf
Write-Step "Patching INF: $outInf"

$content = Get-Content -LiteralPath $outInf -Raw
$patch = Add-Bc250ModelsToInf $content
if ($patch.PatchedSections.Count -eq 0 -and $content -notmatch 'AMD_BC250') {
    throw "Found ati2mtag_Navi10, but no model sections were patched."
}

$patched = $patch.Content
$newline = Get-LineEnding $patched
$newCatalog = "{0}_bc250.cat" -f [System.IO.Path]::GetFileNameWithoutExtension($outInf)

if ($patched -match '(?m)^\s*CatalogFile(\.[^=]+)?\s*=') {
    $patched = $patched -replace '(?m)^\s*CatalogFile(\.[^=]+)?\s*=.*$', "CatalogFile = $newCatalog"
} else {
    $patched = $patched -replace '(?ms)(\[Version\]\s*)', "`$1CatalogFile = $newCatalog$newline"
}

Set-Content -LiteralPath $outInf -Value $patched -Encoding ASCII -NoNewline

Write-Step "Patched sections: $($patch.PatchedSections -join ', ')"
Write-Step "Patched package root: $outRoot"
Write-Step "Patched INF: $outInf"
Write-Step "New catalog name: $newCatalog"
Write-Step "Next headless test: run Inf2Cat/SignTool on $outInfRoot, then shared\vm-test.ps1 -InfPath `"$outInf`""

