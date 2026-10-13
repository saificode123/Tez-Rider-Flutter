param([ValidateSet('storage','tests','ttl','backup','load','device','artifact','acceptance-read')][string]$Kind = 'tests',
    [string]$DeviceAction = 'status')
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location -LiteralPath $repo
if ((Get-Content -LiteralPath 'supabase/.temp/project-ref' -Raw).Trim() -cne 'igeisilhtmglgnqvllrx') {
    throw 'Dedicated TEST link required'
}
$privateDirectory = Join-Path $env:LOCALAPPDATA 'TezRider-FR21'
$keyFile = Join-Path $privateDirectory 'test-api-keys.dpapi'
if (-not (Test-Path -LiteralPath $keyFile)) { throw 'Protected TEST key configuration is missing' }
$protected = Get-Content -LiteralPath $keyFile -Raw | ConvertTo-SecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($protected)
try {
    $env:FR21_TEST_KEYS_JSON = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
}
$env:FR21_PRIVATE_DIRECTORY = $privateDirectory
$env:FR04_DEVICE_ACTION = $DeviceAction
try {
    & 'C:/Users/urreh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' (Join-Path $PSScriptRoot 'FR-04-hosted.py') $Kind
    $result = $LASTEXITCODE
} finally {
    Remove-Item Env:FR21_TEST_KEYS_JSON -ErrorAction SilentlyContinue
    Remove-Item Env:FR21_PRIVATE_DIRECTORY -ErrorAction SilentlyContinue
    Remove-Item Env:FR04_DEVICE_ACTION -ErrorAction SilentlyContinue
}
exit $result
