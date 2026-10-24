param(
  [Parameter(Mandatory = $true)][string]$SigningPropertiesFile,
  [string]$OutputDirectory,
  [string]$MediaBaseUrl = 'https://smartfit-media.pages.dev/v0.3.0-app/',
  [string]$FlutterCommand = 'flutter',
  [switch]$Offline
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$signingFile = (Resolve-Path -LiteralPath $SigningPropertiesFile).Path
if ($signingFile.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Signing properties must be stored outside the repository.'
}
if (Test-Path -LiteralPath (Join-Path $projectRoot 'pubspec_overrides.yaml')) {
  throw 'Local dependency overrides are forbidden in the Play release.'
}

Push-Location $projectRoot
$savedEnvironment = @{}
$isolatedVariables = @(
  'SMARTFIT_SIGNING_PROPERTIES', 'DART_DEFINES', 'SMARTFIT_AI_TOKEN',
  'SMARTFIT_AI_BASE_URL', 'SMARTFIT_MEDIA_PRIMARY_URL',
  'SMARTFIT_MEDIA_SECONDARY_URL'
)
try {
  foreach ($variable in $isolatedVariables) {
    $savedEnvironment[$variable] = [Environment]::GetEnvironmentVariable($variable, 'Process')
    [Environment]::SetEnvironmentVariable($variable, $null, 'Process')
  }
  $env:SMARTFIT_SIGNING_PROPERTIES = $signingFile
  if (@(& git status --porcelain=v1 --untracked-files=all).Count -ne 0) {
    throw 'Build only from a clean, committed release source.'
  }
  $source = (& git rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0) { throw 'Cannot identify release source.' }
  $acceptedSource = 'f5332bfe3746ecbf69d3f5e48c71ba5c90812499'
  & python (Join-Path $PSScriptRoot 'validate_release_source.py')
  if ($LASTEXITCODE -ne 0) { throw 'Unapproved runtime or publication roster changes.' }
  $mediaUri = [Uri]$MediaBaseUrl
  if ($mediaUri.Scheme -ne 'https' -or $mediaUri.Host -ne 'smartfit-media.pages.dev' -or
      $mediaUri.UserInfo -or $mediaUri.Query -or $mediaUri.Fragment -or
      $mediaUri.AbsolutePath -ne '/v0.3.0-app/' -or -not $mediaUri.IsDefaultPort) {
    throw 'Only the verified public HTTPS media distribution root may be included.'
  }
  $pubspec = [IO.File]::ReadAllText((Join-Path $projectRoot 'pubspec.yaml'))
  $version = [regex]::Match($pubspec, '(?m)^version:\s*(1\.0\.0)\+(\d+)\s*$')
  if (-not $version.Success -or [int]$version.Groups[2].Value -le 22) {
    throw 'The 1.0 release must use version 1.0.0 and a build number above 22.'
  }
  $sdkRef = 'f684e02f38e652633c23fa8946a53d02b6aa3ea2'
  if ([regex]::Matches($pubspec, ('(?m)^\s+ref:\s*' + $sdkRef + '\s*$')).Count -ne 2) {
    throw 'Both SDK packages must remain pinned to the approved commit.'
  }
  $buildName = $version.Groups[1].Value
  $buildNumber = $version.Groups[2].Value
  if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $projectRoot ("build/store-release/$buildName+$buildNumber/$source")
  }
  $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
  New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
  $outputBundle = Join-Path $OutputDirectory ("SmartFit-$buildName+$buildNumber.aab")
  if (Test-Path -LiteralPath $outputBundle) { throw 'Refusing to overwrite a delivery bundle.' }

  $pubArguments = @('pub', 'get', '--enforce-lockfile')
  if ($Offline) { $pubArguments += '--offline' }
  & $FlutterCommand @pubArguments
  if ($LASTEXITCODE -ne 0) { throw 'Locked dependency resolution failed.' }
  & git diff --exit-code -- pubspec.lock
  if ($LASTEXITCODE -ne 0) { throw 'Locked dependencies changed.' }
  # Public media distribution is separate from AI. No AI credentials or endpoint.
  & $FlutterCommand build appbundle --release --flavor production --no-pub `
    "--build-name=$buildName" "--build-number=$buildNumber" `
    "--dart-define=SMARTFIT_BUILD_SOURCE=$source" `
    "--dart-define=SMARTFIT_MEDIA_PRIMARY_URL=$MediaBaseUrl"
  if ($LASTEXITCODE -ne 0) { throw 'Signed production app bundle build failed.' }
  if ((& git rev-parse HEAD).Trim() -ne $source -or
      @(& git status --porcelain=v1 --untracked-files=all).Count -ne 0) {
    throw 'Source changed during the build; discard this intermediate bundle and rebuild the committed source.'
  }
  $builtBundle = Join-Path $projectRoot 'build/app/outputs/bundle/productionRelease/app-production-release.aab'
  if (-not (Test-Path -LiteralPath $builtBundle)) { throw 'Expected signed bundle not found.' }
  Copy-Item -LiteralPath $builtBundle -Destination $outputBundle
  $manifest = [ordered]@{
    sourceCommit = $source
    acceptedRuntimeBaseline = $acceptedSource
    appInterfaceAndBusinessLogic = 'accepted flow retained; publication roster, two content adaptations and policy links corrected'
    applicationId = 'com.ugk.smartfit'
    versionName = $buildName
    versionCode = [int]$buildNumber
    sdkCommit = $sdkRef
    aiKeySupplied = $false
    aiEndpointSupplied = $false
    mediaMirrorSupplied = $true
    publicMediaBaseUrl = $MediaBaseUrl
    publishedAppActions = 93
    signing = 'external upload key; no debug-key fallback'
    bundle = $outputBundle
    bytes = (Get-Item -LiteralPath $outputBundle).Length
    sha256 = (Get-FileHash -LiteralPath $outputBundle -Algorithm SHA256).Hash.ToLowerInvariant()
    playConsoleActions = 'none'
    deviceVerification = 'pending; record separately after actual device testing'
  }
  $manifest | ConvertTo-Json -Depth 6 | Set-Content `
    -LiteralPath (Join-Path $OutputDirectory 'build-manifest.json') -Encoding utf8NoBOM
  Write-Output "Signed base-edition bundle: $outputBundle"
  Write-Output "Source: $source; version: $buildName+$buildNumber; API key: not supplied."
} finally {
  foreach ($variable in $isolatedVariables) {
    [Environment]::SetEnvironmentVariable($variable, $savedEnvironment[$variable], 'Process')
  }
  Pop-Location
}
