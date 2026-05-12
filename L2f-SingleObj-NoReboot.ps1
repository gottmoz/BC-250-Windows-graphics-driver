param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("l2f_singleobj_{0}.log" -f $ts)
$projPath = Join-Path $ProjectRoot "amdbc250kmd.vcxproj"
$projBak = "$projPath.bak_$ts"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
$dumpbin = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe"
$pkgSys = Join-Path $ProjectRoot "build\Release\x64\package\amdbc250kmd.sys"
$l2fSrc = Join-Path $ProjectRoot "l2f_minimal_driver.c"
$marker = "L2F_SINGLE_COMPILE_UNIT_20260508_$ts"

function L([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m
    $line | Tee-Object -FilePath $log -Append
}

function Remove-ServiceSafe([string]$name) {
    sc.exe stop $name *>> $log
    sc.exe delete $name *>> $log
}

L "LOG=$log"
L "MARKER=$marker"

$src = @"
#include <ntddk.h>

__declspec(selectany) const char L2F_MARKER_FORCE[] = "$marker";

VOID L2fUnload(_In_ PDRIVER_OBJECT DriverObject)
{
    UNREFERENCED_PARAMETER(DriverObject);
}

NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath)
{
    UNREFERENCED_PARAMETER(RegistryPath);
    DriverObject->DriverUnload = L2fUnload;
    return STATUS_SUCCESS;
}
"@

Set-Content -LiteralPath $l2fSrc -Value $src -Encoding ASCII
Copy-Item $projPath $projBak -Force

try {
    [xml]$proj = Get-Content -LiteralPath $projPath
    $ns = New-Object System.Xml.XmlNamespaceManager($proj.NameTable)
    $ns.AddNamespace("msb", "http://schemas.microsoft.com/developer/msbuild/2003")

    $compileNodes = $proj.SelectNodes("//msb:ClCompile", $ns)
    foreach ($node in $compileNodes) {
        if ($node.Include) {
            $node.ParentNode.RemoveChild($node) | Out-Null
        }
    }

    $itemGroup = $proj.CreateElement("ItemGroup", $proj.Project.NamespaceURI)
    $cl = $proj.CreateElement("ClCompile", $proj.Project.NamespaceURI)
    $cl.SetAttribute("Include", '$(ProjectDir)l2f_minimal_driver.c')
    $itemGroup.AppendChild($cl) | Out-Null
    $proj.Project.AppendChild($itemGroup) | Out-Null

    $proj.Save($projPath)
    L "VCXPROJ_SINGLE_OBJ_PATCHED=1"

    & $msbuild $projPath /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
    L ("BUILD_EXIT={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }

    if (-not (Test-Path $pkgSys)) { throw "Package sys missing: $pkgSys" }

    $bytes = [IO.File]::ReadAllBytes($pkgSys)
    $ascii = [Text.Encoding]::ASCII.GetString($bytes)
    $markerPresent = $ascii.Contains($marker)
    L ("MARKER_PRESENT={0}" -f $markerPresent)

    & $signtool sign /fd sha256 /f C:\bc250new.pfx /p bc250 $pkgSys *>> $log
    L ("SIGN_EXIT={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { throw "Sign failed" }

    if (Test-Path $dumpbin) {
        & $dumpbin /headers $pkgSys *> (Join-Path $ProjectRoot ("L2f_headers_{0}.txt" -f $ts))
        & $dumpbin /imports $pkgSys *> (Join-Path $ProjectRoot ("L2f_imports_{0}.txt" -f $ts))
        & $dumpbin /loadconfig $pkgSys *> (Join-Path $ProjectRoot ("L2f_loadconfig_{0}.txt" -f $ts))
        L "DUMPBIN_ARTIFACTS=1"
    }

    $svc = ("l2f_singleobj_{0}" -f $ts).ToLower()
    $dst = "C:\Windows\System32\drivers\$svc.sys"
    Copy-Item $pkgSys $dst -Force
    L ("HASH={0}" -f (Get-FileHash $dst -Algorithm SHA256).Hash)

    Remove-ServiceSafe $svc
    sc.exe create $svc type= kernel start= demand error= normal binPath= ("\SystemRoot\System32\drivers\$svc.sys") DisplayName= ("BC250 $svc") *>> $log
    sc.exe start $svc *>> $log
    L ("SC_START_EXIT={0}" -f $LASTEXITCODE)
    Start-Sleep -Seconds 2
    sc.exe query $svc *>> $log
    sc.exe stop $svc *>> $log
    sc.exe delete $svc *>> $log
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
}
finally {
    if (Test-Path $projBak) {
        Copy-Item $projBak $projPath -Force
        Remove-Item $projBak -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $l2fSrc -Force -ErrorAction SilentlyContinue
    L "RESTORE_DONE=1"
}

Get-Content $log -Tail 260
