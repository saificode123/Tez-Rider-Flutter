[CmdletBinding()]
param([ValidateSet('Rider','Delivery','Confirmation','Gps','Route','Travel','Stopped')][string]$Action = 'Rider')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if ((Get-Content (Join-Path $repo 'supabase/.temp/project-ref') -Raw).Trim() -cne 'igeisilhtmglgnqvllrx') { throw 'TEST target required.' }
$private = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TezRider-FR21'
$sealed = Get-Content (Join-Path $private 'test-api-keys.dpapi') -Raw | ConvertTo-SecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sealed)
try { $env:FR21_TEST_KEYS_JSON = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
$env:FR21_PRIVATE_DIRECTORY = $private
try {
    $script = switch ($Action) { 'Delivery' { 'AUTH-single-order-inspect.py' } 'Confirmation' { 'AUTH-order-confirmation.py' } { $_ -in 'Gps','Route','Travel','Stopped' } { 'AUTH-delivery-observe.py' } default { 'AUTH-rider-inspect.py' } }
    $arguments = @('-X','utf8',(Join-Path $repo ('tests/integration/' + $script)))
    if ($Action -in 'Gps','Route','Travel','Stopped') { $arguments += $Action.ToLowerInvariant() }
    & 'C:/Users/urreh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' @arguments
    $result = $LASTEXITCODE
} finally { Remove-Item Env:FR21_TEST_KEYS_JSON,Env:FR21_PRIVATE_DIRECTORY -ErrorAction SilentlyContinue }
exit $result
