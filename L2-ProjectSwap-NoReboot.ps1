param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("l2_projectswap_{0}.log" -f $ts)
$srcPath = Join-Path $ProjectRoot "amdbc250_kmd.c"
$srcBak = Join-Path $ProjectRoot ("amdbc250_kmd.c.bak_{0}" -f $ts)
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
$pkgDir = Join-Path $ProjectRoot "build\Release\x64\package"

function L([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m
    $line | Tee-Object -FilePath $log -Append
}

function Remove-ServiceSafe([string]$name) {
    sc.exe stop $name *>> $log
    sc.exe delete $name *>> $log
}

function Build-And-ServiceTest([string]$variantName, [string]$variantSource) {
    L "VARIANT=$variantName"
    Copy-Item -LiteralPath $srcBak -Destination $srcPath -Force
    Set-Content -LiteralPath $srcPath -Value $variantSource -Encoding ASCII

    & $msbuild (Join-Path $ProjectRoot "amdbc250kmd.vcxproj") /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
    L ("BUILD_EXIT_{0}={1}" -f $variantName, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { return }

    $sys = Join-Path $pkgDir "amdbc250kmd.sys"
    if (-not (Test-Path $sys)) {
        L ("NO_SYS_{0}=1" -f $variantName)
        return
    }

    & $signtool sign /fd sha256 /f C:\bc250new.pfx /p bc250 $sys *>> $log
    L ("SIGN_EXIT_{0}={1}" -f $variantName, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { return }

    $svc = ("l2swap_{0}_{1}" -f $variantName, $ts).ToLower()
    $dst = Join-Path "C:\Windows\System32\drivers" ($svc + ".sys")
    Copy-Item $sys $dst -Force
    L ("HASH_{0}={1}" -f $variantName, (Get-FileHash $dst -Algorithm SHA256).Hash)

    Remove-ServiceSafe $svc
    sc.exe create $svc type= kernel start= demand error= normal binPath= ("\SystemRoot\System32\drivers\" + $svc + ".sys") DisplayName= ("BC250 " + $svc) *>> $log
    sc.exe start $svc *>> $log
    L ("SC_START_EXIT_{0}={1}" -f $variantName, $LASTEXITCODE)
    Start-Sleep -Seconds 2
    sc.exe query $svc *>> $log
    sc.exe stop $svc *>> $log
    sc.exe delete $svc *>> $log
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
    L ("CLEANUP_{0}=DONE" -f $variantName)
}

L "LOG=$log"
Copy-Item -LiteralPath $srcPath -Destination $srcBak -Force

$l2b = @"
#include <ntddk.h>
#include <dispmprt.h>

VOID Bc250MiniUnload(_In_ PDRIVER_OBJECT DriverObject) {
    UNREFERENCED_PARAMETER(DriverObject);
}

NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath) {
    UNREFERENCED_PARAMETER(RegistryPath);
    DriverObject->DriverUnload = Bc250MiniUnload;
    return STATUS_SUCCESS;
}
"@

$l2c = @"
#include <ntddk.h>
#include <dispmprt.h>

volatile PVOID g_Bc250DxgkInitializeRef = (PVOID)(ULONG_PTR)&DxgkInitialize;

VOID Bc250MiniUnload(_In_ PDRIVER_OBJECT DriverObject) {
    UNREFERENCED_PARAMETER(DriverObject);
}

NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath) {
    UNREFERENCED_PARAMETER(RegistryPath);
    DriverObject->DriverUnload = Bc250MiniUnload;
    if (g_Bc250DxgkInitializeRef == NULL) {
        return STATUS_UNSUCCESSFUL;
    }
    return STATUS_SUCCESS;
}
"@

try {
    Build-And-ServiceTest -variantName "l2b" -variantSource $l2b
    Build-And-ServiceTest -variantName "l2c" -variantSource $l2c
}
finally {
    Copy-Item -LiteralPath $srcBak -Destination $srcPath -Force
    Remove-Item -LiteralPath $srcBak -Force -ErrorAction SilentlyContinue
    L "SOURCE_RESTORED=1"
}

Get-Content $log -Tail 260
