param([ValidateSet('tests','sql','verify','ttl','device','artifact','canonical')][string]$Kind='tests',[string]$DeviceAction='status')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location -LiteralPath $repo
if((Get-Content 'supabase/.temp/project-ref' -Raw).Trim() -cne 'igeisilhtmglgnqvllrx'){throw 'Dedicated TEST link required'}
$privateDirectory=Join-Path $env:LOCALAPPDATA 'TezRider-FR21'
$protected=Get-Content (Join-Path $privateDirectory 'test-api-keys.dpapi') -Raw | ConvertTo-SecureString
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($protected)
try{$env:FR21_TEST_KEYS_JSON=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)}
$env:FR21_PRIVATE_DIRECTORY=$privateDirectory
$env:FR26_DEVICE_ACTION=$DeviceAction
try {
 & 'C:/Users/urreh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 (Join-Path $PSScriptRoot 'FR-26-hosted.py') $Kind
 $result=$LASTEXITCODE
}finally{Remove-Item Env:FR21_TEST_KEYS_JSON,Env:FR21_PRIVATE_DIRECTORY,Env:FR26_DEVICE_ACTION -ErrorAction SilentlyContinue}
exit $result
