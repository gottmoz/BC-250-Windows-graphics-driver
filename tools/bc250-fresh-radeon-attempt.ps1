$ErrorActionPreference='Stop'
$src='C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF'
$work='C:\Users\Public\bc250-radeon-fresh'
$infOld='u0397406.inf'
$infNew='u0397406_bc250.inf'
$catNew='u0397406_bc250.cat'
$inf2cat='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x86\Inf2Cat.exe'
$sig='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'

if(Test-Path $work){ Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item -Path (Join-Path $src '*') -Destination $work -Recurse -Force
Copy-Item -LiteralPath (Join-Path $work $infOld) -Destination (Join-Path $work $infNew) -Force

$infPath=Join-Path $work $infNew
$txt=Get-Content -LiteralPath $infPath -Raw
$txt=[regex]::Replace($txt,'(?m)^CatalogFile\s*=\s*.+$','CatalogFile=' + $catNew)
$txt=$txt -replace '(?m)^\[ATI\.Mfg\.NTamd64\.10\.0\.1\.\.16299\]$','$0`r`n%AMD13FE.1% = ati2mtag_Navi10, PCI\VEN_1002&DEV_13FE`r`n%AMD13FE.2% = ati2mtag_Navi10, PCI\VEN_1002&DEV_13FE&SUBSYS_00001022'
$txt=$txt -replace '(?m)^\[ATI\.Mfg\.NTamd64\.10\.0\.1\]$','$0`r`n%AMD13FE.1% = ati2mtag_Navi10, PCI\VEN_1002&DEV_13FE`r`n%AMD13FE.2% = ati2mtag_Navi10, PCI\VEN_1002&DEV_13FE&SUBSYS_00001022'
if($txt -notmatch '(?m)^AMD13FE\.1\s*='){
  $txt=$txt -replace '(?m)^\[Strings\]$','$0`r`nAMD13FE.1 = "AMD BC-250 Graphics Adapter"`r`nAMD13FE.2 = "AMD BC-250 Graphics Adapter (SUBSYS 00001022)"'
}
# keep single slashes
$txt=$txt -replace 'PCI\\\\VEN_1002&DEV_13FE&SUBSYS_00001022','PCI\\VEN_1002&DEV_13FE&SUBSYS_00001022'
$txt=$txt -replace 'PCI\\\\VEN_1002&DEV_13FE','PCI\\VEN_1002&DEV_13FE'
Set-Content -LiteralPath $infPath -Value $txt -Encoding ASCII

Write-Output '=== INF INSERT CHECK ==='
Select-String -Path $infPath -Pattern 'CatalogFile=|AMD13FE|DEV_13FE|\[ATI\.Mfg\.NTamd64\.10\.0\.1\]|\[ATI\.Mfg\.NTamd64\.10\.0\.1\.\.16299\]' -CaseSensitive:$false | Select-Object -First 40 | ForEach-Object { $_.Line }

& $inf2cat /driver:$work /os:10_X64
Write-Output ('INF2CAT_EXIT=' + $LASTEXITCODE)
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }

$cert=Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.HasPrivateKey -and $_.Subject -match 'BC250' } | Sort-Object NotAfter -Descending | Select-Object -First 1
if(-not $cert){ throw 'No BC250 cert in CurrentUser\\My' }
$cerPath='C:\Users\Public\bc250-signing.cer'
Export-Certificate -Cert $cert -FilePath $cerPath -Force | Out-Null
certutil -addstore -f TrustedPublisher $cerPath | Out-Null
certutil -addstore -f Root $cerPath | Out-Null

& $sig sign /fd SHA256 /sha1 $cert.Thumbprint /s My (Join-Path $work $catNew)
Write-Output ('SIGN_CAT_EXIT=' + $LASTEXITCODE)
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }

pnputil /delete-driver oem9.inf /uninstall /force | Out-Null
pnputil /add-driver $infPath /install
Write-Output ('PNPUTIL_EXIT=' + $LASTEXITCODE)

$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
Write-Output '=== DEVICE STATE ==='
Get-PnpDevice -Class Display -PresentOnly | Format-List Status,FriendlyName,Problem,Service,InstanceId
Write-Output '=== MATCHING DRIVERS ==='
pnputil /enum-devices /instanceid $inst /drivers
Write-Output '=== SETUPAPI KEY LINES ==='
$setup='C:\Windows\INF\setupapi.dev.log'
Get-Content $setup -Tail 1800 | Select-String -Pattern 'u0397406_bc250|oem9.inf|Rank|Signer Score|Section Name|Add Service|amdkmdag|VEN_1002&DEV_13FE' -CaseSensitive:$false | Select-Object -Last 260 | ForEach-Object { $_.Line }
