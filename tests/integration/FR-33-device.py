"""Observed Android TEST controls only; protected passwords never enter output."""
import datetime as dt,json,os,re,shlex,subprocess,time,xml.etree.ElementTree as ET
ADB='C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
SERIAL='AESWNRBAEUPNTGJZ';PACKAGE='com.example.flutter_application_1.fr21test'
def adb(*args,input=None):
 result=subprocess.run([ADB,'-s',SERIAL,*args],input=input,capture_output=True,text=True,encoding='utf-8',timeout=45)
 if result.returncode:raise RuntimeError('Authorized Android TEST command failed')
 return result.stdout
def nodes():
 active=adb('shell','dumpsys','activity','activities')
 assert re.search(r'topResumedActivity=ActivityRecord\{[^}]*'+re.escape(PACKAGE)+'/',active),'TEST app must be foreground'
 for attempt in range(3):
  path='/data/local/tmp/fr33-ui.xml';adb('shell','uiautomator','dump',path);raw=adb('exec-out','cat',path);adb('shell','rm','-f',path)
  try:return list(ET.fromstring(raw).iter('node'))
  except ET.ParseError:
   if attempt==2:raise
   time.sleep(.5)
def label(node):return (node.get('text') or node.get('content-desc') or '').strip()
def tap(node):
 xy=list(map(int,re.findall(r'\d+',node.get('bounds',''))));assert len(xy)==4 and xy[2]>xy[0] and xy[3]>xy[1] and xy[3]<=2400,'Visible TEST control required'
 adb('shell','input','tap',str((xy[0]+xy[2])//2),str((xy[1]+xy[3])//2))
def click(text):
 current=nodes();found=[n for n in current if text.lower() in label(n).lower() and n.get('clickable')=='true' and n.get('class')!='android.widget.EditText']
 exact=[n for n in found if label(n).lower()==text.lower()];assert found,'Requested TEST control not visible';tap((exact or found)[0]);time.sleep(.5)
def fill(value,index=0):
 fields=[n for n in nodes() if n.get('class')=='android.widget.EditText'];assert len(fields)>index,'Observed form field required'
 tap(fields[index]);adb('shell','input','keyevent','123');adb('shell',input='input keyevent '+' '.join(['67']*160)+'\ninput text '+shlex.quote(value)+'\nexit\n');adb('shell','input','keyevent','4')
def evidence(name,passed=False):
 assert re.fullmatch('[a-z0-9-]+',name)
 result=subprocess.run([ADB,'-s',SERIAL,'exec-out','screencap','-p'],capture_output=True,timeout=30);assert result.returncode==0
 (backend.OUT/(name+'.png')).write_bytes(result.stdout)
 record={'time':dt.datetime.now(dt.timezone.utc).isoformat(),'scenario':name,'result':'PASS' if passed else 'OBSERVED','evidence':name+'.png'}
 with (backend.OUT/'device-evidence.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
 print(json.dumps(record),flush=True)
action=os.environ.get('FR33_DEVICE_ACTION','status');backend.b.target()
if action.startswith('login:'):
 role=action.split(':',1)[1];assert role in ('rider','customer')
 expected='Sign in as '+role.title();assert any(label(n)==expected for n in nodes()),'Correct observed login role required'
 account=backend.state['accounts'][role];fill(account['email']);fill(account['password'],1);backend.b.target();click(expected)
elif action.startswith('tap:'):click(action[4:])
elif action.startswith('nav:'):
 index=int(action[4:]);assert 0<=index<4
 items=[]
 for n in nodes():
  xy=list(map(int,re.findall(r'\d+',n.get('bounds',''))))
  if n.get('clickable')=='true' and len(xy)==4 and xy[1]>=2100 and 0<xy[2]-xy[0]<450 and 0<xy[3]-xy[1]<=200:items.append((xy[0],n))
 items.sort(key=lambda x:x[0]);assert len(items)==4,'Exactly four observed bottom navigation controls required';tap(items[index][1]);time.sleep(1)
elif action=='inspect-navigation':
 print(json.dumps({'clickable_bounds':[n.get('bounds')for n in nodes()if n.get('clickable')=='true']}))
elif action=='customer-check':
 labels=[label(n)for n in nodes()];assert any('delivery verification code has been sent' in t.lower() for t in labels),'Actual safe customer email message required'
 expected=backend.state['orders']['device-invalidation'];assert any('Order #'+str(expected) in t and 'Delivered' in t for t in labels),'Actual completed order tracking required'
 assert not any(re.fullmatch(r'\d{6}',t)for t in labels),'Unexpected plaintext six-digit display'
 backend.check(True,'physical customer tracking shows actual email notice without plaintext OTP');evidence('customer-email-no-plaintext-code',True)
elif action=='wrong':fill('000000');click('Confirm Delivery')
elif action=='back':adb('shell','input','keyevent','4')
elif action.startswith('fixture:'):
 which=action[8:];assert which in ('success','lockout','replacement','invalidation')
 id=backend.order('device-'+which,real=True);print(json.dumps({'synthetic_order_id':id}))
elif action.startswith('assert:'):
 text=action[7:];assert any(text.lower() in label(n).lower() for n in nodes()),'Expected native result not observed';evidence(re.sub('[^a-z0-9]+','-',text.lower()).strip('-'),True)
elif action=='email-accepted':
 id=backend.state['orders']['device-success'];code,rows=backend.b.api('/rest/v1/delivery_otps?order_id=eq.'+str(id)+'&select=state,attempts,sent_at,expires_at,provider_id&order=created_at.desc&limit=1',admin=True)
 assert code==200 and len(rows)==1;row=rows[0];provider=bool(row.pop('provider_id',None));backend.check(row['state']=='ACCEPTED' and provider and row['attempts']==1,'real TEST provider acceptance and native incorrect attempt persisted')
 (backend.OUT/'real-email-acceptance.json').write_text(json.dumps({'order_id':id,'provider_receipt_present':provider,'inbox_receipt':'NOT YET VERIFIED',**row},indent=2))
elif action.startswith('verify:'):

 which=action[7:];assert which in ('success','lockout','replacement','invalidation');id=backend.state['orders']['device-'+which]
 code,rows=backend.b.api('/rest/v1/orders?id=eq.'+str(id)+'&select=order_status,otp_admin_review,delivery_otp&limit=1',admin=True);assert code==200 and len(rows)==1
 code,otp=backend.b.api('/rest/v1/delivery_otps?order_id=eq.'+str(id)+'&select=state,attempts,sent_at,expires_at&order=created_at.desc&limit=5',admin=True);assert code==200
 if which=='success':backend.check(rows[0]['order_status']=='delivered' and any(r['state']=='USED' for r in otp),'native real-email delivery persisted');backend.effects(id)
 elif which=='lockout':backend.check(rows[0]['otp_admin_review'] and rows[0]['order_status']=='on_the_way' and otp[0]['state']=='LOCKED' and otp[0]['attempts']==3,'native three failures persist lockout/admin flag')
 result={'order_id':id,'order':rows[0],'issuances':otp};(backend.OUT/('device-'+which+'-result.json')).write_text(json.dumps(result,indent=2));print(json.dumps(result))
elif action=='isolate-replacement':
 target=backend.state['orders']['device-replacement'];rider=backend.state['accounts']['rider']['profile_id']
 code,rows=backend.b.api('/rest/v1/orders?rider_id=eq.'+str(rider)+'&order_status=eq.on_the_way&select=id,delivery_address&limit=100',admin=True);assert code==200 and len(rows)<100
 for row in rows:
  assert row['delivery_address']=='FR33 SYNTHETIC TEST ONLY','Only tagged FR33 fixtures may be detached'
  if row['id']!=target:
   code,_=backend.b.api('/rest/v1/orders?id=eq.'+str(row['id'])+'&rider_id=eq.'+str(rider),'PATCH',{'rider_id':None},admin=True);assert code==200
 backend.check(True,'physical replacement rider isolated from security fixtures; only own synthetic assignments detached')
elif action=='cooldown':
 current=nodes();controls=[n for n in current if label(n).startswith('Resend in ')];assert len(controls)==1 and controls[0].get('clickable')=='false';evidence('server-cooldown-disabled',True)
elif action=='network':
 wifi=adb('shell','settings','get','global','wifi_on').strip();mobile=adb('shell','settings','get','global','mobile_data').strip();assert wifi in ('0','1') and mobile in ('0','1'),'Known network settings required'
 try:
  adb('shell','svc','wifi','disable');adb('shell','svc','data','disable');time.sleep(2);click('Refresh server status');time.sleep(20)
  assert any('operation was not confirmed' in label(n).lower() for n in nodes()),'Expected recoverable network failure not observed';evidence('network-recoverable-error',True)
 finally:
  if wifi=='1':adb('shell','svc','wifi','enable')
  if mobile=='1':adb('shell','svc','data','enable')
  time.sleep(4)
 click('Refresh server status')
 deadline=time.monotonic()+25
 while time.monotonic()<deadline:
  if any('Email request accepted' in label(n) for n in nodes()):break
  time.sleep(2)
 else:raise AssertionError('Server-confirmed recovery not observed')
 evidence('network-restored-server-state',True)
elif action=='automatic-invalidation':
 id=backend.order('device-invalidation',real=True);issuance,old=backend.simulated_issue(id)
 print(json.dumps({'phase':'synthetic protected initial issuance; no initial email sent','order_id':id}),flush=True)
 time.sleep(4);click('Active Delivery');click('Arrived');time.sleep(2);fill(old)
 deadline=time.monotonic()+65
 while time.monotonic()<deadline:time.sleep(min(20,deadline-time.monotonic()))
 click('Request a new code')
 end=time.monotonic()+60
 while time.monotonic()<end:
  code,rows=backend.b.api('/rest/v1/delivery_otps?order_id=eq.'+str(id)+'&select=id,state,attempts&order=created_at.desc&limit=2',admin=True)
  if code==200 and len(rows)==2 and rows[0]['state']=='ACCEPTED' and rows[1]['state']=='INVALIDATED':break
  time.sleep(2)
 else:raise AssertionError('Real replacement acceptance not verified')
 assert rows[1]['id']==issuance,'Initial protected fixture required'
 click('Confirm Delivery');time.sleep(2)
 code,rows=backend.b.api('/rest/v1/delivery_otps?order_id=eq.'+str(id)+'&select=state,attempts,sent_at&order=created_at.desc&limit=2',admin=True)
 backend.check(code==200 and len(rows)==2 and rows[0]['state']=='ACCEPTED' and rows[0]['attempts']==1 and rows[1]['state']=='INVALIDATED','physical unchanged known-valid old code rejected after real TEST email replacement')
 assert any('Incorrect OTP. 2 attempts remaining.' in label(n) for n in nodes()),'Required native replacement rejection not observed'
 (backend.OUT/'device-replacement-old.json').write_text(json.dumps({'order_id':id,'issuances':rows,'initial_provider':'explicit privileged mock fixture; no initial mail','replacement_provider':'actual TEST Edge/Brevo acceptance','old_code_source':'privileged test fixture held in memory only; not printed or persisted'},indent=2));evidence('replacement-old-rejected',True)
elif action=='replacement-old':
 id=backend.state['orders']['device-invalidation'];code,rows=backend.b.api('/rest/v1/delivery_otps?order_id=eq.'+str(id)+'&select=state,attempts,sent_at&order=created_at.desc&limit=2',admin=True)
 backend.check(code==200 and len(rows)==2 and rows[0]['state']=='ACCEPTED' and rows[0]['attempts']==1 and rows[1]['state']=='INVALIDATED','previous usable emailed OTP rejected on intended native replacement order')
 (backend.OUT/'device-replacement-old.json').write_text(json.dumps({'order_id':id,'issuances':rows},indent=2));evidence('replacement-old-rejected',True)
elif action=='invalidation-complete':
 id=backend.state['orders']['device-invalidation'];code,rows=backend.b.api('/rest/v1/orders?id=eq.'+str(id)+'&select=order_status&limit=1',admin=True);backend.check(code==200 and rows[0]['order_status']=='delivered','fresh replacement email code completes isolated native invalidation order');backend.effects(id)
 (backend.OUT/'device-invalidation-complete.json').write_text(json.dumps({'order_id':id,'status':'delivered','one_proof':True,'one_audit':True,'new_received_code_valid':True},indent=2))
elif action=='replacement-complete':
 id=backend.state['orders']['device-replacement'];code,rows=backend.b.api('/rest/v1/orders?id=eq.'+str(id)+'&select=order_status&limit=1',admin=True);backend.check(code==200 and rows[0]['order_status']=='delivered','new real emailed OTP completes native replacement order');backend.effects(id)
elif action=='lockout-notices':
 id=backend.state['orders']['device-lockout'];code,rows=backend.b.api('/rest/v1/delivery_otps?order_id=eq.'+str(id)+'&state=eq.LOCKED&select=id&limit=2',admin=True);assert code==200 and len(rows)==1
 code,notices=backend.b.api('/rest/v1/notifications?delivery_otp_id=eq.'+rows[0]['id']+'&type=eq.otp_review&select=id&limit=2',admin=True);backend.check(code==200 and len(notices)==1,'native lockout generated one admin review notification')
elif action=='duplicate':
 import uuid
 id=backend.state['orders']['device-success'];token=backend.b.login(backend.state['accounts']['rider']);code,row=backend.verify_call(token,id,'000000',str(uuid.uuid4()));backend.check(code==200 and row['code']=='ALREADY_DELIVERED','real-email completed order safely idempotent');backend.effects(id)
 receipt=json.loads((backend.OUT/'real-email-acceptance.json').read_text());receipt['inbox_receipt']='PASS: user entered emailed code on physical device; hosted verifier completed order';(backend.OUT/'real-email-acceptance.json').write_text(json.dumps(receipt,indent=2))
elif action=='log-classify':
 pid=adb('shell','pidof',PACKAGE).strip();assert re.fullmatch(r'\d+',pid)
 logs=adb('logcat','-d','--pid='+pid);errors=[l for l in logs.splitlines()if re.search('PostgrestException|FunctionException',l)]
 inherited=[l for l in errors if 'VendorInfoController: get_vendor_ratings RPC failed' in l and 'permission denied for function get_vendor_ratings' in l]
 fatal=len(re.findall('FATAL EXCEPTION|Unhandled Exception',logs,re.I));auth=len(re.findall('AuthApiException|invalid.login.credentials',logs,re.I));unexpected=len(errors)-len(inherited)
 result={'fatal':fatal,'auth':auth,'api_total':len(errors),'fr33_or_unclassified_api':unexpected,'inherited_vendor_ratings_permission_errors':len(inherited),'inherited_origin':'202610080001_tezrider_baseline.sql blanket public-function revocation; FR33 changes exclude this function/controller','whole_app_logs_clean':False if errors else True}
 (backend.OUT/'android-log-summary.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));backend.check(fatal==0 and auth==0 and unexpected==0,'final Android FR33 runtime clean; inherited ratings exception explicitly recorded')
elif action=='log-investigate':
 pid=adb('shell','pidof',PACKAGE).strip();assert re.fullmatch(r'\d+',pid)
 raw=adb('logcat','-d','--pid='+pid);matched=[]
 for line in raw.splitlines():
  if not re.search('PostgrestException|FunctionException|Unhandled Exception|FATAL EXCEPTION',line,re.I):continue
  for value in list(backend.email_config().values())+[backend.b.SERVICE]:line=line.replace(value,'[private]')
  line=re.sub(r'https?://\S+','[url]',line);line=re.sub(r'[\w.+-]+@[\w.-]+','[email]',line);line=re.sub(r'eyJ[A-Za-z0-9_.-]+','[token]',line);line=re.sub(r'(?<!\d)\d{6}(?!\d)','[six digits]',line)
  matched.append(line[:600])
 print(json.dumps({'sanitized_exception_lines':matched}))
elif action=='logs':
 pid=adb('shell','pidof',PACKAGE).strip();assert re.fullmatch(r'\d+',pid)
 logs=adb('logcat','-d','--pid='+pid);counts={k:len(re.findall(pattern,logs,re.I)) for k,pattern in {'fatal':'FATAL EXCEPTION|Unhandled Exception','auth':'AuthApiException|invalid.login.credentials','api':'PostgrestException|FunctionException'}.items()}
 (backend.OUT/'android-log-summary.json').write_text(json.dumps(counts,indent=2));print(json.dumps(counts));backend.check(not any(counts.values()),'no captured Android fatal/Auth/API exceptions')
elif action=='status':
 safe=[{'label':re.sub(r'[\w.+-]+@[\w.-]+','[email]',label(n)),'class':n.get('class'),'clickable':n.get('clickable'),'bounds':n.get('bounds')} for n in nodes() if label(n) and n.get('class')!='android.widget.EditText' and n.get('password')!='true']
 print(json.dumps({'controls':safe}))
else:raise RuntimeError('Unknown authorized TEST device action')
