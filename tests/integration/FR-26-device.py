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
  path='/data/local/tmp/fr26-ui.xml';adb('shell','uiautomator','dump',path);raw=adb('exec-out','cat',path);adb('shell','rm','-f',path)
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
action=os.environ.get('FR26_DEVICE_ACTION','status');backend.b.target()
if action.startswith('login:'):
 role=action.split(':',1)[1];assert role in ('admin','customer','other')
 expected='Sign in as '+('Admin' if role=='admin' else 'Customer')
 assert any(label(n)==expected for n in nodes()),'Correct observed login role required'
 account=backend.state['accounts'][role];fill(account['email']);fill(account['password'],1);backend.b.target();click(expected)
elif action.startswith('tap:'):click(action[4:])
elif action.startswith('fill:'):fill(action[5:].replace(' ','%s'))
elif action=='hide-keyboard':
 raw=adb('shell','dumpsys','window')
 if re.search(r'mCurrentFocus=.*(?:InputMethod|Keyboard)',raw):adb('shell','input','keyevent','4');time.sleep(.4)
elif action.startswith('assert:'):
 text=action[7:];assert any(text.lower() in label(n).lower() for n in nodes()),'Expected native result not observed';evidence(re.sub('[^a-z0-9]+','-',text.lower()).strip('-'),True)
elif action.startswith('snapshot:'):evidence(action[9:])
elif action.startswith('open-fixture:'):
 which=action.split(':',1)[1];assert which in ('resolve','reject','realtime')
 id=backend.state['disputes']['device-'+which]['id'];click('Dispute #'+str(id)+' ')
elif action.startswith('verify:'):
 which=action.split(':',1)[1];assert which in ('resolve','reject')
 id=backend.state['disputes']['device-'+which]['id'];admin=backend.state['accounts']['admin'];customer=backend.state['accounts']['customer'];token=backend.b.login(admin)
 code,row=backend.rpc('fr26_detail',{'p_id':id},token);expected='RESOLVED' if which=='resolve' else 'REJECTED'
 backend.check(code==200 and row['decision']==expected and row['decided_by']==admin['profile_id'] and row['admin_note']=='FR26 Android '+which+' note','native '+which+' decision persisted with correct note/actor')
 backend.effects(id,customer['profile_id'],expected)
 (backend.OUT/('device-'+which+'-result.json')).write_text(json.dumps({'dispute_id':id,'decision':expected,'refund_pending':row['refund_pending'],'note_verified':True,'actor_verified':True,'verified_at':dt.datetime.now(dt.timezone.utc).isoformat()},indent=2))
elif action=='attach-identities':
 fixture=backend.state['disputes']['device-resolve'];customer=backend.state['accounts']['customer'];vendor=backend.state['accounts']['vendor'];rider=backend.state['accounts']['rider'];order=fixture['order_id']
 code,rows=backend.api('/rest/v1/orders?id=eq.'+str(order)+'&user_id=eq.'+str(customer['profile_id'])+'&select=delivery_address,order_status&limit=1',admin=True)
 assert code==200 and len(rows)==1 and rows[0]['delivery_address']=='FR26 SYNTHETIC TEST ONLY' and rows[0]['order_status']=='delivered','Isolated delivered synthetic order required'
 code,_=backend.api('/rest/v1/orders?id=eq.'+str(order),'PATCH',{'vendor_id':vendor['profile_id'],'rider_id':rider['profile_id']},admin=True);assert code==200
 token=backend.b.login(backend.state['accounts']['admin']);code,detail=backend.rpc('fr26_detail',{'p_id':fixture['id']},token)
 backend.check(code==200 and detail['rider_id']==rider['profile_id'] and detail['rider_name']=='FR26 synthetic rider' and any(v['id']==vendor['profile_id'] and v['name']=='FR26 synthetic vendor' for v in detail['vendors']),'real joined vendor/rider identities for isolated delivered fixture')
elif action=='realtime-fixture':
 account=backend.state['accounts']['customer'];token=backend.b.login(account)
 id=backend.new_dispute('device-realtime',account,token,None);print(json.dumps({'expected_dispute_id':id}))
elif action=='realtime-reject':
 id=backend.state['disputes']['device-realtime']['id'];token=backend.b.login(backend.state['accounts']['admin-2'])
 code,result=backend.decide(token,id,'REJECTED','FR26 synthetic Realtime rejection');backend.check(code==200 and result['decision']=='REJECTED','isolated second admin Realtime rejection committed')
elif action=='submission-fixture':
 account=backend.state['accounts']['customer']
 code,rows=backend.api('/rest/v1/orders','POST',{'user_id':account['profile_id'],'order_status':'delivered','amount':25,'delivery_address':'FR26 SYNTHETIC TEST ONLY','payment_method':'COD'},admin=True);assert code==201
 backend.state['device_submission_order']=rows[0]['id'];backend.save();print(json.dumps({'synthetic_order_id':rows[0]['id']}))
elif action=='verify-submission':
 account=backend.state['accounts']['customer'];token=backend.b.login(account);order=backend.state['device_submission_order']
 code,rows=backend.api('/rest/v1/disputes?order_id=eq.'+str(order)+'&select=id&limit=2',token=token)
 backend.check(code==200 and len(rows)==1,'native FR25 submission persisted one owned dispute after FR26')
 code,detail=backend.rpc('fr25_detail',{'p_id':rows[0]['id']},token)
 backend.check(code==200 and detail['description']=='FR26 Android submission regression' and detail['evidence_count']==1,'native FR25 description and uploaded evidence preserved')
 (backend.OUT/'device-submission.json').write_text(json.dumps({'order_id':order,'dispute_id':rows[0]['id'],'evidence_count':1,'verified_at':dt.datetime.now(dt.timezone.utc).isoformat()},indent=2))
elif action=='chat-reply':
 account=backend.state['accounts']['customer'];token=backend.b.login(account);code,room=backend.rpc('fr25_support_chat',{},token);assert code==200 and isinstance(room,int)
 code,rows=backend.api('/rest/v1/chat_messages?room_id=eq.'+str(room)+'&sender_id=eq.'+str(account['profile_id'])+'&message=eq.FR26%20Android%20chat%20regression&select=id&limit=2',token=token)
 backend.check(code==200 and len(rows)==1,'native customer chat persisted once after FR26')
 code,rooms=backend.api('/rest/v1/chat_rooms?id=eq.'+str(room)+'&select=user1_id,user2_id&limit=1',admin=True);assert code==200 and len(rooms)==1
 recipient=rooms[0]['user2_id'] if rooms[0]['user1_id']==account['profile_id'] else rooms[0]['user1_id'];code,rows=backend.api('/rest/v1/users?id=eq.'+str(recipient)+'&select=email&limit=1',admin=True);assert code==200 and len(rows)==1
 actor=next((a for source in [backend.state['accounts'],backend.b.state['accounts'],backend.g.state['accounts']] for a in source.values() if a['email']==rows[0]['email']),None);assert actor is not None,'Protected synthetic recipient required'
 code,_=backend.api('/rest/v1/chat_messages','POST',{'room_id':room,'sender_id':recipient,'message':'FR26 Android Realtime chat reply'},backend.b.login(actor));backend.check(code==201,'synthetic authorized support reply persisted')
elif action=='viewer-begin':
 assert any(label(n)=='Private dispute evidence' for n in nodes())
 (backend.OUT/'viewer-observation.json').write_text(json.dumps({'started':time.time(),'started_at':dt.datetime.now(dt.timezone.utc).isoformat()}));evidence('admin-viewer-before-expiry')
elif action=='viewer-expiry':
 start=json.loads((backend.OUT/'viewer-observation.json').read_text())['started'];deadline=start+910
 while time.time()<deadline:time.sleep(min(20,max(.1,deadline-time.time())))
 assert any('The private viewing link expired' in label(n) for n in nodes()),'Actual native expiry not observed'
 evidence('admin-viewer-after-expiry',True)
elif action=='logs':
 pid=adb('shell','pidof',PACKAGE).strip();assert re.fullmatch(r'\d+',pid)
 logs=adb('logcat','-d','--pid='+pid);counts={k:len(re.findall(pattern,logs,re.I)) for k,pattern in {'fatal':'FATAL EXCEPTION|Unhandled Exception','auth':'AuthApiException|invalid.login.credentials','api':'PostgrestException|FunctionException'}.items()}
 (backend.OUT/'android-log-summary.json').write_text(json.dumps(counts,indent=2));print(json.dumps(counts));backend.check(not any(counts.values()),'no captured Android fatal/Auth/API exceptions')
elif action=='back':adb('shell','input','keyevent','4')
elif action.startswith('swipe:'):
 direction=action[6:];assert direction in ('up','down');adb('shell','input','swipe','500','1850' if direction=='up' else '700','500','650' if direction=='up' else '1850','400')
elif action=='status':
 safe=[{'label':re.sub(r'[\w.+-]+@[\w.-]+','[email]',label(n)),'class':n.get('class'),'clickable':n.get('clickable'),'bounds':n.get('bounds')} for n in nodes() if label(n) and n.get('password')!='true']
 print(json.dumps({'controls':safe}))
else:raise RuntimeError('Unknown authorized TEST device action')
