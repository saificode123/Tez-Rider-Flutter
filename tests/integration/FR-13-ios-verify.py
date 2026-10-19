"""Recheck existing TEST GPS/security/FR regressions; never deploy or migrate."""
import importlib.util,json,re,subprocess,sys
from pathlib import Path

spec=importlib.util.spec_from_file_location('fr13',Path(__file__).with_name('FR-13-hosted.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
assert h.b.REF=='igeisilhtmglgnqvllrx'
h.OUT=h.ROOT/'.fr21-local/fr13-ios';h.OUT.mkdir(parents=True,exist_ok=True)
h.h.OUT=h.OUT
def scan():
 base='3408790d7c556665228d4c1cca371c4018a07cea'
 names=set(subprocess.check_output(['git','diff','--name-only','-z',base],cwd=h.ROOT).decode().split('\0')+subprocess.check_output(['git','ls-files','--others','--exclude-standard','-z'],cwd=h.ROOT).decode().split('\0'))-{''}
 protected=[h.b.SERVICE]+[a['password']for a in h.state['accounts'].values()]
 for name in names:
  path=h.ROOT/name;assert path.is_file()and path.stat().st_size<5*1024*1024,'Unexpected artifact candidate'
  assert path.suffix.lower()not in('.p8','.p12','.pfx','.cer','.mobileprovision','.apk','.aab','.ipa','.env')
  assert path.name not in('key.json','google-services.json','GoogleService-Info.plist')
  data=path.read_bytes()
  assert not any(value.encode()in data for value in protected if value),'Protected value in candidate source'
  assert not re.search(rb'-----BEGIN (?:RSA |EC )?PRIVATE KEY-----',data),'Private key in source'
 result={'files_scanned':len(names),'credential_scan':'PASS','credentials_printed':False,'build_or_signing_artifacts':0}
 (h.OUT/'source-scan.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))

actions={'audit':h.resume_audit,'sql':h.sql,'http':h.http_tests,'realtime':h.realtime,'regressions':h.regressions,'scan':scan}
assert sys.argv[1]in actions,'Read-only audit/tests only; no deployment mode'
if sys.argv[1]=='audit':
 # Compare against the accepted FR-13 pre-deployment job baseline; do not
 # replace that baseline with the current state or overwrite accepted evidence.
 baseline=h.ROOT/'.fr21-local/fr13/inspection.json'
 (h.OUT/'inspection.json').write_bytes(baseline.read_bytes())
profile=sys.argv[2]if len(sys.argv)>2 else'all'
assert profile in('all','FR21','FR04','FR25','FR26','FR33','FR28','FR20','FR30-sql','FR30-http','FR30-realtime','FR10','FR17','FR32')
sys.argv=[sys.argv[0],sys.argv[1],profile]
actions[sys.argv[1]]()
