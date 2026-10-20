"""Observed controls on the authorized physical TEST app only; no credential logs."""
import importlib.util,json,re,shlex,sys,datetime as dt,subprocess
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
 current=n.nodes()
 if action=='screen':
  print(json.dumps([{'label':safe(n.label(node)),'bounds':node.get('bounds'),'enabled':node.get('enabled'),'checked':node.get('checked'),'class':node.get('class')}for node in current if node.get('class')!='android.widget.EditText'and(n.label(node)or node.get('clickable')=='true')and not re.fullmatch(r'\d{6}',n.label(node))]))
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
 elif action.startswith('login:'):
  profile=action.split(':',1)[1];assert profile in('physical-rider','physical-customer')
  a=h.state['accounts'][profile];code,user=h.b.api('/auth/v1/admin/users/'+a['auth_id'],admin=True)
  assert code==200 and(profile=='physical-customer'or user['user_metadata'].get('fr14_fixture')is True)
  role='Rider'if profile=='physical-rider'else'Customer'
  assert any(n.label(node)=='Sign in as '+role for node in current)
  for index,value in[(0,a['email']),(1,a['password'])]:
   fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==2
   ui.tap(fields[index]);ui.adb('shell','input','keyevent','123')
   for _ in range(len(fields[index].get('text',''))):ui.adb('shell','input','keyevent','67')
   ui.adb('shell','input','text',shlex.quote(value));ui.adb('shell','input','keyevent','4')
  found=[node for node in n.nodes()if n.label(node)=='Sign in as '+role];assert len(found)==1
  ui.tap(found[0]);emit({'synthetic_login_submitted':profile})
 elif action=='fill-test-contact':
  assert any(n.label(node)=='Contact Details'for node in current),'Observed checkout contact section required'
  fields=[node for node in current if node.get('class')=='android.widget.EditText']
  assert len(fields)>=3 and fields[1].get('text')in('','Phone number'),'Only empty TEST phone field may be filled'
  ui.tap(fields[1]);ui.adb('shell','input','text','0000000000');ui.adb('shell','input','keyevent','4')
  emit({'synthetic_noncontactable_phone_entered':True})
 elif action=='search-physical-product':
  fields=[node for node in current if node.get('class')=='android.widget.EditText']
  assert len(fields)==1 and any(n.label(node)=='Browse Categories'for node in current),'Observed product search required'
  ui.tap(fields[0]);ui.adb('shell','input','text','FR14%sPHYSICAL%sWALK%sTEST');ui.adb('shell','input','keyevent','4')
  emit({'physical_fixture_product_search_submitted':True})
 elif action=='online':
  assert any(n.label(node)=='Rider Dashboard'for node in current)
  switches=[node for node in current if node.get('class')=='android.widget.Switch'];assert len(switches)==1
  if switches[0].get('checked')=='false':ui.tap(switches[0])
  emit({'observed_online_switch_requested':True})
 else:raise ValueError('Unsupported observed action')
if __name__=='__main__':main(sys.argv[1])
