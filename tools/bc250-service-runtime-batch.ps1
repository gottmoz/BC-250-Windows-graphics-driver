param(
  [int]$Iterations = 12,
  [string]$Map = 'ati2mtag_Rembrandt',
  [string]$OutDir = 'C:\Users\Public\bc250-service-runtime-batch'
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = Join-Path $OutDir 'run.log'
$csv = Join-Path $OutDir 'iterations.csv'
$sum = Join-Path $OutDir 'summary.json'
$inst = 'PCI\VEN_1002&DEV_13FE&SUBSYS_00001022&REV_00\4&19CAF403&0&0041'
$svcGpu = 'amduw23g'
$svcEvt = 'AMD External Events Utility'

function Log([string]$m) {
  "$((Get-Date).ToString('o')) $m" | Tee-Object -FilePath $log -Append
}

function Get-State {
  $p = Get-PnpDeviceProperty -InstanceId $inst -KeyName DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_ProblemCode,DEVPKEY_Device_Service -ErrorAction SilentlyContinue
  [pscustomobject]@{
    Inf = ($p | Where-Object KeyName -match 'DriverInfPath').Data
    Code = [int](($p | Where-Object KeyName -match 'ProblemCode').Data)
    Svc = ($p | Where-Object KeyName -match 'Device_Service').Data
  }
}

function Apply-Variant([string]$v) {
  switch ($v) {
    'svc_default' {
      sc.exe config $svcGpu start= demand | Out-Null
      sc.exe config "$svcEvt" start= auto | Out-Null
      sc.exe start "$svcEvt" | Out-Null
    }
    'svc_gpu_auto' {
      sc.exe config $svcGpu start= auto | Out-Null
      sc.exe start $svcGpu | Out-Null
    }
    'svc_evt_disabled' {
      sc.exe stop "$svcEvt" | Out-Null
      sc.exe config "$svcEvt" start= disabled | Out-Null
    }
    'svc_both_demand' {
      sc.exe stop $svcGpu | Out-Null
      sc.exe stop "$svcEvt" | Out-Null
      sc.exe config $svcGpu start= demand | Out-Null
      sc.exe config "$svcEvt" start= demand | Out-Null
    }
    'svc_gpu_restart' {
      sc.exe stop $svcGpu | Out-Null
      Start-Sleep -Seconds 1
      sc.exe start $svcGpu | Out-Null
    }
    'svc_evt_restart' {
      sc.exe stop "$svcEvt" | Out-Null
      Start-Sleep -Seconds 1
      sc.exe start "$svcEvt" | Out-Null
    }
  }
}

$variants = @(
  'svc_default',
  'svc_gpu_auto',
  'svc_evt_disabled',
  'svc_both_demand',
  'svc_gpu_restart',
  'svc_evt_restart'
)

$rows = @()
Log "SERVICE_RUNTIME_BATCH start iterations=$Iterations map=$Map"
for($i=1; $i -le $Iterations; $i++) {
  $v = $variants[($i-1) % $variants.Count]
  $t0 = Get-Date
  $evStart = $t0.AddSeconds(-2)
  Log "ITER $i variant=$v begin"
  Apply-Variant $v

  $out = powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\bc250-safe-iterate.ps1 -map $Map 2>&1
  foreach($ln in $out){ Log "ITER $i $ln" }

  $st = Get-State
  $scGpu = (sc.exe query $svcGpu) -join ' | '
  $scEvt = (sc.exe query "$svcEvt") -join ' | '
  $events = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$evStart} -ErrorAction SilentlyContinue |
    Where-Object {
      $_.ProviderName -match 'Service Control Manager|Kernel-PnP|Display|DriverFrameworks|CodeIntegrity' -or
      $_.Message -match 'amduw23g|AMD External Events Utility|VEN_1002|13FE|display'
    } |
    Select-Object -First 15 TimeCreated,ProviderName,Id,LevelDisplayName,Message
  $evCompact = ($events | ForEach-Object { "[{0:HH:mm:ss}] {1}/{2} {3}" -f $_.TimeCreated,$_.ProviderName,$_.Id,$_.LevelDisplayName }) -join ' || '

  $rows += [pscustomobject]@{
    iteration = $i
    ts = (Get-Date).ToString('o')
    map = $Map
    variant = $v
    state_inf = $st.Inf
    state_code = $st.Code
    state_service = $st.Svc
    sc_gpu = $scGpu
    sc_evt = $scEvt
    events = $evCompact
    result_code43 = [bool](($out -join "`n") -match 'CODE=43')
    rollback_code0 = [bool](($out -join "`n") -match 'ROLLBACK .*CODE=0')
  }

  Log "ITER $i end inf=$($st.Inf) code=$($st.Code) svc=$($st.Svc)"
  Start-Sleep -Seconds 2
}

$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
$summary = [pscustomobject]@{
  generated_at = (Get-Date).ToString('o')
  iterations = $rows.Count
  code43_count = ($rows | Where-Object result_code43).Count
  rollback_code0_count = ($rows | Where-Object rollback_code0).Count
  by_variant = ($rows | Group-Object variant | ForEach-Object {
    [pscustomobject]@{
      variant = $_.Name
      count = $_.Count
      code43 = ($_.Group | Where-Object result_code43).Count
      rb0 = ($_.Group | Where-Object rollback_code0).Count
    }
  })
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path $sum
Log "SERVICE_RUNTIME_BATCH end"
