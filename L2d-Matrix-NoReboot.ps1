param([string]$ProjectRoot = "C:\Dev\BC250-windowsDriverTest")

$ErrorActionPreference = "Continue"
$ts = Get-Date -Format yyyyMMdd_HHmmss
$log = Join-Path $ProjectRoot ("l2d_matrix_{0}.log" -f $ts)
$src = Join-Path $ProjectRoot "amdbc250_kmd.c"
$srcBak = "$src.bak_$ts"
$prj = Join-Path $ProjectRoot "amdbc250kmd.vcxproj"
$prjBak = "$prj.bak_$ts"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$sig = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
$pkgSys = Join-Path $ProjectRoot "build\Release\x64\package\amdbc250kmd.sys"

function L([string]$m) {
    ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $m) | Tee-Object -FilePath $log -Append
}

function Remove-ServiceSafe([string]$name) {
    sc.exe stop $name *>> $log
    sc.exe delete $name *>> $log
}

$min = @"
#include <ntddk.h>
VOID Bc250MiniUnload(_In_ PDRIVER_OBJECT DriverObject){UNREFERENCED_PARAMETER(DriverObject);}
NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject,_In_ PUNICODE_STRING RegistryPath){UNREFERENCED_PARAMETER(RegistryPath); DriverObject->DriverUnload=Bc250MiniUnload; return STATUS_SUCCESS;}
"@

Copy-Item $src $srcBak -Force
Copy-Item $prj $prjBak -Force
Set-Content -LiteralPath $src -Value $min -Encoding ASCII

$variants = @(
    @{ Name = "l2d1_nodisplib"; Remove = @("displib.lib;") },
    @{ Name = "l2d2_nowdm"; Remove = @("wdm.lib;") },
    @{ Name = "l2d3_nodisplib_nowdm"; Remove = @("displib.lib;", "wdm.lib;") }
)

try {
    foreach ($v in $variants) {
        Copy-Item $prjBak $prj -Force
        $xml = Get-Content -Raw $prj
        foreach ($r in $v.Remove) {
            $xml = $xml.Replace($r, "")
        }
        Set-Content -LiteralPath $prj -Value $xml -Encoding UTF8

        L ("VARIANT=" + $v.Name)
        & $msbuild $prj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
        L ("BUILD_EXIT=" + $LASTEXITCODE)
        if ($LASTEXITCODE -ne 0) { continue }

        & $sig sign /fd sha256 /f C:\bc250new.pfx /p bc250 $pkgSys *>> $log
        L ("SIGN_EXIT=" + $LASTEXITCODE)
        if ($LASTEXITCODE -ne 0) { continue }

        $svc = ("{0}_{1}" -f $v.Name, $ts)
        $dst = "C:\Windows\System32\drivers\$svc.sys"
        Copy-Item $pkgSys $dst -Force
        L ("HASH=" + (Get-FileHash $dst -Algorithm SHA256).Hash)

        Remove-ServiceSafe $svc
        sc.exe create $svc type= kernel start= demand error= normal binPath= ("\SystemRoot\System32\drivers\$svc.sys") DisplayName= ("BC250 $svc") *>> $log
        sc.exe start $svc *>> $log
        L ("SC_START_EXIT=" + $LASTEXITCODE)
        Start-Sleep -Seconds 2
        sc.exe query $svc *>> $log
        sc.exe stop $svc *>> $log
        sc.exe delete $svc *>> $log
        Remove-Item $dst -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Copy-Item $srcBak $src -Force
    Copy-Item $prjBak $prj -Force
    Remove-Item $srcBak, $prjBak -Force -ErrorAction SilentlyContinue
    L "RESTORE_DONE=1"
}

Get-Content $log -Tail 260
