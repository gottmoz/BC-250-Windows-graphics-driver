$ErrorActionPreference='Stop'
$sw=[System.Diagnostics.Stopwatch]::StartNew()
$repo='C:\Dev\BC250-windowsDriverTest'
$msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\amd64\MSBuild.exe'
$inf2cat='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x86\Inf2Cat.exe'
$sig='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
Set-Location $repo

Write-Output ('STEP build KMD start ' + (Get-Date -Format o))
& $msbuild amdbc250kmd.vcxproj /p:Configuration=Release /p:Platform=x64 /p:CL_MPCount=1 /p:MultiProcessorCompilation=false /p:UseMultiToolTask=true /p:AdditionalOptions="/FS" /t:Build /m:1 /nodeReuse:false
if($LASTEXITCODE -ne 0){ throw "KMD build failed: $LASTEXITCODE" }
Write-Output ('STEP build UMD start ' + (Get-Date -Format o))
& $msbuild amdbc250umd.vcxproj /p:Configuration=Release /p:Platform=x64 /p:CL_MPCount=1 /p:MultiProcessorCompilation=false /p:UseMultiToolTask=true /p:AdditionalOptions="/FS" /t:Build /m:1 /nodeReuse:false
if($LASTEXITCODE -ne 0){ throw "UMD build failed: $LASTEXITCODE" }

$pkg=Join-Path $repo 'build\Release\x64\package'
New-Item -ItemType Directory -Force -Path $pkg | Out-Null
$suffix='t' + (Get-Date -Format 'yyyyMMddHHmmss')
$kmdBase="amdbc250kmd_$suffix"
$umdBase="amdbc250umd_$suffix"
$svcName="amdbc250kmd$suffix"
$kmdFile="$kmdBase.sys"
$umdFile="$umdBase.dll"

$infText=Get-Content -LiteralPath (Join-Path $repo 'amdbc250.inf') -Raw
$infText=$infText.Replace('AddService = amdbc250kmd, 0x00000002, amdbc250_Service_Inst', "AddService = $svcName, 0x00000002, amdbc250_Service_Inst")
$infText=$infText.Replace('amdbc250kmd.sys', $kmdFile)
$infText=$infText.Replace('amdbc250umd.dll', $umdFile)
$infText=[regex]::Replace($infText, '(?im)^(\s*HKR,\s*,\s*InstalledDisplayDrivers,\s*%REG_MULTI_SZ%,\s*).+$', ('$1' + $umdBase))
$infText=[regex]::Replace($infText, '(?im)^(\s*HKR,\s*,\s*UserModeDriverName,\s*%REG_MULTI_SZ%,\s*).+$', ('$1' + $umdFile))
$infText=[regex]::Replace($infText, '(?im)^(\s*HKR,\s*,\s*UserModeDriverNameWow,\s*%REG_MULTI_SZ%,\s*).+$', ('$1' + $umdFile))
$infText=$infText.Replace('ServiceBinary = %12%\amdbc250kmd.sys', "ServiceBinary = %12%\$kmdFile")
Set-Content -LiteralPath (Join-Path $pkg 'amdbc250.inf') -Value $infText -Encoding ASCII -NoNewline

Copy-Item -LiteralPath (Join-Path $repo 'build\Release\x64\amdbc250kmd.sys') -Destination (Join-Path $pkg $kmdFile) -Force
Copy-Item -LiteralPath (Join-Path $repo 'build\Release\x64\amdbc250umd.dll') -Destination (Join-Path $pkg $umdFile) -Force
Write-Output "UNIQUE_PACKAGE_SUFFIX=$suffix"
Write-Output "UNIQUE_SERVICE=$svcName"
Write-Output "UNIQUE_KMD=$kmdFile"
Write-Output "UNIQUE_UMD=$umdFile"
$iterEventStart=Get-Date

& $inf2cat /driver:$pkg /os:10_X64
if($LASTEXITCODE -ne 0){ throw "Inf2Cat failed: $LASTEXITCODE" }

$cert=Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.HasPrivateKey -and $_.Subject -match 'BC250' } | Sort-Object NotAfter -Descending | Select-Object -First 1
if(-not $cert){ throw 'No BC250 signing cert found' }
$thumb=$cert.Thumbprint
foreach($f in @((Join-Path $pkg $kmdFile),(Join-Path $pkg $umdFile),(Join-Path $pkg 'amdbc250.cat'))){
  & $sig sign /fd SHA256 /sha1 $thumb /s My $f
  if($LASTEXITCODE -ne 0){ throw "Sign failed: $f" }
}
Write-Output "SIGNED_THUMBPRINT=$thumb"

Write-Output ('STEP guarded-run start ' + (Get-Date -Format o))
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'Run-GuardedDriverTest.ps1') -TimeoutSeconds 50 -RebootCountdownSeconds 5 -AllowBaselineBypass -NoRebootRecovery
$guardExit=$LASTEXITCODE
Write-Output "GUARD_EXIT=$guardExit"

Write-Output 'STEP verify state'
pnputil /enum-devices /instanceid "$inst"
Get-PnpDevice -InstanceId $inst | Select-Object Status,FriendlyName,Problem,Present | Format-List
Get-PnpDeviceProperty -InstanceId $inst -KeyName 'DEVPKEY_Device_DriverInfPath','DEVPKEY_Device_Service','DEVPKEY_Device_ProblemCode','DEVPKEY_Device_ProblemStatus' | Select-Object KeyName,Data | Format-Table -AutoSize

$tmp='C:\Users\Public\dxdiag-fast.txt'
Start-Process dxdiag.exe -ArgumentList '/whql:off','/t',$tmp -Wait -WindowStyle Hidden
if(Test-Path $tmp){
  Select-String -Path $tmp -Pattern 'Card name:|Driver Name:|Driver Model:|DDI Version:|Feature Levels:' -CaseSensitive:$false | ForEach-Object { $_.Line }
}

Write-Output 'STEP extensive debug'
Write-Output '=== package inf service/file refs ==='
Select-String -Path (Join-Path $pkg 'amdbc250.inf') -Pattern 'AddService|ServiceBinary|CopyFiles|InstalledDisplayDrivers|UserModeDriverName|FeatureScore|DriverVer' -CaseSensitive:$false | ForEach-Object { $_.Line }
Write-Output '=== package signature verify ==='
& $sig verify /pa /v (Join-Path $pkg 'amdbc250.cat')
Write-Output ('sig_cat_verify_exit=' + $LASTEXITCODE)
& $sig verify /pa /v (Join-Path $pkg $kmdFile)
Write-Output ('sig_kmd_verify_exit=' + $LASTEXITCODE)
Write-Output '=== pnputil drivers for instance ==='
pnputil /enum-devices /instanceid "$inst" /drivers
Write-Output '=== focused current-iteration event correlation ==='
$eventStart=$iterEventStart.AddSeconds(-2)
$focusRegex=([regex]::Escape($svcName) + '|' + [regex]::Escape($kmdFile) + '|' + [regex]::Escape($umdFile) + '|VEN_1002&DEV_13FE')
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$eventStart} -ErrorAction SilentlyContinue |
  Where-Object { $_.Message -match $focusRegex -or $_.ProviderName -match 'Kernel-PnP|Service Control Manager|Display|DxgKrnl|CodeIntegrity' } |
  Select-Object -Last 24 |
  ForEach-Object {
    '--- FOCUSED EVENT XML ---'
    $_.ToXml()
  }
Write-Output '=== recent Kernel-PnP/SCM/CodeIntegrity events XML ==='
$eventStart=(Get-Date).AddMinutes(-10)
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$eventStart} -ErrorAction SilentlyContinue |
  Where-Object { $_.ProviderName -match 'Kernel-PnP|Service Control Manager|Display|DxgKrnl|CodeIntegrity' -or $_.Message -match 'amdbc250|BC-250|VEN_1002|display|graphics|failed to load' } |
  Select-Object -Last 16 |
  ForEach-Object {
    '--- EVENT XML ---'
    $_.ToXml()
  }
foreach($ciLog in @('Microsoft-Windows-CodeIntegrity/Operational','Microsoft-Windows-Kernel-PnP/Configuration')) {
  Write-Output "=== recent $ciLog ==="
  Get-WinEvent -FilterHashtable @{LogName=$ciLog; StartTime=$eventStart} -ErrorAction SilentlyContinue |
    Select-Object -Last 12 |
    ForEach-Object { $_.ToXml() }
}
Write-Output '=== setupapi latest BC250/install tail ==='
$setup='C:\Windows\INF\setupapi.dev.log'
if(Test-Path $setup){
  $lines=Get-Content $setup -Tail 900
  $hit=@()
  $focusSetup=([regex]::Escape($svcName) + '|' + [regex]::Escape($kmdFile) + '|' + [regex]::Escape($umdFile) + '|amdbc250|BC-250|VEN_1002&DEV_13FE|failed|Device not started|0xc01e0438|CM_PROB')
  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -match $focusSetup) { $hit += $i }
  }
  if($hit.Count -gt 0){
    $from=[Math]::Max(0,$hit[0]-40)
    $to=[Math]::Min($lines.Count-1,$hit[-1]+80)
    $lines[$from..$to]
  } else {
    $lines | Select-Object -Last 220
  }
}

$sw.Stop()
$sec=[math]::Round($sw.Elapsed.TotalSeconds,1)
Write-Output "ITERATION_SECONDS=$sec"
if($sec -gt 180){ Write-Output 'ITERATION_TIMEOUT_EXCEEDED=TRUE'; exit 124 }
exit $guardExit


