param([string]$Action='status',[ValidateSet('native','prerequisite','hosted','workflow','boundaries','lifecycle','final02','media','realtime','capability','capability-http')][string]$Kind='native')
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
 $scriptName=switch($Kind){
  'prerequisite' {'FINAL01-prerequisite-http.py'}
  'hosted' {'FINAL01-hosted.py'}
  'workflow' {'FINAL01-workflow.py'}
  'boundaries' {'FINAL01-boundaries.py'}
  'lifecycle' {'FINAL01-lifecycle.py'}
  'final02' {'FINAL02-enforcement.py'}
  'media' {'FINAL02-media.py'}
  'realtime' {'FINAL02-realtime.py'}
  'capability' {'FINAL02-capability.py'}
  'capability-http' {'FINAL02-capability-http.py'}
  default {'FINAL01-native.py'}
 }
 & 'C:/Users/urreh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -X utf8 (Join-Path $PSScriptRoot $scriptName) $Action
 $result=$LASTEXITCODE
}finally{Remove-Item Env:FR21_TEST_KEYS_JSON,Env:FR21_PRIVATE_DIRECTORY -ErrorAction SilentlyContinue}
exit $result
