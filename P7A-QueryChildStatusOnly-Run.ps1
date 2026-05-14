$ErrorActionPreference='Stop'
$repo='C:\Dev\windows-driver-samples\video\KMDOD'
$bdd=Join-Path $repo 'bdd_ddi.cxx'
$bak="$bdd.q2bak"
if(-not (Test-Path $bak)){ throw "Missing backup: $bak" }
$callbackBlock = @"
    InitialData.DxgkDdiAddDevice                    = BddDdiAddDevice;
    InitialData.DxgkDdiStartDevice                  = BddDdiStartDevice;
    InitialData.DxgkDdiStopDevice                   = BddDdiStopDevice;
    InitialData.DxgkDdiResetDevice                  = BddDdiResetDevice;
    InitialData.DxgkDdiRemoveDevice                 = BddDdiRemoveDevice;
    InitialData.DxgkDdiDispatchIoRequest            = BddDdiDispatchIoRequest;
    InitialData.DxgkDdiSetPowerState                = BddDdiSetPowerState;
    InitialData.DxgkDdiUnload                       = BddDdiUnload;
    InitialData.DxgkDdiQueryAdapterInfo             = BddDdiQueryAdapterInfo;
    InitialData.DxgkDdiQueryChildRelations          = BddDdiQueryChildRelations;
    InitialData.DxgkDdiQueryChildStatus             = BddDdiQueryChildStatus;
    InitialData.DxgkDdiQueryDeviceDescriptor        = BddDdiQueryDeviceDescriptor;
    InitialData.DxgkDdiIsSupportedVidPn             = BddDdiIsSupportedVidPn;
    InitialData.DxgkDdiRecommendFunctionalVidPn     = BddDdiRecommendFunctionalVidPn;
    InitialData.DxgkDdiEnumVidPnCofuncModality      = BddDdiEnumVidPnCofuncModality;
"@

function Build-And-RunProfile {
  Copy-Item $bak $bdd -Force
  $raw = Get-Content -Path $bdd -Raw

  $helper = @"

typedef struct _BC250_DOD_DUMMY_CONTEXT {
    ULONG Magic;
    PDEVICE_OBJECT PhysicalDeviceObject;
} BC250_DOD_DUMMY_CONTEXT, *PBC250_DOD_DUMMY_CONTEXT;

static VOID Q2WriteDword(_In_ HANDLE key, _In_ PCWSTR name, _In_ ULONG value)
{
    UNICODE_STRING u;
    RtlInitUnicodeString(&u, name);
    ZwSetValueKey(key, &u, 0, REG_DWORD, &value, sizeof(value));
}

static VOID Q2WriteParamDword(_In_ PCWSTR name, _In_ ULONG value)
{
    UNICODE_STRING path, prmName, valName;
    OBJECT_ATTRIBUTES oaSvc, oaPrm;
    HANDLE hSvc = NULL, hPrm = NULL;
    RtlInitUnicodeString(&path, L"\\Registry\\Machine\\System\\CurrentControlSet\\Services\\amdbc250kmd");
    InitializeObjectAttributes(&oaSvc, &path, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
    if (!NT_SUCCESS(ZwOpenKey(&hSvc, KEY_READ | KEY_WRITE, &oaSvc))) { return; }
    RtlInitUnicodeString(&prmName, L"Parameters");
    InitializeObjectAttributes(&oaPrm, &prmName, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, hSvc, NULL);
    if (NT_SUCCESS(ZwCreateKey(&hPrm, KEY_ALL_ACCESS, &oaPrm, 0, NULL, REG_OPTION_NON_VOLATILE, NULL))) {
        RtlInitUnicodeString(&valName, name);
        ZwSetValueKey(hPrm, &valName, 0, REG_DWORD, &value, sizeof(value));
        ZwClose(hPrm);
    }
    ZwClose(hSvc);
}

static VOID Q2MarkCb(_In_ ULONG cbid, _In_ ULONG status)
{
    Q2WriteParamDword(L"SampleR_LastCb", cbid);
    Q2WriteParamDword(L"SampleR_LastStatus", status);
}

static VOID Q2SampleBreadcrumb(_In_ PUNICODE_STRING RegistryPath, _In_ ULONG phase, _In_ ULONG initApi, _In_ ULONG initVer, _In_ ULONG initSize, _In_ ULONG cbCount, _In_ ULONG status)
{
    HANDLE svcKey = NULL, prmKey = NULL;
    OBJECT_ATTRIBUTES oaSvc, oaPrm;
    UNICODE_STRING prmName;
    InitializeObjectAttributes(&oaSvc, RegistryPath, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
    if (!NT_SUCCESS(ZwCreateKey(&svcKey, KEY_ALL_ACCESS, &oaSvc, 0, NULL, REG_OPTION_NON_VOLATILE, NULL))) { return; }
    RtlInitUnicodeString(&prmName, L"Parameters");
    InitializeObjectAttributes(&oaPrm, &prmName, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, svcKey, NULL);
    if (NT_SUCCESS(ZwCreateKey(&prmKey, KEY_ALL_ACCESS, &oaPrm, 0, NULL, REG_OPTION_NON_VOLATILE, NULL))) {
        Q2WriteDword(prmKey, L"SampleReachedDriverEntry", 1);
        Q2WriteDword(prmKey, L"SampleLastPhase", phase);
        Q2WriteDword(prmKey, L"SampleInitApi", initApi);
        Q2WriteDword(prmKey, L"SampleInitVersion", initVer);
        Q2WriteDword(prmKey, L"SampleInitSize", initSize);
        Q2WriteDword(prmKey, L"SampleCallbackCount", cbCount);
        Q2WriteDword(prmKey, L"SampleDxgkStatus", status);
        ZwClose(prmKey);
    }
    ZwClose(svcKey);
}
"@

  $raw = $raw.Replace('#include "BDD.hxx"', "#include ""BDD.hxx""$helper")
  $raw = [Regex]::Replace($raw, 'InitialData\.DxgkDdiAddDevice[\s\S]*?InitialData\.DxgkDdiSystemDisplayWrite\s*=\s*BddDdiSystemDisplayWrite;\r?\n', $callbackBlock, [System.Text.RegularExpressions.RegexOptions]::Singleline)
  $raw = [Regex]::Replace($raw, 'DriverEntry\([\s\S]*?\{\r?\n\s*PAGED_CODE\(\);', '$0' + "`r`n`r`n    Q2SampleBreadcrumb(pRegistryPath, 1, 2, 0, 0, 15, 0);", [System.Text.RegularExpressions.RegexOptions]::Singleline)
  $replaceCall = @"
Q2SampleBreadcrumb(pRegistryPath, 2, 2, (ULONG)InitialData.Version, (ULONG)sizeof(InitialData), 15, 0);
    NTSTATUS Status = DxgkInitializeDisplayOnlyDriver(pDriverObject, pRegistryPath, &InitialData);
    Q2SampleBreadcrumb(pRegistryPath, 3, 2, (ULONG)InitialData.Version, (ULONG)sizeof(InitialData), 15, (ULONG)Status);
"@
  $raw = $raw -replace 'NTSTATUS Status = DxgkInitializeDisplayOnlyDriver\(pDriverObject, pRegistryPath, &InitialData\);', $replaceCall

  $raw = [Regex]::Replace($raw, 'NTSTATUS\r?\nBddDdiAddDevice\([\s\S]*?\r?\n\}\r?\n\r?\nNTSTATUS\r?\nBddDdiRemoveDevice\(', @"
NTSTATUS
BddDdiAddDevice(
    _In_ DEVICE_OBJECT* pPhysicalDeviceObject,
    _Outptr_ PVOID*  ppDeviceContext)
{
    PAGED_CODE();
    Q2WriteParamDword(L"SampleO_AddEnter", 1);
    if ((pPhysicalDeviceObject == NULL) || (ppDeviceContext == NULL)) { Q2MarkCb(10, STATUS_INVALID_PARAMETER); return STATUS_INVALID_PARAMETER; }
    *ppDeviceContext = NULL;
    PBC250_DOD_DUMMY_CONTEXT Ctx = (PBC250_DOD_DUMMY_CONTEXT)ExAllocatePoolWithTag(NonPagedPoolNx, sizeof(*Ctx), 'D52B');
    if (Ctx == NULL) { Q2MarkCb(10, STATUS_NO_MEMORY); return STATUS_NO_MEMORY; }
    RtlZeroMemory(Ctx, sizeof(*Ctx));
    Ctx->Magic = 0x44353242;
    Ctx->PhysicalDeviceObject = pPhysicalDeviceObject;
    *ppDeviceContext = (PVOID)Ctx;
    Q2WriteParamDword(L"SampleO_AddStatus", STATUS_SUCCESS);
    Q2MarkCb(10, STATUS_SUCCESS);
    return STATUS_SUCCESS;
}

NTSTATUS
BddDdiRemoveDevice(
"@, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $raw = [Regex]::Replace($raw, 'NTSTATUS\r?\nBddDdiStartDevice\([\s\S]*?\r?\n\}\r?\n\r?\nNTSTATUS\r?\nBddDdiStopDevice\(', @"
NTSTATUS
BddDdiStartDevice(
    _In_  VOID*              MiniportDeviceContext,
    _In_  DXGK_START_INFO*   DxgkStartInfo,
    _In_  DXGKRNL_INTERFACE* DxgkInterface,
    _Out_ ULONG*             NumberOfVideoPresentSources,
    _Out_ ULONG*             NumberOfChildren)
{
    PAGED_CODE();
    Q2WriteParamDword(L"SampleO_StartEnter", 1);
    if (!MiniportDeviceContext || !DxgkStartInfo || !DxgkInterface || !NumberOfVideoPresentSources || !NumberOfChildren) { Q2MarkCb(20, STATUS_INVALID_PARAMETER); return STATUS_INVALID_PARAMETER; }
    *NumberOfVideoPresentSources = 1;
    *NumberOfChildren = 1;
    Q2WriteParamDword(L"SampleO_StartViews", 1);
    Q2WriteParamDword(L"SampleO_StartChildren", 1);
    Q2WriteParamDword(L"SampleO_StartStatus", STATUS_SUCCESS);
    Q2MarkCb(20, STATUS_SUCCESS);
    return STATUS_SUCCESS;
}

NTSTATUS
BddDdiStopDevice(
"@, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $raw = [Regex]::Replace($raw, 'NTSTATUS\r?\nBddDdiQueryChildRelations\([\s\S]*?\r?\n\}\r?\n\r?\nNTSTATUS\r?\nBddDdiQueryChildStatus\(', @"
NTSTATUS
BddDdiQueryChildRelations(
    _In_                             VOID*                  pDeviceContext,
    _Out_writes_bytes_(ChildRelationsSize) DXGK_CHILD_DESCRIPTOR* pChildRelations,
    _In_                             ULONG                  ChildRelationsSize)
{
    PAGED_CODE();
    UNREFERENCED_PARAMETER(pDeviceContext);
    UNREFERENCED_PARAMETER(pChildRelations);
    UNREFERENCED_PARAMETER(ChildRelationsSize);
    Q2MarkCb(101, STATUS_SUCCESS);
    return STATUS_SUCCESS;
}

NTSTATUS
BddDdiQueryChildStatus(
"@, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $raw = [Regex]::Replace($raw, 'NTSTATUS\r?\nBddDdiQueryChildStatus\([\s\S]*?\r?\n\}\r?\n\r?\nNTSTATUS\r?\nBddDdiQueryDeviceDescriptor\(', @"
NTSTATUS
BddDdiQueryChildStatus(
    _In_    VOID*              pDeviceContext,
    _Inout_ DXGK_CHILD_STATUS* pChildStatus,
    _In_    BOOLEAN            NonDestructiveOnly)
{
    PAGED_CODE();
    UNREFERENCED_PARAMETER(pDeviceContext);
    UNREFERENCED_PARAMETER(NonDestructiveOnly);
    Q2WriteParamDword(L"SampleP_QueryChildStatusEnter", 1);

    if (pChildStatus == NULL) {
        Q2WriteParamDword(L"SampleP_QueryChildStatusStatus", STATUS_INVALID_PARAMETER);
        Q2MarkCb(102, STATUS_INVALID_PARAMETER);
        return STATUS_INVALID_PARAMETER;
    }

    Q2WriteParamDword(L"SampleP_QueryChildStatusChildUid", pChildStatus->ChildUid);
    Q2WriteParamDword(L"SampleP_QueryChildStatusType", (ULONG)pChildStatus->Type);

    if (pChildStatus->ChildUid != 0) {
        Q2WriteParamDword(L"SampleP_QueryChildStatusStatus", STATUS_INVALID_PARAMETER);
        Q2MarkCb(102, STATUS_INVALID_PARAMETER);
        return STATUS_INVALID_PARAMETER;
    }

    if (pChildStatus->Type == StatusConnection) {
        pChildStatus->HotPlug.Connected = TRUE;
        Q2WriteParamDword(L"SampleP_QueryChildStatusStatus", STATUS_SUCCESS);
        Q2MarkCb(102, STATUS_SUCCESS);
        return STATUS_SUCCESS;
    }

    Q2WriteParamDword(L"SampleP_QueryChildStatusStatus", STATUS_NOT_SUPPORTED);
    Q2MarkCb(102, STATUS_NOT_SUPPORTED);
    return STATUS_NOT_SUPPORTED;
}

NTSTATUS
BddDdiQueryDeviceDescriptor(
"@, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $raw = [Regex]::Replace($raw, 'NTSTATUS\r?\nBddDdiQueryDeviceDescriptor\([\s\S]*?\r?\n\}\r?\n\r?\n//\r?\n// WDDM Display Only Driver DDIs', @"
NTSTATUS
BddDdiQueryDeviceDescriptor(
    _In_  VOID*                     pDeviceContext,
    _In_  ULONG                     ChildUid,
    _Inout_ DXGK_DEVICE_DESCRIPTOR* pDeviceDescriptor)
{
    PAGED_CODE();
    UNREFERENCED_PARAMETER(pDeviceContext);
    UNREFERENCED_PARAMETER(ChildUid);
    UNREFERENCED_PARAMETER(pDeviceDescriptor);
    Q2MarkCb(103, STATUS_GRAPHICS_CHILD_DESCRIPTOR_NOT_SUPPORTED);
    return STATUS_GRAPHICS_CHILD_DESCRIPTOR_NOT_SUPPORTED;
}

//
// WDDM Display Only Driver DDIs
"@, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  Set-Content -Path $bdd -Value $raw -Encoding ASCII

  $proj='C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay.vcxproj'
  $msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
  & $msbuild $proj /t:Build /p:Configuration=Release /p:Platform=x64 /p:WindowsTargetPlatformVersion=10.0.19041.0 /v:minimal
  if($LASTEXITCODE -ne 0){ throw "Build failed" }

  $ts=Get-Date -Format yyyyMMdd_HHmmss
  $out="C:\Dev\BC250-windowsDriverTest\p7a_$ts"
  New-Item -ItemType Directory -Path $out -Force | Out-Null
  $rel='C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay\x64\Release'
  $link='C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe'
  $lib='C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64'
  $sys=Join-Path $out 'P7A_query_child_status_only.sys'
  $objs=@('BDD.obj','BDD_DDI.obj','BDD_DMM.obj','BDD_Util.obj','BltFuncs.obj','BltHw.obj','memory.obj','sampledisplay.res') | ForEach-Object { Join-Path $rel $_ }
  & $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$sys" "/LIBPATH:$lib" $objs ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib
  if($LASTEXITCODE -ne 0){ throw "Link failed" }
  Write-Output ("RUN_PROFILE=P7A|SYS={0}" -f $sys)
  & 'C:\Dev\BC250-windowsDriverTest\P0-N9C-PnpBind-Hashed-NoReboot.ps1' -ProjectRoot 'C:\Dev\BC250-windowsDriverTest' -N9Dir $out -N9SysName 'P7A_query_child_status_only.sys'
}

Build-And-RunProfile
