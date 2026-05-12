$ErrorActionPreference='Continue'
$repo='C:\Dev\BC250-windowsDriverTest'
$proj=Join-Path $repo 'amdbc250kmd.vcxproj'
$bak=Join-Path $repo 'amdbc250kmd.vcxproj.pebak2'
$log=Join-Path $repo 'linker-pe-batch-v2.log'
function Log([string]$m){$ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss';$line="[$ts] $m";Add-Content -LiteralPath $log -Value $line;Write-Output $line}
if(!(Test-Path $bak)){Copy-Item -LiteralPath $proj -Destination $bak -Force}

$variants=@(
 @{Name='D1_baseline'; NoDef='true'; Opt='%(AdditionalOptions)'},
 @{Name='D2_nodef_off'; NoDef='false'; Opt='%(AdditionalOptions)'},
 @{Name='D3_pe61'; NoDef='true'; Opt='/OSVERSION:6.01 /SUBSYSTEM:NATIVE,6.01 %(AdditionalOptions)'},
 @{Name='D4_nodef_off_pe61'; NoDef='false'; Opt='/OSVERSION:6.01 /SUBSYSTEM:NATIVE,6.01 %(AdditionalOptions)'}
)

foreach($v in $variants){
  Copy-Item -LiteralPath $bak -Destination $proj -Force
  [xml]$x = Get-Content -LiteralPath $proj
  $ns = New-Object System.Xml.XmlNamespaceManager($x.NameTable)
  $ns.AddNamespace('msb','http://schemas.microsoft.com/developer/msbuild/2003')

  $linkNodes = $x.SelectNodes('//msb:ItemDefinitionGroup/msb:Link',$ns)
  foreach($ln in $linkNodes){
    $ign = $ln.SelectSingleNode('msb:IgnoreAllDefaultLibraries',$ns)
    if($ign){ $ign.InnerText = $v.NoDef }
    $opt = $ln.SelectSingleNode('msb:AdditionalOptions',$ns)
    if(-not $opt){
      $opt = $x.CreateElement('AdditionalOptions','http://schemas.microsoft.com/developer/msbuild/2003')
      $ln.AppendChild($opt) | Out-Null
    }
    $opt.InnerText = $v.Opt
  }
  $x.Save($proj)

  Log "ITER_START $($v.Name)"
  $sw=[Diagnostics.Stopwatch]::StartNew(); $out=powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Public\remote-iter-fast.ps1' 2>&1; $code=$LASTEXITCODE; $sw.Stop(); $sec=[math]::Round($sw.Elapsed.TotalSeconds,1)
  $tmp=Join-Path $repo ("tmp_"+$v.Name+".log"); $out|Out-File -LiteralPath $tmp -Encoding ascii
  $marker=(Select-String -Path $tmp -Pattern 'CM_PROB_FAILED_DRIVER_ENTRY|problem status: 0xc0000059|0xC00000E5|KMD build failed|GUARD_EXIT='|Select-Object -Last 1).Line
  Log "ITER_END $($v.Name) exit=$code seconds=$sec marker=$marker"
  if($sec -gt 180){ Log "ITER_ABORT $($v.Name) exceeded 180s"; break }
}

Copy-Item -LiteralPath $bak -Destination $proj -Force
Log 'LINKER-PE v2 batch done; project restored.'
