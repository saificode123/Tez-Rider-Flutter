$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$mirror='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-auth-debug/android-build-20261012-125502'
if(-not(Test-Path -LiteralPath $mirror)){throw 'Existing accepted Android build mirror required'}
if((Get-Content (Join-Path $repo 'supabase/.temp/project-ref') -Raw).Trim() -cne 'igeisilhtmglgnqvllrx'){throw 'Isolated TEST link required'}
$allowed=@('lib/controllers/rider_controller.dart','lib/screens/rider_dashboard.dart','lib/services/delivery_otp_service.dart','lib/services/pre_delivery_checklist_service.dart','lib/widgets/pre_delivery_checklist_card.dart')
foreach($source in Get-ChildItem -LiteralPath (Join-Path $repo 'lib') -File -Recurse){
 $relative=[IO.Path]::GetRelativePath($repo,$source.FullName).Replace('\','/')
 $destination=Join-Path $mirror $relative
 $exists=Test-Path -LiteralPath $destination
 $changed=-not $exists
 if(-not $changed){$changed=(Get-FileHash -LiteralPath $source.FullName).Hash -cne (Get-FileHash -LiteralPath $destination).Hash}
 if($changed){
  if($exists -and $relative -notin $allowed -and
      (Get-Content -LiteralPath $source.FullName -Raw).Replace("`r`n","`n") -cne
      (Get-Content -LiteralPath $destination -Raw).Replace("`r`n","`n")){
    throw "Unexpected stale mirror source: $relative"
  }
  New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
  Copy-Item -LiteralPath $source.FullName -Destination $destination -Force
 }
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
 if(-not(Test-Path -LiteralPath (Join-Path $mirror $name))){Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $mirror $name)}
}
$defines=Join-Path $repo '.fr21-local/public-defines.json'
$configuration=Get-Content -LiteralPath $defines -Raw | ConvertFrom-Json
if($configuration.SUPABASE_URL -cne 'https://igeisilhtmglgnqvllrx.supabase.co' -or $configuration.FR21_ISOLATED_TEST -ne $true -or $configuration.FR30_ANDROID_PUSH -ne $true){throw 'Accepted TEST build flags required'}
$log=Join-Path $repo '.fr21-local/checklist/build.log'
Push-Location -LiteralPath $mirror
try {
 & 'C:/Users/urreh/Downloads/flutter/bin/cache/dart-sdk/bin/dart.exe' 'C:/Users/urreh/Downloads/flutter/bin/cache/flutter_tools.snapshot' build apk --debug --flavor fr21test --target-platform android-arm64 --dart-define-from-file=$defines *> $log
 $result=$LASTEXITCODE
}finally{Pop-Location}
Get-Content -LiteralPath $log -Tail 4
exit $result
