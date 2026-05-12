Get-ChildItem -Path C:\ -Filter *.iso -Recurse -ErrorAction SilentlyContinue | Select-Object -First 20 FullName,Length,LastWriteTime | Out-String | Write-Output
