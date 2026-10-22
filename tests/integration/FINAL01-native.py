"""Observed native TEST actions; no credential output or unrelated device access."""
import importlib.util,json,re,subprocess,sys,time,shlex,hashlib,datetime
from pathlib import Path
import xml.etree.ElementTree as ET
spec=importlib.util.spec_from_file_location('backend',Path(__file__).with_name('FR-04-hosted.py'))
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
b.target()
ROOT=b.ROOT;OUT=ROOT/'.fr21-local/final01';OUT.mkdir(exist_ok=True)
ADB='C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
SERIAL='AESWNRBAEUPNTGJZ';PKG='com.example.flutter_application_1.fr21test'
accounts=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']
def adb(*args,input=None):
 p=subprocess.run([ADB,'-s',SERIAL,*args],input=input,capture_output=True,text=True,encoding='utf-8',timeout=50)
 assert p.returncode==0,'Authorized TEST device action failed';return p.stdout

def nodes():
 active=adb('shell','dumpsys','activity','activities')
 assert re.search(r'topResumedActivity=ActivityRecord\{[^}]*'+re.escape(PKG)+'/',active),'Only TEST app may be inspected'
 for attempt in range(3):
  try:
   adb('shell','uiautomator','dump','/data/local/tmp/final01-ui.xml')
   raw=adb('exec-out','cat','/data/local/tmp/final01-ui.xml')
   result=list(ET.fromstring(raw).iter('node'));(OUT/'ui.private.xml').write_text(raw,encoding='utf-8');return result
  except (ET.ParseError,AssertionError):
   if attempt==2:raise
   time.sleep(.5)
def label(n):return (n.get('text') or n.get('content-desc') or '').strip()
def safe(s):return re.sub(r'\S+@\S+','[email]',s)
def tap(n):
 xy=list(map(int,re.findall(r'\d+',n.get('bounds',''))));assert len(xy)==4 and xy[2]>xy[0] and xy[3]>xy[1]
 adb('shell','input','tap',str((xy[0]+xy[2])//2),str((xy[1]+xy[3])//2));time.sleep(.5)
def click(value):
 choices=[n for n in nodes() if label(n)==value and n.get('enabled')!='false']
 clickable=[n for n in choices if n.get('clickable')=='true'];choices=clickable or choices
 assert len(choices)==1,'Exactly one observed control required: '+value;tap(choices[0])
def record(check,surface='android'):
 result={'check':check,'result':'PASS','surface':surface,'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'activation_deployed':(OUT/'deployment-202610220004.json').exists()}
 if surface=='android':result.update(device=SERIAL,package=PKG)
 else:result.update(project=b.REF)
 with(OUT/'native-results.jsonl').open('a',encoding='utf-8')as f:f.write(json.dumps(result)+'\n')
 print(json.dumps(result))
def picture(name):
 p=subprocess.run([ADB,'-s',SERIAL,'exec-out','screencap','-p'],capture_output=True,timeout=30);assert p.returncode==0
 (OUT/(name+'.png')).write_bytes(p.stdout)

def main(action):
 if action=='install':
  evidence=json.loads((OUT/'build-evidence.json').read_text(encoding='utf-8-sig'))
  assert evidence['project']==b.REF and evidence['package']==PKG
  for s in evidence['sources']:assert hashlib.sha256((ROOT/s['path']).read_bytes()).hexdigest().upper()==s['sha256'],'Source changed after build; rebuild first'
  apk=Path(evidence['apk']);assert hashlib.sha256(apk.read_bytes()).hexdigest().upper()==evidence['sha256']
  aapt='C:/Users/urreh/AppData/Local/Android/Sdk/build-tools/36.0.0/aapt.exe'
  package=subprocess.run([aapt,'dump','badging',str(apk)],capture_output=True,text=True,timeout=30)
  assert package.returncode==0 and re.search(r"^package: name='"+re.escape(PKG)+"'",package.stdout),'Built APK package must match TEST'
  adb('install','-r',str(apk));record('current-source TEST APK installed with package and source-hash checks')
 elif action=='launch':
  adb('shell','am','force-stop',PKG);adb('shell','monkey','-p',PKG,'1');time.sleep(5)
 elif action=='status':
  current=nodes();print(json.dumps({'controls':[{'label':safe(label(n)),'bounds':n.get('bounds'),'class':n.get('class'),'clickable':n.get('clickable')} for n in current if (label(n) or n.get('clickable')=='true') and n.get('class')!='android.widget.EditText'],'fields':len([n for n in current if n.get('class')=='android.widget.EditText'])}))
 elif action.startswith('tap:'):click(action[4:])
 elif action.startswith('bounds:'):
  found=[n for n in nodes()if n.get('bounds')==action[7:] and n.get('clickable')=='true'];assert len(found)==1;tap(found[0])
 elif action=='back':
  nodes();adb('shell','input','keyevent','4');time.sleep(.5)
 elif action.startswith('login:'):
  role=action[6:];assert role in('customer','vendor','rider','admin','final01')
  account=json.loads(b.crypt((b.PRIVATE/'final01-workflow.bin').read_bytes(),True))if role=='final01'else accounts[role]
  prefix='final01-'if role=='final01'else 'fr28-'
  assert account['email'].startswith(prefix)and account['email'].endswith('@example.test')
  role='customer'if role=='final01'else role
  current=nodes();assert any(label(n)=='Sign in as '+role.title()for n in current)
  for index,value in enumerate([account['email'],account['password']]):
   fields=[n for n in nodes()if n.get('class')=='android.widget.EditText'];assert len(fields)==2
   tap(fields[index]);adb('shell','input','keyevent','123')
   # Credentials are stdin-only, never tool output or report content.
   adb('shell',input='input keyevent '+' '.join(['67']*160)+'\ninput text '+shlex.quote(value)+'\nexit\n')
   adb('shell','input','keyevent','4')
  click('Sign in as '+role.title());time.sleep(4)
 elif action.startswith('assert:'):
  expected=action[7:];deadline=time.monotonic()+20
  while not any(expected in label(n)for n in nodes()):
   assert time.monotonic()<deadline,'Expected native outcome missing: '+expected
   time.sleep(1)
  name=re.sub(r'[^a-z0-9]+','-',expected.lower())[:65];picture(name);record('observed native '+expected)
 elif action.startswith('revoke:'):
  role=action[7:];assert role in('customer','vendor','rider','admin')
  account=accounts[role]
  assert account['email'].startswith('fr28-')and account['email'].endswith('@example.test')
  token=b.login(account)
  code,_=b.api('/auth/v1/logout?scope=global','POST',token=token)
  assert code in(200,204),'Synthetic account session revocation not confirmed'
  record('server confirmed global logout for synthetic '+role+'; physical denial requires separate observation','HTTP')
 elif action=='scan-changed':
  protected=[b.SERVICE]+[a['password']for a in accounts.values()]
  fixture=json.loads(b.crypt((b.PRIVATE/'final01-workflow.bin').read_bytes(),True))
  protected.append(fixture['password'])
  protected.extend(a['password']for a in b.fr04['accounts'].values()if 'password'in a)
  names=set()
  for args in [('diff','--name-only','-z','HEAD'),('ls-files','--others','--exclude-standard','-z')]:
   names.update(subprocess.check_output(['git',*args],cwd=ROOT).decode().split('\0'))
  paths=[ROOT/name for name in names if name and (ROOT/name).is_file()]
  assert all(not any(value.encode()in path.read_bytes()for value in protected if value)for path in paths),'Protected credential found in changed file; value withheld'
  result={'changed_files_checked':len(paths),'protected_credential_matches':0,'scope':'actual TEST service key and protected FR28/FR04/FINAL01 fixture passwords; separate bounded pattern/history scan'}
  (OUT/'final02-protected-scan.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result))
 elif action=='restore-fixture':
  import uuid
  fixture=json.loads(b.crypt((b.PRIVATE/'final01-workflow.bin').read_bytes(),True))
  assert fixture['email'].startswith('final01-')and fixture['email'].endswith('@example.test')and fixture.get('cancelled')
  code,rows=b.api('/rest/v1/users?id=eq.'+str(fixture['profile_id'])+'&select=is_blocked',admin=True)
  assert code==200 and len(rows)==1
  if rows[0]['is_blocked']:
   code,pending=b.api('/rest/v1/fr28_operations?target_id=eq.'+str(fixture['profile_id'])+'&state=neq.SYNCED&select=id,desired_blocked',admin=True)
   assert code==200 and len(pending)<=1
   assert not pending or pending[0]['desired_blocked']is False,'Unexpected pending block needs review'
   request=pending[0]['id']if pending else str(uuid.uuid4())
   token=b.login(accounts['admin'])
   code,result=b.api('/functions/v1/admin-user-status','POST',{'target_id':fixture['profile_id'],'blocked':False,'request_id':request},token)
   assert code==200 and result.get('is_blocked')is False and result.get('code')!='AUTH_SYNC_PENDING','Fixture unblock not confirmed'
  code,rows=b.api('/rest/v1/users?id=eq.'+str(fixture['profile_id'])+'&select=is_blocked',admin=True)
  assert code==200 and rows==[{'is_blocked':False}]
  record('new synthetic customer confirmed unblocked after physical Admin test','HTTP')
 elif action=='assistant-smoke':
  code,result=b.api('/functions/v1/shopping-assistant','GET');assert code==405 and result.get('code')=='METHOD_NOT_ALLOWED'
  record('deployed TEST assistant method guard; no provider request','HTTP')
 else:raise ValueError('Unsupported bounded native action')
if __name__=='__main__':main(sys.argv[1])
