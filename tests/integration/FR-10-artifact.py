"""Verify the actual fresh TEST APK; never emit protected credential contents."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import zipfile

spec = importlib.util.spec_from_file_location('fr30', Path(__file__).with_name('FR-30-hosted.py'))
previous = importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)
b = previous.b
ROOT = previous.ROOT
OUT = ROOT / '.fr21-local/fr10'
MIRROR = Path('C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-auth-debug/android-build-20261012-125502')
APK = MIRROR / 'build/app/outputs/flutter-apk/app-fr21test-debug.apk'
assert (ROOT/'supabase/.temp/project-ref').read_text().strip() == b.REF
assert 'Built ' in (OUT/'build.log').read_text(encoding='utf-8'), 'Successful fresh build required'
sources = list((ROOT/'lib').rglob('*.dart'))
assert all(p.read_bytes() == (MIRROR/p.relative_to(ROOT)).read_bytes() for p in sources), 'APK build source mirror is stale'
defines = json.loads((ROOT/'.fr21-local/public-defines.json').read_text())
assert defines['SUPABASE_URL'] == b.BASE and defines['FR21_ISOLATED_TEST'] is True and defines['FR30_ANDROID_PUSH'] is True
account = json.loads(Path('C:/secrets/tez-rider/key.json').read_text(encoding='utf-8-sig'))
push = json.loads(b.crypt((b.PRIVATE/'fr30-push-state.bin').read_bytes(), True))
protected = [account['private_key'], account['private_key_id'], push['worker_key'], b.SERVICE]
for name in ['fr10-accounts.bin','fr30-accounts.bin']:
    state = json.loads(b.crypt((b.PRIVATE/name).read_bytes(), True))
    protected.extend(a['password'] for a in state['accounts'].values())
patterns = [value.encode() for value in protected if value]
files = sorted(set(subprocess.check_output(['git','diff','--name-only','-z','HEAD'],cwd=ROOT).decode().split('\0') + subprocess.check_output(['git','ls-files','--others','--exclude-standard','-z'],cwd=ROOT).decode().split('\0')) - {''})
for name in files:
    path = ROOT/name
    assert path.is_file() and path.stat().st_size < 5*1024*1024, 'Unexpected changed file'
    assert not any(secret in path.read_bytes() for secret in patterns), 'Protected credential in source'
    assert path.suffix not in ('.apk','.p8','.p12','.env') and path.name not in ('google-services.json','key.json'), 'Forbidden staged artifact candidate'
found = {value:False for value in [b.BASE.encode(),b'fr10_checkout',b'fr10_vendor_transition']}
forbidden = patterns + [b'https://arrqsvejrfdbacfwtpcc.supabase.co']
overlap = max(len(value) for value in forbidden+list(found))-1
with zipfile.ZipFile(APK) as archive:
    for entry in archive.infolist():
        if entry.is_dir():continue
        with archive.open(entry)as stream:
            previous_chunk = b''
            while chunk := stream.read(256*1024):
                payload = previous_chunk+chunk
                assert not any(value in payload for value in forbidden), 'Protected credential or production endpoint in APK'
                for value in found:
                    found[value] = found[value] or value in payload
                previous_chunk = payload[-overlap:]
assert all(found.values()), 'Actual TEST endpoint and FR10 code required in APK'
aapt = 'C:/Users/urreh/AppData/Local/Android/Sdk/build-tools/36.0.0/aapt.exe'
manifest = subprocess.run([aapt,'dump','badging',str(APK)],capture_output=True,text=True,timeout=30)
assert manifest.returncode == 0 and "package: name='com.example.flutter_application_1.fr21test'"in manifest.stdout, 'Wrong Android application'
with APK.open('rb')as stream:
    digest = hashlib.file_digest(stream,'sha256').hexdigest()
native_file = OUT/'native-evidence.jsonl'
native_executed = native_file.exists() and any(json.loads(line).get('physical_fixture_final_integrity') == 'PASS' for line in native_file.read_text(encoding='utf-8').splitlines())
result = {'sha256':digest,'bytes':APK.stat().st_size,'source_files_matched':len(sources),'test_only':True,'fr10_code_present':True,
          'credential_scan_passed':True,'files_scanned':len(files),'production_endpoint_absent':True,'physical_device_test':'EXECUTED; see native-evidence.jsonl' if native_executed else 'NOT EXECUTED',
          'source_sha256':{str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
(OUT/'artifact.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items()if k!='source_sha256'}))
