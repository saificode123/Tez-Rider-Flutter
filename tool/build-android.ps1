[CmdletBinding()]
param(
    [ValidateSet('TEST', 'Production')][string]$Environment = 'TEST',
    [ValidateSet('apk', 'appbundle')][string]$Format = 'apk',
    [ValidateSet('debug', 'release')][string]$Mode = 'debug',
    [string]$DefinesFile,
    [string]$ProductionApplicationId,
    [string]$FlutterPath,
    [switch]$PreflightOnly,
    [switch]$CleanFlutterMetadata,
    [switch]$CleanOfflineIntermediates
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path -LiteralPath (Join-Path $repo 'pubspec.yaml'))) {
    throw 'Run this helper from the existing TezRider repository.'
}
if (-not $DefinesFile) {
    $DefinesFile = Join-Path $repo ('.fr21-local/' + $(if ($Environment -eq 'TEST') { 'public-defines.json' } else { 'production-defines.json' }))
}
$DefinesFile = (Resolve-Path -LiteralPath $DefinesFile).Path
$configuration = Get-Content -LiteralPath $DefinesFile -Raw | ConvertFrom-Json
$allowed = @('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'FR21_ISOLATED_TEST', 'FR30_ANDROID_PUSH', 'FR30_FIREBASE_PROJECT_ID')
foreach ($property in $configuration.PSObject.Properties.Name) {
    if ($property -notin $allowed) { throw 'Unrecognized define: keep credentials and server-only configuration out of mobile builds.' }
}
$expectedRef = if ($Environment -eq 'TEST') { 'igeisilhtmglgnqvllrx' } else { 'arrqsvejrfdbacfwtpcc' }
if ($configuration.SUPABASE_URL -cne "https://$expectedRef.supabase.co" -or
    $configuration.FR21_ISOLATED_TEST -isnot [bool] -or
    $configuration.FR21_ISOLATED_TEST -ne ($Environment -eq 'TEST')) {
    throw 'Backend URL and boolean isolation flag must match the requested environment.'
}
$publicKey = [string]$configuration.SUPABASE_ANON_KEY
if ($publicKey.StartsWith('sb_publishable_')) {
    if ($publicKey.Length -lt 24) { throw 'A configured publishable key is required.' }
} elseif ($publicKey.Split('.').Count -eq 3) {
    try {
        $payload = $publicKey.Split('.')[1].Replace('-', '+').Replace('_', '/')
        $payload = $payload.PadRight($payload.Length + ((4 - $payload.Length % 4) % 4), '=')
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    } catch { throw 'The public backend key is malformed.' }
    if ($claims.role -cne 'anon' -or $claims.ref -cne $expectedRef) {
        throw 'Only an anon key belonging to the requested backend is permitted.'
    }
} else { throw 'Only a public publishable or anon backend key is permitted.' }
if ($Environment -eq 'Production') {
    if ($Mode -ne 'release') { throw 'Production builds must use release mode.' }
    if ($ProductionApplicationId -notmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,}$' -or
        $ProductionApplicationId.StartsWith('com.example.')) {
        throw 'Supply the owner-approved production application ID.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $repo 'android/key.properties'))) {
        throw 'Private android/key.properties and its upload keystore are required for production.'
    }
    $signingText = Get-Content -LiteralPath (Join-Path $repo 'android/key.properties') -Raw
    foreach ($field in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
        if ($signingText -notmatch "(?m)^[ \t]*$field[ \t]*=[ \t]*\S[^\r\n]*\r?$") {
            throw 'Private signing configuration has missing fields. Complete it before a production build.'
        }
    }
    if ($configuration.FR30_ANDROID_PUSH -eq $true) {
        throw 'The existing Android push integration is TEST-only; production push is not qualified.'
    }
}
if ($Format -eq 'appbundle' -and $Mode -ne 'release') { throw 'App bundles require release mode.' }
if ($PreflightOnly) {
    Write-Output "PASS: $Environment configuration preflight. No build, installation or deployment executed."
    return
}
if ($CleanFlutterMetadata) {
    # Old depfiles may reference a removed Windows drive alias. Clear only
    # generated Flutter intermediates; retain dependencies, APKs and app data.
    $verifiedRoot = [IO.Path]::GetFullPath($repo).TrimEnd([IO.Path]::DirectorySeparatorChar)
    foreach ($relative in @('.dart_tool/flutter_build', 'build/app/intermediates/flutter')) {
        $generatedPath = [IO.Path]::GetFullPath((Join-Path $repo $relative))
        if (-not $generatedPath.StartsWith($verifiedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Generated metadata target escaped the repository.'
        }
        if (Test-Path -LiteralPath $generatedPath) {
            Remove-Item -LiteralPath $generatedPath -Recurse -Force
        }
    }
}
if (-not $FlutterPath) {
    $FlutterPath = (Get-Command flutter -ErrorAction Stop).Source
}
$flavor = if ($Environment -eq 'TEST') { 'fr21test' } else { 'production' }
$modeSuffix = if ($Mode -eq 'debug') { 'Debug' } else { 'Release' }
$variant = $flavor + $modeSuffix
$variantTitle = $variant.Substring(0, 1).ToUpperInvariant() + $variant.Substring(1)
if ($CleanOfflineIntermediates) {
    # OneDrive may leave historical generated binaries as offline placeholders.
    # Rebuild those files instead of hanging while the cloud provider recalls them.
    $appRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build/app'))
    $appBoundary = $appRoot + [IO.Path]::DirectorySeparatorChar
    $intermediates = Join-Path $appRoot 'intermediates'
    $apkOutputs = Join-Path $appRoot "outputs/apk/$flavor/$Mode"
    $flutterApk = Join-Path $appRoot "outputs/flutter-apk/app-$flavor-$Mode.apk"
    $candidates = @(
        if (Test-Path -LiteralPath $intermediates) {
            Get-ChildItem -LiteralPath $intermediates -Recurse -File | Where-Object {
                $_.FullName.Contains("\$variant\") -or $_.FullName.Contains("\package${variantTitle}\")
            }
        }
        if (Test-Path -LiteralPath $apkOutputs) { Get-ChildItem -LiteralPath $apkOutputs -Recurse -File }
        foreach ($path in @($flutterApk, "$flutterApk.sha1")) {
            if (Test-Path -LiteralPath $path) { Get-Item -LiteralPath $path }
        }
    )
    $removed = 0
    foreach ($file in $candidates) {
        $target = [IO.Path]::GetFullPath($file.FullName)
        if (-not $target.StartsWith($appBoundary, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Generated offline-file target escaped the app build directory.'
        }
        if (([long]$file.Attributes -band 0x401000) -ne 0) {
            Remove-Item -LiteralPath $target -Force
            $removed++
        }
    }
    Write-Output "Removed $removed offline generated files for $variant; sources and other variants retained."
}
$mergedAssets = [IO.Path]::GetFullPath((Join-Path $repo "build/app/intermediates/assets/$variant/merge${variantTitle}Assets"))
$verifiedBuildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build')) + [IO.Path]::DirectorySeparatorChar
if (-not $mergedAssets.StartsWith($verifiedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Generated merged-assets path escaped the build directory.'
}
# Gradle's directory cleanup fails for these deeply nested Windows paths.
# PowerShell/.NET handles them; do not remove sources, APKs or other variants.
if (Test-Path -LiteralPath $mergedAssets) {
    Remove-Item -LiteralPath $mergedAssets -Recurse -Force
}
# The resource merger uses the same deeply nested Windows cleanup path.
# Clear only this variant's generated merge state before Gradle recreates it.
foreach ($resourcePath in @(
    "incremental/$variant/merge${variantTitle}Resources",
    "incremental/$variant/package${variantTitle}Resources",
    "packaged_res/$variant/package${variantTitle}Resources"
)) {
    $mergedResources = [IO.Path]::GetFullPath((Join-Path $repo "build/app/intermediates/$resourcePath"))
    if (-not $mergedResources.StartsWith($verifiedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Generated merged-resources path escaped the build directory.'
    }
    if (Test-Path -LiteralPath $mergedResources) {
        Remove-Item -LiteralPath $mergedResources -Recurse -Force
    }
}
$outputDirectory = Join-Path $repo ('build/delivery/' + $Environment.ToLowerInvariant())
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$log = Join-Path $outputDirectory 'build.log'
$arguments = @('build', $Format, "--$Mode", '--flavor', $flavor, "--dart-define-from-file=$DefinesFile")
if ($Format -eq 'apk' -and $Environment -eq 'TEST') { $arguments += @('--target-platform', 'android-arm64') }
function Get-SourceManifest {
    @(git -C $repo ls-files --cached --others --exclude-standard -- lib assets android pubspec.yaml pubspec.lock | Sort-Object | ForEach-Object {
        $source = Join-Path $repo $_
        if (Test-Path -LiteralPath $source -PathType Leaf) { [ordered]@{ path = $_; sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash } }
    })
}
$sourceManifest = Get-SourceManifest
$oldApplicationId = $env:ORG_GRADLE_PROJECT_tezriderApplicationId
Push-Location -LiteralPath $repo
try {
    if ($Environment -eq 'Production') { $env:ORG_GRADLE_PROJECT_tezriderApplicationId = $ProductionApplicationId }
    # Use the configured Windows SDK directly; avoid launcher/bootstrap cache
    # repairs during a reproducible release build.
    $sdkBin = Split-Path $FlutterPath -Parent
    $dartRuntime = Join-Path $sdkBin 'cache/dart-sdk/bin/dart.exe'
    $flutterSnapshot = Join-Path $sdkBin 'cache/flutter_tools.snapshot'
    if ([IO.Path]::GetExtension($FlutterPath) -eq '.bat' -and
        (Test-Path -LiteralPath $dartRuntime) -and (Test-Path -LiteralPath $flutterSnapshot)) {
        & $dartRuntime $flutterSnapshot @arguments *> $log
    } else {
        & $FlutterPath @arguments *> $log
    }
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed. Inspect the ignored build/delivery log.' }
    $artifact = if ($Format -eq 'apk') {
        Join-Path $repo "build/app/outputs/flutter-apk/app-$flavor-$Mode.apk"
    } elseif ($Environment -eq 'TEST') {
        Join-Path $repo 'build/app/outputs/bundle/fr21testRelease/app-fr21test-release.aab'
    } else {
        Join-Path $repo 'build/app/outputs/bundle/productionRelease/app-production-release.aab'
    }
    if (-not (Test-Path -LiteralPath $artifact)) { throw 'Build returned without the expected Android artifact.' }
    if (($sourceManifest | ConvertTo-Json -Depth 4 -Compress) -cne ((Get-SourceManifest) | ConvertTo-Json -Depth 4 -Compress)) {
        throw 'Source changed during the build; rebuild before claiming this artifact matches current source.'
    }
    $destination = Join-Path $outputDirectory (Split-Path $artifact -Leaf)
    Copy-Item -LiteralPath $artifact -Destination $destination -Force
    @{
        environment = $Environment; project = $expectedRef; flavor = $flavor; mode = $Mode
        artifact = $destination; sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        head = (git -C $repo rev-parse HEAD); utc = [DateTime]::UtcNow.ToString('o'); sources = $sourceManifest
        installed = $false; productionDeployed = $false
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outputDirectory 'build-evidence.json') -Encoding utf8
    Write-Output "Built $destination. No installation or deployment executed."
} finally {
    $env:ORG_GRADLE_PROJECT_tezriderApplicationId = $oldApplicationId
    Pop-Location
}
