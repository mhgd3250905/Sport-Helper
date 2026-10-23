param(
  [Parameter(Mandatory = $true)][string]$AppKeyFile,
  [ValidateSet('production', 'internal')][string]$Flavor = 'production',
  [string]$MediaPrimaryUrl = '',
  [string]$MediaSecondaryUrl = '',
  [string]$FlutterCommand = 'flutter',
  [string]$PythonCommand = 'python',
  [string]$BuildLog = '.buildlog/release-build.log'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$appKey = $null
$defines = @()
try {
  $keyPath = (Resolve-Path -LiteralPath $AppKeyFile).Path
  $content = [System.IO.File]::ReadAllText($keyPath).Trim()
  $matchesFound = [regex]::Matches($content, '(?i)X-App-Key[''"`]?\s*[:=\uFF1A]\s*[''"`]?([^\s''"`]+)')
  if ($matchesFound.Count -eq 1) {
    $appKey = $matchesFound[0].Groups[1].Value
  } elseif ($matchesFound.Count -eq 0 -and $content -notmatch '\s') {
    $appKey = $content
  } else {
    throw 'Provide one X-App-Key entry or a file containing only the Worker app key.'
  }
  if ([string]::IsNullOrWhiteSpace($appKey)) { throw 'Worker app key is empty.' }
  $content = $null
  $defines += '--dart-define=SMARTFIT_AI_TOKEN=' + $appKey
  if ($Flavor -eq 'internal') {
    $defines += '--dart-define=UGK_INTERNAL_MEDIA_PREVIEW=true'
    $defines += '--dart-define=SMARTFIT_INCLUDE_PENDING_MEDIA=true'
    $buildSource = & git rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $buildSource -notmatch '^[0-9a-f]{40}$') {
      throw 'Cannot identify the source revision for internal diagnostics.'
    }
    $defines += '--dart-define=SMARTFIT_BUILD_SOURCE=' + $buildSource
  }
  foreach ($entry in @(@('SMARTFIT_MEDIA_PRIMARY_URL', $MediaPrimaryUrl), @('SMARTFIT_MEDIA_SECONDARY_URL', $MediaSecondaryUrl))) {
    if (-not [string]::IsNullOrWhiteSpace($entry[1])) {
      $uri = [uri]$entry[1]
      if (-not $uri.IsAbsoluteUri -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
          $uri.Scheme -notin @('http', 'https') -or ($Flavor -eq 'production' -and $uri.Scheme -ne 'https')) {
        throw 'Use a public HTTPS media base URL; HTTP is allowed only in the separate internal build.'
      }
      $defines += '--dart-define=' + $entry[0] + '=' + $entry[1]
    }
  }
  $logDirectory = Split-Path -Parent $BuildLog
  if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
  }
  & $FlutterCommand build apk --release --split-per-abi --no-pub --flavor $Flavor @defines *> $BuildLog
  $buildStatus = $LASTEXITCODE
  if ($buildStatus -ne 0) { throw 'Release build failed; inspect the local build log.' }
  $jniChecker = Join-Path $PSScriptRoot 'verify_android_storage_jni.py'
  $reportDirectory = if ($logDirectory) { $logDirectory } else { '.' }
  foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
    $apkPath = Join-Path (Get-Location) "build/app/outputs/flutter-apk/app-$abi-$Flavor-release.apk"
    $reportPath = Join-Path $reportDirectory "storage-jni-$Flavor-$abi.json"
    & $PythonCommand $jniChecker --apk $apkPath --report $reportPath
    if ($LASTEXITCODE -ne 0) { throw 'Release APK failed the storage JNI compatibility check.' }
  }
} finally {
  # Never print the source contents, key, or complete build command.
  $content = $null
  $appKey = $null
  $defines = @()
}
Write-Output "Release APKs built for flavor: $Flavor (split per ABI)."
