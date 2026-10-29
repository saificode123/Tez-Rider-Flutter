"""Observed controls on the authorized physical TEST app only; no credential logs."""
import importlib.util,json,re,shlex,sys,datetime as dt,subprocess,uuid,xml.etree.ElementTree as ET
from pathlib import Path
def load(name,file):
 spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
h=load('fr14','FR-14-hosted.py');n=load('fr13native','FR-13-native.py');ui=n.ui
def safe(value):
 value=re.sub(r'[^\s@]+@[^\s@]+','[TEST account]',value)
 return re.sub(r'-?\d+\.\d{4,}','[coordinate]',value)
def emit(data):
 data['utc']=dt.datetime.now(dt.timezone.utc).isoformat()
 with(h.OUT/'native-evidence.jsonl').open('a')as f:f.write(json.dumps(data)+'\n')
 print(json.dumps(data),flush=True)
def main(action):
 if action=='dismiss-password-save':
  assert ui.PKG in ui.adb('shell','dumpsys','activity','activities').split('topResumedActivity=')[-1].splitlines()[0],'TEST app must remain resumed'
  path='/data/local/tmp/release-password-'+uuid.uuid4().hex+'.xml'
  try:
   assert 'dumped to:'in ui.adb('shell','uiautomator','dump',path)
   overlay=list(ET.fromstring(ui.adb('exec-out','cat',path)).iter('node'))
  finally:ui.adb('shell','rm',path)
  assert any(node.get('package')=='android'and node.get('text')=='Save password to Google?'for node in overlay),'Observed Google password-save prompt required'
  found=[node for node in overlay if node.get('package')=='android'and node.get('text')=='Not now']
  if len(found)==1:ui.tap(found[0])
  else:ui.adb('shell','input','keyevent','4')
  emit({'TEST_password_save_declined':True});return
 current=n.nodes()
 if action=='screen':
  print(json.dumps([{'label':safe(n.label(node)),'bounds':node.get('bounds'),'enabled':node.get('enabled'),'checked':node.get('checked'),'class':node.get('class')}for node in current if node.get('class')!='android.widget.EditText'and(n.label(node)or node.get('clickable')=='true')and not re.fullmatch(r'\d{6}',n.label(node))]))
 elif action=='scroll-rider-profile':
  assert any(n.label(node)=='TezRider Partner'for node in current)and any(n.label(node)=='Profile'for node in current),'Rider profile tab required'
  ui.adb('shell','input','swipe','540','1900','540','950','450');emit({'rider_profile_scrolled':True})
 elif action=='scroll-my-profile':
  assert any(n.label(node)=='My Profile'for node in current),'Canonical My Profile screen required'
  ui.adb('shell','input','swipe','540','1890','540','860','450');emit({'canonical_profile_scrolled':True})
 elif action=='scroll-release-product':
  assert any(n.label(node)=='Chicken Biryani'for node in current)and any(n.label(node)=='Sana Foods'for node in current),'Reviewed TEST product detail required'
  ui.adb('shell','input','swipe','540','1880','540','1010','450');emit({'reviewed_test_product_scrolled':True})
 elif action=='scroll-account':
  assert any(n.label(node)=='Me'for node in current)and any(n.label(node)=='Customer'for node in current),'Customer account tab required'
  ui.adb('shell','input','swipe','540','1810','540','760','450');emit({'TEST_account_scrolled':True})
 elif action=='back':
  ui.adb('shell','input','keyevent','4');emit({'TEST_back_requested':True})
 elif action=='runtime-evidence':
  pid=ui.adb('shell','pidof',ui.PKG).strip();assert re.fullmatch(r'\d+(?: \d+)*',pid)
  connectivity=ui.adb('shell','dumpsys','connectivity')
  match=re.search(r'Active default network:\s*(none|null|\d+)\b',connectivity)
  emit({'TEST_app_foreground':True,'TEST_process':pid,'default_network_present':None if not match else match[1]not in('none','null')})
 elif action=='screenshot':
  p=subprocess.run([ui.ADB,'-s',ui.SERIAL,'exec-out','screencap','-p'],capture_output=True,timeout=30);assert p.returncode==0
  (h.OUT/'native-screen.png').write_bytes(p.stdout);emit({'TEST_screenshot_saved':True})
 elif action.startswith('tap-bounds:'):
  bounds=action.split(':',1)[1]
  found=[node for node in current if node.get('bounds')==bounds and node.get('clickable')=='true']
  assert len(found)==1 and found[0].get('enabled')!='false','Observed clickable bounds required'
  ui.tap(found[0]);emit({'observed_bounds_tapped':bounds,'outcome_pending':True})
 elif action.startswith('tap:'):
  label=action.split(':',1)[1];found=[node for node in current if node.get('class')!='android.widget.EditText'and n.label(node)==label]
  assert len(found)==1 and found[0].get('enabled')!='false','Exactly one observed enabled TEST control required'
  ui.tap(found[0]);emit({'observed_control':safe(label),'outcome_pending':True})
 elif action.startswith(('login:','login-demo:')):
  profile=action.split(':',1)[1]
  if action.startswith('login-demo:'):
   assert profile in('sana','mariam')
   demo=json.loads(h.b.crypt((h.b.PRIVATE/'master-demo-credentials.dpapi').read_bytes(),True))
   a=demo['accounts'][profile];role='Vendor'if profile=='sana'else'Admin'
  else:
   assert profile in('physical-rider','physical-customer')
   a=h.state['accounts'][profile];role='Rider'if profile=='physical-rider'else'Customer'
  owner_file=h.b.PRIVATE/'rider-auth-verification.dpapi'
  if owner_file.exists():
   owner=json.loads(h.b.crypt(owner_file.read_bytes(),True))
   assert a['auth_id']!=owner['auth_id'],'Owner Rider requires private manual password entry'
  code,user=h.b.api('/auth/v1/admin/users/'+a['auth_id'],admin=True)
  assert code==200 and(profile!='physical-rider'or user['user_metadata'].get('fr14_fixture')is True)
  code,rows=h.b.api('/rest/v1/users?auth_user_id=eq.'+a['auth_id']+'&select=id,role,verification_status,is_blocked',admin=True)
  assert code==200 and len(rows)==1 and rows[0]['id']==a['profile_id'] and rows[0]['role']==role.lower() and rows[0]['verification_status']=='approved'and not rows[0]['is_blocked']
  assert any(n.label(node)=='Sign in as '+role for node in current)
  for index,value in[(0,a['email']),(1,a['password'])]:
   fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==2
   ui.tap(fields[index]);ui.adb('shell','input','keyevent','123')
   for _ in range(len(fields[index].get('text',''))):ui.adb('shell','input','keyevent','67')
   ui.adb('shell','input','text',shlex.quote(value));ui.adb('shell','input','keyevent','4')
  found=[node for node in n.nodes()if n.label(node)=='Sign in as '+role];assert len(found)==1
  ui.tap(found[0]);emit({'synthetic_login_submitted':profile})
 elif action=='complete-test-profile-phone':
  assert any(n.label(node)=='Complete Registration'and node.get('class')=='android.widget.Button'for node in current),'Existing profile completion form required'
  fields=[node for node in current if node.get('class')=='android.widget.EditText']
  assert len(fields)==2 and fields[0].get('text')=='FR33 synthetic customer','Retained TEST Customer name required'
  assert fields[1].get('text')in('','Phone Number','Enter phone number'),'Only missing TEST phone may be supplied'
  ui.tap(fields[1]);ui.adb('shell','input','text','0000000000');ui.adb('shell','input','keyevent','4')
  emit({'existing_test_profile_noncontactable_phone_entered':True})
 elif action=='fill-owner-rider-email':
  assert any(n.label(node)=='Sign in as Rider'for node in current),'Observed Rider login required'
  target=json.loads(h.b.crypt((h.b.PRIVATE/'rider-auth-verification.dpapi').read_bytes(),True))
  assert len(target['profiles'])==1 and target['profiles'][0]['id']==999 and target['profiles'][0]['role']=='rider'
  fields=[node for node in current if node.get('class')=='android.widget.EditText'];assert len(fields)==2
  # Only email is accessed. Password fields are never read, filled or submitted.
  field=fields[0];ui.tap(field);ui.adb('shell','input','keyevent','123')
  for _ in range(len(field.get('text',''))):ui.adb('shell','input','keyevent','67')
  ui.adb('shell','input','text',shlex.quote(target['email']));ui.adb('shell','input','keyevent','4')
  emit({'owner_rider_email_prefilled_without_password_access':True})
 elif action=='fill-test-contact':
  assert any(n.label(node)=='Contact Details'for node in current),'Observed checkout contact section required'
  fields=[node for node in current if node.get('class')=='android.widget.EditText']
  assert len(fields)>=3 and fields[1].get('text')in('','Phone number'),'Only empty TEST phone field may be filled'
  ui.tap(fields[1]);ui.adb('shell','input','text','0000000000');ui.adb('shell','input','keyevent','4')
  emit({'synthetic_noncontactable_phone_entered':True})
 elif action=='open-release-product':
  found=[node for node in current if 'Chicken Biryani'in n.label(node)and'Fictional TEST demonstration item.'in n.label(node)and'PKR 350'in n.label(node)]
  assert len(found)==1 and found[0].get('enabled')!='false','Reviewed unique TEST product required'
  ui.tap(found[0]);emit({'reviewed_test_product_opened':True})
 elif action in('search-physical-product','search-release-product'):
  fields=[node for node in current if node.get('class')=='android.widget.EditText']
  assert len(fields)==1 and any(n.label(node)=='Browse Categories'for node in current),'Observed product search required'
  term='Chicken%sBiryani'if action=='search-release-product'else'FR14%sPHYSICAL%sWALK%sTEST'
  ui.tap(fields[0]);ui.adb('shell','input','text',term);ui.adb('shell','input','keyevent','4')
  emit({'fixture_product_search_submitted':action})
 elif action in('online','offline'):
  assert any(n.label(node)=='Rider Dashboard'for node in current)
  switches=[node for node in current if node.get('class')=='android.widget.Switch'];assert len(switches)==1
  if (switches[0].get('checked')=='true') != (action=='online'):
   # Flutter merges the full availability card into Switch semantics. Its
   # centre is not the actual thumb; use the trailing switch area observed on
   # the English Rider Dashboard, bounded by the freshly inspected control.
   bounds=list(map(int,re.findall(r'\d+',switches[0].get('bounds',''))));assert len(bounds)==4
   x1,y1,x2,y2=bounds;assert x2>x1 and y2>y1
   ui.adb('shell','input','tap',str(x2-(x2-x1)//6),str((y1+y2)//2))
  emit({'observed_'+action+'_switch_requested':True})
 else:raise ValueError('Unsupported observed action')
if __name__=='__main__':main(sys.argv[1])
