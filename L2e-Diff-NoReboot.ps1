param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")
$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("l2e_diff_{0}.log" -f $ts)
function L([string]$m){("[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m) | Tee-Object -FilePath $log -Append}
$dumpbin = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"
if(-not (Test-Path $dumpbin)){ $dumpbin = (Get-Command dumpbin.exe -ErrorAction SilentlyContinue).Source }
L "DUMPBIN=$dumpbin"
$l1 = Join-Path $ProjectRoot "l1_hello\bc250hello.sys"
$l0 = Join-Path $ProjectRoot "build\Release\x64\package\amdbc250kmd.sys"
if(Test-Path $l1){
  & $dumpbin /headers $l1 *> (Join-Path $ProjectRoot "L1_headers.txt")
  & $dumpbin /imports $l1 *> (Join-Path $ProjectRoot "L1_imports.txt")
  & $dumpbin /loadconfig $l1 *> (Join-Path $ProjectRoot "L1_loadconfig.txt")
  L "L1_DUMPBIN_REFRESH=1"
}else{ L "L1_SYS_MISSING=1" }
if(Test-Path $l0){
  & $dumpbin /headers $l0 *> (Join-Path $ProjectRoot "L0_headers.txt")
  & $dumpbin /imports $l0 *> (Join-Path $ProjectRoot "L0_imports.txt")
  & $dumpbin /loadconfig $l0 *> (Join-Path $ProjectRoot "L0_loadconfig.txt")
  L "L0_DUMPBIN_REFRESH=1"
}else{ L "L0_SYS_MISSING=1" }
$files = @(
  @{A="L1_headers.txt";B="L0_headers.txt";O="L2e_headers_diff.txt"},
  @{A="L1_imports.txt";B="L0_imports.txt";O="L2e_imports_diff.txt"},
  @{A="L1_loadconfig.txt";B="L0_loadconfig.txt";O="L2e_loadconfig_diff.txt"}
)
foreach($f in $files){
  $a = Join-Path $ProjectRoot $f.A
  $b = Join-Path $ProjectRoot $f.B
  $o = Join-Path $ProjectRoot $f.O
  if((Test-Path $a) -and (Test-Path $b)){
    cmd /c "fc /n \"$a\" \"$b\" > \"$o\""
    L ("DIFF_DONE="+$f.O)
  } else {
    L ("DIFF_SKIP="+$f.O)
  }
}
L "KEY_HEADER_LINES"
if(Test-Path (Join-Path $ProjectRoot "L2e_headers_diff.txt")){
  Get-Content (Join-Path $ProjectRoot "L2e_headers_diff.txt") | Select-String -Pattern "subsystem version|operating system version|entry point|characteristics|machine|DLL characteristics|Section alignment|file alignment" -CaseSensitive:$false | ForEach-Object { $_.Line } | Tee-Object -FilePath $log -Append
}
L "KEY_IMPORT_LINES"
if(Test-Path (Join-Path $ProjectRoot "L2e_imports_diff.txt")){
  Get-Content (Join-Path $ProjectRoot "L2e_imports_diff.txt") | Select-String -Pattern "ntoskrnl|hal|wdm|displib|dxgkrnl|wdmsec|BufferOverflow|Ke|Mm|Rtl|Zw" -CaseSensitive:$false | Select-Object -First 80 | ForEach-Object { $_.Line } | Tee-Object -FilePath $log -Append
}
Get-Content $log -Tail 220
