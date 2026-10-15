"""Scan changed source and the TEST APK against actual protected credentials."""
from pathlib import Path
import importlib.util,json,subprocess,zipfile,sys
spec=importlib.util.spec_from_file_location('fr30',Path(__file__).with_name('FR-30-hosted.py'))
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
account=json.loads(Path('C:/secrets/tez-rider/key.json').read_text(encoding='utf-8-sig'))
state=json.loads(b.b.crypt((b.b.PRIVATE/'fr30-push-state.bin').read_bytes(),True))
protected=[account['private_key'],account['private_key_id'],state['worker_key'],b.b.SERVICE]
protected.extend(a['password']for a in b.state['accounts'].values())
patterns=[value.encode()for value in protected if value]
def git(*args):return subprocess.check_output(['git',*args],cwd=b.ROOT).decode().split('\0')
files=sorted(set(git('diff','--name-only','-z','HEAD')+git('ls-files','--others','--exclude-standard','-z'))-{'','.gitignore'})
for name in files:
 path=b.ROOT/name
 assert path.is_file()and path.stat().st_size<5*1024*1024,'Unexpected feature artifact'
 assert not any(value in path.read_bytes()for value in patterns),'Protected credential in changed source'
assert subprocess.run(['git','check-ignore','-q','android/app/src/fr21test/google-services.json'],cwd=b.ROOT).returncode==0
assert 'android/app/src/fr21test/google-services.json'not in files
apk_checked=False
if '--apk'in sys.argv:
 with zipfile.ZipFile(b.OUT/'TezRider-FR30-Test-debug.apk')as archive:
  for name in archive.namelist():
   if not name.endswith('/'):
    payload=archive.read(name)
    assert not any(value in payload for value in patterns),'Protected credential in TEST APK'
 apk_checked=True
result={'changed_source_files':len(files),'credential_matches':0,'test_client_config_ignored':True,'test_apk_scanned':apk_checked,'private_key_disclosed':False}
(b.OUT/'push-security.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
