$msbuild = 'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
$proj = 'C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay.vcxproj'
$ver = '10.0.26100.0'
$env:DDK_INC_PATH = "C:\Program Files (x86)\Windows Kits\10\Include\$ver\km;C:\Program Files (x86)\Windows Kits\10\Include\$ver\shared"
$env:SDK_INC_PATH = "C:\Program Files (x86)\Windows Kits\10\Include\$ver\um;C:\Program Files (x86)\Windows Kits\10\Include\$ver\ucrt;C:\Program Files (x86)\Windows Kits\10\Include\$ver\shared"
$env:DDK_LIB_PATH = "C:\Program Files (x86)\Windows Kits\10\Lib\$ver\km\x64"
& $msbuild $proj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /v:minimal
$ec=$LASTEXITCODE
Write-Host "BUILD_EXIT=$ec"
if (Test-Path 'C:\Dev\windows-driver-samples\video\KMDOD\Sample\x64\Release') {
  Get-ChildItem -Path 'C:\Dev\windows-driver-samples\video\KMDOD\Sample\x64\Release' -File | Select-Object Name,Length,LastWriteTime
}
