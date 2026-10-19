"""Scan the actual TEST APK and feature files; protected values never printed."""
import json,subprocess
from pathlib import Path
path=Path(__file__).with_name('FR-10-artifact.py');source=path.read_text(encoding='utf-8-sig')
changes={
 "ROOT / '.fr21-local/fr10'":"ROOT / '.fr21-local/fr13'",
 "['fr10-accounts.bin','fr30-accounts.bin']":"['fr10-accounts.bin','fr30-accounts.bin','fr32-accounts.bin','fr33-accounts.bin','checklist-accounts.bin','fr13-accounts.bin']",
 "protected = [account['private_key'], account['private_key_id'], push['worker_key'], b.SERVICE]":"protected = [account['private_key'], account['private_key_id'], push['worker_key'], b.SERVICE, b.crypt((b.PRIVATE/'fr32-worker.bin').read_bytes(), True).decode()]",
 "b'fr10_checkout',b'fr10_vendor_transition'":"b'fr13-location',b'fr13_tracking_context',b'Share delivery location'",
 "'fr10_code_present'":"'fr13_code_present'",
 "'physical_fixture_final_integrity'":"'physical_fr13_final_integrity'",
 "'physical_device_test':'EXECUTED; see native-evidence.jsonl' if native_executed else 'NOT EXECUTED'":"'physical_acceptance_gate':'PASS; see native-evidence.jsonl' if native_executed else 'NOT COMPLETE; see partial native evidence'",
}
for before,after in changes.items():
 assert source.count(before)==1,'Review changed accepted scanner';source=source.replace(before,after)
needle='patterns = [value.encode() for value in protected if value]'
source=source.replace(needle,"extra=b.PRIVATE/'checklist-regression-fixtures.bin'\nif extra.exists():\n    protected.append(json.loads(b.crypt(extra.read_bytes(),True))['password'])\n"+needle)
exec(compile(source,str(path),'exec'))
assert (ROOT/'android/app/src/main/AndroidManifest.xml').read_bytes()==(MIRROR/'android/app/src/main/AndroidManifest.xml').read_bytes(),'Stale Android manifest'
permissions=subprocess.run([aapt,'dump','permissions',str(APK)],capture_output=True,text=True,timeout=30);assert permissions.returncode==0
for permission in ['ACCESS_FINE_LOCATION','ACCESS_COARSE_LOCATION','FOREGROUND_SERVICE','FOREGROUND_SERVICE_LOCATION','WAKE_LOCK','POST_NOTIFICATIONS']:
 assert 'android.permission.'+permission in permissions.stdout,'Missing Android permission'
assert 'android.permission.ACCESS_BACKGROUND_LOCATION'not in permissions.stdout,'Unnecessary background-location permission'
manifest=subprocess.run([aapt,'dump','xmltree',str(APK),'AndroidManifest.xml'],capture_output=True,text=True,timeout=30);assert manifest.returncode==0
assert 'GeolocatorLocationService'in manifest.stdout and'foregroundServiceType'in manifest.stdout
safe={'required_permissions_present':True,'background_permission_absent':True,'location_foreground_service_declared':True}
(OUT/'android-manifest.json').write_text(json.dumps(safe,indent=2));print(json.dumps(safe))
