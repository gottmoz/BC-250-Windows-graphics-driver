param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("n9s_shape_build_{0}.log" -f $ts)
$work = Join-Path $ProjectRoot ("n9s_shape_build_{0}" -f $ts)
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
  param(
    [string]$Name,
    [UInt32]$InitVersion,
    [int]$ShapeId
  )

  $marker = "N9S_${Name}_$ts"
  $code = @"
#include <ntddk.h>
#include <dispmprt.h>

__declspec(selectany) const char N9S_MARKER[] = "$marker";

#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0
#endif

#define BC_SHAPE_ID %SHAPE_ID%
#define BC_INIT_VERSION 0x%INITVER%

static VOID BcWriteDword(_In_ HANDLE Key, _In_ PCWSTR Name, _In_ ULONG Value)
{
    UNICODE_STRING vn;
    RtlInitUnicodeString(&vn, Name);
    ZwSetValueKey(Key, &vn, 0, REG_DWORD, &Value, sizeof(Value));
}

static VOID BcWritePre(_In_ PUNICODE_STRING RegistryPath, _In_ ULONG StructKind, _In_ ULONG InitVersion, _In_ ULONG InitSize, _In_ ULONG CallbackCount, _In_ ULONG CallbackMask, _In_ ULONG FirstOff, _In_ ULONG LastOff)
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
        BcWriteDword(prmKey, L"Bc250ShapeId", BC_SHAPE_ID);
        BcWriteDword(prmKey, L"Bc250InitStructKind", StructKind);
        BcWriteDword(prmKey, L"Bc250ReachedDriverEntry", 1);
        BcWriteDword(prmKey, L"Bc250InitVersion", InitVersion);
        BcWriteDword(prmKey, L"Bc250InitSize", InitSize);
        BcWriteDword(prmKey, L"Bc250CallbackCount", CallbackCount);
        BcWriteDword(prmKey, L"Bc250CallbacksMask", CallbackMask);
        BcWriteDword(prmKey, L"Bc250FirstNonNullOffset", FirstOff);
        BcWriteDword(prmKey, L"Bc250LastNonNullOffset", LastOff);
        BcWriteDword(prmKey, L"Bc250BuildNtddi", NTDDI_VERSION);
        BcWriteDword(prmKey, L"Bc250BuildWin32Winnt", _WIN32_WINNT);
        BcWriteDword(prmKey, L"Bc250DxgkInterfaceVersionMacro", DXGKDDI_INTERFACE_VERSION);
        BcWriteDword(prmKey, L"Bc250DriverInitDataSize", (ULONG)sizeof(DRIVER_INITIALIZATION_DATA));
        BcWriteDword(prmKey, L"Bc250DxgkStatus", 0xFFFFFFFF);
        BcWriteDword(prmKey, L"Bc250Phase", 1);
        ZwClose(prmKey);
    }
    ZwClose(svcKey);
}

static VOID BcWritePost(_In_ PUNICODE_STRING RegistryPath, _In_ NTSTATUS Status)
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
        BcWriteDword(prmKey, L"Bc250DxgkStatus", (ULONG)Status);
        BcWriteDword(prmKey, L"Bc250Phase", 2);
        ZwClose(prmKey);
    }
    ZwClose(svcKey);
}

static VOID BcMark(_In_ ULONG off, _Inout_ PULONG first, _Inout_ PULONG last, _Inout_ PULONG count)
{
    if (*first == 0xFFFFFFFF) { *first = off; }
    *last = off;
    *count = *count + 1;
}

NTSTATUS APIENTRY BcAdd(_In_ CONST PDEVICE_OBJECT pdo, _Out_ PVOID* ctx){UNREFERENCED_PARAMETER(pdo); if(ctx){*ctx=(PVOID)1;} return STATUS_SUCCESS;}
NTSTATUS APIENTRY BcStart(_In_ CONST PVOID c,_In_ PDXGK_START_INFO s,_In_ PDXGKRNL_INTERFACE i,_Out_ PULONG src,_Out_ PULONG ch){UNREFERENCED_PARAMETER(c);UNREFERENCED_PARAMETER(s);UNREFERENCED_PARAMETER(i); if(src){*src=0;} if(ch){*ch=0;} return STATUS_SUCCESS;}
NTSTATUS APIENTRY BcStop(_In_ CONST PVOID c){UNREFERENCED_PARAMETER(c); return STATUS_SUCCESS;}
NTSTATUS APIENTRY BcRemove(_In_ CONST PVOID c){UNREFERENCED_PARAMETER(c); return STATUS_SUCCESS;}
NTSTATUS APIENTRY BcIo(_In_ CONST PVOID c,_In_ ULONG v,_Inout_ PVIDEO_REQUEST_PACKET p){UNREFERENCED_PARAMETER(c);UNREFERENCED_PARAMETER(v);UNREFERENCED_PARAMETER(p); return STATUS_NOT_SUPPORTED;}
NTSTATUS APIENTRY BcPower(_In_ CONST PVOID c,_In_ ULONG u,_In_ DEVICE_POWER_STATE d,_In_ POWER_ACTION a){UNREFERENCED_PARAMETER(c);UNREFERENCED_PARAMETER(u);UNREFERENCED_PARAMETER(d);UNREFERENCED_PARAMETER(a); return STATUS_SUCCESS;}
NTSTATUS APIENTRY BcQai(_In_ CONST PVOID c,_In_ CONST DXGKARG_QUERYADAPTERINFO* q){UNREFERENCED_PARAMETER(c);UNREFERENCED_PARAMETER(q); return STATUS_NOT_SUPPORTED;}
VOID APIENTRY BcUnload(VOID){}

NTSTATUS APIENTRY StubNtStatus(VOID){ return STATUS_SUCCESS; }
NTSTATUS APIENTRY StubNtNotSupported(VOID){ return STATUS_NOT_SUPPORTED; }
BOOLEAN APIENTRY StubBool(VOID){ return TRUE; }
VOID APIENTRY StubVoid(VOID){ }

NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath)
{
    NTSTATUS status;
    ULONG firstOff = 0xFFFFFFFF;
    ULONG lastOff = 0;
    ULONG count = 0;
    ULONG mask = 0;

    if (BC_SHAPE_ID == 4) {
        KMDDOD_INITIALIZATION_DATA init;
        RtlZeroMemory(&init, sizeof(init));
        init.Version = BC_INIT_VERSION;

        init.DxgkDdiAddDevice = BcAdd; mask |= (1u<<0); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiAddDevice), &firstOff, &lastOff, &count);
        init.DxgkDdiStartDevice = BcStart; mask |= (1u<<1); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiStartDevice), &firstOff, &lastOff, &count);
        init.DxgkDdiStopDevice = BcStop; mask |= (1u<<2); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiStopDevice), &firstOff, &lastOff, &count);
        init.DxgkDdiRemoveDevice = BcRemove; mask |= (1u<<3); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiRemoveDevice), &firstOff, &lastOff, &count);
        init.DxgkDdiDispatchIoRequest = BcIo; mask |= (1u<<4); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiDispatchIoRequest), &firstOff, &lastOff, &count);
        init.DxgkDdiSetPowerState = BcPower; mask |= (1u<<5); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiSetPowerState), &firstOff, &lastOff, &count);
        init.DxgkDdiUnload = BcUnload; mask |= (1u<<6); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiUnload), &firstOff, &lastOff, &count);
        init.DxgkDdiQueryAdapterInfo = BcQai; mask |= (1u<<7); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiQueryAdapterInfo), &firstOff, &lastOff, &count);

        init.DxgkDdiQueryChildRelations = (PDXGKDDI_QUERY_CHILD_RELATIONS)StubNtStatus; mask |= (1u<<8); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiQueryChildRelations), &firstOff, &lastOff, &count);
        init.DxgkDdiQueryChildStatus = (PDXGKDDI_QUERY_CHILD_STATUS)StubNtStatus; mask |= (1u<<9); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiQueryChildStatus), &firstOff, &lastOff, &count);
        init.DxgkDdiQueryDeviceDescriptor = (PDXGKDDI_QUERY_DEVICE_DESCRIPTOR)StubNtStatus; mask |= (1u<<10); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiQueryDeviceDescriptor), &firstOff, &lastOff, &count);
        init.DxgkDdiIsSupportedVidPn = (PDXGKDDI_ISSUPPORTEDVIDPN)StubNtStatus; mask |= (1u<<11); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiIsSupportedVidPn), &firstOff, &lastOff, &count);
        init.DxgkDdiRecommendFunctionalVidPn = (PDXGKDDI_RECOMMENDFUNCTIONALVIDPN)StubNtStatus; mask |= (1u<<12); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiRecommendFunctionalVidPn), &firstOff, &lastOff, &count);
        init.DxgkDdiEnumVidPnCofuncModality = (PDXGKDDI_ENUMVIDPNCOFUNCMODALITY)StubNtStatus; mask |= (1u<<13); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiEnumVidPnCofuncModality), &firstOff, &lastOff, &count);
        init.DxgkDdiCommitVidPn = (PDXGKDDI_COMMITVIDPN)StubNtStatus; mask |= (1u<<14); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiCommitVidPn), &firstOff, &lastOff, &count);
        init.DxgkDdiSetVidPnSourceVisibility = (PDXGKDDI_SETVIDPNSOURCEVISIBILITY)StubNtStatus; mask |= (1u<<15); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiSetVidPnSourceVisibility), &firstOff, &lastOff, &count);
        init.DxgkDdiUpdateActiveVidPnPresentPath = (PDXGKDDI_UPDATEACTIVEVIDPNPRESENTPATH)StubNtStatus; mask |= (1u<<16); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiUpdateActiveVidPnPresentPath), &firstOff, &lastOff, &count);
        init.DxgkDdiRecommendMonitorModes = (PDXGKDDI_RECOMMENDMONITORMODES)StubNtStatus; mask |= (1u<<17); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiRecommendMonitorModes), &firstOff, &lastOff, &count);
        init.DxgkDdiQueryVidPnHWCapability = (PDXGKDDI_QUERYVIDPNHWCAPABILITY)StubNtStatus; mask |= (1u<<18); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiQueryVidPnHWCapability), &firstOff, &lastOff, &count);
        init.DxgkDdiGetScanLine = (PDXGKDDI_GETSCANLINE)StubNtStatus; mask |= (1u<<19); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiGetScanLine), &firstOff, &lastOff, &count);
        init.DxgkDdiControlInterrupt = (PDXGKDDI_CONTROLINTERRUPT)StubNtStatus; mask |= (1u<<20); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiControlInterrupt), &firstOff, &lastOff, &count);
        init.DxgkDdiPresentDisplayOnly = (PDXGKDDI_PRESENTDISPLAYONLY)StubNtStatus; mask |= (1u<<21); BcMark(FIELD_OFFSET(KMDDOD_INITIALIZATION_DATA, DxgkDdiPresentDisplayOnly), &firstOff, &lastOff, &count);

        BcWritePre(RegistryPath, 2, init.Version, (ULONG)sizeof(init), count, mask, firstOff, lastOff);
        status = DxgkInitializeDisplayOnlyDriver(DriverObject, RegistryPath, &init);
        BcWritePost(RegistryPath, status);
        return status;
    }
    else {
        DRIVER_INITIALIZATION_DATA init;
        RtlZeroMemory(&init, sizeof(init));
        init.Version = BC_INIT_VERSION;

        if (BC_SHAPE_ID >= 1) {
            init.DxgkDdiAddDevice = BcAdd; mask |= (1u<<0); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiAddDevice), &firstOff, &lastOff, &count);
            init.DxgkDdiStartDevice = BcStart; mask |= (1u<<1); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiStartDevice), &firstOff, &lastOff, &count);
            init.DxgkDdiStopDevice = BcStop; mask |= (1u<<2); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiStopDevice), &firstOff, &lastOff, &count);
            init.DxgkDdiRemoveDevice = BcRemove; mask |= (1u<<3); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiRemoveDevice), &firstOff, &lastOff, &count);
        }
        if (BC_SHAPE_ID >= 2) {
            init.DxgkDdiDispatchIoRequest = BcIo; mask |= (1u<<4); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiDispatchIoRequest), &firstOff, &lastOff, &count);
            init.DxgkDdiSetPowerState = BcPower; mask |= (1u<<5); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiSetPowerState), &firstOff, &lastOff, &count);
            init.DxgkDdiUnload = BcUnload; mask |= (1u<<6); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiUnload), &firstOff, &lastOff, &count);
        }
        if (BC_SHAPE_ID >= 3) {
            init.DxgkDdiQueryAdapterInfo = BcQai; mask |= (1u<<7); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiQueryAdapterInfo), &firstOff, &lastOff, &count);
        }
        if (BC_SHAPE_ID >= 5) {
            init.DxgkDdiQueryChildRelations = (PDXGKDDI_QUERY_CHILD_RELATIONS)StubNtStatus; mask |= (1u<<8); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiQueryChildRelations), &firstOff, &lastOff, &count);
            init.DxgkDdiQueryChildStatus = (PDXGKDDI_QUERY_CHILD_STATUS)StubNtStatus; mask |= (1u<<9); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiQueryChildStatus), &firstOff, &lastOff, &count);
            init.DxgkDdiQueryDeviceDescriptor = (PDXGKDDI_QUERY_DEVICE_DESCRIPTOR)StubNtStatus; mask |= (1u<<10); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiQueryDeviceDescriptor), &firstOff, &lastOff, &count);
            init.DxgkDdiIsSupportedVidPn = (PDXGKDDI_ISSUPPORTEDVIDPN)StubNtStatus; mask |= (1u<<11); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiIsSupportedVidPn), &firstOff, &lastOff, &count);
            init.DxgkDdiRecommendFunctionalVidPn = (PDXGKDDI_RECOMMENDFUNCTIONALVIDPN)StubNtStatus; mask |= (1u<<12); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiRecommendFunctionalVidPn), &firstOff, &lastOff, &count);
            init.DxgkDdiEnumVidPnCofuncModality = (PDXGKDDI_ENUMVIDPNCOFUNCMODALITY)StubNtStatus; mask |= (1u<<13); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiEnumVidPnCofuncModality), &firstOff, &lastOff, &count);
            init.DxgkDdiCommitVidPn = (PDXGKDDI_COMMITVIDPN)StubNtStatus; mask |= (1u<<14); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiCommitVidPn), &firstOff, &lastOff, &count);
            init.DxgkDdiSetVidPnSourceAddress = (PDXGKDDI_SETVIDPNSOURCEADDRESS)StubNtStatus; mask |= (1u<<15); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiSetVidPnSourceAddress), &firstOff, &lastOff, &count);
            init.DxgkDdiSetVidPnSourceVisibility = (PDXGKDDI_SETVIDPNSOURCEVISIBILITY)StubNtStatus; mask |= (1u<<16); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiSetVidPnSourceVisibility), &firstOff, &lastOff, &count);
            init.DxgkDdiRecommendMonitorModes = (PDXGKDDI_RECOMMENDMONITORMODES)StubNtStatus; mask |= (1u<<17); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiRecommendMonitorModes), &firstOff, &lastOff, &count);
            init.DxgkDdiQueryVidPnHWCapability = (PDXGKDDI_QUERYVIDPNHWCAPABILITY)StubNtStatus; mask |= (1u<<18); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiQueryVidPnHWCapability), &firstOff, &lastOff, &count);
            init.DxgkDdiGetScanLine = (PDXGKDDI_GETSCANLINE)StubNtStatus; mask |= (1u<<19); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiGetScanLine), &firstOff, &lastOff, &count);
            init.DxgkDdiControlInterrupt = (PDXGKDDI_CONTROLINTERRUPT)StubNtStatus; mask |= (1u<<20); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiControlInterrupt), &firstOff, &lastOff, &count);
            init.DxgkDdiUpdateActiveVidPnPresentPath = (PDXGKDDI_UPDATEACTIVEVIDPNPRESENTPATH)StubNtStatus; mask |= (1u<<21); BcMark(FIELD_OFFSET(DRIVER_INITIALIZATION_DATA, DxgkDdiUpdateActiveVidPnPresentPath), &firstOff, &lastOff, &count);
        }

        BcWritePre(RegistryPath, 1, init.Version, (ULONG)sizeof(init), count, mask, firstOff, lastOff);
        status = DxgkInitialize(DriverObject, RegistryPath, &init);
        BcWritePost(RegistryPath, status);
        return status;
    }
}
"@

  $hex = ('{0:X4}' -f $InitVersion)
  $code = $code.Replace('%INITVER%', $hex)
  $code = $code.Replace('%SHAPE_ID%', [string]$ShapeId)

  Set-Content -LiteralPath $srcPath -Value $code -Encoding ASCII
  L ("{0}|SOURCE_WRITTEN=1|SHAPE={1}|INITVER=0x{2}" -f $Name, $ShapeId, $hex)

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
  Run-Variant -Name 'S0_EMPTY_V4002' -InitVersion 0x4002 -ShapeId 0
  Run-Variant -Name 'S1_LIFECYCLE_V4002' -InitVersion 0x4002 -ShapeId 1
  Run-Variant -Name 'S2_LIFE_PWR_IO_V4002' -InitVersion 0x4002 -ShapeId 2
  Run-Variant -Name 'S3_PLUS_QAI_V4002' -InitVersion 0x4002 -ShapeId 3
  Run-Variant -Name 'S4_DODLIKE_V4002' -InitVersion 0x4002 -ShapeId 4
  Run-Variant -Name 'S5_FULLDISP_V4002' -InitVersion 0x4002 -ShapeId 5
  Run-Variant -Name 'S3_PLUS_QAI_VC004' -InitVersion 0xC004 -ShapeId 3
  Run-Variant -Name 'S4_DODLIKE_VC004' -InitVersion 0xC004 -ShapeId 4
}
finally {
  Copy-Item -LiteralPath $srcBak -Destination $srcPath -Force
  Remove-Item -LiteralPath $srcBak -Force -ErrorAction SilentlyContinue
  L 'SOURCE_RESTORED=1'
}

L ("WORK_DIR={0}" -f $work)
L 'N9S_DONE=1'
Get-Content $log -Tail 320
