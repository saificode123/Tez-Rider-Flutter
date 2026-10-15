"""Observed physical controls; exact TEST package/device and synthetic accounts."""
import json,os,re,subprocess,time,shlex,xml.etree.ElementTree as ET
from pathlib import Path
ADB='C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
SERIAL='AESWNRBAEUPNTGJZ';PACKAGE='com.example.flutter_application_1.fr21test'
state=json.loads(backend.b.crypt((backend.b.PRIVATE/'fr20-accounts.bin').read_bytes(),True))
def adb(*args,input=None):
 r=subprocess.run([ADB,'-s',SERIAL,*args],input=input,capture_output=True,text=True,encoding='utf-8',timeout=45)
 assert r.returncode==0,'Authorized Android TEST command failed';return r.stdout
def nodes():
 assert re.search(r'topResumedActivity=ActivityRecord\{[^}]*'+re.escape(PACKAGE)+'/',adb('shell','dumpsys','activity','activities')),'TEST app must be foreground'
 for attempt in range(3):
  adb('shell','uiautomator','dump','/data/local/tmp/fr20-ui.xml')
  try:return list(ET.fromstring(adb('exec-out','cat','/data/local/tmp/fr20-ui.xml')).iter('node'))
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

action=os.environ.get('FR20_DEVICE_ACTION','status');backend.b.target()
if action=='status':print(json.dumps({'labels':[re.sub(r'\S+@\S+','[email]',label(n))for n in nodes()if label(n)],'edit_fields':len([n for n in nodes()if n.get('class')=='android.widget.EditText'])}))
elif action=='controls':print(json.dumps({'controls':[{'label':re.sub(r'\S+@\S+','[email]',label(n)),'bounds':n.get('bounds'),'class':n.get('class')}for n in nodes()if n.get('clickable')=='true']}))
elif action=='launch':adb('shell','am','force-stop',PACKAGE);adb('shell','monkey','-p',PACKAGE,'1');time.sleep(5)
elif action.startswith('tap:'):click(action[4:])
elif action.startswith('bounds:'):
 matches=[n for n in nodes()if n.get('bounds')==action[7:]and n.get('clickable')=='true'];assert len(matches)==1,'Observed control required';tap(matches[0])
elif action.startswith('login:'):
 key=action[6:];role=key.removeprefix('physical-');assert role in('admin','vendor','rider');a=state['accounts'][key]
 assert any(label(n)=='Sign in as '+role.title()for n in nodes()),'Observed login role required'
 fill(a['email']);fill(a['password'],1);click('Sign in as '+role.title());time.sleep(4)
elif action=='back':adb('shell','input','keyevent','4')
elif action.startswith('assert:'):
 text=action[7:];assert any(text.lower()in label(n).lower()for n in nodes()),'Expected native result required';record(re.sub('[^a-z0-9]+','-',text.lower()).strip('-')[:65])
elif action.startswith('fixture:'):
 nodes();backend.native_fixture(action[8:])
elif action.startswith('submit:'):
 which=action[7:];row=state['orders']['native-'+which]
 visible_until=time.monotonic()+25
 while not any('Order #'+str(row['vendor_order_id'])in label(n)for n in nodes()):
  assert time.monotonic()<visible_until,'Newest synthetic vendor order must be visible';time.sleep(.5)
 click('Mark Ready & Call Rider');deadline=time.monotonic()+35;message=False
 expected='within 5 km'if which=='5km'else 'expanding the search to 10 km'if which=='10km'else 'Administrators notified for manual assignment'
 while time.monotonic()<deadline:
  current=[label(n)for n in nodes()]
  if any(expected in x for x in current):message=True;break
  if any('not confirmed'in x for x in current):break
  if which in('5km','10km')and not any('Mark Ready & Call Rider'in x for x in current):break
  time.sleep(.3)
 record('native-'+which+'-result-observed');print(json.dumps({'result_message_observed':message}))
elif action.startswith('verify:'):
 which=action[7:];row=state['orders']['native-'+which]
 c,result=backend.b.rpc('fr20_assignment_status',{'p_vendor_order_id':row['vendor_order_id']},backend.b.login(state['accounts']['vendor']))
 assert c==200 and result['code']==('NO_RIDER_AVAILABLE'if which in('none','offline','blocked')else 'ALREADY_ASSIGNED'),'Native assignment persistence required'
 c,assignments=backend.b.api('/rest/v1/rider_assignments?orderid=eq.'+str(row['id'])+'&select=id,riderid',admin=True)
 assigned=which in('5km','10km');assert c==200 and len(assignments)==(1 if assigned else 0),'Native assignment count required'
 if assigned:assert assignments[0]['riderid']==state['accounts']['physical-rider']['profile_id'],'Correct approved physical synthetic rider required'
 event='rider_assigned'if assigned else'manual_assignment'
 c,notices=backend.b.api('/rest/v1/notifications?assignment_order_id=eq.'+str(row['id'])+'&assignment_event=eq.'+event+'&select=id,user_id,message',admin=True);assert c==200
 if assigned:assert len(notices)==1 and notices[0]['message']=='New delivery job assigned.','Exact native rider notice required'
 else:
  c,admins=backend.b.api('/rest/v1/users?role=eq.admin&verification_status=eq.approved&is_blocked=eq.false&select=id',admin=True)
  assert c==200 and sorted(n['user_id']for n in notices)==sorted(a['id']for a in admins),'One native escalation per eligible admin required'
 state.setdefault('native_notice_counts',{}).setdefault(which,len(notices))
 assert state['native_notice_counts'][which]==len(notices),'Native retry must not duplicate notices'
 backend.state.update(state);backend.save()
 record('native-'+which+'-persisted')
elif action=='retry-none':
 row=state['orders']['native-none'];assert any('Order #'+str(row['vendor_order_id'])in label(n)for n in nodes()),'Latest native no-rider order required';click('Retry Rider Matching');time.sleep(3)
elif action=='replay-assigned':
 row=state['orders']['native-5km'];token=backend.b.login(state['accounts']['vendor'])
 c,before=backend.b.rpc('fr20_assignment_status',{'p_vendor_order_id':row['vendor_order_id']},token);assert c==200 and before['code']=='ALREADY_ASSIGNED'
 c,after=backend.b.rpc('fr21_ready_and_assign',{'p_vendor_order_id':row['vendor_order_id']},token)
 assert c==200 and after['code']=='ALREADY_ASSIGNED'and after['assignment_id']==before['assignment_id']and after['rider_id']==before['rider_id'],'No native assignment may be replaced on replay'
 record('native-assigned-order-replay-preserved')
elif action=='logs':
 pid=adb('shell','pidof',PACKAGE).strip();assert re.fullmatch(r'\d+',pid)
 logs=adb('logcat','-d','--pid='+pid);counts={k:len(re.findall(pattern,logs,re.I))for k,pattern in{'fatal':'FATAL EXCEPTION','unhandled':'Unhandled Exception','auth':'AuthApiException','api':'PostgrestException|FunctionException'}.items()}
 (backend.OUT/'android-log-summary.json').write_text(json.dumps(counts,indent=2),encoding='utf-8');print(json.dumps(counts))
elif action=='log-detail':
 pid=adb('shell','pidof',PACKAGE).strip();assert re.fullmatch(r'\d+',pid)
 lines=adb('logcat','-d','--pid='+pid).splitlines();selected=[]
 for i,line in enumerate(lines):
  if 'Unhandled Exception'in line:selected.extend(lines[max(0,i-1):i+15])
 safe='\n'.join(selected)
 for secret in [backend.b.SERVICE]+[a['password']for a in state['accounts'].values()]:safe=safe.replace(secret,'[secret]')
 safe=re.sub(r'https?://\S+','[url]',safe);safe=re.sub(r'\S+@\S+','[email]',safe);safe=re.sub(r'eyJ[A-Za-z0-9_.-]+','[token]',safe)
 print(safe[:5000])
elif action=='restore-physical':
 rider=state['accounts']['physical-rider'];c,result=backend.b.api('/functions/v1/admin-user-status','POST',{'target_id':rider['profile_id'],'blocked':False,'request_id':str(__import__('uuid').uuid4())},backend.b.login(state['accounts']['admin']))
 assert c==200 and result['code']in('OK','NO_CHANGE');print(json.dumps({'synthetic_rider_restored':True}))
else:raise AssertionError('Unknown guarded native action')
