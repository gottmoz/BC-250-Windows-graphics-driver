param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("l2_vcxproj_contract_{0}.log" -f $ts)
$work = Join-Path $ProjectRoot ("l2_vcxproj_{0}" -f $ts)
New-Item -ItemType Directory -Path $work -Force | Out-Null

function L([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m
    $line | Tee-Object -FilePath $log -Append
}

function Remove-ServiceSafe([string]$name) {
    sc.exe stop $name *>> $log
    sc.exe delete $name *>> $log
}

L "LOG=$log"
L "WORK=$work"

$vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
if (-not $msbuild) {
    $msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
}
L "MSBUILD=$msbuild"

$wdkVer = "10.0.19041.0"
$kitRoot = "C:\Program Files (x86)\Windows Kits\10"
$signtool = Join-Path $kitRoot "bin\$wdkVer\x64\signtool.exe"

$baseProps = @"
<Project>
  <ItemDefinitionGroup>
    <ClCompile>
      <WarningLevel>Level3</WarningLevel>
      <Optimization>MaxSpeed</Optimization>
      <PreprocessorDefinitions>_AMD64_;AMD64;_WIN64;NTDDI_VERSION=0x0A000000;WINNT=1;%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <AdditionalIncludeDirectories>$kitRoot\Include\$wdkVer\km;$kitRoot\Include\$wdkVer\shared;$kitRoot\Include\$wdkVer\km\crt;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
    </ClCompile>
    <Link>
      <AdditionalDependencies>ntoskrnl.lib;hal.lib;BufferOverflowFastFailK.lib;%(AdditionalDependencies)</AdditionalDependencies>
      <AdditionalLibraryDirectories>$kitRoot\Lib\$wdkVer\km\x64;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>
      <Driver>Driver</Driver>
      <SubSystem>Native</SubSystem>
      <EntryPointSymbol>DriverEntry</EntryPointSymbol>
    </Link>
  </ItemDefinitionGroup>
</Project>
"@
Set-Content -LiteralPath (Join-Path $work "Directory.Build.props") -Value $baseProps -Encoding UTF8

function New-Variant([string]$name, [string]$code, [string]$extraDeps) {
    $dir = Join-Path $work $name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $cPath = Join-Path $dir "$name.c"
    Set-Content -LiteralPath $cPath -Value $code -Encoding ASCII

    $guid = [guid]::NewGuid().ToString("B").ToUpper()

    $vcx = @'
<Project DefaultTargets="Build" ToolsVersion="Current" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup Label="ProjectConfigurations">
    <ProjectConfiguration Include="Release|x64"><Configuration>Release</Configuration><Platform>x64</Platform></ProjectConfiguration>
  </ItemGroup>
  <PropertyGroup Label="Globals"><ProjectGuid>__GUID__</ProjectGuid><Keyword>Win32Proj</Keyword><Platform>x64</Platform></PropertyGroup>
  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.Default.props" />
  <PropertyGroup Condition="'$(Configuration)|$(Platform)'=='Release|x64'" Label="Configuration"><ConfigurationType>Driver</ConfigurationType><UseDebugLibraries>false</UseDebugLibraries><PlatformToolset>v143</PlatformToolset><CharacterSet>Unicode</CharacterSet></PropertyGroup>
  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.props" />
  <ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='Release|x64'">
    <ClCompile><RuntimeLibrary>MultiThreaded</RuntimeLibrary></ClCompile>
    <Link><AdditionalDependencies>__EXTRA_DEPS__;%(AdditionalDependencies)</AdditionalDependencies></Link>
  </ItemDefinitionGroup>
  <ItemGroup><ClCompile Include="__NAME__.c" /></ItemGroup>
  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.targets" />
</Project>
'@

    $vcx = $vcx.Replace("__GUID__", $guid).Replace("__NAME__", $name).Replace("__EXTRA_DEPS__", $extraDeps)
    $projPath = Join-Path $dir "$name.vcxproj"
    Set-Content -LiteralPath $projPath -Value $vcx -Encoding UTF8

    return @{
        Name = $name
        Dir  = $dir
        Proj = $projPath
    }
}

$l2bCode = @"
#include <ntddk.h>
#include <dispmprt.h>

VOID L2bUnload(_In_ PDRIVER_OBJECT DriverObject) {
    UNREFERENCED_PARAMETER(DriverObject);
}

NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath) {
    UNREFERENCED_PARAMETER(RegistryPath);
    DriverObject->DriverUnload = L2bUnload;
    return STATUS_SUCCESS;
}
"@

$l2cCode = @"
#include <ntddk.h>
#include <dispmprt.h>

volatile PVOID g_DxgkRef = (PVOID)(ULONG_PTR)&DxgkInitialize;

VOID L2cUnload(_In_ PDRIVER_OBJECT DriverObject) {
    UNREFERENCED_PARAMETER(DriverObject);
}

NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath) {
    UNREFERENCED_PARAMETER(RegistryPath);
    DriverObject->DriverUnload = L2cUnload;
    if (g_DxgkRef == NULL) {
        return STATUS_UNSUCCESSFUL;
    }
    return STATUS_SUCCESS;
}
"@

$variants = @(
    (New-Variant -name ("l2b_dispheaders_" + $ts) -code $l2bCode -extraDeps ""),
    (New-Variant -name ("l2c_dxgkimport_" + $ts) -code $l2cCode -extraDeps "dxgkrnl.lib")
)

foreach ($v in $variants) {
    L ("BUILD_START=" + $v.Name)
    & $msbuild $v.Proj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
    L ("BUILD_EXIT_{0}={1}" -f $v.Name, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { continue }

    $sys = Join-Path $v.Dir ("x64\Release\" + $v.Name + ".sys")
    if (-not (Test-Path $sys)) {
        $sys = Get-ChildItem -Path $v.Dir -Recurse -Filter "*.sys" | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $sys) {
        L ("NO_SYS=" + $v.Name)
        continue
    }

    & $signtool sign /fd sha256 /f C:\bc250new.pfx /p bc250 $sys *>> $log
    L ("SIGN_EXIT_{0}={1}" -f $v.Name, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { continue }

    $svc = $v.Name
    $dst = Join-Path "C:\Windows\System32\drivers" ($svc + ".sys")
    Copy-Item $sys $dst -Force
    L ("HASH_{0}={1}" -f $svc, (Get-FileHash $dst -Algorithm SHA256).Hash)

    Remove-ServiceSafe $svc
    sc.exe create $svc type= kernel start= demand error= normal binPath= ("\SystemRoot\System32\drivers\" + $svc + ".sys") DisplayName= ("BC250 " + $svc) *>> $log
    sc.exe start $svc *>> $log
    L ("SC_START_EXIT_{0}={1}" -f $svc, $LASTEXITCODE)
    Start-Sleep -Seconds 2
    sc.exe query $svc *>> $log
    sc.exe stop $svc *>> $log
    sc.exe delete $svc *>> $log
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
    L ("CLEANUP_DONE=" + $svc)
}

Get-Content $log -Tail 260
