param(
    [string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest"
)

$ErrorActionPreference = "Continue"
$pkg = Join-Path $ProjectRoot "build\Release\x64\package\amdbc250kmd.sys"
$log = Join-Path $ProjectRoot ("l0_l1_kernel_contract_{0}.log" -f (Get-Date -Format yyyyMMdd_HHmmss))

function L {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $Message
    $line | Tee-Object -FilePath $log -Append
}

L "LOG=$log"
L "NO_REBOOT=1"

if (-not (Test-Path $pkg)) {
    L "ERROR missing package: $pkg"
    exit 2
}

$dumpbin = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"
if (-not (Test-Path $dumpbin)) {
    $dumpbin = (Get-Command dumpbin.exe -ErrorAction SilentlyContinue).Source
}
L "DUMPBIN=$dumpbin"

if ($dumpbin) {
    & $dumpbin /headers $pkg *> (Join-Path $ProjectRoot "L0_headers.txt")
    & $dumpbin /imports $pkg *> (Join-Path $ProjectRoot "L0_imports.txt")
    & $dumpbin /loadconfig $pkg *> (Join-Path $ProjectRoot "L0_loadconfig.txt")
    L "L0_DUMPBIN_DONE"
}

$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
if (Test-Path $signtool) {
    & $signtool verify /pa /v $pkg *> (Join-Path $ProjectRoot "L0_signtool_verify.txt")
    L "L0_SIGVERIFY_DONE"
}

$helloDir = Join-Path $ProjectRoot "l1_hello"
New-Item -ItemType Directory -Path $helloDir -Force | Out-Null
$helloC = Join-Path $helloDir "bc250hello.c"
@'
typedef long NTSTATUS;
typedef void* PVOID;
#define STATUS_SUCCESS ((NTSTATUS)0x00000000L)
NTSTATUS MyEntry(PVOID DriverObject, PVOID RegistryPath) {
    (void)DriverObject;
    (void)RegistryPath;
    return STATUS_SUCCESS;
}
'@ | Set-Content -LiteralPath $helloC -Encoding ASCII

$vsDevCmd = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
$envOutput = cmd /c "`"$vsDevCmd`" -arch=x64 & set" 2>&1
$envOutput | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*=' } | ForEach-Object {
    $parts = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($parts[0], $parts[1], "Process")
}

$wdk = "C:\Program Files (x86)\Windows Kits\10"
$obj = Join-Path $helloDir "bc250hello.obj"
$sys = Join-Path $helloDir "bc250hello.sys"

& cl.exe /nologo /W3 /WX- /O1 /Oi /GS- /TC /kernel /D_AMD64_ /DAMD64 /D_WIN64 /D_NTDDK_ `
    "/I$wdk\Include\10.0.19041.0\km" "/I$wdk\Include\10.0.19041.0\shared" `
    /c $helloC /Fo$obj *>> $log
L "L1_CL_EXIT=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) {
    Get-Content $log -Tail 160
    exit 3
}

$libPath = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64"
& link.exe /DRIVER:WDM /SUBSYSTEM:NATIVE /ENTRY:MyEntry /NODEFAULTLIB `
    /OUT:$sys /LIBPATH:$libPath $obj ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib *>> $log
L "L1_LINK_EXIT=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) {
    Get-Content $log -Tail 160
    exit 4
}

if (Test-Path $signtool) {
    & $signtool sign /fd sha256 /f C:\bc250new.pfx /p bc250 $sys *>> $log
    L "L1_SIGN_EXIT=$LASTEXITCODE"
}

$dst = "C:\Windows\System32\drivers\bc250hello.sys"
Copy-Item $sys $dst -Force
L ("L1_HELLO_HASH={0}" -f (Get-FileHash $dst -Algorithm SHA256).Hash)

sc.exe stop bc250hello *>> $log
sc.exe delete bc250hello *>> $log
sc.exe create bc250hello type= kernel start= demand error= normal binPath= "\SystemRoot\System32\drivers\bc250hello.sys" DisplayName= "BC250 Hello Driver" *>> $log

$before = (Get-Date).AddMinutes(-2)
sc.exe start bc250hello *>> $log
L "L1_SC_START_EXIT=$LASTEXITCODE"
Start-Sleep -Seconds 2
sc.exe query bc250hello *>> $log

Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = $before } -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match "Service Control Manager|Kernel-PnP" -or $_.Message -match "bc250hello" } |
    Select-Object TimeCreated, Id, ProviderName, Message |
    Format-List * |
    Out-String -Width 4096 |
    Add-Content $log

sc.exe stop bc250hello *>> $log
sc.exe delete bc250hello *>> $log
Remove-Item $dst -Force -ErrorAction SilentlyContinue
L "L1_CLEANUP_DONE"

Get-Content $log -Tail 220
