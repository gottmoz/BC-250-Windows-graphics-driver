$log='C:\Users\Public\bc250_app_term_errors.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== Application log term-related ==='
Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddDays(-2)} -ErrorAction SilentlyContinue |
 Where-Object { $_.LevelDisplayName -in @('Error','Warning') -and ($_.Message -match 'TermService|termsrv|rdpcorets|Remote Desktop|svchost.exe') } |
 Select-Object -First 120 TimeCreated,Id,ProviderName,LevelDisplayName,Message |
 Format-List | Out-String | Tee-Object -FilePath $log -Append
W '=== END ==='
