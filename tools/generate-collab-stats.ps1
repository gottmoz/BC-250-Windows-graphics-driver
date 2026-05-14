param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$testMatrix = Join-Path $RepoRoot 'TEST_MATRIX.md'
$progress = Join-Path $RepoRoot 'PROGRESS.md'
$statsDir = Join-Path $RepoRoot 'stats'

if (!(Test-Path $testMatrix) -or !(Test-Path $progress)) {
  throw "Missing TEST_MATRIX.md or PROGRESS.md"
}

$tm = Get-Content -Raw -Path $testMatrix
$pr = Get-Content -Raw -Path $progress

$tests = [regex]::Matches($tm, '(?m)^###\s+T-\d+').Count
$resultLines = [regex]::Matches($tm, '(?m)^-\s+Result:\s+(.+)$')
$pass = 0; $fail = 0; $buildFail = 0
foreach($m in $resultLines){
  $v = $m.Groups[1].Value.ToLowerInvariant()
  if($v -match 'build fail'){ $buildFail++ }
  elseif($v -match '^pass'){ $pass++ }
  elseif($v -match '^fail'){ $fail++ }
}

function CountPattern([string]$text, [string]$pattern){
  return [regex]::Matches($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
}

$patterns = [ordered]@{
  'status_0xC0000059' = '0xC0000059'
  'status_0xC00000E5' = '0xC00000E5'
  'problem_0x15_status_0x0' = 'Problem\s+0x15\s*/\s*Status\s+0x0'
  'code_43' = 'Code\s+43|CM_PROB_FAILED_POST_START\s*\(43\)'
  'cm_prob_failed_driver_entry' = 'CM_PROB_FAILED_DRIVER_ENTRY'
  'cm_prob_failed_add' = 'CM_PROB_FAILED_ADD'
}

$signal = [ordered]@{}
foreach($k in $patterns.Keys){
  $signal[$k] = [ordered]@{
    TEST_MATRIX = CountPattern $tm $patterns[$k]
    PROGRESS = CountPattern $pr $patterns[$k]
  }
}

$recentProgress = [regex]::Matches($pr, '(?m)^###\s+\d{4}-\d{2}-\d{2}[^\r\n]*') | ForEach-Object { $_.Value }
if($recentProgress.Count -gt 12){
  $recentProgress = $recentProgress | Select-Object -Last 12
}

$generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss K')
$today = (Get-Date).ToString('yyyy-MM-dd')

$data = [ordered]@{
  generated_at = $generated
  source_files = @('TEST_MATRIX.md','PROGRESS.md')
  totals = [ordered]@{
    test_entries = $tests
    result_lines = $resultLines.Count
    pass = $pass
    fail = $fail
    build_fail = $buildFail
  }
  key_signals = $signal
  recent_progress_markers = @($recentProgress)
  collaboration_next_steps = @(
    'Reproducera senaste stabila bas med hash-gate (B_EQ_C) innan varje test',
    'Halla DOD callback-shape som passerar init (inkl. ResetDevice) som fast baseline',
    'Logga AddDevice/StartDevice breadcrumbs till registry for varje iteration',
    'Publicera nya runs i TEST_MATRIX.md och PROGRESS.md med en-andring-per-test'
  )
}

$jsonPath = Join-Path $statsDir ("driver_status_{0}.json" -f $today)
$mdPath = Join-Path $statsDir ("driver_status_{0}.md" -f $today)

$data | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $jsonPath

$md = @()
$md += "# BC-250 Driver Stats ($today)"
$md += ""
$md += "Generated: $generated"
$md += ""
$md += "## Totals"
$md += "- Test entries (T-###): $tests"
$md += "- Result lines: $($resultLines.Count)"
$md += "- PASS: $pass"
$md += "- FAIL: $fail"
$md += "- BUILD FAIL: $buildFail"
$md += ""
$md += "## Key Signals"
foreach($k in $signal.Keys){
  $tmc = $signal[$k].TEST_MATRIX
  $prc = $signal[$k].PROGRESS
  $md += "- ${k}: TEST_MATRIX=$tmc, PROGRESS=$prc"
}
$md += ""
$md += "## Recent Progress Markers"
foreach($line in $recentProgress){ $md += "- $line" }
$md += ""
$md += "## Collaboration Next Steps"
foreach($step in $data.collaboration_next_steps){ $md += "- $step" }

$md | Set-Content -Encoding UTF8 $mdPath
Write-Output "WROTE: $jsonPath"
Write-Output "WROTE: $mdPath"
