param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("n9r_build_{0}.log" -f $ts)
$work = Join-Path $ProjectRoot ("n9r_build_{0}" -f $ts)
New-Item -ItemType Directory -Path $work -Force | Out-Null

$srcPath = Join-Path $ProjectRoot "amdbc250_kmd.c"
$srcBak = "$srcPath.bak_$ts"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$link = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe"
$kmLib = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64"
$objPath = Join-Path $ProjectRoot "build\Release\x64\amdbc250kmd\amdbc250_kmd.obj"

function L([string]$m) {
  ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) | Tee-Object -FilePath $log -Append
}
function HashOf([string]$p) {
  if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash }
  return "MISSING"
}

$code = @"
#include <ntddk.h>
#include <dispmprt.h>

__declspec(selectany) const char N9R_MARKER[] = "N9R_REG_BREADCRUMB___N9R_MARKER__";

#define BC250_TAG 'R9CB'

static VOID Bc250WriteDword(_In_ HANDLE Key, _In_ PCWSTR Name, _In_ ULONG Value)
{
    UNICODE_STRING vn;
    RtlInitUnicodeString(&vn, Name);
    ZwSetValueKey(Key, &vn, 0, REG_DWORD, &Value, sizeof(Value));
}

static VOID Bc250WriteBreadcrumbsPre(
    _In_ PUNICODE_STRING RegistryPath,
    _In_ ULONG InitVersion,
    _In_ ULONG InitSize,
    _In_ ULONG CallbackCount
)
{
    HANDLE svcKey = NULL;
    HANDLE prmKey = NULL;
    OBJECT_ATTRIBUTES oaSvc;
    OBJECT_ATTRIBUTES oaPrm;
    UNICODE_STRING prmName;
    NTSTATUS st;

    InitializeObjectAttributes(&oaSvc, RegistryPath, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
    st = ZwCreateKey(&svcKey, KEY_ALL_ACCESS, &oaSvc, 0, NULL, REG_OPTION_NON_VOLATILE, NULL);
    if (!NT_SUCCESS(st)) {
        return;
    }

    RtlInitUnicodeString(&prmName, L"Parameters");
    InitializeObjectAttributes(&oaPrm, &prmName, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, svcKey, NULL);
    st = ZwCreateKey(&prmKey, KEY_ALL_ACCESS, &oaPrm, 0, NULL, REG_OPTION_NON_VOLATILE, NULL);
    if (NT_SUCCESS(st)) {
        Bc250WriteDword(prmKey, L"Bc250ReachedDriverEntry", 1);
        Bc250WriteDword(prmKey, L"Bc250InitVersion", InitVersion);
        Bc250WriteDword(prmKey, L"Bc250InitSize", InitSize);
        Bc250WriteDword(prmKey, L"Bc250CallbackCount", CallbackCount);
        Bc250WriteDword(prmKey, L"Bc250DxgkStatus", 0xFFFFFFFF);
        Bc250WriteDword(prmKey, L"Bc250Phase", 1);
        ZwClose(prmKey);
    }
    ZwClose(svcKey);
}

static VOID Bc250WriteBreadcrumbsPost(
    _In_ PUNICODE_STRING RegistryPath,
    _In_ NTSTATUS Status
)
{
    HANDLE svcKey = NULL;
    HANDLE prmKey = NULL;
    OBJECT_ATTRIBUTES oaSvc;
    OBJECT_ATTRIBUTES oaPrm;
    UNICODE_STRING prmName;
    NTSTATUS st;
    ULONG s = (ULONG)Status;

    InitializeObjectAttributes(&oaSvc, RegistryPath, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
    st = ZwCreateKey(&svcKey, KEY_ALL_ACCESS, &oaSvc, 0, NULL, REG_OPTION_NON_VOLATILE, NULL);
    if (!NT_SUCCESS(st)) {
        return;
    }

    RtlInitUnicodeString(&prmName, L"Parameters");
    InitializeObjectAttributes(&oaPrm, &prmName, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, svcKey, NULL);
    st = ZwCreateKey(&prmKey, KEY_ALL_ACCESS, &oaPrm, 0, NULL, REG_OPTION_NON_VOLATILE, NULL);
    if (NT_SUCCESS(st)) {
        Bc250WriteDword(prmKey, L"Bc250DxgkStatus", s);
        Bc250WriteDword(prmKey, L"Bc250Phase", 2);
        ZwClose(prmKey);
    }
    ZwClose(svcKey);
}

NTSTATUS APIENTRY N9rAddDevice(_In_ CONST PDEVICE_OBJECT PhysicalDeviceObject, _Out_ PVOID* MiniportDeviceContext)
{ UNREFERENCED_PARAMETER(PhysicalDeviceObject); if (MiniportDeviceContext) { *MiniportDeviceContext = (PVOID)1; } return STATUS_SUCCESS; }
NTSTATUS APIENTRY N9rStartDevice(_In_ CONST PVOID MiniportDeviceContext,_In_ PDXGK_START_INFO DxgkStartInfo,_In_ PDXGKRNL_INTERFACE DxgkInterface,_Out_ PULONG NumberOfVideoPresentSources,_Out_ PULONG NumberOfChildren)
{ UNREFERENCED_PARAMETER(MiniportDeviceContext); UNREFERENCED_PARAMETER(DxgkStartInfo); UNREFERENCED_PARAMETER(DxgkInterface); if (NumberOfVideoPresentSources) { *NumberOfVideoPresentSources = 0; } if (NumberOfChildren) { *NumberOfChildren = 0; } return STATUS_SUCCESS; }
NTSTATUS APIENTRY N9rStopDevice(_In_ CONST PVOID MiniportDeviceContext)
{ UNREFERENCED_PARAMETER(MiniportDeviceContext); return STATUS_SUCCESS; }
NTSTATUS APIENTRY N9rRemoveDevice(_In_ CONST PVOID MiniportDeviceContext)
{ UNREFERENCED_PARAMETER(MiniportDeviceContext); return STATUS_SUCCESS; }
NTSTATUS APIENTRY N9rDispatchIoRequest(_In_ CONST PVOID MiniportDeviceContext,_In_ ULONG VidPnSourceId,_Inout_ PVIDEO_REQUEST_PACKET VideoRequestPacket)
{ UNREFERENCED_PARAMETER(MiniportDeviceContext); UNREFERENCED_PARAMETER(VidPnSourceId); UNREFERENCED_PARAMETER(VideoRequestPacket); return STATUS_NOT_SUPPORTED; }
NTSTATUS APIENTRY N9rSetPowerState(_In_ CONST PVOID MiniportDeviceContext,_In_ ULONG DeviceUid,_In_ DEVICE_POWER_STATE DevicePowerState,_In_ POWER_ACTION ActionType)
{ UNREFERENCED_PARAMETER(MiniportDeviceContext); UNREFERENCED_PARAMETER(DeviceUid); UNREFERENCED_PARAMETER(DevicePowerState); UNREFERENCED_PARAMETER(ActionType); return STATUS_SUCCESS; }
NTSTATUS APIENTRY N9rQueryAdapterInfo(_In_ CONST PVOID MiniportDeviceContext,_In_ CONST DXGKARG_QUERYADAPTERINFO* pQueryAdapterInfo)
{ UNREFERENCED_PARAMETER(MiniportDeviceContext); UNREFERENCED_PARAMETER(pQueryAdapterInfo); return STATUS_NOT_SUPPORTED; }
VOID APIENTRY N9rUnload(VOID) {}

NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath)
{
    DRIVER_INITIALIZATION_DATA init;
    ULONG callbackCount = 0;
    NTSTATUS status;

    RtlZeroMemory(&init, sizeof(init));
    init.Version = DXGKDDI_INTERFACE_VERSION;
    init.DxgkDdiAddDevice = N9rAddDevice; callbackCount++;
    init.DxgkDdiStartDevice = N9rStartDevice; callbackCount++;
    init.DxgkDdiStopDevice = N9rStopDevice; callbackCount++;
    init.DxgkDdiRemoveDevice = N9rRemoveDevice; callbackCount++;
    init.DxgkDdiDispatchIoRequest = N9rDispatchIoRequest; callbackCount++;
    init.DxgkDdiSetPowerState = N9rSetPowerState; callbackCount++;
    init.DxgkDdiUnload = N9rUnload; callbackCount++;
    init.DxgkDdiQueryAdapterInfo = N9rQueryAdapterInfo; callbackCount++;

    Bc250WriteBreadcrumbsPre(RegistryPath, init.Version, (ULONG)sizeof(init), callbackCount);
    status = DxgkInitialize(DriverObject, RegistryPath, &init);
    Bc250WriteBreadcrumbsPost(RegistryPath, status);
    return status;
}
"@

Copy-Item -LiteralPath $srcPath -Destination $srcBak -Force
$marker = "N9R_$ts"
Set-Content -LiteralPath $srcPath -Value ($code.Replace("__N9R_MARKER__", $marker)) -Encoding ASCII
L "SOURCE_WRITTEN=1"
L ("MARKER={0}" -f $marker)
try {
  & $msbuild (Join-Path $ProjectRoot "amdbc250kmd.vcxproj") /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
  L ("BUILD_EXIT={0}" -f $LASTEXITCODE)
  if ($LASTEXITCODE -ne 0) { throw "Build failed" }

  $sys = Join-Path $work "N9R_DXGK_BREADCRUMB.sys"
  Remove-Item -LiteralPath $sys -Force -ErrorAction SilentlyContinue
  & $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$sys" "/LIBPATH:$kmLib" $objPath ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib *>> $log
  L ("LINK_EXIT={0}" -f $LASTEXITCODE)
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $sys)) { throw "Link failed" }
  L ("SYS_HASH={0}" -f (HashOf $sys))
  L ("WORK_DIR={0}" -f $work)
}
finally {
  if (Test-Path $srcBak) {
    Copy-Item -LiteralPath $srcBak -Destination $srcPath -Force
    Remove-Item -LiteralPath $srcBak -Force -ErrorAction SilentlyContinue
  }
  L "SOURCE_RESTORED=1"
}

L "N9R_BUILD_DONE=1"
Get-Content $log -Tail 240
