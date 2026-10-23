param(
  [Parameter(Mandatory = $true)][string]$AppKeyFile,
  [ValidateSet('A', 'B', 'A2')][string[]]$Variants = @('A2'),
  [int]$BuildNumber = 21,
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
  $appRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
  $currentRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
  if ($currentRoot.TrimEnd('\', '/') -ne $appRoot.TrimEnd('\', '/')) {
    throw 'Run this helper from its owning App worktree.'
  }
  $source = (& git rev-parse HEAD).Trim()
  $baseMain = (& git rev-parse main).Trim()
  if ($LASTEXITCODE -ne 0 -or $source -notmatch '^[0-9a-f]{40}$' -or $baseMain -notmatch '^[0-9a-f]{40}$') {
    throw 'Cannot resolve the source and main revisions.'
  }
  & git merge-base --is-ancestor $baseMain $source
  if ($LASTEXITCODE -ne 0) { throw 'Rebase onto the approved main before building candidates.' }
  & git diff --quiet HEAD -- lib android ios pubspec.yaml pubspec.lock tools/branding
  if ($LASTEXITCODE -ne 0) { throw 'Commit runtime, icon and build-tool changes before building.' }
  $pubspec = [System.IO.File]::ReadAllText((Join-Path $appRoot 'pubspec.yaml'))
  $buildInfo = [System.IO.File]::ReadAllText((Join-Path $appRoot 'lib/app/build_info.dart'))
  $reportSource = [System.IO.File]::ReadAllText((Join-Path $appRoot 'lib/diagnostics/performance_report.dart'))
  if ($pubspec -notmatch "(?m)^version:\s*0\.1\.0\+$BuildNumber\s*$" -or
      $buildInfo -notmatch "version\s*=\s*'0\.1\.0\+$BuildNumber'" -or
      $reportSource -notmatch "'appBuild':\s*'$BuildNumber'") {
    throw 'Build number must match the App and performance-report identities.'
  }
  $sdkRef = 'f684e02f38e652633c23fa8946a53d02b6aa3ea2'
  $lockPath = Join-Path $appRoot 'pubspec.lock'
  $lock = [System.IO.File]::ReadAllText($lockPath)
  foreach ($package in @('ugk_coach', 'ugk_trainer')) {
    $block = [regex]::Match($lock, "(?ms)^  ${package}:\r?\n.*?(?=^  \S|\z)").Value
    if (-not $block -or $block -notmatch "(?m)^      ref: $sdkRef\r?$" -or
        $block -notmatch "(?m)^      resolved-ref: $sdkRef\r?$") {
      throw 'SDK lock differs from the approved main revision.'
    }
  }
  $lockSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $lockPath).Hash.ToLowerInvariant()
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
    ('--dart-define=SMARTFIT_BUILD_SOURCE=' + $source),
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
    & $FlutterCommand build apk --release --no-pub --flavor internal --split-per-abi --target-platform android-arm64 --build-name 0.1.0 --build-number $BuildNumber "--dart-define=SMARTFIT_ICON_VARIANT=$variant" @defines *> $buildLog
    if ($LASTEXITCODE -ne 0) { throw "Icon $variant release build failed; inspect its private local build log." }
    $currentSource = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentSource -ne $source) { throw 'Source revision changed during build.' }
    & git diff --quiet HEAD -- lib android ios pubspec.yaml pubspec.lock tools/branding
    if ($LASTEXITCODE -ne 0) { throw 'Runtime, icon or build-tool files changed during build.' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $lockPath).Hash.ToLowerInvariant() -ne $lockSha) {
      throw 'Dependency lock bytes changed during build.'
    }
    $built = Join-Path $appRoot 'build/app/outputs/flutter-apk/app-arm64-v8a-internal-release.apk'
    $destination = Join-Path $OutputDirectory "SmartFit-0.1.0+$BuildNumber-internal-icon$variant.apk"
    Copy-Item -LiteralPath $built -Destination $destination
    $jniReport = Join-Path $OutputDirectory "storage-jni-icon$variant.json"
    & $PythonCommand tools/coach/verify_android_storage_jni.py --apk $destination --report $jniReport
    if ($LASTEXITCODE -ne 0) { throw "Icon $variant storage JNI gate failed." }
    $receipt = [ordered]@{
      variant = $variant
      sourceCommit = $source
      baseMain = $baseMain
      flavor = 'internal'
      versionName = '0.1.0'
      versionCode = (2000 + $BuildNumber)
      buildMode = 'release'
      abi = 'arm64-v8a'
      sdkRef = $sdkRef
      lockSha256 = $lockSha
      apk = [System.IO.Path]::GetFullPath($destination).Replace('\', '/')
      sizeBytes = (Get-Item -LiteralPath $destination).Length
      sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
      runtimeCleanBeforeAndAfterBuild = $true
      createdAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $receiptPath = Join-Path $OutputDirectory "build-icon$variant-receipt.json"
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($receiptPath), (($receipt | ConvertTo-Json -Depth 4) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    Write-Output "Built internal icon $variant arm64 release candidate; source and JNI checks passed."
  }
} finally {
  # Never print key contents or the complete build command.
  $content = $null
  $appKey = $null
  $defines = @()
}
