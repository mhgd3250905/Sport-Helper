param(
  [Parameter(Mandatory = $true)][string]$AppKeyFile,
  [string]$FlutterCommand = 'flutter',
  [string]$BuildLog = '.buildlog/ai-debug-build.log'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$buildStatus = 1
$appKey = $null
$define = $null
try {
  $content = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $AppKeyFile)).Trim()
  # A shared local note may contain an upstream API key as well. Only use
  # the explicitly labelled Worker app key; never select an upstream key.
  $matchesFound = [regex]::Matches($content, '(?i)X-App-Key[''"`]?\s*[:=：]\s*[''"`]?([^\s''"`]+)')
  if ($matchesFound.Count -eq 1) {
    $appKey = $matchesFound[0].Groups[1].Value
  } elseif ($matchesFound.Count -eq 0 -and $content -notmatch '\s') {
    $appKey = $content
  } else {
    throw 'Provide one X-App-Key entry or a file containing only the Worker app key.'
  }
  if ([string]::IsNullOrWhiteSpace($appKey)) { throw 'Worker app key is empty.' }
  $content = $null
  $define = '--dart-define=SMARTFIT_AI_TOKEN=' + $appKey
  $logDirectory = Split-Path -Parent $BuildLog
  if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
  }
  & $FlutterCommand build apk --debug --no-pub $define *> $BuildLog
  $buildStatus = $LASTEXITCODE
} finally {
  # Never echo the key, command argument, or source file contents.
  $appKey = $null
  $define = $null
  $content = $null
}
if ($buildStatus -ne 0) { throw 'Android build failed; inspect the local build log.' }
Write-Output 'Android debug APK built with the Worker app key supplied by --dart-define.'
