"""Static readiness only: never substitutes for an Xcode build/iPhone test."""
import hashlib,json,platform,plistlib,re,shutil,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BASE='3408790d7c556665228d4c1cca371c4018a07cea'
def accepted(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT).decode().replace('\r\n','\n')
def read(path):return(ROOT/path).read_text(encoding='utf-8-sig')
assert read('supabase/.temp/project-ref').strip()=='igeisilhtmglgnqvllrx'
info=plistlib.loads((ROOT/'ios/Runner/Info.plist').read_bytes())
assert info['UIBackgroundModes']==['location']
assert 'NSLocationWhenInUseUsageDescription'in info
assert not any('Always'in key for key in info)
framework=plistlib.loads((ROOT/'ios/Flutter/AppFrameworkInfo.plist').read_bytes())
assert framework['MinimumOSVersion']=='15.0'
project=read('ios/Runner.xcodeproj/project.pbxproj')
assert re.findall(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);',project)==['15.0']*3
assert 'com.apple.BackgroundModes'in project
pod=read('ios/Podfile');assert "platform :ios, '15.0'"in pod and 'BYPASS_PERMISSION_LOCATION_ALWAYS=1'in pod
for name in ('Debug','Release'):
 assert 'Pods-Runner.'+name.lower()+'.xcconfig'in read('ios/Flutter/'+name+'.xcconfig')
source=read('lib/services/delivery_location_platform.dart')
pattern=r'class AndroidRiderLocationSource.*?(?=\nclass SupabaseDeliveryLocationBackend)'
android=re.search(pattern,source,re.S)[0]
assert android==re.search(pattern,accepted('lib/services/delivery_location_platform.dart'),re.S)[0]
assert source.split('class SupabaseDeliveryLocationBackend',1)[1]==accepted('lib/services/delivery_location_platform.dart').split('class SupabaseDeliveryLocationBackend',1)[1]
for path in ('android/app/src/main/AndroidManifest.xml','lib/screens/map_screen.dart','lib/screens/customer/order_history_screen.dart','ios/Runner/AppDelegate.swift','pubspec.yaml','pubspec.lock'):
 assert read(path)==accepted(path),'Unexpected change: '+path
changed=subprocess.check_output(['git','diff','--name-only',BASE],cwd=ROOT,text=True).splitlines()
assert not any(path.startswith(('supabase/','android/'))for path in changed)
tools={name:shutil.which(name)is not None for name in ('xcodebuild','xcrun','pod','sw_vers','ruby')}
result={'scope':'FR-13 iOS static readiness only','base':BASE,'host':platform.system(),
 'location_usage_and_background_configuration':'PASS','when_in_use_only':True,
 'minimum_ios':'15.0','cocoapods_template_present':True,'podfile_native_syntax_check':'NOT EXECUTED'if not tools['ruby']else'AVAILABLE, not executed by this check',
 'android_location_source_unchanged':True,'android_source_sha256':hashlib.sha256(android.encode()).hexdigest(),
 'android_manifest_unchanged':True,'trusted_backend_customer_feed_and_security_unchanged':True,
 'dependencies_unchanged':True,'native_tools_available':tools,
 'native_ios_build':'NOT EXECUTED','physical_iphone_tests':'NOT EXECUTED','ios_functional_acceptance':False}
output=ROOT/'docs/evidence/FR-13-ios-static.json';output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
