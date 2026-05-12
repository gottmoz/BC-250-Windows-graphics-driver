$ErrorActionPreference='Continue'
$repo='C:\Dev\BC250-windowsDriverTest'
$proj=Join-Path $repo 'amdbc250kmd.vcxproj'
$bak=Join-Path $repo 'amdbc250kmd.vcxproj.pebak'
$log=Join-Path $repo 'linker-pe-batch.log'

function Log([string]$m){$ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss';$line="[$ts] $m";Add-Content -LiteralPath $log -Value $line;Write-Output $line}
if(!(Test-Path $bak)){Copy-Item -LiteralPath $proj -Destination $bak -Force}
$base=Get-Content -LiteralPath $bak -Raw

$variants=@(
 @{Name='C1_baseline'; NoDef='true'; Pe61='false'},
 @{Name='C2_nodef_off'; NoDef='false'; Pe61='false'},
 @{Name='C3_pe61'; NoDef='true'; Pe61='true'},
 @{Name='C4_nodef_off_pe61'; NoDef='false'; Pe61='true'}
)

foreach($v in $variants){
 $txt=$base
 if($v.NoDef -eq 'true'){
   $txt=$txt.Replace('<IgnoreAllDefaultLibraries>true</IgnoreAllDefaultLibraries>','<IgnoreAllDefaultLibraries>true</IgnoreAllDefaultLibraries>')
 } else {
   $txt=$txt.Replace('<IgnoreAllDefaultLibraries>true</IgnoreAllDefaultLibraries>','<IgnoreAllDefaultLibraries>false</IgnoreAllDefaultLibraries>')
 }

 # Ensure AdditionalOptions node exists under both Link groups
 if($txt -notmatch '<AdditionalOptions>'){ 
   $txt=[regex]::Replace($txt,'(?s)(<SubSystem>Native</SubSystem>\s*<Driver>WDM</Driver>)','$1`r`n      <AdditionalOptions>%(AdditionalOptions)</AdditionalOptions>')
 }
 if($v.Pe61 -eq 'true'){
   $txt=[regex]::Replace($txt,'<AdditionalOptions>[^<]*</AdditionalOptions>','<AdditionalOptions>/OSVERSION:6.01 /SUBSYSTEM:NATIVE,6.01 %(AdditionalOptions)</AdditionalOptions>')
 } else {
   $txt=[regex]::Replace($txt,'<AdditionalOptions>[^<]*</AdditionalOptions>','<AdditionalOptions>%(AdditionalOptions)</AdditionalOptions>')
 }

 Set-Content -LiteralPath $proj -Value $txt -Encoding UTF8 -NoNewline
 Log "ITER_START $($v.Name)"
 $sw=[Diagnostics.Stopwatch]::StartNew(); $out=powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Public\remote-iter-fast.ps1' 2>&1; $code=$LASTEXITCODE; $sw.Stop(); $sec=[math]::Round($sw.Elapsed.TotalSeconds,1)
 $tmp=Join-Path $repo ("tmp_"+$v.Name+".log"); $out|Out-File -LiteralPath $tmp -Encoding ascii
 $marker=(Select-String -Path $tmp -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|problem status: 0xc0000059|0xC00000E5|KMD build failed|GUARD_EXIT='|Select-Object -Last 1).Line
 Log "ITER_END $($v.Name) exit=$code seconds=$sec marker=$marker"
 if($sec -gt 180){Log "ITER_ABORT $($v.Name) exceeded 180s";break}
}

Copy-Item -LiteralPath $bak -Destination $proj -Force
Log 'LINKER-PE batch done; project restored.'
