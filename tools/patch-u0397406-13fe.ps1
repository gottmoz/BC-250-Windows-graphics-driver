$ErrorActionPreference='Stop'
$inf='C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF\u0397406.inf'
$bak='C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF\u0397406.inf.backup.fix.' + (Get-Date -Format 'yyyyMMddHHmmss')
Copy-Item -LiteralPath $inf -Destination $bak -Force
$lines = Get-Content -LiteralPath $inf
$out = New-Object System.Collections.Generic.List[string]
$insertModel = $false
$insertStr = $false
foreach($line in $lines){
  $out.Add($line)
  if(-not $insertModel -and $line -match '^\[ATI\.Mfg\.NTamd64\.10\.0\.1\.\.16299\]$'){
    $out.Add('%AMD13FE.1% = ati2mtag_Navi10, PCI\\VEN_1002&DEV_13FE')
    $out.Add('%AMD13FE.2% = ati2mtag_Navi10, PCI\\VEN_1002&DEV_13FE&SUBSYS_00001022')
    $insertModel = $true
  }
  if(-not $insertStr -and $line -match '^\[Strings\]$'){
    $out.Add('AMD13FE.1 = "AMD BC-250 Graphics Adapter"')
    $out.Add('AMD13FE.2 = "AMD BC-250 Graphics Adapter (SUBSYS 00001022)"')
    $insertStr = $true
  }
}
# remove duplicates if already existed
$final = New-Object System.Collections.Generic.List[string]
$seen = @{}
foreach($l in $out){
  if($l -match '^%AMD13FE\.[12]%\s*=|^AMD13FE\.[12]\s*='){
    if($seen.ContainsKey($l)){ continue }
    $seen[$l]=$true
  }
  $final.Add($l)
}
Set-Content -LiteralPath $inf -Value $final -Encoding ASCII
Write-Output 'PATCH_OK'
Select-String -Path $inf -Pattern 'AMD13FE|DEV_13FE' -CaseSensitive:$false | Select-Object -First 20 LineNumber,Line | Format-Table -AutoSize
