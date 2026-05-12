param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("n9rver_build_{0}.log" -f $ts)
$work = Join-Path $ProjectRoot ("n9rver_build_{0}" -f $ts)
New-Item -ItemType Directory -Path $work -Force | Out-Null

$srcPath = Join-Path $ProjectRoot "amdbc250_kmd.c"
$srcBak = "$srcPath.bak_$ts"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$link = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe"
$kmLib = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64"
$objPath = Join-Path $ProjectRoot "build\Release\x64\amdbc250kmd\amdbc250_kmd.obj"

function L([string]$m) { ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) | Tee-Object -FilePath $log -Append }
function HashOf([string]$p) { if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash } return "MISSING" }

function Run-Variant {
  param([string]$Name,[UInt32]$InitVersion)

  $marker = "N9RVER_${Name}_$ts"
  $code = @"
#include <ntddk.h>
#include <dispmprt.h>

__declspec(selectany) const char N9RVER_MARKER[] = "$marker";

#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0
#endif

static VOID Bc250WriteDword(_In_ HANDLE Key, _In_ PCWSTR Name, _In_ ULONG Value)
{
    UNICODE_STRING vn;
    RtlInitUnicodeString(&vn, Name);
    ZwSetValueKey(Key, &vn, 0, REG_DWORD, &Value, sizeof(Value));
}

static VOID Bc250WritePre(_In_ PUNICODE_STRING RegistryPath, _In_ ULONG InitVersion, _In_ ULONG InitSize, _In_ ULONG CallbackCount, _In_ ULONG CallbackMask)
{
    HANDLE svcKey = NULL;
    HANDLE prmKey = NULL;
    OBJECT_ATTRIBUTES oaSvc;
    OBJECT_ATTRIBUTES oaPrm;
    UNICODE_STRING prmName;
    NTSTATUS st;

    InitializeObjectAttributes(&oaSvc, RegistryPath, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
    st = ZwCreateKey(&svcKey, KEY_ALL_ACCESS, &oaSvc, 0, NULL, REG_OPTION_NON_VOLATILE, NULL);
    if (!NT_SUCCESS(st)) return;

    RtlInitUnicodeString(&prmName, L"Parameters");
    InitializeObjectAttributes(&oaPrm, &prmName, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, svcKey, NULL);
    st = ZwCreateKey(&prmKey, KEY_ALL_ACCESS, &oaPrm, 0, NULL, REG_OPTION_NON_VOLATILE, NULL);
    if (NT_SUCCESS(st)) {
        Bc250WriteDword(prmKey, L"Bc250ReachedDriverEntry", 1);
        Bc250WriteDword(prmKey, L"Bc250InitVersion", InitVersion);
        Bc250WriteDword(prmKey, L"Bc250InitSize", InitSize);
        Bc250WriteDword(prmKey, L"Bc250CallbackCount", CallbackCount);
        Bc250WriteDword(prmKey, L"Bc250CallbacksMask", CallbackMask);
        Bc250WriteDword(prmKey, L"Bc250BuildNtddi", NTDDI_VERSION);
        Bc250WriteDword(prmKey, L"Bc250BuildWin32Winnt", _WIN32_WINNT);
        Bc250WriteDword(prmKey, L"Bc250DxgkInterfaceVersionMacro", DXGKDDI_INTERFACE_VERSION);
        Bc250WriteDword(prmKey, L"Bc250DriverInitDataSize", (ULONG)sizeof(DRIVER_INITIALIZATION_DATA));
        Bc250WriteDword(prmKey, L"Bc250DxgkStatus", 0xFFFFFFFF);
        Bc250WriteDword(prmKey, L"Bc250Phase", 1);
        ZwClose(prmKey);
    }
    ZwClose(svcKey);
}

static VOID Bc250WritePost(_In_ PUNICODE_STRING RegistryPath, _In_ NTSTATUS Status)
{
    HANDLE svcKey = NULL;
    HANDLE prmKey = NULL;
    OBJECT_ATTRIBUTES oaSvc;
    OBJECT_ATTRIBUTES oaPrm;
    UNICODE_STRING prmName;
    NTSTATUS st;

    InitializeObjectAttributes(&oaSvc, RegistryPath, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
    st = ZwCreateKey(&svcKey, KEY_ALL_ACCESS, &oaSvc, 0, NULL, REG_OPTION_NON_VOLATILE, NULL);
    if (!NT_SUCCESS(st)) return;

    RtlInitUnicodeString(&prmName, L"Parameters");
    InitializeObjectAttributes(&oaPrm, &prmName, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, svcKey, NULL);
    st = ZwCreateKey(&prmKey, KEY_ALL_ACCESS, &oaPrm, 0, NULL, REG_OPTION_NON_VOLATILE, NULL);
    if (NT_SUCCESS(st)) {
        Bc250WriteDword(prmKey, L"Bc250DxgkStatus", (ULONG)Status);
        Bc250WriteDword(prmKey, L"Bc250Phase", 2);
        ZwClose(prmKey);
    }
    ZwClose(svcKey);
}

NTSTATUS APIENTRY BcAdd(_In_ CONST PDEVICE_OBJECT pdo, _Out_ PVOID* ctx){UNREFERENCED_PARAMETER(pdo); if(ctx){*ctx=(PVOID)1;} return STATUS_SUCCESS;}
NTSTATUS APIENTRY BcStart(_In_ CONST PVOID c,_In_ PDXGK_START_INFO s,_In_ PDXGKRNL_INTERFACE i,_Out_ PULONG src,_Out_ PULONG ch){UNREFERENCED_PARAMETER(c);UNREFERENCED_PARAMETER(s);UNREFERENCED_PARAMETER(i); if(src){*src=0;} if(ch){*ch=0;} return STATUS_SUCCESS;}
NTSTATUS APIENTRY BcStop(_In_ CONST PVOID c){UNREFERENCED_PARAMETER(c); return STATUS_SUCCESS;}
NTSTATUS APIENTRY BcRemove(_In_ CONST PVOID c){UNREFERENCED_PARAMETER(c); return STATUS_SUCCESS;}
NTSTATUS APIENTRY BcIo(_In_ CONST PVOID c,_In_ ULONG v,_Inout_ PVIDEO_REQUEST_PACKET p){UNREFERENCED_PARAMETER(c);UNREFERENCED_PARAMETER(v);UNREFERENCED_PARAMETER(p); return STATUS_NOT_SUPPORTED;}
NTSTATUS APIENTRY BcPower(_In_ CONST PVOID c,_In_ ULONG u,_In_ DEVICE_POWER_STATE d,_In_ POWER_ACTION a){UNREFERENCED_PARAMETER(c);UNREFERENCED_PARAMETER(u);UNREFERENCED_PARAMETER(d);UNREFERENCED_PARAMETER(a); return STATUS_SUCCESS;}
NTSTATUS APIENTRY BcQai(_In_ CONST PVOID c,_In_ CONST DXGKARG_QUERYADAPTERINFO* q){UNREFERENCED_PARAMETER(c);UNREFERENCED_PARAMETER(q); return STATUS_NOT_SUPPORTED;}
VOID APIENTRY BcUnload(VOID){}

NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath)
{
    DRIVER_INITIALIZATION_DATA init;
    ULONG mask = 0;
    NTSTATUS status;

    RtlZeroMemory(&init, sizeof(init));
    init.Version = 0x%INITVER%;
    init.DxgkDdiAddDevice = BcAdd; mask |= (1u<<0);
    init.DxgkDdiStartDevice = BcStart; mask |= (1u<<1);
    init.DxgkDdiStopDevice = BcStop; mask |= (1u<<2);
    init.DxgkDdiRemoveDevice = BcRemove; mask |= (1u<<3);
    init.DxgkDdiDispatchIoRequest = BcIo; mask |= (1u<<4);
    init.DxgkDdiSetPowerState = BcPower; mask |= (1u<<5);
    init.DxgkDdiUnload = BcUnload; mask |= (1u<<6);
    init.DxgkDdiQueryAdapterInfo = BcQai; mask |= (1u<<7);

    Bc250WritePre(RegistryPath, init.Version, (ULONG)sizeof(init), 8, mask);
    status = DxgkInitialize(DriverObject, RegistryPath, &init);
    Bc250WritePost(RegistryPath, status);
    return status;
}
"@

  $hex = ('{0:X4}' -f $InitVersion)
  $code = $code.Replace('%INITVER%', $hex)
  Set-Content -LiteralPath $srcPath -Value $code -Encoding ASCII
  L ("{0}|SOURCE_WRITTEN=1|INITVER=0x{1}" -f $Name, $hex)

  & $msbuild (Join-Path $ProjectRoot "amdbc250kmd.vcxproj") /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
  L ("{0}|BUILD_EXIT={1}" -f $Name, $LASTEXITCODE)
  if ($LASTEXITCODE -ne 0) { return }

  $sys = Join-Path $work ("{0}.sys" -f $Name)
  Remove-Item -LiteralPath $sys -Force -ErrorAction SilentlyContinue
  & $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$sys" "/LIBPATH:$kmLib" $objPath ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib *>> $log
  L ("{0}|LINK_EXIT={1}" -f $Name, $LASTEXITCODE)
  if ($LASTEXITCODE -eq 0 -and (Test-Path $sys)) {
      L ("{0}|SYS_HASH={1}" -f $Name, (HashOf $sys))
  }
}

Copy-Item -LiteralPath $srcPath -Destination $srcBak -Force
try {
  Run-Variant -Name 'R13_VER_0x4002' -InitVersion 0x4002
  Run-Variant -Name 'R20_VER_0x5023' -InitVersion 0x5023
  Run-Variant -Name 'R21_VER_0x6003' -InitVersion 0x6003
  Run-Variant -Name 'R27_VER_0xC004' -InitVersion 0xC004
}
finally {
  Copy-Item -LiteralPath $srcBak -Destination $srcPath -Force
  Remove-Item -LiteralPath $srcBak -Force -ErrorAction SilentlyContinue
  L 'SOURCE_RESTORED=1'
}

L ("WORK_DIR={0}" -f $work)
L 'N9RVER_DONE=1'
Get-Content $log -Tail 260
