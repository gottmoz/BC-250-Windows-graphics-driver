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
    [string]$AddMode,   # normal|nomem
    [string]$StartMode, # orig|11|00|fail
    [int]$CbCount
  )

  Copy-Item $bak $bdd -Force
  $raw = Get-Content -Path $bdd -Raw

  $helper = @"

static VOID Q2WriteDword(_In_ HANDLE key, _In_ PCWSTR name, _In_ ULONG value)
{
    UNICODE_STRING u;
    RtlInitUnicodeString(&u, name);
    ZwSetValueKey(key, &u, 0, REG_DWORD, &value, sizeof(value));
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

  $addForce = ''
  if($AddMode -eq 'nomem'){
    $addForce = @"
    Q2WriteParamDword(L"SampleO_AddStatus", STATUS_NO_MEMORY);
    return STATUS_NO_MEMORY;
"@
  }

  $addBody = @"
NTSTATUS
BddDdiAddDevice(
    _In_ DEVICE_OBJECT* pPhysicalDeviceObject,
    _Outptr_ PVOID*  ppDeviceContext)
{
    PAGED_CODE();
    Q2WriteParamDword(L"SampleO_AddEnter", 1);

    if ((pPhysicalDeviceObject == NULL) ||
        (ppDeviceContext == NULL))
    {
        Q2WriteParamDword(L"SampleO_AddStatus", STATUS_INVALID_PARAMETER);
        return STATUS_INVALID_PARAMETER;
    }
    *ppDeviceContext = NULL;
__ADD_FORCE__
    BASIC_DISPLAY_DRIVER* pBDD = new(NonPagedPoolNx) BASIC_DISPLAY_DRIVER(pPhysicalDeviceObject);
    if (pBDD == NULL)
    {
        Q2WriteParamDword(L"SampleO_AddStatus", STATUS_NO_MEMORY);
        return STATUS_NO_MEMORY;
    }

    *ppDeviceContext = pBDD;
    Q2WriteParamDword(L"SampleO_AddStatus", STATUS_SUCCESS);
    return STATUS_SUCCESS;
}
"@
  $addBody = $addBody.Replace('__ADD_FORCE__',$addForce)
  $raw = [Regex]::Replace($raw, 'NTSTATUS\r?\nBddDdiAddDevice\([\s\S]*?\r?\n\}\r?\n\r?\nNTSTATUS\r?\nBddDdiRemoveDevice\(', "$addBody`r`nNTSTATUS`r`nBddDdiRemoveDevice(", [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $startOverride = @"
    BASIC_DISPLAY_DRIVER* pBDD = reinterpret_cast<BASIC_DISPLAY_DRIVER*>(pDeviceContext);
    return pBDD->StartDevice(pDxgkStartInfo, pDxgkInterface, pNumberOfViews, pNumberOfChildren);
"@
  if($StartMode -eq '11'){
    $startOverride = @"
    if (pNumberOfViews) { *pNumberOfViews = 1; }
    if (pNumberOfChildren) { *pNumberOfChildren = 1; }
    Q2WriteParamDword(L"SampleO_StartViews", 1);
    Q2WriteParamDword(L"SampleO_StartChildren", 1);
    Q2WriteParamDword(L"SampleO_StartStatus", STATUS_SUCCESS);
    return STATUS_SUCCESS;
"@
  } elseif($StartMode -eq '00'){
    $startOverride = @"
    if (pNumberOfViews) { *pNumberOfViews = 0; }
    if (pNumberOfChildren) { *pNumberOfChildren = 0; }
    Q2WriteParamDword(L"SampleO_StartViews", 0);
    Q2WriteParamDword(L"SampleO_StartChildren", 0);
    Q2WriteParamDword(L"SampleO_StartStatus", STATUS_SUCCESS);
    return STATUS_SUCCESS;
"@
  } elseif($StartMode -eq 'fail'){
    $startOverride = @"
    Q2WriteParamDword(L"SampleO_StartStatus", STATUS_UNSUCCESSFUL);
    return STATUS_UNSUCCESSFUL;
"@
  }

  $startBody = @"
NTSTATUS
BddDdiStartDevice(
    _In_  VOID*              pDeviceContext,
    _In_  DXGK_START_INFO*   pDxgkStartInfo,
    _In_  DXGKRNL_INTERFACE* pDxgkInterface,
    _Out_ ULONG*             pNumberOfViews,
    _Out_ ULONG*             pNumberOfChildren)
{
    PAGED_CODE();
    BDD_ASSERT_CHK(pDeviceContext != NULL);
    Q2WriteParamDword(L"SampleO_StartEnter", 1);

__START_OVERRIDE__
}
"@
  $startBody = $startBody.Replace('__START_OVERRIDE__',$startOverride)
  $raw = [Regex]::Replace($raw, 'NTSTATUS\r?\nBddDdiStartDevice\([\s\S]*?\r?\n\}\r?\n\r?\nNTSTATUS\r?\nBddDdiStopDevice\(', "$startBody`r`nNTSTATUS`r`nBddDdiStopDevice(", [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $stopInject = '    Q2WriteParamDword(L"SampleO_StopEnter", 1);'
  $raw = $raw -replace 'BddDdiStopDevice\([\s\S]*?\{\r?\n\s*PAGED_CODE\(\);\r?\n\s*BDD_ASSERT_CHK\(pDeviceContext != NULL\);', "BddDdiStopDevice(`r`n    _In_  VOID* pDeviceContext)`r`n{`r`n    PAGED_CODE();`r`n    BDD_ASSERT_CHK(pDeviceContext != NULL);`r`n$stopInject"

  $removeInject = '    Q2WriteParamDword(L"SampleO_RemoveEnter", 1);'
  $raw = $raw -replace 'BddDdiRemoveDevice\([\s\S]*?\{\r?\n\s*PAGED_CODE\(\);', "BddDdiRemoveDevice(`r`n    _In_  VOID* pDeviceContext)`r`n{`r`n    PAGED_CODE();`r`n$removeInject"

  Set-Content -Path $bdd -Value $raw -Encoding ASCII

  $proj='C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay.vcxproj'
  $msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
  & $msbuild $proj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /p:WindowsTargetPlatformVersion=10.0.19041.0 /v:minimal
  if($LASTEXITCODE -ne 0){ throw "Build failed for $Name" }

  $ts=Get-Date -Format yyyyMMdd_HHmmss
  $out="C:\Dev\BC250-windowsDriverTest\o_${Name}_$ts"
  New-Item -ItemType Directory -Path $out -Force | Out-Null

  $rel='C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay\x64\Release'
  $link='C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe'
  $lib='C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64'
  $sys=Join-Path $out ("O_${Name}.sys")
  $objs=@('BDD.obj','BDD_DDI.obj','BDD_DMM.obj','BDD_Util.obj','BltFuncs.obj','BltHw.obj','memory.obj','sampledisplay.res') | ForEach-Object { Join-Path $rel $_ }
  & $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$sys" "/LIBPATH:$lib" $objs ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib
  if($LASTEXITCODE -ne 0){ throw "Link failed for $Name" }

  Write-Host ("RUN_PROFILE=$Name|ADD=$AddMode|START=$StartMode|SYS=$sys")
  & 'C:\Dev\BC250-windowsDriverTest\P0-N9C-PnpBind-Hashed-NoReboot.ps1' -ProjectRoot 'C:\Dev\BC250-windowsDriverTest' -N9Dir $out -N9SysName ("O_${Name}.sys")
}

Build-And-RunProfile -Name 'O2' -AddMode 'nomem' -StartMode 'orig' -CbCount 15
Build-And-RunProfile -Name 'O3' -AddMode 'normal' -StartMode '11' -CbCount 15
Build-And-RunProfile -Name 'O4' -AddMode 'normal' -StartMode '00' -CbCount 15
Build-And-RunProfile -Name 'O5' -AddMode 'normal' -StartMode 'fail' -CbCount 15

