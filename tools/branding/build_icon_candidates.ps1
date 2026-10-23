param(
  [Parameter(Mandatory = $true)][string]$AppKeyFile,
  [ValidateSet('A', 'B')][string[]]$Variants = @('A', 'B'),
  [int]$BuildNumber = 17,
  [string]$MediaPrimaryUrl = '',
  [string]$MediaSecondaryUrl = '',
  [string]$FlutterCommand = 'flutter',
  [string]$PythonCommand = 'python',
  [string]$OutputDirectory = '.buildlog/brand-review/install'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$appKey = $null
$content = $null
$defines = @()
try {
  # Profile avoids importing unrelated main-branch release/JNI fixes into this
  # icon-only branch. These packages are for icon/colour review, not perf A/B.
  & $PythonCommand (Join-Path $PSScriptRoot 'build_icons.py') --check
  if ($LASTEXITCODE -ne 0) { throw 'Icon resource verification failed.' }
  $keyPath = (Resolve-Path -LiteralPath $AppKeyFile).Path
  $content = [System.IO.File]::ReadAllText($keyPath).Trim()
  $entries = [regex]::Matches($content, '(?i)X-App-Key[''"`]?\s*[:=\uFF1A]\s*[''"`]?([^\s''"`]+)')
  if ($entries.Count -eq 1) {
    $appKey = $entries[0].Groups[1].Value
  } elseif ($entries.Count -eq 0 -and $content -notmatch '\s') {
    $appKey = $content
  } else {
    throw 'Provide a file containing one Worker app key.'
  }
  if ([string]::IsNullOrWhiteSpace($appKey)) { throw 'Worker app key is empty.' }
  $content = $null
  $defines = @(
    ('--dart-define=SMARTFIT_AI_TOKEN=' + $appKey),
    '--dart-define=UGK_INTERNAL_MEDIA_PREVIEW=true',
    '--dart-define=SMARTFIT_INCLUDE_PENDING_MEDIA=true'
  )
  foreach ($entry in @(@('SMARTFIT_MEDIA_PRIMARY_URL', $MediaPrimaryUrl), @('SMARTFIT_MEDIA_SECONDARY_URL', $MediaSecondaryUrl))) {
    if (-not [string]::IsNullOrWhiteSpace($entry[1])) {
      $uri = [uri]$entry[1]
      if (-not $uri.IsAbsoluteUri -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.Scheme -notin @('http', 'https')) {
        throw 'Use an absolute public media URL without credentials, query, or fragment.'
      }
      $defines += '--dart-define=' + $entry[0] + '=' + $entry[1]
    }
  }
  New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
  foreach ($variant in $Variants) {
    $buildLog = Join-Path $OutputDirectory "build-icon$variant.log"
    & $FlutterCommand build apk --profile --no-pub --flavor internal --split-per-abi --target-platform android-arm64 --build-name 0.1.0 --build-number $BuildNumber "--dart-define=SMARTFIT_ICON_VARIANT=$variant" @defines *> $buildLog
    if ($LASTEXITCODE -ne 0) { throw "Icon $variant profile build failed; inspect its local build log." }
    $built = Join-Path (Get-Location) 'build/app/outputs/flutter-apk/app-arm64-v8a-internal-profile.apk'
    $destination = Join-Path $OutputDirectory "SmartFit-0.1.0+$BuildNumber-internal-icon$variant.apk"
    Copy-Item -LiteralPath $built -Destination $destination
    Write-Output "Built internal icon $variant profile candidate."
  }
} finally {
  # Never print key contents or the complete build command.
  $content = $null
  $appKey = $null
  $defines = @()
}
