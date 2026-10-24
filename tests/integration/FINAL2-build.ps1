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
# Storage cleanup removed older temporary mirror files. Restore missing sources
# from the existing project; retain the accepted low-memory/local Gradle setup.
foreach($directory in @('assets','android')){
 foreach($sourceDirectory in Get-ChildItem -LiteralPath (Join-Path $repo $directory) -Directory -Recurse){
  $relativeDirectory=[IO.Path]::GetRelativePath($repo,$sourceDirectory.FullName).Replace('\','/')
  if($relativeDirectory -match '(^|/)(\.gradle|\.kotlin|build)(/|$)'){continue}
  New-Item -ItemType Directory -Force -Path (Join-Path $mirror $relativeDirectory) | Out-Null
 }
 foreach($source in Get-ChildItem -LiteralPath (Join-Path $repo $directory) -File -Recurse){
  $relative=[IO.Path]::GetRelativePath($repo,$source.FullName).Replace('\','/')
  if($relative -match '(^|/)(\.gradle|\.kotlin|build)/' -or $relative -in @('android/gradle.properties','android/local.properties')){continue}
  $destination=Join-Path $mirror $relative
  if(-not(Test-Path -LiteralPath $destination)){
   New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
   Copy-Item -LiteralPath $source.FullName -Destination $destination
  }
 }
}
foreach($name in @('pubspec.yaml','pubspec.lock')){
 $source=Join-Path $repo $name
 $destination=Join-Path $mirror $name
 if(-not(Test-Path -LiteralPath $destination) -or (Get-FileHash -LiteralPath $source).Hash -cne (Get-FileHash -LiteralPath $destination).Hash){
  Copy-Item -LiteralPath $source -Destination $destination -Force
 }
 if((Get-FileHash -LiteralPath $source).Hash -cne (Get-FileHash -LiteralPath $destination).Hash){throw 'Mirror dependency manifest mismatch'}
 $manifest+=@{path=$name;sha256=(Get-FileHash -LiteralPath $source).Hash}
}
# Recreate only missing temporary configuration after OS cleanup.
foreach($name in @('gradle.properties','local.properties')){
 $destination=Join-Path $mirror ('android/'+$name)
 if(-not(Test-Path -LiteralPath $destination)){
  Copy-Item -LiteralPath (Join-Path $repo ('android/'+$name)) -Destination $destination
  if($name -eq 'gradle.properties'){
   $text=(Get-Content -LiteralPath $destination -Raw) -replace 'org.gradle.jvmargs=.*','org.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=768m -XX:+HeapDumpOnOutOfMemoryError'
   $text+="`norg.gradle.workers.max=2`n"
   Set-Content -LiteralPath $destination -Value $text -Encoding utf8
  }
 }
}
$log=Join-Path $repo '.fr21-local/final2/build.log'
Push-Location -LiteralPath $mirror
try {
 & 'C:/Users/urreh/Downloads/flutter/bin/cache/dart-sdk/bin/dart.exe' 'C:/Users/urreh/Downloads/flutter/bin/cache/flutter_tools.snapshot' build apk --debug --flavor fr21test --target-platform android-arm64 --dart-define-from-file=$defines *> $log
 $result=$LASTEXITCODE
}finally{Pop-Location}
if($result -ne 0){Write-Output 'TEST build failed; protected build log retained';exit $result}
$apk=Join-Path $mirror 'build/app/outputs/flutter-apk/app-fr21test-debug.apk'
$evidence=@{project='igeisilhtmglgnqvllrx';package='com.example.flutter_application_1.fr21test';apk=$apk;sha256=(Get-FileHash -LiteralPath $apk).Hash;sources=$manifest;head=(git -C $repo rev-parse HEAD)}
$evidence | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $repo '.fr21-local/final2/build-evidence.json') -Encoding utf8
Write-Output 'Current-source isolated TEST APK built; source and APK hashes recorded privately.'
