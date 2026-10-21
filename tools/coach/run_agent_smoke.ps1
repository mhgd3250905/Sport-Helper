param(
  [Parameter(Mandatory = $true)][string]$AppKeyFile,
  [string]$FlutterCommand = 'flutter',
  [string]$SmokeLog = '.buildlog/skill-agent-live.log',
  [switch]$MemoryOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$appKey = $null
$define = $null
$content = $null
try {
  $content = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $AppKeyFile)).Trim()
  $found = [regex]::Matches($content, '(?i)X-App-Key[''"`]?\s*[:=\uFF1A]\s*[''"`]?([^\s''"`]+)')
  if ($found.Count -eq 1) { $appKey = $found[0].Groups[1].Value }
  elseif ($found.Count -eq 0 -and $content -notmatch '\s') { $appKey = $content }
  else { throw 'Provide exactly one Worker X-App-Key entry.' }
  if ([string]::IsNullOrWhiteSpace($appKey)) { throw 'Worker app key is empty.' }
  $define = '--dart-define=SMARTFIT_AI_TOKEN=' + $appKey
  $directory = Split-Path -Parent $SmokeLog
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }
  $smokeOptions = @('--dart-define=SMARTFIT_RUN_LIVE=true')
  if ($MemoryOnly) { $smokeOptions += '--dart-define=SMARTFIT_SMOKE_MEMORY_ONLY=true' }
  & $FlutterCommand test --no-pub 'tools/coach/worker_agent_smoke.dart' @smokeOptions $define --reporter expanded *> $SmokeLog
  $runExit = $LASTEXITCODE
} finally {
  $appKey = $null
  $define = $null
  $content = $null
}
if ($runExit -ne 0) { throw 'Worker smoke did not pass; inspect the local smoke report.' }
Write-Output 'Worker Agent smoke completed; results are saved under .buildlog/skill-agent-smoke.'
