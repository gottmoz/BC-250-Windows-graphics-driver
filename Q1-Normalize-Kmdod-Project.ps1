$proj='C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay.vcxproj'
$bak = "$proj.normbak"
if(-not (Test-Path $bak)){ Copy-Item $proj $bak -Force }
[xml]$x = Get-Content -Path $proj
$ns = New-Object System.Xml.XmlNamespaceManager($x.NameTable)
$ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')

$inc = 'C:\Program Files (x86)\Windows Kits\10\Include\10.0.22000.0\km;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22000.0\shared;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22000.0\um;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22000.0\ucrt'
$lib = 'C:\Program Files (x86)\Windows Kits\10\Lib\10.0.22000.0\km\x64'
$defs = '_AMD64_;AMD64;_WIN64;WIN64;%(PreprocessorDefinitions)'

$globals = $x.SelectSingleNode('//m:PropertyGroup[@Label="Globals"]',$ns)
if($globals -and -not $globals.WindowsTargetPlatformVersion){
  $n = $x.CreateElement('WindowsTargetPlatformVersion',$x.Project.NamespaceURI)
  $n.InnerText = '10.0.22000.0'
  [void]$globals.AppendChild($n)
} elseif($globals.WindowsTargetPlatformVersion){
  $globals.WindowsTargetPlatformVersion = '10.0.22000.0'
}

$itemDefs = $x.SelectNodes('//m:ItemDefinitionGroup[contains(@Condition,"|x64")]', $ns)
foreach($idg in $itemDefs){
  $cl = $idg.SelectSingleNode('m:ClCompile', $ns)
  if(-not $cl){ $cl = $x.CreateElement('ClCompile',$x.Project.NamespaceURI); [void]$idg.AppendChild($cl) }
  $ai = $cl.SelectSingleNode('m:AdditionalIncludeDirectories',$ns)
  if(-not $ai){ $ai = $x.CreateElement('AdditionalIncludeDirectories',$x.Project.NamespaceURI); [void]$cl.AppendChild($ai) }
  $ai.InnerText = "$inc;%(AdditionalIncludeDirectories)"
  $pd = $cl.SelectSingleNode('m:PreprocessorDefinitions',$ns)
  if(-not $pd){ $pd = $x.CreateElement('PreprocessorDefinitions',$x.Project.NamespaceURI); [void]$cl.AppendChild($pd) }
  $pd.InnerText = $defs

  $rc = $idg.SelectSingleNode('m:ResourceCompile',$ns)
  if($rc){
    $rai = $rc.SelectSingleNode('m:AdditionalIncludeDirectories',$ns)
    if(-not $rai){ $rai = $x.CreateElement('AdditionalIncludeDirectories',$x.Project.NamespaceURI); [void]$rc.AppendChild($rai) }
    $rai.InnerText = "$inc;%(AdditionalIncludeDirectories)"
  }

  $midl = $idg.SelectSingleNode('m:Midl',$ns)
  if($midl){
    $mai = $midl.SelectSingleNode('m:AdditionalIncludeDirectories',$ns)
    if(-not $mai){ $mai = $x.CreateElement('AdditionalIncludeDirectories',$x.Project.NamespaceURI); [void]$midl.AppendChild($mai) }
    $mai.InnerText = "$inc;%(AdditionalIncludeDirectories)"
  }

  $lnk = $idg.SelectSingleNode('m:Link',$ns)
  if(-not $lnk){ $lnk = $x.CreateElement('Link',$x.Project.NamespaceURI); [void]$idg.AppendChild($lnk) }
  $ald = $lnk.SelectSingleNode('m:AdditionalLibraryDirectories',$ns)
  if(-not $ald){ $ald = $x.CreateElement('AdditionalLibraryDirectories',$x.Project.NamespaceURI); [void]$lnk.AppendChild($ald) }
  $ald.InnerText = "$lib;%(AdditionalLibraryDirectories)"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($proj, $x.OuterXml, $utf8NoBom)
Write-Host 'Q1_NORMALIZE_DONE=1'

$msbuild='C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
& $msbuild $proj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /p:WindowsTargetPlatformVersion=10.0.22000.0 /v:minimal
$ec=$LASTEXITCODE
Write-Host ("Q1_NORMALIZE_BUILD_EXIT=$ec")
Get-ChildItem -Path 'C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay\x64\Release' -File -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTime
