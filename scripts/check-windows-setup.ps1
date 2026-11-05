[CmdletBinding()]
param(
    [string]$EnvFile = '.env',
    [switch]$SkipDeviceCheck
)
# Read-only preflight. Does not install software, change settings or send messages.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$failures = 0
function Result([bool]$Ok, [string]$Label, [string]$Fix) {
    if ($Ok) { Write-Output "PASS: $Label" }
    else { $script:failures++; Write-Output "FAIL: $Label. $Fix" }
}
Push-Location -LiteralPath $repo
try {
    $driveName = [IO.Path]::GetPathRoot($repo).TrimEnd('\').TrimEnd(':')
    $drive = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
    if ($drive -and $null -ne $drive.Free) {
        Result ($drive.Free -ge 2GB) 'At least 2 GB free build working space' 'Free space on the project drive before a full build; reserve 10 GB or more for a fresh toolchain/dependency download (planning allowance, not a guarantee).'
    }
    $git = Get-Command git -ErrorAction SilentlyContinue
    Result ($null -ne $git) 'Git available' 'Install Git for Windows and reopen PowerShell.'
    if ($git) {
        $head = & git rev-parse HEAD 2>$null
        $branch = & git branch --show-current 2>$null
        Write-Output "INFO: Branch $branch; commit $head"
        & git merge-base --is-ancestor 2a059547a3054b35d34d6e81c181ef8879e2c19b HEAD 2>$null
        Result ($LASTEXITCODE -eq 0) 'Shared baseline included' 'Fetch origin and select feature/final-2-functional; preserve local changes first.'
        if ($branch -notin @('main', 'feature/final-2-functional', 'feature/final-customer-delivery-fixes')) {
            Write-Output 'WARN: Use the reviewed delivery branch or the exact verified commit from the acceptance report.'
        }
    }
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    Result ($null -ne $flutter) 'Flutter available' 'Add the Flutter SDK bin folder to PATH, then reopen PowerShell.'
    $doctor = ''
    if ($flutter) {
        $versionText = (& $flutter.Source --version --machine 2>$null) -join "`n"
        try {
            $version = $versionText | ConvertFrom-Json
            Result ($version.frameworkVersion -eq '3.47.6' -and $version.channel -eq 'stable') 'Verified Flutter 3.47.6 stable' 'Use the verified SDK version; see docs/PARTNER-WINDOWS-SETUP.md.'
            $dartVersion = [regex]::Match([string]$version.dartSdkVersion, '^\d+\.\d+\.\d+').Value
            Result ($dartVersion -and [version]$dartVersion -ge [version]'3.13.0') 'Dart >=3.13.0' 'Use Dart bundled with Flutter 3.47.6; do not install a separate Dart SDK.'
        } catch { Result $false 'Flutter version readable' 'Run flutter --version and resolve its first error.' }
        $doctor = (& $flutter.Source doctor -v 2>&1 | Out-String)
        $javaPath = [regex]::Match($doctor, 'Java binary at:\s*([^\r\n]+)').Groups[1].Value.Trim()
        if ($javaPath -and -not (Test-Path -LiteralPath $javaPath) -and (Test-Path -LiteralPath ($javaPath + '.exe'))) { $javaPath += '.exe' }
        if ($javaPath -and (Test-Path -LiteralPath $javaPath)) {
            $previousErrorPolicy = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $javaText = (& $javaPath -version 2>&1 | Out-String)
            } finally { $ErrorActionPreference = $previousErrorPolicy }
            Result ($javaText -match 'version "17\.') 'Flutter-selected JDK 17' 'Install Temurin 17 and set flutter config --jdk-dir to its installation directory.'
        } else { Result $false 'Flutter-selected Java available' 'Run flutter doctor -v and configure JDK 17.' }
        $sdk = [regex]::Match($doctor, 'Android SDK at\s*([^\r\n]+)').Groups[1].Value.Trim()
        Result ([bool]$sdk -and (Test-Path -LiteralPath $sdk)) 'Android SDK detected' 'Set the Android SDK location in Android Studio, then rerun flutter doctor -v.'
        if ($sdk -and (Test-Path -LiteralPath $sdk)) {
            foreach ($component in @('platforms/android-36', 'build-tools/35.0.0', 'ndk/28.2.13676358', 'platform-tools/adb.exe', 'cmdline-tools')) {
                Result (Test-Path -LiteralPath (Join-Path $sdk $component)) "Android component $component" 'Install this component using Android Studio > SDK Manager (Show Package Details).'
            }
            Result ($doctor -match 'All Android licenses accepted') 'Android licenses accepted' 'Run flutter doctor --android-licenses.'
        }
    }
    $path = if ([IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repo $EnvFile }
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    Result $exists 'Compile-time environment file present' 'Copy .env.example to .env and obtain approved TEST public configuration privately.'
    $values = @{}
    if ($exists) {
        $raw = Get-Content -LiteralPath $path -Raw
        if ($raw.TrimStart().StartsWith('{')) {
            try {
                $json = $raw | ConvertFrom-Json
                foreach ($p in $json.PSObject.Properties) { $values[$p.Name] = [string]$p.Value }
            } catch { Result $false 'Environment JSON valid' 'Use the KEY=VALUE format from .env.example or valid JSON.' }
        } else {
            foreach ($line in ($raw -split '\r?\n')) {
                $text = $line.Trim()
                if (-not $text -or $text.StartsWith('#')) { continue }
                if ($text -notmatch '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
                    Result $false 'Environment line valid' 'Use one KEY=VALUE per line; do not paste shell commands.'
                    continue
                }
                $name = $Matches[1]
                $value = $Matches[2].Trim()
                if ($value -match '^(["''])(.*)\1\s*(?:#.*)?$') { $value = $Matches[2] }
                else { $value = ($value -split '#', 2)[0].Trim() }
                Result (-not $values.ContainsKey($name)) "Unique configuration name $name" 'Remove duplicate entries.'
                $values[$name] = $value
            }
        }
        Result ($values['SUPABASE_URL'] -ceq 'https://igeisilhtmglgnqvllrx.supabase.co') 'Authorized TEST backend' 'Use only the authorized TEST URL from .env.example.'
        Result ($values['FR21_ISOLATED_TEST'] -ieq 'true') 'TEST isolation explicitly enabled' 'Set FR21_ISOLATED_TEST=true.'
        $anon = [string]$values['SUPABASE_ANON_KEY']
        $publishable = [string]$values['SUPABASE_PUBLISHABLE_KEY']
        Result (-not ($anon -and $publishable -and $anon -cne $publishable)) 'Public key names unambiguous' 'Set only SUPABASE_PUBLISHABLE_KEY or SUPABASE_ANON_KEY.'
        $key = if ($anon) { $anon } else { $publishable }
        $keyOk = $key.StartsWith('sb_publishable_') -and $key.Length -ge 24
        if ($key.Split('.').Count -eq 3) {
            try {
                $payload = $key.Split('.')[1].Replace('-', '+').Replace('_', '/')
                $payload = $payload.PadRight($payload.Length + ((4 - $payload.Length % 4) % 4), '=')
                $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
                $keyOk = $claims.role -ceq 'anon' -and $claims.ref -ceq 'igeisilhtmglgnqvllrx'
            } catch { $keyOk = $false }
        }
        Result $keyOk 'Public client key configured' 'Obtain a TEST publishable/anon key; never use service-role or sb_secret keys.'
        $allowed = @('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_PUBLISHABLE_KEY', 'FR21_ISOLATED_TEST', 'FR30_ANDROID_PUSH', 'FR30_FIREBASE_PROJECT_ID')
        foreach ($name in $values.Keys) {
            if ($name -notin $allowed) {
                if ($name -eq 'SUPABASE_JWKS_URL') { Write-Output 'WARN: SUPABASE_JWKS_URL is unused by Flutter; remove it from the mobile defines file.' }
                else { Result $false 'Only documented mobile configuration names' 'Remove server-only or unknown settings; see .env.example.' }
            }
        }
        $push = $values['FR30_ANDROID_PUSH'] -ieq 'true'
        Result ($values['FR30_ANDROID_PUSH'] -imatch '^(true|false)$') 'Push flag is explicit' 'Set FR30_ANDROID_PUSH=true for full Android TEST notification acceptance, or false for a documented push-disabled build.'
        $firebasePath = Join-Path $repo 'android/app/src/fr21test/google-services.json'
        if ($push) {
            Result (Test-Path -LiteralPath $firebasePath) 'TEST Firebase file present' 'Obtain the approved TEST Firebase client file; do not copy the root legacy configuration.'
        }
        if (Test-Path -LiteralPath $firebasePath) {
            try {
                $firebase = Get-Content -LiteralPath $firebasePath -Raw | ConvertFrom-Json
                $packages = @($firebase.client | ForEach-Object { $_.client_info.android_client_info.package_name })
                Result ($firebase.project_info.project_id -ceq 'tez-rider-fe12b' -and $packages -ccontains 'com.example.flutter_application_1.fr21test') 'Firebase TEST project and package match' 'Download the registered fr21test Android client from the approved TEST Firebase project.'
            } catch { Result $false 'Firebase JSON readable' 'Download the original google-services.json again.' }
        }
        if ($push) {
            Result ($values['FR30_FIREBASE_PROJECT_ID'] -ceq 'tez-rider-fe12b') 'Firebase define matches TEST project' 'Set FR30_FIREBASE_PROJECT_ID=tez-rider-fe12b.'
        }
        if ($git) {
            $trackedConfig = @(& git ls-files -- $EnvFile)
            Result ($trackedConfig.Count -eq 0) 'Local configuration untracked' 'Do not commit credentials. Review tracking before sharing.'
        }
    }
    if ($flutter -and -not $SkipDeviceCheck) {
        $devicesText = (& $flutter.Source devices --machine 2>$null) -join "`n"
        try {
            $devices = @($devicesText | ConvertFrom-Json)
            $android = @($devices | Where-Object { $_.targetPlatform -like 'android*' })
            Result ($android.Count -gt 0) 'Android device available' 'Start an Android emulator or enable USB debugging, accept the phone RSA prompt and install its OEM driver.'
        } catch { Result $false 'Device inventory readable' 'Run flutter devices and adb devices to diagnose.' }
    }
    Write-Output "RESULT: $failures failure(s). No configuration values or credentials displayed."
} finally { Pop-Location }
if ($failures -gt 0) { exit 1 }
exit 0
