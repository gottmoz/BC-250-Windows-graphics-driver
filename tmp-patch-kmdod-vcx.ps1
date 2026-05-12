$proj = 'C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay.vcxproj'
$bak = $proj + '.bak_bc250'
if (-not (Test-Path $bak)) { Copy-Item $proj $bak -Force }
$xml = Get-Content $proj -Raw
$inc = 'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\km;C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared;C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\um;C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\ucrt'
$lib = 'C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\km\x64'
$xml = $xml.Replace('$(DDK_INC_PATH);$(SDK_INC_PATH);$(KIT_SHARED_INC_PATH_WDK)', $inc)
$xml = $xml.Replace('$(DDK_INC_PATH);$(SDK_INC_PATH)', $inc)
$xml = $xml.Replace('$(DDK_LIB_PATH)\', ($lib + '\'))
Set-Content -Path $proj -Value $xml -Encoding UTF8
Write-Host 'PATCHED=1'
