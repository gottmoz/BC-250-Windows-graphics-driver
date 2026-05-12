Get-ChildItem -Path 'C:\Program Files (x86)\Windows Kits\10\Samples' -Recurse -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match 'kmdod|display-only|displayonly|basicdisplay' } |
  Select-Object -First 40 -ExpandProperty FullName
