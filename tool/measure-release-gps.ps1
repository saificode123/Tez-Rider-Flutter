[CmdletBinding()]
param([ValidateSet('foreground','background','recovery','routes','delivery-preflight','feedback-probe','customer-runtime')][string]$Mode = 'foreground')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if ((Get-Content (Join-Path $repo 'supabase/.temp/project-ref') -Raw).Trim() -cne 'igeisilhtmglgnqvllrx') { throw 'TEST required.' }
$private = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TezRider-FR21'
$sealed = Get-Content (Join-Path $private 'test-api-keys.dpapi') -Raw | ConvertTo-SecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sealed)
try { $env:FR21_TEST_KEYS_JSON = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
$env:FR21_PRIVATE_DIRECTORY = $private
try {
    & 'C:/Users/urreh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 (Join-Path $repo 'tests/integration/RELEASE-gps-measure.py') $Mode
    $result = $LASTEXITCODE
} finally { Remove-Item Env:FR21_TEST_KEYS_JSON,Env:FR21_PRIVATE_DIRECTORY -ErrorAction SilentlyContinue }
exit $result
