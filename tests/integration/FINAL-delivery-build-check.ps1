$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$helper = Join-Path $repo 'tool/build-android.ps1'
$directory = Join-Path $repo 'build/delivery/preflight-tests'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$fixture = Join-Path $directory 'defines.json'
$results = [Collections.Generic.List[object]]::new()
function Check-Configuration {
    param([string]$Name, [hashtable]$Configuration, [bool]$Allowed, [hashtable]$Arguments = @{})
    $Configuration | ConvertTo-Json | Set-Content -LiteralPath $fixture -Encoding utf8
    $accepted = $false
    try { & $helper -DefinesFile $fixture -PreflightOnly @Arguments | Out-Null; $accepted = $true } catch { }
    if ($accepted -ne $Allowed) { throw "Preflight assertion failed: $Name" }
    $results.Add(@{ test = $Name; result = 'PASS' })
}
$valid = @{ SUPABASE_URL = 'https://igeisilhtmglgnqvllrx.supabase.co'; SUPABASE_ANON_KEY = 'sb_publishable_fixture_not_a_real_key'; FR21_ISOLATED_TEST = $true }
Check-Configuration 'TEST accepts correctly isolated public configuration' $valid $true
$case = $valid.Clone(); $case.SUPABASE_URL = 'https://arrqsvejrfdbacfwtpcc.supabase.co'
Check-Configuration 'TEST rejects production endpoint' $case $false
$case = $valid.Clone(); $case.FR21_ISOLATED_TEST = $false
Check-Configuration 'TEST rejects disabled isolation' $case $false
$case = $valid.Clone(); $case.FR21_ISOLATED_TEST = 'true'
Check-Configuration 'TEST rejects string instead of boolean flag' $case $false
$case = $valid.Clone(); $case.SUPABASE_ANON_KEY = 'sb_secret_fixture_not_a_real_key'
Check-Configuration 'Mobile build rejects privileged key' $case $false
$case = $valid.Clone(); $case.SERVICE_ROLE_KEY = 'fixture'
Check-Configuration 'Mobile build rejects server-only define' $case $false
function New-FixtureJwt([string]$Role, [string]$Project) {
    $payload = @{ role = $Role; ref = $Project } | ConvertTo-Json -Compress
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    "fixture.$base64.fixture"
}
$case = $valid.Clone(); $case.SUPABASE_ANON_KEY = New-FixtureJwt 'service_role' 'igeisilhtmglgnqvllrx'
Check-Configuration 'Mobile build rejects service-role JWT' $case $false
$case = $valid.Clone(); $case.SUPABASE_ANON_KEY = New-FixtureJwt 'anon' 'arrqsvejrfdbacfwtpcc'
Check-Configuration 'TEST rejects JWT for another project' $case $false
Check-Configuration 'Production rejects TEST configuration' $valid $false @{ Environment = 'Production'; Mode = 'release' }
$case = $valid.Clone(); $case.SUPABASE_URL = 'https://arrqsvejrfdbacfwtpcc.supabase.co'; $case.FR21_ISOLATED_TEST = $false
Check-Configuration 'Production rejects debug mode' $case $false @{ Environment = 'Production'; Mode = 'debug' }
Check-Configuration 'Production requires approved application ID' $case $false @{ Environment = 'Production'; Mode = 'release' }
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $directory 'results.json') -Encoding utf8
Write-Output "$($results.Count) configuration preflight assertions PASS. No build, network or device operations executed."
