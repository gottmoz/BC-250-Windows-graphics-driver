$ErrorActionPreference='Stop'
$repo='C:\Dev\windows-driver-samples\video\KMDOD'
$bdd=Join-Path $repo 'bdd_ddi.cxx'
$bak="$bdd.q2bak"
if(-not (Test-Path $bak)){ Copy-Item $bdd $bak -Force }
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

if ($raw -notmatch 'Q2SampleBreadcrumb') {
    $raw = $raw.Replace('#include "BDD.hxx"', "#include ""BDD.hxx""$helper")
}

$needle = 'PAGED_CODE();'
$idx = $raw.IndexOf($needle)
if($idx -ge 0 -and $raw -notmatch 'SampleLastPhase'){
    $insert = "`r`n`r`n    Q2SampleBreadcrumb(pRegistryPath, 1, 2, 0, 0, 0, 0);"
    $raw = $raw.Insert($idx + $needle.Length, $insert)
}

$replacement = @"
Q2SampleBreadcrumb(pRegistryPath, 2, 2, (ULONG)InitialData.Version, (ULONG)sizeof(InitialData), 28, 0);
    NTSTATUS Status = DxgkInitializeDisplayOnlyDriver(pDriverObject, pRegistryPath, &InitialData);
    Q2SampleBreadcrumb(pRegistryPath, 3, 2, (ULONG)InitialData.Version, (ULONG)sizeof(InitialData), 28, (ULONG)Status);
"@
$raw = $raw -replace 'NTSTATUS Status = DxgkInitializeDisplayOnlyDriver\(pDriverObject, pRegistryPath, &InitialData\);', $replacement

Set-Content -Path $bdd -Value $raw -Encoding ASCII
Write-Host 'Q2_PATCHED=1'

$proj='C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay.vcxproj'
$msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
& $msbuild $proj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /p:WindowsTargetPlatformVersion=10.0.19041.0 /v:minimal
$ec=$LASTEXITCODE
Write-Host ('Q2_BUILD_EXIT=' + $ec)
if($ec -ne 0){ exit $ec }

$ts=Get-Date -Format yyyyMMdd_HHmmss
$out='C:\Dev\BC250-windowsDriverTest\q2_sample_breadcrumb_' + $ts
New-Item -ItemType Directory -Path $out -Force | Out-Null
$rel='C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay\x64\Release'
$link='C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe'
$lib='C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64'
$sys=Join-Path $out 'Q2_SAMPLEDISPLAY_BREADCRUMB.sys'
$objs=@('BDD.obj','BDD_DDI.obj','BDD_DMM.obj','BDD_Util.obj','BltFuncs.obj','BltHw.obj','memory.obj','sampledisplay.res') | ForEach-Object { Join-Path $rel $_ }
& $link /DRIVER:WDM /NODEFAULTLIB /ENTRY:DriverEntry /SUBSYSTEM:NATIVE /OPT:NOREF /OPT:NOICF /RELEASE "/OUT:$sys" "/LIBPATH:$lib" $objs ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdmsec.lib displib.lib wdm.lib
$lec=$LASTEXITCODE
Write-Host ('Q2_LINK_EXIT=' + $lec)
if($lec -ne 0){ exit $lec }
Write-Host ('Q2_SYS=' + $sys)
Write-Host ('Q2_HASH=' + (Get-FileHash $sys -Algorithm SHA256).Hash)

& 'C:\Dev\BC250-windowsDriverTest\P0-N9C-PnpBind-Hashed-NoReboot.ps1' -ProjectRoot 'C:\Dev\BC250-windowsDriverTest' -N9Dir $out -N9SysName 'Q2_SAMPLEDISPLAY_BREADCRUMB.sys'
