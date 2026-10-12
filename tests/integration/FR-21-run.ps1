param([ValidateSet('backend','flutter','auth','device')][string]$Kind = 'backend',
    [ValidateSet('status','database','toggle','doubletap','start','stop','logs','networkoff','networkon','retry','assign','cancel','reject','crashbegin','crashend')][string]$DeviceAction = 'status')
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
try {
    $scriptFile = switch ($Kind) {
        'backend' { 'FR-21-hosted.py' }
        'flutter' { 'FR-21-flutter-hosted.py' }
        'auth' { 'FR-21-auth-regression.py' }
        'device' { 'FR-21-device.py' }
    }
    $scriptArguments = @()
    if ($Kind -eq 'device') { $scriptArguments = @($DeviceAction) }
    & 'C:/Users/urreh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' (Join-Path $PSScriptRoot $scriptFile) @scriptArguments
    $result = $LASTEXITCODE
} finally {
    Remove-Item Env:FR21_TEST_KEYS_JSON -ErrorAction SilentlyContinue
    Remove-Item Env:FR21_PRIVATE_DIRECTORY -ErrorAction SilentlyContinue
}
exit $result
