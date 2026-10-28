[CmdletBinding()]
param(
    [ValidateRange(30, 120)][int]$Seconds = 60,
    [ValidateSet('foreground', 'background', 'recovery', 'stopped', 'route', 'clocks')][string]$Label = 'foreground'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if ((Get-Content -LiteralPath (Join-Path $repo 'supabase/.temp/project-ref') -Raw).Trim() -cne 'igeisilhtmglgnqvllrx') {
    throw 'Authorized TEST link required.'
}
$private = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TezRider-FR21'
$protected = Get-Content -LiteralPath (Join-Path $private 'test-api-keys.dpapi') -Raw | ConvertTo-SecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($protected)
try { $env:FR21_TEST_KEYS_JSON = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
$env:FR21_PRIVATE_DIRECTORY = $private
try {
    & 'C:/Users/urreh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 (Join-Path $repo 'tests/integration/MASTER-gps-observe.py') $Seconds $Label
    $result = $LASTEXITCODE
} finally {
    Remove-Item Env:FR21_TEST_KEYS_JSON,Env:FR21_PRIVATE_DIRECTORY -ErrorAction SilentlyContinue
}
exit $result
