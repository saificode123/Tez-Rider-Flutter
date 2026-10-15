"""Authorized TEST Firebase setup. Never emits credential contents."""
from pathlib import Path
import importlib.util,json,re,secrets,shutil,subprocess,tempfile,sys
spec=importlib.util.spec_from_file_location('fr30',Path(__file__).with_name('FR-30-hosted.py'))
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
def configure():
 b.b.target()
 source=Path('C:/secrets/tez-rider/google-services.json');credential=Path('C:/secrets/tez-rider/key.json')
 client=json.loads(source.read_text(encoding='utf-8-sig'));account=json.loads(credential.read_text(encoding='utf-8-sig'))
 project=client['project_info']['project_id'];package='com.example.flutter_application_1.fr21test'
 assert re.fullmatch(r'[a-z][a-z0-9-]{4,28}[a-z0-9]',project)
 assert any(x.get('client_info',{}).get('android_client_info',{}).get('package_name')==package for x in client['client'])
 assert account['project_id']==project and account['type']=='service_account'and account['private_key'].startswith('-----BEGIN PRIVATE KEY-----')
 destination=b.ROOT/'android/app/src/fr21test/google-services.json'
 assert subprocess.run(['git','check-ignore','-q',str(destination)],cwd=b.ROOT).returncode==0
 shutil.copyfile(source,destination)
 protected=b.b.PRIVATE/'fr30-push-state.bin'
 state=json.loads(b.b.crypt(protected.read_bytes(),True))if protected.exists()else{'worker_key':secrets.token_hex(32),'project':project}
 assert state['project']==project
 protected.write_bytes(b.b.crypt(json.dumps(state).encode()))
 cli='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
 pending=[]
 try:
  with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=b.b.PRIVATE,prefix='fr30-push-',suffix='.env',delete=False)as f:
   pending.append(Path(f.name));f.write('FR30_FIREBASE_PROJECT_ID='+project+'\nFR30_PUSH_WORKER_KEY='+state['worker_key']+'\nFR30_FIREBASE_SERVICE_ACCOUNT='+json.dumps(account,separators=(',',':'))+'\n')
  result=subprocess.run([cli,'secrets','set','--project-ref',b.b.REF,'--env-file',str(pending[-1])],cwd=b.ROOT,capture_output=True,text=True,timeout=120)
  assert result.returncode==0,'TEST secret setup unconfirmed'
  with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',dir=b.b.PRIVATE,prefix='fr30-push-',suffix='.sql',delete=False)as f:
   pending.append(Path(f.name));f.write("do $$declare sid uuid;begin select id into sid from vault.secrets where name='fr30_android_push_worker';if sid is null then perform vault.create_secret('"+state['worker_key']+"','fr30_android_push_worker','FR30 TEST Android dispatch worker');else perform vault.update_secret(sid,'"+state['worker_key']+"');end if;end$$;select true as configured;")
  assert b.query(pending[-1])['rows'][0]['configured']
 finally:
  for path in pending:path.unlink(missing_ok=True)
 defines=b.ROOT/'.fr21-local/public-defines.json';data=json.loads(defines.read_text(encoding='utf-8'))
 assert data['SUPABASE_URL']==b.b.BASE
 data['FR30_ANDROID_PUSH']=True;data['FR30_FIREBASE_PROJECT_ID']=project
 defines.write_text(json.dumps(data,indent=2),encoding='utf-8')
 print(json.dumps({'client_verified':True,'client_ignored':True,'project':project,'test_secrets_configured':True,'vault_worker_configured':True,'dispatch_enabled':False,'private_key_disclosed':False}))
try:configure()
except Exception:
 print(json.dumps({'configured':False,'reason':'Guarded TEST push setup failed; credential contents withheld'}));sys.exit(1)
