"""Observed physical controls; exact TEST package/device and synthetic accounts."""
import json,os,re,subprocess,time,shlex,xml.etree.ElementTree as ET
from pathlib import Path
ADB='C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
SERIAL='AESWNRBAEUPNTGJZ';PACKAGE='com.example.flutter_application_1.fr21test'
state=backend.state
def adb(*args,input=None):
 r=subprocess.run([ADB,'-s',SERIAL,*args],input=input,capture_output=True,text=True,encoding='utf-8',timeout=45)
 assert r.returncode==0,'Authorized Android TEST command failed';return r.stdout
def nodes(permission=False):
 expected=r'(?:com\.google\.android\.permissioncontroller|com\.android\.permissioncontroller)'if permission else re.escape(PACKAGE)
 assert re.search(r'topResumedActivity=ActivityRecord\{[^}]*'+expected+'/',adb('shell','dumpsys','activity','activities')),'Expected TEST app or requested permission dialog must be foreground'
 for attempt in range(3):
  adb('shell','uiautomator','dump','/data/local/tmp/fr30-ui.xml')
  try:return list(ET.fromstring(adb('exec-out','cat','/data/local/tmp/fr30-ui.xml')).iter('node'))
  except ET.ParseError:
   if attempt==2:raise
   time.sleep(1)
def label(n):return(n.get('text')or n.get('content-desc')or '').strip()
def tap(n):
 xy=list(map(int,re.findall(r'\d+',n.get('bounds',''))));assert len(xy)==4 and xy[2]>xy[0]and xy[3]>xy[1],'Observed visible control required'
 adb('shell','input','tap',str((xy[0]+xy[2])//2),str((xy[1]+xy[3])//2))
def click(value):
 candidates=[n for n in nodes()if n.get('clickable')=='true'and n.get('class')!='android.widget.EditText'and value.lower()in label(n).lower()]
 exact=[n for n in candidates if label(n).lower()==value.lower()];assert candidates,'Requested native control not visible: '+value;tap((exact or candidates)[0]);time.sleep(.5)
def fill(value,index=0):
 fields=[n for n in nodes()if n.get('class')=='android.widget.EditText'];assert len(fields)>index,'Observed form field required'
 tap(fields[index]);adb('shell','input','keyevent','123');adb('shell',input='input keyevent '+' '.join(['67']*160)+'\ninput text '+shlex.quote(value)+'\nexit\n');adb('shell','input','keyevent','4')
def record(name):
 r=subprocess.run([ADB,'-s',SERIAL,'exec-out','screencap','-p'],capture_output=True,timeout=30);assert r.returncode==0
 (backend.OUT/(name+'.png')).write_bytes(r.stdout)
 row={'scenario':name,'result':'PASS','device':SERIAL,'package':PACKAGE,'evidence':name+'.png'}
 with(backend.OUT/'device-evidence.jsonl').open('a')as f:f.write(json.dumps(row)+'\n')
 print(json.dumps(row))

action=os.environ.get('FR30_DEVICE_ACTION','status');backend.b.target()
if action=='status':print(json.dumps({'labels':[re.sub(r'\S+@\S+','[email]',label(n))for n in nodes()if label(n)],'edit_fields':len([n for n in nodes()if n.get('class')=='android.widget.EditText'])}))
elif action=='permission-controls':print(json.dumps({'controls':[{'label':label(n),'bounds':n.get('bounds')}for n in nodes(True)if label(n)]}))
elif action.startswith('permission-tap:'):
 matches=[n for n in nodes(True)if label(n)==action[15:]and n.get('clickable')=='true'];assert len(matches)==1,'Observed permission button required';tap(matches[0])
elif action=='controls':print(json.dumps({'controls':[{'label':re.sub(r'\S+@\S+','[email]',label(n)),'bounds':n.get('bounds'),'class':n.get('class')}for n in nodes()if n.get('clickable')=='true']}))
elif action.startswith('bounds:'):
 matches=[n for n in nodes()if n.get('bounds')==action[7:]and n.get('clickable')=='true'];assert len(matches)==1,'Observed native control required';tap(matches[0])
elif action=='launch':adb('shell','am','force-stop',PACKAGE);adb('shell','monkey','-p',PACKAGE,'1');time.sleep(5)
elif action.startswith('tap:'):click(action[4:])
elif action in('compose','compose-final'):
 assert any('Broadcast notifications'in label(n)for n in nodes()),'Composer required'
 fill('FR30 native broadcast'if action=='compose'else 'FR30 final vendor broadcast');fill('Synthetic physical verification message.',1)
elif action.startswith('badge:'):
 expected=action[6:];current=[label(n)for n in nodes()];assert 'My Location'in current,'Customer home required'
 assert (expected in current)if expected!='0'else not any(x.isdecimal()for x in current),'Expected native unread badge required'
 record('native-unread-badge-'+expected)
elif action=='offline':
 settings={k:adb('shell','settings','get','global',k).strip()for k in ['wifi_on','mobile_data']}
 (backend.OUT/'native-network-state.json').write_text(json.dumps(settings),encoding='utf-8')
 adb('shell','svc','wifi','disable');adb('shell','svc','data','disable')
 assert adb('shell','settings','get','global','wifi_on').strip()=='0','WiFi disabled required'
 adb('shell','input','keyevent','3');print(json.dumps({'phone_network_disabled':True,'app_backgrounded':True}))
elif action=='reconnect':
 settings=json.loads((backend.OUT/'native-network-state.json').read_text(encoding='utf-8'))
 if settings['wifi_on']=='1':adb('shell','svc','wifi','enable')
 if settings['mobile_data']=='1':adb('shell','svc','data','enable')
 adb('shell','monkey','-p',PACKAGE,'1');print(json.dumps({'original_network_settings_restored':True,'app_resumed':True}))
elif action in('confirm-send','double-confirm'):
 current=nodes();audience='CUSTOMERS'if any('Audience: Customers'in label(n)for n in current)else 'VENDORS'if any('Audience: Vendors'in label(n)for n in current)else None
 assert audience is not None,'Verified synthetic audience required';backend.safe_audience(audience)
 if action=='confirm-send':click('Confirm send')
 else:
  matches=[n for n in nodes()if label(n)=='Confirm send'and n.get('clickable')=='true'];assert len(matches)==1
  tap(matches[0]);tap(matches[0]);print(json.dumps({'native_confirmation_double_tap_executed':True}))
elif action.startswith('login:'):
 key=action[6:];role=key.split('-')[-1];assert role in('admin','customer','vendor','rider');a=state['accounts'][key]
 assert any(label(n)=='Sign in as '+role.title()for n in nodes()),'Observed login role required'
 fill(a['email']);fill(a['password'],1);click('Sign in as '+role.title());time.sleep(4)
elif action=='back':adb('shell','input','keyevent','4')
elif action.startswith('assert:'):
 text=action[7:];until=time.monotonic()+25
 while not any(text.lower()in label(n).lower()for n in nodes()):
  assert time.monotonic()<until,'Expected native result required';time.sleep(.5)
 record(re.sub('[^a-z0-9]+','-',text.lower()).strip('-')[:65])
elif action.startswith('assert-no:'):
 text=action[10:];assert not any(text.lower()in label(n).lower()for n in nodes()),'Other-role notification must be absent';record('native-other-role-excluded')
elif action=='logs':
 pid=adb('shell','pidof',PACKAGE).strip();assert re.fullmatch(r'\d+',pid)
 logs=adb('logcat','-d','--pid='+pid);counts={k:len(re.findall(pattern,logs,re.I))for k,pattern in{'fatal':'FATAL EXCEPTION','unhandled':'Unhandled Exception','auth':'AuthApiException','api':'PostgrestException|FunctionException'}.items()}
 contexts=[]
 for match in re.finditer('PostgrestException|FunctionException',logs,re.I):
  context=logs[max(0,match.start()-120):match.end()+450]
  contexts.append(re.sub(r'eyJ[A-Za-z0-9_.-]+|\S+@\S+|[A-Za-z0-9_-]{30,}','[redacted]',context))
 (backend.OUT/'android-api-context.json').write_text(json.dumps({'sanitized_contexts':contexts},indent=2),encoding='utf-8')
 (backend.OUT/'android-log-summary.json').write_text(json.dumps(counts,indent=2),encoding='utf-8');print(json.dumps(counts))
else:raise AssertionError('Unknown native action')
