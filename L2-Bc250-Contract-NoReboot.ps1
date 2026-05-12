param(
    [string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest"
)

$ErrorActionPreference = "Continue"
$log = Join-Path $ProjectRoot ("l2_bc250_contract_{0}.log" -f (Get-Date -Format yyyyMMdd_HHmmss))
$work = Join-Path $ProjectRoot "l2_contract"

function L {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $Message
    $line | Tee-Object -FilePath $log -Append
}

function Remove-ServiceSafe {
    param([string]$Name)
    sc.exe stop $Name *>> $log
    sc.exe delete $Name *>> $log
}

function Build-And-RunVariant {
    param(
        [string]$VariantName,
        [string]$SourceContent,
        [string[]]$ExtraLibs
    )

    $src = Join-Path $work ("{0}.c" -f $VariantName)
    $obj = Join-Path $work ("{0}.obj" -f $VariantName)
    $sys = Join-Path $work ("{0}.sys" -f $VariantName)
    $dst = Join-Path "C:\Windows\System32\drivers" ("{0}.sys" -f $VariantName)
    $svc = $VariantName
    $before = (Get-Date).AddMinutes(-2)

    $SourceContent | Set-Content -LiteralPath $src -Encoding ASCII

    & cl.exe /nologo /W3 /WX- /O1 /Oi /GS- /TC /kernel `
        /D_AMD64_ /DAMD64 /D_WIN64 /D_NTDDK_ /DNTDDI_VERSION=0x0A000000 /DWINNT=1 `
        "/I$script:wdk\Include\10.0.19041.0\km" "/I$script:wdk\Include\10.0.19041.0\shared" "/I$script:wdk\Include\10.0.19041.0\km\crt" `
        /c $src /Fo$obj *>> $log
    L ("{0}_CL_EXIT={1}" -f $VariantName, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { return }

    $linkArgs = @(
        "/DRIVER:WDM",
        "/SUBSYSTEM:NATIVE",
        "/ENTRY:DriverEntry",
        "/NODEFAULTLIB",
        "/OUT:$sys",
        "/LIBPATH:$script:libPath",
        $obj,
        "ntoskrnl.lib",
        "hal.lib",
        "BufferOverflowFastFailK.lib"
    ) + $ExtraLibs

    & link.exe @linkArgs *>> $log
    L ("{0}_LINK_EXIT={1}" -f $VariantName, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { return }

    & $script:signtool sign /fd sha256 /f C:\bc250new.pfx /p bc250 $sys *>> $log
    L ("{0}_SIGN_EXIT={1}" -f $VariantName, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { return }

    Copy-Item $sys $dst -Force
    L ("{0}_HASH={1}" -f $VariantName, (Get-FileHash $dst -Algorithm SHA256).Hash)

    Remove-ServiceSafe -Name $svc
    sc.exe create $svc type= kernel start= demand error= normal binPath= ("\SystemRoot\System32\drivers\{0}.sys" -f $VariantName) DisplayName= ("BC250 {0}" -f $VariantName) *>> $log
    sc.exe start $svc *>> $log
    L ("{0}_SC_START_EXIT={1}" -f $VariantName, $LASTEXITCODE)
    Start-Sleep -Seconds 2
    sc.exe query $svc *>> $log

    Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = $before } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match "Service Control Manager|Kernel-PnP" -or $_.Message -match $VariantName } |
        Select-Object TimeCreated, Id, ProviderName, Message |
        Format-List * |
        Out-String -Width 4096 |
        Add-Content $log

    Remove-ServiceSafe -Name $svc
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
    L ("{0}_CLEANUP_DONE" -f $VariantName)
}

L "LOG=$log"
L "NO_REBOOT=1"

$dumpbin = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"
if (-not (Test-Path $dumpbin)) { $dumpbin = (Get-Command dumpbin.exe -ErrorAction SilentlyContinue).Source }
$script:signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
$script:wdk = "C:\Program Files (x86)\Windows Kits\10"
$script:libPath = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64"

$vsDevCmd = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
$envOutput = cmd /c "`"$vsDevCmd`" -arch=x64 & set" 2>&1
$envOutput | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*=' } | ForEach-Object {
    $parts = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($parts[0], $parts[1], "Process")
}

New-Item -ItemType Directory -Path $work -Force | Out-Null

$l1sys = Join-Path $ProjectRoot "l1_hello\bc250hello.sys"
if ((Test-Path $l1sys) -and $dumpbin) {
    & $dumpbin /headers $l1sys *> (Join-Path $ProjectRoot "L1_headers.txt")
    & $dumpbin /imports $l1sys *> (Join-Path $ProjectRoot "L1_imports.txt")
    & $dumpbin /loadconfig $l1sys *> (Join-Path $ProjectRoot "L1_loadconfig.txt")
    L "L1_DUMPBIN_DONE"
}

$l2a = @'
typedef long NTSTATUS;
typedef void* PVOID;
#define STATUS_SUCCESS ((NTSTATUS)0x00000000L)
NTSTATUS DriverEntry(PVOID DriverObject, PVOID RegistryPath) {
    (void)DriverObject;
    (void)RegistryPath;
    return STATUS_SUCCESS;
}
'@

$l2b = @'
#include <ntddk.h>
#include <dispmprt.h>
NTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath) {
    UNREFERENCED_PARAMETER(DriverObject);
    UNREFERENCED_PARAMETER(RegistryPath);
    return STATUS_SUCCESS;
}
'@

$l2c = @'
#include <ntddk.h>
#include <dispmprt.h>
extern NTSTATUS NTAPI DxgkInitialize(PDRIVER_OBJECT, PUNICODE_STRING, PDRIVER_INITIALIZATION_DATA);
volatile PVOID g_keep_dxgkimport = (PVOID)DxgkInitialize;
NTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath) {
    UNREFERENCED_PARAMETER(DriverObject);
    UNREFERENCED_PARAMETER(RegistryPath);
    if (g_keep_dxgkimport == NULL) {
        return STATUS_UNSUCCESSFUL;
    }
    return STATUS_SUCCESS;
}
'@

Build-And-RunVariant -VariantName "l2a_kmdmin" -SourceContent $l2a -ExtraLibs @()
Build-And-RunVariant -VariantName "l2b_dispheaders" -SourceContent $l2b -ExtraLibs @()
Build-And-RunVariant -VariantName "l2c_dxgkimport" -SourceContent $l2c -ExtraLibs @("dxgkrnl.lib")

Get-Content $log -Tail 260
