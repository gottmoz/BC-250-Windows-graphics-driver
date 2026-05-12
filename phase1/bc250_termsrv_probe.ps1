$log='C:\Users\Public\bc250_termsrv_probe.log'
if(Test-Path $log){Remove-Item $log -Force}
function W($m){$m|Tee-Object -FilePath $log -Append}
W '=== termsrv probe ==='
$path='C:\Windows\System32\termsrv.dll'
W "Path: $path"
Get-Item $path | Select-Object FullName,Length,CreationTime,LastWriteTime | Format-List | Out-String | Tee-Object -FilePath $log -Append
Get-Item $path | Select-Object -ExpandProperty VersionInfo | Select-Object FileVersion,ProductVersion,OriginalFilename,CompanyName | Format-List | Out-String | Tee-Object -FilePath $log -Append
$sig = Get-AuthenticodeSignature -FilePath $path
$sig | Select-Object Status,StatusMessage | Format-List | Out-String | Tee-Object -FilePath $log -Append
if($sig.SignerCertificate){
  $sig.SignerCertificate | Select-Object Subject,Issuer,NotBefore,NotAfter,Thumbprint | Format-List | Out-String | Tee-Object -FilePath $log -Append
}
W '--- TermService registry ---'
reg query "HKLM\SYSTEM\CurrentControlSet\Services\TermService" /s | Out-File -FilePath $log -Append -Encoding utf8
W '--- WinStations RDP-Tcp ACL ---'
try { (Get-Acl 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp').Access | Select-Object IdentityReference,RegistryRights,AccessControlType,IsInherited | Format-Table -Auto | Out-String | Tee-Object -FilePath $log -Append } catch { W $_.Exception.Message }
W '=== END ==='
