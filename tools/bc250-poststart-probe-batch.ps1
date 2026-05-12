param(
  [int]$Iterations = 10,
  [string]$OutDir = 'C:\Users\Public\bc250-poststart-probe-batch'
)

$ErrorActionPreference='Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log=Join-Path $OutDir 'run.log'
$csv=Join-Path $OutDir 'iterations.csv'
$sum=Join-Path $OutDir 'summary.json'

$src='C:\AMD\AMD-Software-Installer\Packages\Drivers\Display\WT6A_INF'
$inf2cat='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x86\Inf2Cat.exe'
$sig='C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe'
$devcon='C:\Program Files (x86)\Windows Kits\10\Tools\x64\devcon.exe'
$inst='PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$map='ati2mtag_Rembrandt'

function Log([string]$m){ "$((Get-Date).ToString('o')) $m" | Tee-Object -FilePath $log -Append }
function Get-State {
  $p=Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_Service,DEVPKEY_Device_ProblemCode,DEVPKEY_Device_ProblemStatus -ErrorAction SilentlyContinue
  [pscustomobject]@{
    inf=($p|? KeyName -match 'DriverInfPath').Data
    svc=($p|? KeyName -match 'Device_Service').Data
    code=[int](($p|? KeyName -match 'ProblemCode').Data)
    status=($p|? KeyName -match 'ProblemStatus').Data
  }
}
function Probe([string]$tag){
  $s=Get-State
  $gpu=(sc.exe query amduw23g) -join ' | '
  $evt=(sc.exe query "AMD External Events Utility") -join ' | '
  [pscustomobject]@{
    tag=$tag; ts=(Get-Date).ToString('o'); inf=$s.inf; svc=$s.svc; code=$s.code; pstatus=$s.status; gpuSvc=$gpu; evtSvc=$evt
  }
}

$delays=@(0,2,5,10)
$rows=@()

Log "POSTSTART_PROBE_BATCH start iterations=$Iterations map=$map"
for($i=1; $i -le $Iterations; $i++){
  $iterId="{0:yyyyMMdd-HHmmss}-I{1:D3}" -f (Get-Date),$i
  $work='C:\Users\Public\bc250-probe-'+$iterId
  if(Test-Path $work){ Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }
  New-Item -Type Directory -Path $work | Out-Null

  Log "ITER $i begin id=$iterId"
  $cert = @(
    Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue
    Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue
  ) | Where-Object { $_.HasPrivateKey -and $_.Subject -match 'BC250' } | Sort-Object NotAfter -Descending | Select-Object -First 1
  if(-not $cert){ Log "ITER $i cert_missing"; continue }

  Copy-Item -Path (Join-Path $src '*') -Destination $work -Recurse -Force
  $inf=Join-Path $work 'u0397406.inf'
  $txt=Get-Content -Raw -LiteralPath $inf
  $txt=$txt -replace '(?m)^\[ATI\.Mfg\.NTamd64\.10\.0\.1\.\.16299\]$',"`$0`r`n%AMD13FE.1% = $map, PCI\VEN_1002&DEV_13FE`r`n%AMD13FE.2% = $map, PCI\VEN_1002&DEV_13FE&SUBSYS_00001022"
  $txt=$txt -replace '(?m)^\[ATI\.Mfg\.NTamd64\.10\.0\.1\]$',"`$0`r`n%AMD13FE.1% = $map, PCI\VEN_1002&DEV_13FE`r`n%AMD13FE.2% = $map, PCI\VEN_1002&DEV_13FE&SUBSYS_00001022"
  if($txt -notmatch '(?m)^AMD13FE\.1\s*='){
    $txt=$txt -replace '(?m)^\[Strings\]$',"`$0`r`nAMD13FE.1 = `"AMD BC-250 Graphics Adapter ($map)`"`r`nAMD13FE.2 = `"AMD BC-250 Graphics Adapter ($map SUBSYS)`""
  }
  Set-Content -LiteralPath $inf -Value $txt -Encoding ASCII

  & $inf2cat /driver:$work /os:10_X64 | Out-Null
  if($LASTEXITCODE -ne 0){ Log "ITER $i inf2cat_fail=$LASTEXITCODE"; continue }
  & $sig sign /fd SHA256 /sha1 $cert.Thumbprint /s My (Join-Path $work 'u0397406.cat') | Out-Null
  if($LASTEXITCODE -ne 0){ Log "ITER $i sign_fail=$LASTEXITCODE"; continue }

  # Baseline sanitize
  pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
  pnputil /delete-driver oem9.inf /uninstall /force | Out-Null
  pnputil /scan-devices | Out-Null

  # Bind candidate
  pnputil /add-driver $inf /install | Out-Null
  & $devcon update $inf 'PCI\VEN_1002&DEV_13FE' | Out-Null

  # Probe windows before rollback
  $probes=@()
  foreach($d in $delays){
    if($d -gt 0){ Start-Sleep -Seconds $d }
    $p=Probe("t+$d")
    $probes += $p
    Log ("ITER {0} PROBE {1} inf={2} svc={3} code={4} pstatus={5}" -f $i,$p.tag,$p.inf,$p.svc,$p.code,$p.pstatus)
  }

  # Rollback
  & $devcon update C:\Windows\INF\display.inf 'PCI\VEN_1002&DEV_13FE' | Out-Null
  pnputil /scan-devices | Out-Null
  pnputil /restart-device "$inst" | Out-Null
  pnputil /remove-device ROOT\DISPLAY\0000 | Out-Null
  Start-Sleep -Seconds 2
  $post=Get-State
  Log ("ITER {0} ROLLBACK inf={1} code={2}" -f $i,$post.inf,$post.code)

  # compact row
  $rows += [pscustomobject]@{
    iteration=$i
    iter_id=$iterId
    map=$map
    p0_code=($probes | ? tag -eq 't+0' | Select-Object -ExpandProperty code)
    p2_code=($probes | ? tag -eq 't+2' | Select-Object -ExpandProperty code)
    p5_code=($probes | ? tag -eq 't+5' | Select-Object -ExpandProperty code)
    p10_code=($probes | ? tag -eq 't+10' | Select-Object -ExpandProperty code)
    p0_svc=($probes | ? tag -eq 't+0' | Select-Object -ExpandProperty svc)
    p2_svc=($probes | ? tag -eq 't+2' | Select-Object -ExpandProperty svc)
    p5_svc=($probes | ? tag -eq 't+5' | Select-Object -ExpandProperty svc)
    p10_svc=($probes | ? tag -eq 't+10' | Select-Object -ExpandProperty svc)
    rollback_inf=$post.inf
    rollback_code=$post.code
  }

  Log "ITER $i end"
  Start-Sleep -Seconds 2
}

$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
$summary=[pscustomobject]@{
  generated_at=(Get-Date).ToString('o')
  iterations=$rows.Count
  p0_code43=($rows|? {$_.p0_code -eq 43}).Count
  p2_code43=($rows|? {$_.p2_code -eq 43}).Count
  p5_code43=($rows|? {$_.p5_code -eq 43}).Count
  p10_code43=($rows|? {$_.p10_code -eq 43}).Count
  rollback_code0=($rows|? {$_.rollback_code -eq 0}).Count
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $sum
Log "POSTSTART_PROBE_BATCH end"
