$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$mirror='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-auth-debug/android-build-20261012-125502'
if(-not(Test-Path -LiteralPath $mirror)){throw 'Existing configured Android build mirror required'}
if((Get-Content (Join-Path $repo 'supabase/.temp/project-ref') -Raw).Trim() -cne 'igeisilhtmglgnqvllrx'){throw 'TEST link required'}
$defines=Join-Path $repo '.fr21-local/public-defines.json'
$configuration=Get-Content -LiteralPath $defines -Raw | ConvertFrom-Json
if($configuration.SUPABASE_URL -cne 'https://igeisilhtmglgnqvllrx.supabase.co' -or $configuration.FR21_ISOLATED_TEST -ne $true){throw 'Isolated TEST flags required'}
$manifest=@()
foreach($relative in @(git -C $repo ls-files --cached --others --exclude-standard -- lib)){
 $source=Join-Path $repo $relative
 $destination=Join-Path $mirror $relative
 if(-not(Test-Path -LiteralPath $source)){throw 'Tracked source missing'}
 New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
 if(-not(Test-Path -LiteralPath $destination) -or (Get-FileHash -LiteralPath $source).Hash -cne (Get-FileHash -LiteralPath $destination).Hash){
  Copy-Item -LiteralPath $source -Destination $destination -Force
 }
 if((Get-FileHash -LiteralPath $source).Hash -cne (Get-FileHash -LiteralPath $destination).Hash){throw 'Mirror source mismatch'}
 $manifest+=@{path=$relative;sha256=(Get-FileHash -LiteralPath $source).Hash}
}
$log=Join-Path $repo '.fr21-local/final03/build.log'
Push-Location -LiteralPath $mirror
try {
 & 'C:/Users/urreh/Downloads/flutter/bin/cache/dart-sdk/bin/dart.exe' 'C:/Users/urreh/Downloads/flutter/bin/cache/flutter_tools.snapshot' build apk --debug --flavor fr21test --target-platform android-arm64 --dart-define-from-file=$defines *> $log
 $result=$LASTEXITCODE
}finally{Pop-Location}
if($result -ne 0){Write-Output 'TEST build failed; protected build log retained';exit $result}
$apk=Join-Path $mirror 'build/app/outputs/flutter-apk/app-fr21test-debug.apk'
$evidence=@{project='igeisilhtmglgnqvllrx';package='com.example.flutter_application_1.fr21test';apk=$apk;sha256=(Get-FileHash -LiteralPath $apk).Hash;sources=$manifest;head=(git -C $repo rev-parse HEAD)}
$evidence | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $repo '.fr21-local/final03/build-evidence.json') -Encoding utf8
Write-Output 'Current-source isolated TEST APK built; source and APK hashes recorded privately.'

