"""Android TEST only. Never print passwords, saved sessions or private links."""
import datetime as dt,json,os,re,shlex,subprocess,time,xml.etree.ElementTree as ET
ADB='C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
SERIAL='AESWNRBAEUPNTGJZ';PACKAGE='com.example.flutter_application_1.fr21test'
def adb(*args,input=None):
 result=subprocess.run([ADB,'-s',SERIAL,*args],input=input,capture_output=True,text=True,encoding='utf-8',timeout=45)
 if result.returncode:raise RuntimeError('Android TEST operation failed')
 return result.stdout
def nodes():
 active=adb('shell','dumpsys','activity','activities')
 if not re.search(r'topResumedActivity=ActivityRecord\{[^}]*'+re.escape(PACKAGE)+'/',active):raise RuntimeError('TezRider TEST must be foreground')
 path='/data/local/tmp/fr25-ui.xml';adb('shell','uiautomator','dump',path)
 raw=adb('exec-out','cat',path);adb('shell','rm','-f',path)
 return list(ET.fromstring(raw).iter('node'))
def label(node):return (node.get('text') or node.get('content-desc') or '').strip()
def tap(node):
 xy=list(map(int,re.findall(r'\d+',node.get('bounds',''))));assert len(xy)==4 and xy[3]>xy[1]
 adb('shell','input','tap',str((xy[0]+xy[2])//2),str((xy[1]+xy[3])//2))
def click(text):
 candidates=[n for n in nodes() if text.lower() in label(n).lower() and n.get('clickable')=='true']
 assert candidates,'Requested TEST control is not visible';tap(candidates[0]);time.sleep(1)
def fill(value,index=0):
 fields=[n for n in nodes() if n.get('class')=='android.widget.EditText'];assert len(fields)>index
 tap(fields[index]);adb('shell','input','keyevent','123');adb('shell',input='input keyevent '+' '.join(['67']*110)+'\ninput text '+shlex.quote(value)+'\nexit\n');adb('shell','input','keyevent','4')
def evidence(name,passed=False):
 path=backend.OUT/(name+'.png');result=subprocess.run([ADB,'-s',SERIAL,'exec-out','screencap','-p'],capture_output=True,timeout=30);assert result.returncode==0;path.write_bytes(result.stdout)
 record={'time':dt.datetime.now(dt.timezone.utc).isoformat(),'scenario':name,'result':'PASS' if passed else 'OBSERVED','evidence':path.name}
 with (backend.OUT/'device-evidence.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
 print(json.dumps(record),flush=True)
action=os.environ.get('FR25_DEVICE_ACTION','status');backend.b.target()
if action in ('login','login-other','login-rider','login-pending'):
 account=backend.b.fr04['accounts']['rider-pending' if action=='login-pending' else 'rider-a'] if action in ('login-rider','login-pending') else backend.state['accounts']['customer-b' if action=='login-other' else 'customer-a']
 fill(account['email']);fill(account['password'],1);backend.b.target();click('Sign in as');time.sleep(4)
elif action.startswith('tap:'):click(action[4:])
elif action.startswith('fill:'):fill(action[5:].replace(' ','%s'))
elif action.startswith('snapshot:'):evidence(action[9:])
elif action.startswith('assert:'):
 text=action[7:];assert any(text.lower() in label(n).lower() for n in nodes()),'Expected native UI was not observed';evidence(re.sub('[^a-z0-9]+','-',text.lower()).strip('-'),True)
elif action=='push-image':
 adb('shell','mkdir','-p','/sdcard/Pictures/TezRider-Test');adb('push',str(backend.OUT/'synthetic-evidence.png'),'/sdcard/Pictures/TezRider-Test/FR25-SYNTHETIC.png');adb('shell','am','broadcast','-a','android.intent.action.MEDIA_SCANNER_SCAN_FILE','-d','file:///sdcard/Pictures/TezRider-Test/FR25-SYNTHETIC.png')
elif action=='submit-confirmation':
 click('Submit dispute');deadline=time.monotonic()+55;observed_busy=False
 while time.monotonic()<deadline:
  current=nodes()
  if any('Evidence ' in label(n) for n in current):
   observed_busy=any(n.get('clickable')=='false' and label(n) in ('Submit dispute','Retry submission') for n in current)
  if any('Dispute submitted. Under review within 48 h.' in label(n) for n in current):
   evidence('exact-native-success-confirmation',True);break
  time.sleep(.3)
 else:raise AssertionError('Exact native confirmation was not observed')
 print(json.dumps({'busy_disabled_observed':observed_busy}))
elif action=='verify-isolation':
 token=backend.b.login(backend.state['accounts']['customer-b']);dispute_id=backend.state['device_dispute_id']
 code,_=backend.rpc('fr25_detail',{'p_id':dispute_id},token);backend.check(backend.denied(code),'second native customer denied first native dispute detail')
 code,_=backend.api('/functions/v1/fr25-evidence','POST',{'action':'view','dispute_id':dispute_id,'index':1},token);backend.check(backend.denied(code),'second native customer denied first native evidence URL')
elif action=='verify-expiry':
 order_id=backend.state['device_expired_order'];account=backend.state['accounts']['customer-a'];token=backend.b.login(account)
 code,rows=backend.api('/rest/v1/disputes?order_id=eq.'+str(order_id)+'&select=id&limit=1',token=token)
 backend.check(code==200 and rows==[],'native expiry rejection persisted no dispute')
elif action.startswith('verify-submission:'):
 order_id=action.split(':',1)[1];assert order_id.isdecimal(),'Synthetic order ID required'
 account=backend.state['accounts']['customer-a'];token=backend.b.login(account)
 code,orders=backend.api('/rest/v1/orders?id=eq.'+order_id+'&user_id=eq.'+str(account['profile_id'])+'&select=id,delivery_address&limit=1',token=token)
 assert code==200 and len(orders)==1 and orders[0]['delivery_address']=='FR25 SYNTHETIC TEST ONLY','Isolated synthetic order required'
 code,rows=backend.api('/rest/v1/disputes?order_id=eq.'+order_id+'&select=id&limit=2',token=token)
 backend.check(code==200 and len(rows)==1,'native submission persisted exactly one owned dispute')
 dispute_id=rows[0]['id'];code,detail=backend.rpc('fr25_detail',{'p_id':dispute_id},token)
 backend.check(code==200 and detail['description']=='FR25 physical device synthetic evidence test' and 1<=detail['evidence_count']<=3,'native description and evidence count persisted')
 code,notices=backend.api('/rest/v1/notifications?dispute_id=eq.'+str(dispute_id)+'&select=id&limit=2',admin=True)
 backend.check(code==200 and len(notices)==1,'native submission created exactly one admin notification')
 backend.state['device_dispute_id']=dispute_id;backend.save()
 (backend.OUT/'device-submission.json').write_text(json.dumps({'project_ref':backend.b.REF,'order_id':int(order_id),'dispute_id':dispute_id,'evidence_count':detail['evidence_count'],'notification_count':len(notices),'verified_at':dt.datetime.now(dt.timezone.utc).isoformat()},indent=2))
elif action.startswith('expire-order:'):
 order_id=action.split(':',1)[1];assert order_id.isdecimal()
 actor=backend.state['accounts']['customer-a']['profile_id'];assert isinstance(actor,int)
 # Fixture-only timestamp change: exact definition is restored inside the same
 # transaction before commit. Other sessions never see an altered trigger.
 file=backend.OUT/'device-expiry-fixture.sql'
 file.write_text("begin; set local lock_timeout='5s'; set local statement_timeout='30s'; do $test$ declare original text; begin if not exists(select 1 from public.orders where id="+order_id+" and user_id="+str(actor)+" and delivery_address='FR25 SYNTHETIC TEST ONLY' and order_status='delivered') or exists(select 1 from public.disputes where order_id="+order_id+") then raise exception 'Isolated unsubmitted synthetic order required'; end if; original:=pg_get_functiondef('public.fr25_delivery_timestamp()'::regprocedure); execute 'create or replace function public.fr25_delivery_timestamp() returns trigger language plpgsql set search_path='''' as $body$ begin return new; end $body$'; update public.orders set delivered_at=clock_timestamp()-interval '24 hours 5 seconds' where id="+order_id+" and user_id="+str(actor)+"; execute original; if pg_get_functiondef('public.fr25_delivery_timestamp()'::regprocedure)<>original then raise exception 'Trigger restoration failed'; end if; end $test$; commit; select id,delivered_at<clock_timestamp()-interval '24 hours' as expired from public.orders where id="+order_id+";")
 result=backend.query(file);backend.check(len(result['rows'])==1 and result['rows'][0]['expired'] is True,'isolated synthetic device order expired with deployed trigger restored')
 backend.state['device_expired_order']=int(order_id);backend.save()
elif action=='chat-reply':
 account=backend.state['accounts']['customer-a'];token=backend.b.login(account)
 code,room=backend.rpc('fr25_support_chat',{},token);assert code==200 and isinstance(room,int)
 code,rows=backend.api('/rest/v1/chat_messages?room_id=eq.'+str(room)+'&sender_id=eq.'+str(account['profile_id'])+'&message=eq.FR25%20Android%20chat%20preservation%2020261013&select=id&limit=2',token=token)
 backend.check(code==200 and len(rows)==1,'native customer chat message persisted exactly once')
 code,rooms=backend.api('/rest/v1/chat_rooms?id=eq.'+str(room)+'&select=user1_id,user2_id&limit=1',admin=True);assert code==200 and len(rooms)==1
 recipient=rooms[0]['user2_id'] if rooms[0]['user1_id']==account['profile_id'] else rooms[0]['user1_id']
 code,rows=backend.api('/rest/v1/users?id=eq.'+str(recipient)+'&select=email&limit=1',admin=True);assert code==200 and len(rows)==1
 actor=next((a for a in backend.state['accounts'].values() if a['email']==rows[0]['email']),None)
 if actor is None:actor=next((a for a in backend.b.state['accounts'].values() if a['email']==rows[0]['email']),None)
 assert actor is not None,'Protected synthetic admin credentials required'
 admin_token=backend.b.login(actor);message='FR25 native Realtime reply '+dt.datetime.now(dt.timezone.utc).strftime('%H%M%S')
 code,_=backend.api('/rest/v1/chat_messages','POST',{'room_id':room,'sender_id':recipient,'message':message},admin_token)
 backend.check(code==201,'synthetic approved admin reply persisted')
 backend.state['device_chat_reply']=message;backend.save();print(json.dumps({'expected_visible_reply':message}))
elif action.startswith('presence:'):
 expectation=action.split(':',1)[1];assert expectation in ('online','heartbeat','offline')
 account=backend.b.fr04['accounts']['rider-a'];token=backend.b.login(account)
 code,rows=backend.api('/rest/v1/riders?userid=eq.'+str(account['profile_id'])+'&select=is_online,last_seen&limit=1',token=token)
 assert code==200 and isinstance(rows,list) and len(rows)==1,'Presence lookup status '+str(code)+'; row count '+str(len(rows) if isinstance(rows,list) else 'unavailable')
 row=rows[0];now=dt.datetime.now(dt.timezone.utc);seen=dt.datetime.fromisoformat(row['last_seen'].replace('Z','+00:00')) if row['last_seen'] else None
 if expectation=='offline':backend.check(row['is_online'] is False,'native rider Offline persisted after FR25')
 else:
  code,profiles=backend.api('/rest/v1/users?id=eq.'+str(account['profile_id'])+'&select=verification_status&limit=1',admin=True)
  backend.check(code==200 and len(profiles)==1 and profiles[0]['verification_status']=='approved' and row['is_online'] is True and seen is not None and (now-seen).total_seconds()<120,'native approved rider Online has fresh persisted heartbeat after FR25')
  if expectation=='heartbeat':backend.check(seen>dt.datetime.fromisoformat(backend.state['device_presence_sample']),'native rider heartbeat timestamp advanced after FR25')
  backend.state['device_presence_sample']=seen.isoformat();backend.save()
 with (backend.OUT/'device-presence.jsonl').open('a') as f:f.write(json.dumps({'time':now.isoformat(),'expectation':expectation,**row})+'\n')
elif action=='cnic-regression':
 account=backend.b.fr04['accounts']['rider-pending'];token=backend.b.login(account)
 code,row=backend.rpc('fr04_application_status',{},token)
 backend.check(code==200 and row['document_valid'] is True and row['verification_status']=='approved','existing synthetic rider CNIC remains valid and approved after FR25')
 assert any(label(n)=='Rider Dashboard' for n in nodes()),'Approved rider native dashboard required'
 evidence('fr04-approved-rider-routing',True)
elif action=='artifact':
 backend.b.artifact()
 import zipfile
 passwords=[a['password'].encode() for a in backend.state['accounts'].values()]
 names=set()
 for args in (['git','diff','--name-only','-z'],['git','diff','--cached','--name-only','-z'],['git','ls-files','--others','--exclude-standard','-z']):names.update(subprocess.check_output(args,cwd=backend.ROOT).decode().split('\0'))
 for name in names-{''}:
  file=backend.ROOT/name
  if file.is_file():assert not any(p in file.read_bytes() for p in passwords),'FR25 private credential in changed file'
 with zipfile.ZipFile(backend.OUT/'TezRider-FR25-Test-debug.apk') as archive:
  for item in archive.infolist():
   if not item.is_dir():assert not any(p in archive.read(item) for p in passwords),'FR25 private credential in APK'
 backend.check(True,'FR25 credentials absent from changed files and final installed APK')
elif action=='logs':
 pid=adb('shell','pidof',PACKAGE).strip();assert re.fullmatch(r'\d+',pid),'TEST app PID required';logs=adb('logcat','-d','--pid='+pid)
 result={'fatal':len(re.findall(r'FATAL EXCEPTION|Unhandled Exception',logs,re.I)),'auth':len(re.findall(r'AuthApiException|invalid.login.credentials',logs,re.I)),'api':len(re.findall(r'PostgrestException|FunctionException',logs,re.I))}
 (backend.OUT/'android-log-summary.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));backend.check(not any(result.values()),'no observed Android fatal/auth/API exceptions in captured process logs')
elif action=='back':adb('shell','input','keyevent','4');time.sleep(1)
elif action.startswith('swipe:'):
 direction=action[6:];assert direction in ('up','down');adb('shell','input','swipe','500','1850' if direction=='up' else '700','500','650' if direction=='up' else '1850','400');time.sleep(1)
elif action=='status':
 safe=[]
 for n in nodes():
  value=label(n)
  if value and not n.get('password')=='true':safe.append({'label':re.sub(r'[\w.+-]+@[\w.-]+','[email]',value),'class':n.get('class'),'clickable':n.get('clickable'),'bounds':n.get('bounds')})
 print(json.dumps({'controls':safe},ensure_ascii=True))
else:raise RuntimeError('Unknown authorized device action')
