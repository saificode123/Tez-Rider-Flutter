"""Observed physical controls; exact TEST package/device and synthetic accounts."""
import json,os,re,subprocess,time,shlex,xml.etree.ElementTree as ET
from pathlib import Path
ADB='C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
SERIAL='AESWNRBAEUPNTGJZ';PACKAGE='com.example.flutter_application_1.fr21test'
state=json.loads(backend.b.crypt((backend.b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))
def adb(*args,input=None):
 r=subprocess.run([ADB,'-s',SERIAL,*args],input=input,capture_output=True,text=True,encoding='utf-8',timeout=45)
 assert r.returncode==0,'Authorized Android TEST command failed';return r.stdout
def nodes():
 assert re.search(r'topResumedActivity=ActivityRecord\{[^}]*'+re.escape(PACKAGE)+'/',adb('shell','dumpsys','activity','activities')),'TEST app must be foreground'
 for attempt in range(3):
  adb('shell','uiautomator','dump','/data/local/tmp/fr28-ui.xml')
  try:return list(ET.fromstring(adb('exec-out','cat','/data/local/tmp/fr28-ui.xml')).iter('node'))
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
action=os.environ.get('FR28_DEVICE_ACTION','status');backend.b.target()
if action=='regression-fixture':
 customer=backend.previous.state['accounts']['customer'];rider=state['accounts']['physical-rider']
 config=backend.previous.email_config()
 assert customer['email'].lower()==config['BREVO_TEST_RECIPIENT'].lower(),'Configured TEST recipient required'
 c,rows=backend.b.api('/rest/v1/orders?rider_id=eq.'+str(rider['profile_id'])+'&order_status=eq.on_the_way&select=id&limit=1',admin=True)
 assert c==200 and not rows,'Rider must have no existing active delivery'
 assert 'native_regression_order'not in state,'Reuse the saved native regression order'
 c,rows=backend.b.api('/rest/v1/orders','POST',{'user_id':customer['profile_id'],'rider_id':rider['profile_id'],'order_status':'on_the_way','amount':25,'payment_method':'COD','delivery_address':'FR28 NATIVE REGRESSION SYNTHETIC TEST ONLY'},admin=True)
 assert c==201 and len(rows)==1,'New isolated regression order required'
 state['accounts']['physical-customer']=customer;state['native_regression_order']=rows[0]['id']
 (backend.b.PRIVATE/'fr28-accounts.bin').write_bytes(backend.b.crypt(json.dumps(state).encode()))
 print(json.dumps({'synthetic_order_id':rows[0]['id'],'configured_recipient_verified':True}))
elif action=='regression-email':
 order=state['native_regression_order']
 c,rows=backend.b.api('/rest/v1/delivery_otps?order_id=eq.'+str(order)+'&select=state,provider_id&order=created_at.desc&limit=1',admin=True)
 assert c==200 and len(rows)==1 and rows[0]['state']=='ACCEPTED'and rows[0]['provider_id'],'Real provider acceptance required'
 record('regression-real-email-accepted')
elif action=='regression-delivered':
 order=state['native_regression_order']
 c,rows=backend.b.api('/rest/v1/orders?id=eq.'+str(order)+'&select=order_status,delivery_otp&limit=1',admin=True)
 assert c==200 and len(rows)==1 and rows[0]['order_status']=='delivered'and rows[0]['delivery_otp']is None,'Native confirmed delivery required'
 backend.previous.effects(order);record('regression-native-delivery-confirmed')
elif action=='regression-submitted':
 order=state['native_regression_order'];customer=state['accounts']['physical-customer'];token=backend.b.login(customer)
 c,rows=backend.b.api('/rest/v1/disputes?order_id=eq.'+str(order)+'&select=id&limit=2',token=token)
 assert c==200 and len(rows)==1,'One native dispute required'
 dispute=rows[0]['id'];c,detail=backend.b.rpc('fr25_detail',{'p_id':dispute},token)
 assert c==200 and detail['description']=='FR28 native synthetic dispute regression'and detail['evidence_count']==1,'Native description and private evidence required'
 c,rows=backend.b.api('/rest/v1/notifications?dispute_id=eq.'+str(dispute)+'&select=id&limit=2',admin=True)
 assert c==200 and len(rows)==1,'One submission notification required'
 state['native_regression_dispute']=dispute
 (backend.b.PRIVATE/'fr28-accounts.bin').write_bytes(backend.b.crypt(json.dumps(state).encode()))
 record('regression-native-dispute-submitted');print(json.dumps({'synthetic_dispute_id':dispute}))
elif action=='regression-decided':
 dispute=state['native_regression_dispute'];admin=state['accounts']['admin'];token=backend.b.login(admin)
 c,detail=backend.b.rpc('fr26_detail',{'p_id':dispute},token)
 assert c==200 and detail['decision']=='REJECTED'and detail['decided_by']==admin['profile_id']and detail['admin_note']=='FR28 native synthetic review regression','Native final decision, actor and note required'
 backend.previous.g.effects(dispute,state['accounts']['physical-customer']['profile_id'],'REJECTED')
 record('regression-native-admin-decision')
elif action=='regression-submit':
 click('Submit dispute');deadline=time.monotonic()+55
 while time.monotonic()<deadline:
  if any('Dispute submitted. Under review within 48 h.'in label(n)for n in nodes()):record('regression-native-submission-confirmation');break
  time.sleep(.5)
 else:raise AssertionError('Exact native submission confirmation not observed')
elif action=='picker-status':
 active=adb('shell','dumpsys','activity','activities')
 assert any(p in active for p in('com.google.android.photopicker','com.google.android.providers.media.module','com.android.providers.media','com.google.android.documentsui','com.android.documentsui')),'System image picker required'
 adb('shell','uiautomator','dump','/data/local/tmp/fr28-picker.xml')
 items=list(ET.fromstring(adb('exec-out','cat','/data/local/tmp/fr28-picker.xml')).iter('node'))
 safe=[]
 for n in items:
  value=label(n)
  if not value:continue
  value=re.sub(r'\S+@\S+','[email]',value)
  if re.search(r'\.(?:png|jpe?g)',value,re.I)and 'FR25-SYNTHETIC.png'not in value:value='[other image]'
  safe.append({'label':value,'bounds':n.get('bounds'),'clickable':n.get('clickable')})
 print(json.dumps({'controls':safe}))
elif action=='status':print(json.dumps({'labels':[re.sub(r'\S+@\S+','[email]',label(n))for n in nodes()if label(n)],'edit_fields':len([n for n in nodes()if n.get('class')=='android.widget.EditText'])}))
elif action=='controls':print(json.dumps({'controls':[{'label':re.sub(r'\S+@\S+','[email]',label(n)),'bounds':n.get('bounds'),'class':n.get('class')}for n in nodes()if n.get('clickable')=='true']}))
elif action.startswith('bounds:'):
 matches=[n for n in nodes()if n.get('bounds')==action[7:]and n.get('clickable')=='true'];assert len(matches)==1,'Exact observed control required';tap(matches[0]);time.sleep(.5)
elif action=='launch':adb('shell','am','force-stop',PACKAGE);adb('shell','monkey','-p',PACKAGE,'1');time.sleep(5)
elif action.startswith('tap:'):click(action[4:])
elif action.startswith('fill:'):fill(action[5:])
elif action.startswith('login:'):
 key=action[6:];role=key.removeprefix('physical-');assert role in('admin','customer','vendor','rider');a=state['accounts'][key]
 assert any('Sign in as '+role.title()==label(n)for n in nodes()),'Observed login role required'
 fill(a['email']);fill(a['password'],1);click('Sign in as '+role.title());time.sleep(4)
elif action=='blocked-login':
 a=state['accounts']['customer'];assert any(label(n)=='Sign in as Customer'for n in nodes()),'Customer login required'
 fill(a['email']);fill(a['password'],1);click('Sign in as Customer')
 deadline=time.monotonic()+15
 while time.monotonic()<deadline:
  if any('Your account has been blocked. Please contact support.'in label(n)for n in nodes()):record('blocked-login-support-message');break
  time.sleep(.5)
 else:raise AssertionError('Native banned-login message not observed')
elif action.startswith('assert:'):
 text=action[7:];assert any(text.lower()in label(n).lower()for n in nodes()),'Expected physical result not observed'
 record(re.sub('[^a-z0-9]+','-',text.lower()).strip('-')[:65])
elif action.startswith('assert-exact:'):
 text=action[13:];assert any(label(n)==text for n in nodes()),'Exact native result not observed'
 record('exact-'+re.sub('[^a-z0-9]+','-',text.lower()).strip('-')[:59])
elif action=='live-customer-block':
 assert any('Search food, stores, cuisines'in label(n)for n in nodes()),'Observed customer dashboard after controlled synthetic login required'
 admin=state['accounts']['admin'];customer=state['accounts']['customer'];token=backend.b.login(admin)
 code,result=backend.b.api('/functions/v1/admin-user-status','POST',{'target_id':customer['profile_id'],'blocked':True,'request_id':str(__import__('uuid').uuid4())},token=token)
 assert code==200 and result['code']=='OK','Confirmed TEST block required'
 deadline=time.monotonic()+25
 while time.monotonic()<deadline:
  if any('Your account has been blocked'in label(n)for n in nodes()):record('realtime-forced-signout');break
  time.sleep(1)
 else:raise AssertionError('Native forced sign-out/message not observed')
elif action=='restore-customer':
 token=backend.b.login(state['accounts']['admin']);customer=state['accounts']['customer']
 code,result=backend.b.api('/functions/v1/admin-user-status','POST',{'target_id':customer['profile_id'],'blocked':False,'request_id':str(__import__('uuid').uuid4())},token=token)
 assert code==200 and result['code']in('OK','NO_CHANGE'),'Confirmed TEST unblock required';print(json.dumps({'customer_restored':True}))
elif action.startswith('block-role:'):
 key=action[11:];assert key in('physical-vendor','physical-rider')
 a=state['accounts'][key];token=backend.b.login(state['accounts']['admin'])
 user_token=backend.b.login(a)
 if key=='physical-rider':
  c,rows=backend.b.api('/rest/v1/riders?userid=eq.'+str(a['profile_id'])+'&select=is_online&limit=1',admin=True)
  assert c==200 and len(rows)==1 and rows[0]['is_online']is True,'Physical rider must first be confirmed Online'
 c,r=backend.b.api('/auth/v1/admin/users/'+a['auth_id'],admin=True)
 assert c==200 and (r.get('user_metadata',{}).get('fr21_fixture')is True or r.get('user_metadata',{}).get('fr04_fixture')is True or r.get('user_metadata',{}).get('fr33_fixture')is True),'Only tagged synthetic role fixture may be blocked'
 c,r=backend.b.api('/functions/v1/admin-user-status','POST',{'target_id':a['profile_id'],'blocked':True,'request_id':str(__import__('uuid').uuid4())},token=token)
 assert c==200 and r['code']=='OK','Confirmed synthetic role block required'
 if key=='physical-rider':
  c,r=backend.b.rpc('fr21_set_presence',{'p_online':True,'p_epoch':1,'p_sequence':1},user_token)
 else:
  # An impossible row filter verifies the pre-request 403 without risking
  # any existing order mutation if authorization regresses in a future run.
  c,r=backend.b.api('/rest/v1/vendor_orders?id=eq.-1&vendor_id=eq.'+str(a['profile_id']),'PATCH',{'status':'accepted'},token=user_token)
 assert c==403 and r['message']=='FR28_ACCOUNT_BLOCKED','Existing synthetic role JWT protected operation must be 403'
 if key=='physical-rider':
  c,rows=backend.b.api('/rest/v1/riders?userid=eq.'+str(a['profile_id'])+'&select=is_online&limit=1',admin=True)
  assert c==200 and len(rows)==1 and rows[0]['is_online']is False,'Blocked physical rider must be offline'
 deadline=time.monotonic()+25
 while time.monotonic()<deadline:
  current=[label(n)for n in nodes()]
  if any('Your account has been blocked'in value for value in current)or any(value.startswith('Sign in as ')for value in current):record(key+'-blocked-native-signout');break
  time.sleep(.5)
 else:raise AssertionError('Blocked physical role sign-out not observed')
elif action.startswith('restore-role:'):
 key=action[13:];assert key in('physical-vendor','physical-rider');a=state['accounts'][key];token=backend.b.login(state['accounts']['admin'])
 c,r=backend.b.api('/functions/v1/admin-user-status','POST',{'target_id':a['profile_id'],'blocked':False,'request_id':str(__import__('uuid').uuid4())},token=token)
 assert c==200 and r['code']in('OK','NO_CHANGE'),'Confirmed synthetic role restore required';print(json.dumps({'restored_role':key}))
elif action=='back':adb('shell','input','keyevent','4')
elif action=='logs':
 pid=adb('shell','pidof',PACKAGE).strip();assert re.fullmatch(r'\d+',pid),'TEST process required'
 logs=adb('logcat','-d','--pid='+pid,'-v','brief')
 counts={name:len(re.findall(pattern,logs,re.I))for name,pattern in {'fatal':'FATAL EXCEPTION','unhandled':'Unhandled Exception','blocked':'FR28_ACCOUNT_BLOCKED','errors':'PostgrestException|AuthException'}.items()}
 for secret in [backend.b.SERVICE]+[a['password']for a in state['accounts'].values()]:logs=logs.replace(secret,'[redacted]')
 logs=re.sub(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+','[token]',logs)
 logs=re.sub(r'\S+@\S+','[email]',logs)
 (backend.OUT/'android-log-sanitized.txt').write_text(logs,encoding='utf-8')
 (backend.OUT/'android-log-summary.json').write_text(json.dumps(counts,indent=2));print(json.dumps(counts))
else:raise AssertionError('Unsupported device action')
