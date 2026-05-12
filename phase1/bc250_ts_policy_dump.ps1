$k='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
if(Test-Path $k){
  Get-ItemProperty -Path $k | Format-List *
}else{
  'Policy key missing'
}
