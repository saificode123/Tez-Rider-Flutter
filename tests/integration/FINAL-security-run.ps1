param([ValidateSet('hosted')][string]$Kind='hosted')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location -LiteralPath $repo
if((Get-Content 'supabase/.temp/project-ref' -Raw).Trim() -cne 'igeisilhtmglgnqvllrx'){throw 'Dedicated TEST link required'}
$privateDirectory=Join-Path $env:LOCALAPPDATA 'TezRider-FR21'
$protected=Get-Content (Join-Path $privateDirectory 'test-api-keys.dpapi') -Raw | ConvertTo-SecureString
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($protected)
try{$env:FR21_TEST_KEYS_JSON=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)}
$env:FR21_PRIVATE_DIRECTORY=$privateDirectory
try {
 & 'C:/Users/urreh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 (Join-Path $PSScriptRoot 'FINAL-security-hosted.py')
 $result=$LASTEXITCODE
}finally{Remove-Item Env:FR21_TEST_KEYS_JSON,Env:FR21_PRIVATE_DIRECTORY -ErrorAction SilentlyContinue}
exit $result
