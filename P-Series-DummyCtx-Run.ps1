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
  param(
    [string]$Name,
    [string]$StartMode, # fail|11|00
    [int]$CbCount = 15
  )

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
    if (!NT_SUCCESS(ZwOpenKey(&hSvc, KEY_READ | KEY_WRITE, &oaSvc)))
    {
        return;
    }

    RtlInitUnicodeString(&prmName, L"Parameters");
    InitializeObjectAttributes(&oaPrm, &prmName, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, hSvc, NULL);
    if (NT_SUCCESS(ZwCreateKey(&hPrm, KEY_ALL_ACCESS, &oaPrm, 0, NULL, REG_OPTION_NON_VOLATILE, NULL)))
    {
        RtlInitUnicodeString(&valName, name);
        ZwSetValueKey(hPrm, &valName, 0, REG_DWORD, &value, sizeof(value));
        ZwClose(hPrm);
    }

    ZwClose(hSvc);
}

static VOID Q2SampleBreadcrumb(_In_ PUNICODE_STRING RegistryPath, _In_ ULONG phase, _In_ ULONG initApi, _In_ ULONG initVer, _In_ ULONG initSize, _In_ ULONG cbCount, _In_ ULONG status)
{
    HANDLE svcKey = NULL, prmKey = NULL;
    OBJECT_ATTRIBUTES oaSvc, oaPrm;
    UNICODE_STRING prmName;

    InitializeObjectAttributes(&oaSvc, RegistryPath, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
    if (!NT_SUCCESS(ZwCreateKey(&svcKey, KEY_ALL_ACCESS, &oaSvc, 0, NULL, REG_OPTION_NON_VOLATILE, NULL)))
    {
        return;
    }

    RtlInitUnicodeString(&prmName, L"Parameters");
    InitializeObjectAttributes(&oaPrm, &prmName, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, svcKey, NULL);
    if (NT_SUCCESS(ZwCreateKey(&prmKey, KEY_ALL_ACCESS, &oaPrm, 0, NULL, REG_OPTION_NON_VOLATILE, NULL)))
    {
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

  $patCallbacks = 'InitialData\.DxgkDdiAddDevice[\s\S]*?InitialData\.DxgkDdiSystemDisplayWrite\s*=\s*BddDdiSystemDisplayWrite;\r?\n'
  $raw = [Regex]::Replace($raw, $patCallbacks, $callbackBlock, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $driverEntryPat = 'DriverEntry\([\s\S]*?\{\r?\n\s*PAGED_CODE\(\);'
  $driverEntryRepl = '$0' + "`r`n`r`n    Q2SampleBreadcrumb(pRegistryPath, 1, 2, 0, 0, $CbCount, 0);"
  $raw = [Regex]::Replace($raw, $driverEntryPat, $driverEntryRepl, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $replaceCall = @"
Q2SampleBreadcrumb(pRegistryPath, 2, 2, (ULONG)InitialData.Version, (ULONG)sizeof(InitialData), $CbCount, 0);
    NTSTATUS Status = DxgkInitializeDisplayOnlyDriver(pDriverObject, pRegistryPath, &InitialData);
    Q2SampleBreadcrumb(pRegistryPath, 3, 2, (ULONG)InitialData.Version, (ULONG)sizeof(InitialData), $CbCount, (ULONG)Status);
"@
  $raw = $raw -replace 'NTSTATUS Status = DxgkInitializeDisplayOnlyDriver\(pDriverObject, pRegistryPath, &InitialData\);', $replaceCall

  $addBody = @"
NTSTATUS
BddDdiAddDevice(
    _In_ DEVICE_OBJECT* pPhysicalDeviceObject,
    _Outptr_ PVOID*  ppDeviceContext)
{
    PAGED_CODE();
    Q2WriteParamDword(L"SampleO_AddEnter", 1);
    Q2WriteParamDword(L"SampleO_AddIrql", (ULONG)KeGetCurrentIrql());

    if ((pPhysicalDeviceObject == NULL) || (ppDeviceContext == NULL))
    {
        Q2WriteParamDword(L"SampleO_AddStatus", STATUS_INVALID_PARAMETER);
        return STATUS_INVALID_PARAMETER;
    }

    *ppDeviceContext = NULL;

    PBC250_DOD_DUMMY_CONTEXT Ctx = (PBC250_DOD_DUMMY_CONTEXT)ExAllocatePoolWithTag(NonPagedPoolNx, sizeof(*Ctx), 'D52B');
    if (Ctx == NULL)
    {
        Q2WriteParamDword(L"SampleO_AddStatus", STATUS_NO_MEMORY);
        return STATUS_NO_MEMORY;
    }

    RtlZeroMemory(Ctx, sizeof(*Ctx));
    Ctx->Magic = 0x44353242;
    Ctx->PhysicalDeviceObject = pPhysicalDeviceObject;
    *ppDeviceContext = (PVOID)Ctx;

    Q2WriteParamDword(L"SampleO_AddCtxPtrLow", (ULONG)((ULONG_PTR)Ctx & 0xFFFFFFFF));
    Q2WriteParamDword(L"SampleO_AddCtxPtrHigh", (ULONG)(((ULONG_PTR)Ctx >> 32) & 0xFFFFFFFF));
    Q2WriteParamDword(L"SampleO_AddOutPtrLow", (ULONG)((ULONG_PTR)ppDeviceContext & 0xFFFFFFFF));
    Q2WriteParamDword(L"SampleO_AddOutPtrHigh", (ULONG)(((ULONG_PTR)ppDeviceContext >> 32) & 0xFFFFFFFF));
    Q2WriteParamDword(L"SampleO_AddStatus", STATUS_SUCCESS);
    return STATUS_SUCCESS;
}
"@
  $raw = [Regex]::Replace($raw, 'NTSTATUS\r?\nBddDdiAddDevice\([\s\S]*?\r?\n\}\r?\n\r?\nNTSTATUS\r?\nBddDdiRemoveDevice\(', "$addBody`r`nNTSTATUS`r`nBddDdiRemoveDevice(", [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $removeBody = @"
NTSTATUS
BddDdiRemoveDevice(
    _In_  VOID* pDeviceContext)
{
    PAGED_CODE();
    Q2WriteParamDword(L"SampleO_RemoveEnter", 1);
    if (pDeviceContext != NULL)
    {
        ExFreePoolWithTag(pDeviceContext, 'D52B');
    }
    return STATUS_SUCCESS;
}
"@
  $raw = [Regex]::Replace($raw, 'NTSTATUS\r?\nBddDdiRemoveDevice\([\s\S]*?\r?\n\}\r?\n\r?\nNTSTATUS\r?\nBddDdiStartDevice\(', "$removeBody`r`nNTSTATUS`r`nBddDdiStartDevice(", [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $startOverride = @"
    Q2WriteParamDword(L"SampleO_StartStatus", STATUS_UNSUCCESSFUL);
    return STATUS_UNSUCCESSFUL;
"@
  if($StartMode -eq '11'){
    $startOverride = @"
    if (!MiniportDeviceContext || !DxgkStartInfo || !DxgkInterface || !NumberOfVideoPresentSources || !NumberOfChildren) {
        Q2WriteParamDword(L"SampleO_StartStatus", STATUS_INVALID_PARAMETER);
        return STATUS_INVALID_PARAMETER;
    }
    *NumberOfVideoPresentSources = 1;
    *NumberOfChildren = 1;
    Q2WriteParamDword(L"SampleO_StartViews", 1);
    Q2WriteParamDword(L"SampleO_StartChildren", 1);
    Q2WriteParamDword(L"SampleO_StartStatus", STATUS_SUCCESS);
    return STATUS_SUCCESS;
"@
  } elseif($StartMode -eq '00'){
    $startOverride = @"
    if (!MiniportDeviceContext || !DxgkStartInfo || !DxgkInterface || !NumberOfVideoPresentSources || !NumberOfChildren) {
        Q2WriteParamDword(L"SampleO_StartStatus", STATUS_INVALID_PARAMETER);
        return STATUS_INVALID_PARAMETER;
    }
    *NumberOfVideoPresentSources = 0;
    *NumberOfChildren = 0;
    Q2WriteParamDword(L"SampleO_StartViews", 0);
    Q2WriteParamDword(L"SampleO_StartChildren", 0);
    Q2WriteParamDword(L"SampleO_StartStatus", STATUS_SUCCESS);
    return STATUS_SUCCESS;
"@
  }

  $startBody = @"
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
    Q2WriteParamDword(L"SampleO_StartIrql", (ULONG)KeGetCurrentIrql());
__START_OVERRIDE__
}
"@
  $startBody = $startBody.Replace('__START_OVERRIDE__',$startOverride)
  $raw = [Regex]::Replace($raw, 'NTSTATUS\r?\nBddDdiStartDevice\([\s\S]*?\r?\n\}\r?\n\r?\nNTSTATUS\r?\nBddDdiStopDevice\(', "$startBody`r`nNTSTATUS`r`nBddDdiStopDevice(", [System.Text.RegularExpressions.RegexOptions]::Singleline)

  Set-Content -Path $bdd -Value $raw -Encoding ASCII

  $proj='C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay.vcxproj'
  $msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
  & $msbuild $proj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /p:WindowsTargetPlatformVersion=10.0.19041.0 /v:minimal
  if($LASTEXITCODE -ne 0){ throw "Build failed for $Name" }

  $ts=Get-Date -Format yyyyMMdd_HHmmss
  $out="C:\Dev\BC250-windowsDriverTest\p_${Name}_$ts"
  New-Item -ItemType Directory -Path $out -Force | Out-Null

  $rel='C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay\x64\Release'
  $link='C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe'
  $lib='C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64'
  $sys=Join-Path $out ("P_${Name}.sys")
  $objs=@('BDD.obj','BDD_DDI.obj','BDD_DMM.obj','BDD_Util.obj','BltFuncs.obj','BltHw.obj','memory.obj','sampledisplay.res') | ForEach-Object { Join-Path $rel $_ }
  & $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$sys" "/LIBPATH:$lib" $objs ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib
  if($LASTEXITCODE -ne 0){ throw "Link failed for $Name" }

  Write-Host ("RUN_PROFILE=$Name|START=$StartMode|SYS=$sys")
  & 'C:\Dev\BC250-windowsDriverTest\P0-N9C-PnpBind-Hashed-NoReboot.ps1' -ProjectRoot 'C:\Dev\BC250-windowsDriverTest' -N9Dir $out -N9SysName ("P_${Name}.sys")
}

Build-And-RunProfile -Name 'P1' -StartMode 'fail'
Build-And-RunProfile -Name 'P2' -StartMode '11'
Build-And-RunProfile -Name 'P3' -StartMode '00'
