Get-ChildItem -Path 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter Inf2Cat.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
