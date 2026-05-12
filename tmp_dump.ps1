$d='C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe'
& $d /imports C:\Dev\BC250-windowsDriverTest\l1_hello\bc250hello.sys > C:\Dev\BC250-windowsDriverTest\L1_imports.txt
& $d /imports C:\Dev\BC250-windowsDriverTest\build\Release\x64\package\amdbc250kmd.sys > C:\Dev\BC250-windowsDriverTest\L0_imports.txt
& $d /loadconfig C:\Dev\BC250-windowsDriverTest\l1_hello\bc250hello.sys > C:\Dev\BC250-windowsDriverTest\L1_loadconfig.txt
& $d /loadconfig C:\Dev\BC250-windowsDriverTest\build\Release\x64\package\amdbc250kmd.sys > C:\Dev\BC250-windowsDriverTest\L0_loadconfig.txt
