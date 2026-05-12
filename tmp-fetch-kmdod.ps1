$repo = 'C:\Dev\windows-driver-samples'
if (-not (Test-Path $repo)) {
  git clone --depth 1 --filter=blob:none --sparse https://github.com/microsoft/Windows-driver-samples.git $repo
}
Set-Location $repo
git sparse-checkout set video/KMDOD
Get-ChildItem -Path (Join-Path $repo 'video\KMDOD') -Recurse -File | Select-Object -First 40 FullName
