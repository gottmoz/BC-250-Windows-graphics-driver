param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("n9_entryonly_{0}.log" -f $ts)
$work = Join-Path $ProjectRoot ("n9_entryonly_{0}" -f $ts)
New-Item -ItemType Directory -Path $work -Force | Out-Null

$srcPath = Join-Path $ProjectRoot "amdbc250_kmd.c"
$srcBak = "$srcPath.bak_$ts"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$link = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe"
$dumpbin = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
$objPath = Join-Path $ProjectRoot "build\Release\x64\amdbc250kmd\amdbc250_kmd.obj"
$kmLib = "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64"
$pkg = Join-Path $ProjectRoot "build\Release\x64\package\amdbc250kmd.sys"

function L([string]$m) {
    ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) | Tee-Object -FilePath $log -Append
}

function HashOf([string]$p) {
    if (Test-Path $p) { return (Get-FileHash $p -Algorithm SHA256).Hash }
    return "MISSING"
}

function HasMarker([string]$p, [string]$mk) {
    if (-not (Test-Path $p)) { return $false }
    try {
        $a = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($p))
        return $a.Contains($mk)
    }
    catch { return $false }
}

function Remove-ServiceSafe([string]$n) {
    sc.exe stop $n *>> $log
    sc.exe delete $n *>> $log
}

function Run-N9Variant {
    param(
        [string]$Name,
        [string]$Code
    )

    $marker = "N9_${Name}_$ts"
    $variantCode = $Code.Replace("__N9_MARKER__", $marker)
    Set-Content -LiteralPath $srcPath -Value $variantCode -Encoding ASCII
    L ("{0}|SOURCE_WRITTEN=1" -f $Name)

    & $msbuild (Join-Path $ProjectRoot "amdbc250kmd.vcxproj") /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
    L ("{0}|BUILD_EXIT={1}" -f $Name, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { return }

    if (-not (Test-Path $objPath)) {
        L ("{0}|OBJ_MISSING=1" -f $Name)
        return
    }
    L ("{0}|OBJ_HASH={1}" -f $Name, (HashOf $objPath))

    $aSys = Join-Path $work ("{0}.sys" -f $Name)
    Remove-Item -LiteralPath $aSys -Force -ErrorAction SilentlyContinue

    & $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$aSys" "/LIBPATH:$kmLib" $objPath ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib *>> $log
    L ("{0}|LINK_EXIT={1}" -f $Name, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $aSys)) { return }

    $aPre = HashOf $aSys
    $hasM = HasMarker $aSys $marker
    L ("{0}|A_PRE={1}|MARKER={2}" -f $Name, $aPre, $hasM)
    if (-not $hasM) {
        L ("{0}|SKIP_NO_MARKER=1" -f $Name)
        return
    }

    & $signtool sign /fd sha256 /f C:\bc250new.pfx /p bc250 $aSys *>> $log
    L ("{0}|SIGN_EXIT={1}" -f $Name, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { return }

    $aPost = HashOf $aSys
    $svc = ("n9_{0}_{1}" -f $Name.ToLower(), $ts)
    $cSys = "C:\Windows\System32\drivers\$svc.sys"
    Copy-Item -LiteralPath $aSys -Destination $cSys -Force
    $cHash = HashOf $cSys
    $eq = ($aPost -eq $cHash)
    L ("{0}|A_POST={1}|C_HASH={2}|A_EQ_C={3}|B_HASH={4}" -f $Name, $aPost, $cHash, $eq, (HashOf $pkg))
    if (-not $eq) {
        L ("{0}|SKIP_HASH_MISMATCH=1" -f $Name)
        return
    }

    Remove-ServiceSafe $svc
    sc.exe create $svc type= kernel start= demand error= normal binPath= ("\SystemRoot\System32\drivers\$svc.sys") DisplayName= ("BC250 $svc") *>> $log
    sc.exe start $svc *>> $log
    L ("{0}|SC_START_EXIT={1}" -f $Name, $LASTEXITCODE)
    Start-Sleep -Seconds 2
    sc.exe query $svc *>> $log

    if (Test-Path $dumpbin) {
        & $dumpbin /imports $aSys *> (Join-Path $work ("{0}_imports.txt" -f $Name))
        & $dumpbin /headers $aSys *> (Join-Path $work ("{0}_headers.txt" -f $Name))
        & $dumpbin /loadconfig $aSys *> (Join-Path $work ("{0}_loadconfig.txt" -f $Name))
    }

    Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = (Get-Date).AddMinutes(-5) } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match "Service Control Manager|Kernel-PnP" -or $_.Message -match $svc } |
        Select-Object -First 10 TimeCreated, Id, ProviderName, Message |
        Format-List * |
        Out-String -Width 4096 |
        Add-Content $log

    sc.exe stop $svc *>> $log
    sc.exe delete $svc *>> $log
    Remove-Item -LiteralPath $cSys -Force -ErrorAction SilentlyContinue
}

L "LOG=$log"
L "NO_REBOOT=1"

$n9a = @"
typedef long NTSTATUS;
typedef void* PVOID;
#define STATUS_SUCCESS ((NTSTATUS)0x00000000L)
__declspec(selectany) const char N9A_MARKER[] = "__N9_MARKER__";
NTSTATUS DriverEntry(PVOID DriverObject, PVOID RegistryPath){(void)DriverObject;(void)RegistryPath; return STATUS_SUCCESS;}
"@

$n9b = @"
#include <ntddk.h>
#include <dispmprt.h>
__declspec(selectany) const char N9B_MARKER[] = "__N9_MARKER__";
VOID N9bUnload(_In_ PDRIVER_OBJECT DriverObject){UNREFERENCED_PARAMETER(DriverObject);}
NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath){UNREFERENCED_PARAMETER(RegistryPath); DriverObject->DriverUnload = N9bUnload; return STATUS_SUCCESS;}
"@

$n9c = @"
#include <ntddk.h>
#include <dispmprt.h>
__declspec(selectany) const char N9C_MARKER[] = "__N9_MARKER__";

NTSTATUS APIENTRY N9cAddDevice(_In_ CONST PDEVICE_OBJECT PhysicalDeviceObject, _Out_ PVOID* MiniportDeviceContext){UNREFERENCED_PARAMETER(PhysicalDeviceObject); if(MiniportDeviceContext){*MiniportDeviceContext=(PVOID)1;} return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9cStartDevice(_In_ CONST PVOID MiniportDeviceContext,_In_ PDXGK_START_INFO DxgkStartInfo,_In_ PDXGKRNL_INTERFACE DxgkInterface,_Out_ PULONG NumberOfVideoPresentSources,_Out_ PULONG NumberOfChildren){UNREFERENCED_PARAMETER(MiniportDeviceContext);UNREFERENCED_PARAMETER(DxgkStartInfo);UNREFERENCED_PARAMETER(DxgkInterface); if(NumberOfVideoPresentSources){*NumberOfVideoPresentSources=0;} if(NumberOfChildren){*NumberOfChildren=0;} return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9cStopDevice(_In_ CONST PVOID MiniportDeviceContext){UNREFERENCED_PARAMETER(MiniportDeviceContext); return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9cRemoveDevice(_In_ CONST PVOID MiniportDeviceContext){UNREFERENCED_PARAMETER(MiniportDeviceContext); return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9cDispatchIoRequest(_In_ CONST PVOID MiniportDeviceContext,_In_ ULONG VidPnSourceId,_Inout_ PVIDEO_REQUEST_PACKET VideoRequestPacket){UNREFERENCED_PARAMETER(MiniportDeviceContext);UNREFERENCED_PARAMETER(VidPnSourceId);UNREFERENCED_PARAMETER(VideoRequestPacket); return STATUS_NOT_SUPPORTED;}
NTSTATUS APIENTRY N9cSetPowerState(_In_ CONST PVOID MiniportDeviceContext,_In_ ULONG DeviceUid,_In_ DEVICE_POWER_STATE DevicePowerState,_In_ POWER_ACTION ActionType){UNREFERENCED_PARAMETER(MiniportDeviceContext);UNREFERENCED_PARAMETER(DeviceUid);UNREFERENCED_PARAMETER(DevicePowerState);UNREFERENCED_PARAMETER(ActionType); return STATUS_SUCCESS;}
NTSTATUS APIENTRY N9cQueryAdapterInfo(_In_ CONST PVOID MiniportDeviceContext,_In_ CONST DXGKARG_QUERYADAPTERINFO* pQueryAdapterInfo){UNREFERENCED_PARAMETER(MiniportDeviceContext);UNREFERENCED_PARAMETER(pQueryAdapterInfo); return STATUS_NOT_SUPPORTED;}
VOID APIENTRY N9cUnload(VOID){}

NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath)
{
    DRIVER_INITIALIZATION_DATA init;
    RtlZeroMemory(&init, sizeof(init));
    init.Version = DXGKDDI_INTERFACE_VERSION;
    init.DxgkDdiAddDevice = N9cAddDevice;
    init.DxgkDdiStartDevice = N9cStartDevice;
    init.DxgkDdiStopDevice = N9cStopDevice;
    init.DxgkDdiRemoveDevice = N9cRemoveDevice;
    init.DxgkDdiDispatchIoRequest = N9cDispatchIoRequest;
    init.DxgkDdiSetPowerState = N9cSetPowerState;
    init.DxgkDdiUnload = N9cUnload;
    init.DxgkDdiQueryAdapterInfo = N9cQueryAdapterInfo;
    return DxgkInitialize(DriverObject, RegistryPath, &init);
}
"@

Copy-Item -LiteralPath $srcPath -Destination $srcBak -Force
try {
    Run-N9Variant -Name "N9A_ENTRYONLY_NO_DXGK" -Code $n9a
    Run-N9Variant -Name "N9B_ENTRYONLY_DISPMPRT_NO_DXGK" -Code $n9b
    Run-N9Variant -Name "N9C_ENTRYONLY_DXGK_MIN" -Code $n9c
}
finally {
    Copy-Item -LiteralPath $srcBak -Destination $srcPath -Force
    Remove-Item -LiteralPath $srcBak -Force -ErrorAction SilentlyContinue
    L "SOURCE_RESTORED=1"
}

L "N9_DONE=1"
Get-Content $log -Tail 360
