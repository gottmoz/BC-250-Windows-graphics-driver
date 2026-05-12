$root='C:\Dev\BC250-windowsDriverTest'
$ts=Get-Date -Format yyyyMMdd_HHmmss
$log=Join-Path $root ("m0b_build_trace_{0}.log" -f $ts)
$src=Join-Path $root 'amdbc250_kmd.c'
$bak="$src.bak_$ts"
$marker="AMDBC250_FULL_KMD_M0B_$ts"
$msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
function L($m){("[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m)|Tee-Object -FilePath $log -Append}
function HasMarker($p,$m){if(-not (Test-Path $p)){return $false};$a=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($p)); return $a.Contains($m)}
Copy-Item $src $bak -Force
try{
 Add-Content -LiteralPath $src -Value "`r`n__declspec(selectany) const char g_M0BMarker[] = `"$marker`";`r`n"
 L("MARKER=$marker")
 $start=Get-Date
 & $msbuild (Join-Path $root 'amdbc250kmd.vcxproj') /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:diag *>> $log
 L("BUILD_EXIT=$LASTEXITCODE")
 $recent=Get-ChildItem -Path $root -Recurse -Filter *.sys -ErrorAction SilentlyContinue | Where-Object {$_.LastWriteTime -ge $start.AddMinutes(-3)} | Sort-Object LastWriteTime -Descending
 L("RECENT_SYS_COUNT="+$recent.Count)
 foreach($f in $recent){ L("RECENT_SYS={0}|{1}|M={2}" -f $f.FullName,$f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'),(HasMarker $f.FullName $marker)) }
}
finally{
 Copy-Item $bak $src -Force
 Remove-Item $bak -Force -EA SilentlyContinue
 L('RESTORE_DONE=1')
}
Get-Content $log -Tail 260
