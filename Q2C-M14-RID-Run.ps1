$ErrorActionPreference='Stop'
$repo='C:\Dev\windows-driver-samples\video\KMDOD'
$bdd=Join-Path $repo 'bdd_ddi.cxx'
$bak="$bdd.q2bak"
if(-not (Test-Path $bak)){ throw "Missing backup: $bak" }

function Build-And-RunProfile {
  param(
    [string]$Name,
    [string]$Block,
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
"@

  $raw = $raw.Replace('#include "BDD.hxx"', "#include ""BDD.hxx""$helper")

  $patCallbacks = 'InitialData\.DxgkDdiAddDevice[\s\S]*?InitialData\.DxgkDdiSystemDisplayWrite\s*=\s*BddDdiSystemDisplayWrite;\r?\n'
  $raw = [Regex]::Replace($raw, $patCallbacks, $Block, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $driverEntryPat = 'DriverEntry\([\s\S]*?\{\r?\n\s*PAGED_CODE\(\);'
  $driverEntryRepl = '$0' + "`r`n`r`n    Q2SampleBreadcrumb(pRegistryPath, 1, 2, 0, 0, $CbCount, 0);"
  $raw = [Regex]::Replace($raw, $driverEntryPat, $driverEntryRepl, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $replaceCall = @"
Q2SampleBreadcrumb(pRegistryPath, 2, 2, (ULONG)InitialData.Version, (ULONG)sizeof(InitialData), $CbCount, 0);
    NTSTATUS Status = DxgkInitializeDisplayOnlyDriver(pDriverObject, pRegistryPath, &InitialData);
    Q2SampleBreadcrumb(pRegistryPath, 3, 2, (ULONG)InitialData.Version, (ULONG)sizeof(InitialData), $CbCount, (ULONG)Status);
"@
  $raw = $raw -replace 'NTSTATUS Status = DxgkInitializeDisplayOnlyDriver\(pDriverObject, pRegistryPath, &InitialData\);', $replaceCall

  Set-Content -Path $bdd -Value $raw -Encoding ASCII

  $proj='C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay.vcxproj'
  $msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
  & $msbuild $proj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /p:WindowsTargetPlatformVersion=10.0.19041.0 /v:minimal
  if($LASTEXITCODE -ne 0){ throw "Build failed for $Name" }

  $ts=Get-Date -Format yyyyMMdd_HHmmss
  $out="C:\Dev\BC250-windowsDriverTest\q2c_${Name}_$ts"
  New-Item -ItemType Directory -Path $out -Force | Out-Null

  $rel='C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay\x64\Release'
  $link='C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe'
  $lib='C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64'
  $sys=Join-Path $out ("Q2C_${Name}.sys")
  $objs=@('BDD.obj','BDD_DDI.obj','BDD_DMM.obj','BDD_Util.obj','BltFuncs.obj','BltHw.obj','memory.obj','sampledisplay.res') | ForEach-Object { Join-Path $rel $_ }
  & $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$sys" "/LIBPATH:$lib" $objs ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib
  if($LASTEXITCODE -ne 0){ throw "Link failed for $Name" }

  Write-Host ("RUN_PROFILE=$Name|SYS=$sys")
  & 'C:\Dev\BC250-windowsDriverTest\P0-N9C-PnpBind-Hashed-NoReboot.ps1' -ProjectRoot 'C:\Dev\BC250-windowsDriverTest' -N9Dir $out -N9SysName ("Q2C_${Name}.sys")
}

$full = @"
    InitialData.DxgkDdiAddDevice                    = BddDdiAddDevice;
    InitialData.DxgkDdiStartDevice                  = BddDdiStartDevice;
    InitialData.DxgkDdiStopDevice                   = BddDdiStopDevice;
    InitialData.DxgkDdiResetDevice                  = BddDdiResetDevice;
    InitialData.DxgkDdiRemoveDevice                 = BddDdiRemoveDevice;
    InitialData.DxgkDdiDispatchIoRequest            = BddDdiDispatchIoRequest;
    InitialData.DxgkDdiInterruptRoutine             = BddDdiInterruptRoutine;
    InitialData.DxgkDdiDpcRoutine                   = BddDdiDpcRoutine;
    InitialData.DxgkDdiQueryChildRelations          = BddDdiQueryChildRelations;
    InitialData.DxgkDdiQueryChildStatus             = BddDdiQueryChildStatus;
    InitialData.DxgkDdiQueryDeviceDescriptor        = BddDdiQueryDeviceDescriptor;
    InitialData.DxgkDdiSetPowerState                = BddDdiSetPowerState;
    InitialData.DxgkDdiUnload                       = BddDdiUnload;
    InitialData.DxgkDdiQueryAdapterInfo             = BddDdiQueryAdapterInfo;
    InitialData.DxgkDdiSetPointerPosition           = BddDdiSetPointerPosition;
    InitialData.DxgkDdiSetPointerShape              = BddDdiSetPointerShape;
    InitialData.DxgkDdiIsSupportedVidPn             = BddDdiIsSupportedVidPn;
    InitialData.DxgkDdiRecommendFunctionalVidPn     = BddDdiRecommendFunctionalVidPn;
    InitialData.DxgkDdiEnumVidPnCofuncModality      = BddDdiEnumVidPnCofuncModality;
    InitialData.DxgkDdiSetVidPnSourceVisibility     = BddDdiSetVidPnSourceVisibility;
    InitialData.DxgkDdiCommitVidPn                  = BddDdiCommitVidPn;
    InitialData.DxgkDdiUpdateActiveVidPnPresentPath = BddDdiUpdateActiveVidPnPresentPath;
    InitialData.DxgkDdiRecommendMonitorModes        = BddDdiRecommendMonitorModes;
    InitialData.DxgkDdiQueryVidPnHWCapability       = BddDdiQueryVidPnHWCapability;
    InitialData.DxgkDdiPresentDisplayOnly           = BddDdiPresentDisplayOnly;
    InitialData.DxgkDdiStopDeviceAndReleasePostDisplayOwnership = BddDdiStopDeviceAndReleasePostDisplayOwnership;
    InitialData.DxgkDdiSystemDisplayEnable          = BddDdiSystemDisplayEnable;
    InitialData.DxgkDdiSystemDisplayWrite           = BddDdiSystemDisplayWrite;
"@

$min8 = @"
    InitialData.DxgkDdiAddDevice         = BddDdiAddDevice;
    InitialData.DxgkDdiStartDevice       = BddDdiStartDevice;
    InitialData.DxgkDdiStopDevice        = BddDdiStopDevice;
    InitialData.DxgkDdiRemoveDevice      = BddDdiRemoveDevice;
    InitialData.DxgkDdiDispatchIoRequest = BddDdiDispatchIoRequest;
    InitialData.DxgkDdiSetPowerState     = BddDdiSetPowerState;
    InitialData.DxgkDdiUnload            = BddDdiUnload;
    InitialData.DxgkDdiQueryAdapterInfo  = BddDdiQueryAdapterInfo;
"@

$mid14 = @"
    InitialData.DxgkDdiAddDevice                    = BddDdiAddDevice;
    InitialData.DxgkDdiStartDevice                  = BddDdiStartDevice;
    InitialData.DxgkDdiStopDevice                   = BddDdiStopDevice;
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

$m14r = @"
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

$m14i = @"
    InitialData.DxgkDdiAddDevice                    = BddDdiAddDevice;
    InitialData.DxgkDdiStartDevice                  = BddDdiStartDevice;
    InitialData.DxgkDdiStopDevice                   = BddDdiStopDevice;
    InitialData.DxgkDdiRemoveDevice                 = BddDdiRemoveDevice;
    InitialData.DxgkDdiDispatchIoRequest            = BddDdiDispatchIoRequest;
    InitialData.DxgkDdiInterruptRoutine             = BddDdiInterruptRoutine;
    InitialData.DxgkDdiDpcRoutine                   = BddDdiDpcRoutine;
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

$m14rid = @"
    InitialData.DxgkDdiAddDevice                    = BddDdiAddDevice;
    InitialData.DxgkDdiStartDevice                  = BddDdiStartDevice;
    InitialData.DxgkDdiStopDevice                   = BddDdiStopDevice;
    InitialData.DxgkDdiResetDevice                  = BddDdiResetDevice;
    InitialData.DxgkDdiRemoveDevice                 = BddDdiRemoveDevice;
    InitialData.DxgkDdiDispatchIoRequest            = BddDdiDispatchIoRequest;
    InitialData.DxgkDdiInterruptRoutine             = BddDdiInterruptRoutine;
    InitialData.DxgkDdiDpcRoutine                   = BddDdiDpcRoutine;
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

Build-And-RunProfile -Name 'M14R' -Block $m14r -CbCount 15
Build-And-RunProfile -Name 'M14I' -Block $m14i -CbCount 16
Build-And-RunProfile -Name 'M14RID' -Block $m14rid -CbCount 17
