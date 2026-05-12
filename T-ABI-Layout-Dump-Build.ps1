param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("t_abi_dump_build_{0}.log" -f $ts)
$work = Join-Path $ProjectRoot ("t_abi_dump_build_{0}" -f $ts)
New-Item -ItemType Directory -Path $work -Force | Out-Null

$srcPath = Join-Path $ProjectRoot "amdbc250_kmd.c"
$srcBak = "$srcPath.bak_$ts"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$link = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe"
$kmLib = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64"
$objPath = Join-Path $ProjectRoot "build\Release\x64\amdbc250kmd\amdbc250_kmd.obj"

function L([string]$m) { ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) | Tee-Object -FilePath $log -Append }
function HashOf([string]$p) { if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash } return "MISSING" }

$code = @"
#include <ntddk.h>
#include <dispmprt.h>

__declspec(selectany) const char T_ABI_MARKER[] = "T_ABI_LAYOUT_DUMP_%TS%";

#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0
#endif

static VOID Wd(_In_ HANDLE k, _In_ PCWSTR n, _In_ ULONG v){UNICODE_STRING u; RtlInitUnicodeString(&u,n); ZwSetValueKey(k,&u,0,REG_DWORD,&v,sizeof(v));}

static VOID DumpAbi(_In_ PUNICODE_STRING RegistryPath)
{
    HANDLE svcKey=NULL, prmKey=NULL;
    OBJECT_ATTRIBUTES oaSvc, oaPrm;
    UNICODE_STRING prmName;
    NTSTATUS st;

    InitializeObjectAttributes(&oaSvc, RegistryPath, OBJ_CASE_INSENSITIVE|OBJ_KERNEL_HANDLE, NULL, NULL);
    st = ZwCreateKey(&svcKey, KEY_ALL_ACCESS, &oaSvc, 0, NULL, REG_OPTION_NON_VOLATILE, NULL);
    if(!NT_SUCCESS(st)) return;

    RtlInitUnicodeString(&prmName, L"Parameters");
    InitializeObjectAttributes(&oaPrm, &prmName, OBJ_CASE_INSENSITIVE|OBJ_KERNEL_HANDLE, svcKey, NULL);
    st = ZwCreateKey(&prmKey, KEY_ALL_ACCESS, &oaPrm, 0, NULL, REG_OPTION_NON_VOLATILE, NULL);
    if (NT_SUCCESS(st)) {
        Wd(prmKey, L"Bc250AbiDumpPresent", 1);
        Wd(prmKey, L"Bc250BuildNtddi", NTDDI_VERSION);
        Wd(prmKey, L"Bc250BuildWin32Winnt", _WIN32_WINNT);
        Wd(prmKey, L"Bc250DxgkInterfaceVersionMacro", DXGKDDI_INTERFACE_VERSION);

        Wd(prmKey, L"AbiSize_DRIVER_INITIALIZATION_DATA", (ULONG)sizeof(DRIVER_INITIALIZATION_DATA));
        Wd(prmKey, L"AbiSize_KMDDOD_INITIALIZATION_DATA", (ULONG)sizeof(KMDDOD_INITIALIZATION_DATA));

        Wd(prmKey, L"AbiOff_DRV_AddDevice", FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiAddDevice));
        Wd(prmKey, L"AbiOff_DRV_StartDevice", FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiStartDevice));
        Wd(prmKey, L"AbiOff_DRV_QueryAdapterInfo", FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiQueryAdapterInfo));
        Wd(prmKey, L"AbiOff_DRV_SetVidPnSourceAddress", FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiSetVidPnSourceAddress));
        Wd(prmKey, L"AbiOff_DRV_ControlInterrupt", FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiControlInterrupt));
        Wd(prmKey, L"AbiOff_DRV_QueryVidPnHWCapability", FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiQueryVidPnHWCapability));

        Wd(prmKey, L"AbiOff_DOD_AddDevice", FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiAddDevice));
        Wd(prmKey, L"AbiOff_DOD_StartDevice", FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiStartDevice));
        Wd(prmKey, L"AbiOff_DOD_QueryAdapterInfo", FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiQueryAdapterInfo));
        Wd(prmKey, L"AbiOff_DOD_ControlInterrupt", FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiControlInterrupt));
        Wd(prmKey, L"AbiOff_DOD_QueryVidPnHWCapability", FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiQueryVidPnHWCapability));
        Wd(prmKey, L"AbiOff_DOD_PresentDisplayOnly", FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiPresentDisplayOnly));

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
    NTSTATUS status;

    DumpAbi(RegistryPath);

    RtlZeroMemory(&init, sizeof(init));
    init.Version = 0x4002;
    init.DxgkDdiAddDevice = BcAdd;
    init.DxgkDdiStartDevice = BcStart;
    init.DxgkDdiStopDevice = BcStop;
    init.DxgkDdiRemoveDevice = BcRemove;
    init.DxgkDdiDispatchIoRequest = BcIo;
    init.DxgkDdiSetPowerState = BcPower;
    init.DxgkDdiUnload = BcUnload;
    init.DxgkDdiQueryAdapterInfo = BcQai;

    status = DxgkInitialize(DriverObject, RegistryPath, &init);
    return status;
}
"@

$code = $code.Replace('%TS%', $ts)
Copy-Item -LiteralPath $srcPath -Destination $srcBak -Force
try {
    Set-Content -LiteralPath $srcPath -Value $code -Encoding ASCII
    L 'SOURCE_WRITTEN=1'

    & $msbuild (Join-Path $ProjectRoot 'amdbc250kmd.vcxproj') /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
    L ("BUILD_EXIT={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { throw 'Build failed' }

    $sys = Join-Path $work 'T_ABI_LAYOUT_DUMP.sys'
    Remove-Item -LiteralPath $sys -Force -ErrorAction SilentlyContinue
    & $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$sys" "/LIBPATH:$kmLib" $objPath ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib *>> $log
    L ("LINK_EXIT={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $sys)) { throw 'Link failed' }
    L ("SYS_HASH={0}" -f (HashOf $sys))
    L ("WORK_DIR={0}" -f $work)
}
finally {
    Copy-Item -LiteralPath $srcBak -Destination $srcPath -Force
    Remove-Item -LiteralPath $srcBak -Force -ErrorAction SilentlyContinue
    L 'SOURCE_RESTORED=1'
}

L 'T_ABI_BUILD_DONE=1'
Get-Content $log -Tail 220
