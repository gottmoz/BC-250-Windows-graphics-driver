param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("n9def_build_{0}.log" -f $ts)
$work = Join-Path $ProjectRoot ("n9def_build_{0}" -f $ts)
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

function Run-Variant {
    param([string]$Name,[string]$Code)
    $marker = "N9_${Name}_$ts"
    Set-Content -LiteralPath $srcPath -Value ($Code.Replace("__N9_MARKER__", $marker)) -Encoding ASCII
    L ("{0}|SOURCE_WRITTEN=1" -f $Name)

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

$n9d = @"
#include <ntddk.h>
#include <dispmprt.h>
__declspec(selectany) const char N9D_MARKER[] = "__N9_MARKER__";
NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath)
{
    DRIVER_INITIALIZATION_DATA init;
    RtlZeroMemory(&init, sizeof(init));
    init.Version = DXGKDDI_INTERFACE_VERSION;
    return DxgkInitialize(DriverObject, RegistryPath, &init);
}
"@

$n9e = @"
#include <ntddk.h>
#include <dispmprt.h>
__declspec(selectany) const char N9E_MARKER[] = "__N9_MARKER__";
NTSTATUS APIENTRY N9eAddDevice(_In_ CONST PDEVICE_OBJECT PhysicalDeviceObject, _Out_ PVOID* MiniportDeviceContext){UNREFERENCED_PARAMETER(PhysicalDeviceObject); if(MiniportDeviceContext){*MiniportDeviceContext=(PVOID)1;} return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9eStartDevice(_In_ CONST PVOID MiniportDeviceContext,_In_ PDXGK_START_INFO DxgkStartInfo,_In_ PDXGKRNL_INTERFACE DxgkInterface,_Out_ PULONG NumberOfVideoPresentSources,_Out_ PULONG NumberOfChildren){UNREFERENCED_PARAMETER(MiniportDeviceContext);UNREFERENCED_PARAMETER(DxgkStartInfo);UNREFERENCED_PARAMETER(DxgkInterface); if(NumberOfVideoPresentSources){*NumberOfVideoPresentSources=0;} if(NumberOfChildren){*NumberOfChildren=0;} return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9eStopDevice(_In_ CONST PVOID MiniportDeviceContext){UNREFERENCED_PARAMETER(MiniportDeviceContext); return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9eRemoveDevice(_In_ CONST PVOID MiniportDeviceContext){UNREFERENCED_PARAMETER(MiniportDeviceContext); return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9eDispatchIoRequest(_In_ CONST PVOID MiniportDeviceContext,_In_ ULONG VidPnSourceId,_Inout_ PVIDEO_REQUEST_PACKET VideoRequestPacket){UNREFERENCED_PARAMETER(MiniportDeviceContext);UNREFERENCED_PARAMETER(VidPnSourceId);UNREFERENCED_PARAMETER(VideoRequestPacket); return STATUS_NOT_SUPPORTED;}
NTSTATUS APIENTRY N9eSetPowerState(_In_ CONST PVOID MiniportDeviceContext,_In_ ULONG DeviceUid,_In_ DEVICE_POWER_STATE DevicePowerState,_In_ POWER_ACTION ActionType){UNREFERENCED_PARAMETER(MiniportDeviceContext);UNREFERENCED_PARAMETER(DeviceUid);UNREFERENCED_PARAMETER(DevicePowerState);UNREFERENCED_PARAMETER(ActionType); return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9eQueryAdapterInfo(_In_ CONST PVOID MiniportDeviceContext,_In_ CONST DXGKARG_QUERYADAPTERINFO* pQueryAdapterInfo){UNREFERENCED_PARAMETER(MiniportDeviceContext);UNREFERENCED_PARAMETER(pQueryAdapterInfo); return STATUS_NOT_SUPPORTED;}
VOID APIENTRY N9eUnload(VOID){}
NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath)
{
    DRIVER_INITIALIZATION_DATA init;
    RtlZeroMemory(&init, sizeof(init));
    init.Version = DXGKDDI_INTERFACE_VERSION;
    init.DxgkDdiAddDevice = N9eAddDevice;
    init.DxgkDdiStartDevice = N9eStartDevice;
    init.DxgkDdiStopDevice = N9eStopDevice;
    init.DxgkDdiRemoveDevice = N9eRemoveDevice;
    init.DxgkDdiDispatchIoRequest = N9eDispatchIoRequest;
    init.DxgkDdiSetPowerState = N9eSetPowerState;
    init.DxgkDdiUnload = N9eUnload;
    init.DxgkDdiQueryAdapterInfo = N9eQueryAdapterInfo;
    return DxgkInitialize(DriverObject, RegistryPath, &init);
}
"@

$n9f = @"
#include <ntddk.h>
#include <dispmprt.h>
__declspec(selectany) const char N9F_MARKER[] = "__N9_MARKER__";
NTSTATUS APIENTRY N9fAddDevice(_In_ CONST PDEVICE_OBJECT PhysicalDeviceObject, _Out_ PVOID* MiniportDeviceContext){UNREFERENCED_PARAMETER(PhysicalDeviceObject); if(MiniportDeviceContext){*MiniportDeviceContext=(PVOID)1;} return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9fStartDevice(_In_ CONST PVOID MiniportDeviceContext,_In_ PDXGK_START_INFO DxgkStartInfo,_In_ PDXGKRNL_INTERFACE DxgkInterface,_Out_ PULONG NumberOfVideoPresentSources,_Out_ PULONG NumberOfChildren){UNREFERENCED_PARAMETER(MiniportDeviceContext);UNREFERENCED_PARAMETER(DxgkStartInfo);UNREFERENCED_PARAMETER(DxgkInterface); if(NumberOfVideoPresentSources){*NumberOfVideoPresentSources=0;} if(NumberOfChildren){*NumberOfChildren=0;} return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9fStopDevice(_In_ CONST PVOID MiniportDeviceContext){UNREFERENCED_PARAMETER(MiniportDeviceContext); return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9fRemoveDevice(_In_ CONST PVOID MiniportDeviceContext){UNREFERENCED_PARAMETER(MiniportDeviceContext); return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9fDispatchIoRequest(_In_ CONST PVOID MiniportDeviceContext,_In_ ULONG VidPnSourceId,_Inout_ PVIDEO_REQUEST_PACKET VideoRequestPacket){UNREFERENCED_PARAMETER(MiniportDeviceContext);UNREFERENCED_PARAMETER(VidPnSourceId);UNREFERENCED_PARAMETER(VideoRequestPacket); return STATUS_NOT_SUPPORTED;}
NTSTATUS APIENTRY N9fSetPowerState(_In_ CONST PVOID MiniportDeviceContext,_In_ ULONG DeviceUid,_In_ DEVICE_POWER_STATE DevicePowerState,_In_ POWER_ACTION ActionType){UNREFERENCED_PARAMETER(MiniportDeviceContext);UNREFERENCED_PARAMETER(DeviceUid);UNREFERENCED_PARAMETER(DevicePowerState);UNREFERENCED_PARAMETER(ActionType); return STATUS_SUCCESS;}
VOID APIENTRY N9fUnload(VOID){}
NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath)
{
    KMDDOD_INITIALIZATION_DATA init;
    RtlZeroMemory(&init, sizeof(init));
    init.Version = DXGKDDI_INTERFACE_VERSION;
    init.DxgkDdiAddDevice = N9fAddDevice;
    init.DxgkDdiStartDevice = N9fStartDevice;
    init.DxgkDdiStopDevice = N9fStopDevice;
    init.DxgkDdiRemoveDevice = N9fRemoveDevice;
    init.DxgkDdiDispatchIoRequest = N9fDispatchIoRequest;
    init.DxgkDdiSetPowerState = N9fSetPowerState;
    init.DxgkDdiUnload = N9fUnload;
    return DxgkInitializeDisplayOnlyDriver(DriverObject, RegistryPath, &init);
}
"@

Copy-Item -LiteralPath $srcPath -Destination $srcBak -Force
try {
    Run-Variant -Name "N9D_DXGK_EMPTY" -Code $n9d
    Run-Variant -Name "N9E_DXGK_MINCALLBACK" -Code $n9e
    Run-Variant -Name "N9F_DOD_MIN" -Code $n9f
}
finally {
    Copy-Item -LiteralPath $srcBak -Destination $srcPath -Force
    Remove-Item -LiteralPath $srcBak -Force -ErrorAction SilentlyContinue
    L "SOURCE_RESTORED=1"
}

L ("WORK_DIR={0}" -f $work)
L "N9DEF_DONE=1"
Get-Content $log -Tail 220
