$ProjectRoot='C:\Dev\BC250-windowsDriverTest'
$ts=Get-Date -Format yyyyMMdd_HHmmss
$log=Join-Path $ProjectRoot ("l2f_manual_link_{0}.log" -f $ts)
$proj=Join-Path $ProjectRoot 'amdbc250kmd.vcxproj'
$projBak="$proj.bak_$ts"
$src=Join-Path $ProjectRoot 'l2f_minimal_driver.c'
$marker="L2F_SINGLE_COMPILE_UNIT_MANUAL_$ts"
$msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
$sig='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
$link='C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe'
$lib='C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\km\x64'
function L($m){("[{0}] {1}" -f (Get-Date -Format HH:mm:ss),$m)|Tee-Object -FilePath $log -Append}
function RmSvc($n){sc.exe stop $n *>> $log; sc.exe delete $n *>> $log}
$code=@"
#include <ntddk.h>
__declspec(selectany) const char L2F_MARKER_FORCE[] = "$marker";
VOID L2fUnload(_In_ PDRIVER_OBJECT DriverObject){UNREFERENCED_PARAMETER(DriverObject);}
NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject,_In_ PUNICODE_STRING RegistryPath){UNREFERENCED_PARAMETER(RegistryPath); DriverObject->DriverUnload=L2fUnload; return STATUS_SUCCESS;}
"@
Set-Content -LiteralPath $src -Value $code -Encoding ASCII
Copy-Item $proj $projBak -Force
try {
 [xml]$x=Get-Content -LiteralPath $proj
 $ns=New-Object System.Xml.XmlNamespaceManager($x.NameTable); $ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
 $nodes=$x.SelectNodes('//m:ClCompile',$ns)
 foreach($n in $nodes){ if($n.Include){$n.ParentNode.RemoveChild($n)|Out-Null}}
 $ig=$x.CreateElement('ItemGroup',$x.Project.NamespaceURI)
 $cl=$x.CreateElement('ClCompile',$x.Project.NamespaceURI)
 $cl.SetAttribute('Include','$(ProjectDir)l2f_minimal_driver.c')
 $ig.AppendChild($cl)|Out-Null; $x.Project.AppendChild($ig)|Out-Null
 $x.Save($proj)
 L('PROJECT_PATCHED=1')
 & $msbuild $proj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal *>> $log
 L("BUILD_EXIT=$LASTEXITCODE")
 if($LASTEXITCODE -ne 0){throw 'build fail'}
 $obj=Join-Path $ProjectRoot 'build\Release\x64\amdbc250kmd\l2f_minimal_driver.obj'
 if(-not (Test-Path $obj)){ throw "obj missing $obj" }
 $sys=Join-Path $ProjectRoot ("build\Release\x64\l2f_manual_$ts.sys")
 & $link /DRIVER:WDM /SUBSYSTEM:NATIVE /ENTRY:DriverEntry /NODEFAULTLIB /OUT:$sys /LIBPATH:$lib $obj ntoskrnl.lib hal.lib BufferOverflowFastFailK.lib wdm.lib displib.lib *>> $log
 L("LINK_EXIT=$LASTEXITCODE")
 if($LASTEXITCODE -ne 0){throw 'link fail'}
 $a=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($sys))
 L("MARKER_PRESENT=" + $a.Contains($marker))
 & $sig sign /fd sha256 /f C:\bc250new.pfx /p bc250 $sys *>> $log
 L("SIGN_EXIT=$LASTEXITCODE")
 $svc="l2fmanual_$ts"
 $dst="C:\Windows\System32\drivers\$svc.sys"
 Copy-Item $sys $dst -Force
 L("HASH=" + (Get-FileHash $dst -Algorithm SHA256).Hash)
 RmSvc $svc
 sc.exe create $svc type= kernel start= demand error= normal binPath= "\SystemRoot\System32\drivers\$svc.sys" DisplayName= "BC250 $svc" *>> $log
 sc.exe start $svc *>> $log
 L("SC_START_EXIT=$LASTEXITCODE")
 Start-Sleep 2
 sc.exe query $svc *>> $log
 sc.exe stop $svc *>> $log
 sc.exe delete $svc *>> $log
 Remove-Item $dst -Force -EA SilentlyContinue
}
finally {
 Copy-Item $projBak $proj -Force
 Remove-Item $projBak -Force -EA SilentlyContinue
 Remove-Item $src -Force -EA SilentlyContinue
 L('RESTORE_DONE=1')
}
Get-Content $log -Tail 260
