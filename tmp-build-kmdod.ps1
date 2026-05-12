$msbuild = 'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
$proj = 'C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay.vcxproj'
& $msbuild $proj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal
Get-ChildItem -Path 'C:\Dev\windows-driver-samples\video\KMDOD\Sample\x64\Release' -File | Select-Object Name,Length,LastWriteTime
