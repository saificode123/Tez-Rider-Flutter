param([string]$Action='status',[ValidateSet('native','prerequisite','hosted','workflow','boundaries','lifecycle')][string]$Kind='native')
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
 & 'C:/Users/urreh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 (Join-Path $PSScriptRoot $(if($Kind -eq 'prerequisite'){'FINAL01-prerequisite-http.py'}elseif($Kind -eq 'hosted'){'FINAL01-hosted.py'}elseif($Kind -eq 'workflow'){'FINAL01-workflow.py'}elseif($Kind -eq 'boundaries'){'FINAL01-boundaries.py'}elseif($Kind -eq 'lifecycle'){'FINAL01-lifecycle.py'}else{'FINAL01-native.py'})) $Action
 $result=$LASTEXITCODE
}finally{Remove-Item Env:FR21_TEST_KEYS_JSON,Env:FR21_PRIVATE_DIRECTORY -ErrorAction SilentlyContinue}
exit $result
