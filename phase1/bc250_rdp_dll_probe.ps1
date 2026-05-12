$files=@('C:\Windows\System32\rdpcorets.dll','C:\Windows\System32\rdpbase.dll','C:\Windows\System32\rdpserverbase.dll','C:\Windows\System32\winsta.dll')
foreach($f in $files){
  if(Test-Path $f){
    "=== $f ==="
    $i=Get-Item $f
    $i.VersionInfo | Select-Object FileVersion,ProductVersion,OriginalFilename | Format-List
    (Get-AuthenticodeSignature -FilePath $f) | Select-Object Status,StatusMessage | Format-List
  } else { "MISSING: $f" }
}
