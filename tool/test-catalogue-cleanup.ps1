[CmdletBinding()]
param(
    [ValidateSet('plan','apply','rollback','verify')][string]$Mode='plan',
    [string]$ApprovedSha256
)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
if ((Get-Content -LiteralPath (Join-Path $repo 'supabase/.temp/project-ref') -Raw).Trim() -cne 'igeisilhtmglgnqvllrx') { throw 'Authorized TEST required.' }
if ($Mode -ne 'plan' -and $ApprovedSha256 -notmatch '^[0-9a-f]{64}$') { throw 'Review and explicitly authorize the exact manifest SHA-256 before invoking a change.' }
$private=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TezRider-FR21'
$protected=Get-Content -LiteralPath (Join-Path $private 'test-api-keys.dpapi') -Raw | ConvertTo-SecureString
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($protected)
try { $env:FR21_TEST_KEYS_JSON=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
$env:FR21_PRIVATE_DIRECTORY=$private
try {
    $arguments=@((Join-Path $repo 'tests/integration/MASTER-catalogue-cleanup.py'),$Mode)
    if ($Mode -ne 'plan') { $arguments+=$ApprovedSha256 }
    & 'C:/Users/urreh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 @arguments
    $result=$LASTEXITCODE
} finally { Remove-Item Env:FR21_TEST_KEYS_JSON,Env:FR21_PRIVATE_DIRECTORY -ErrorAction SilentlyContinue }
exit $result
