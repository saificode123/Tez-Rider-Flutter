"""FR30 guarded TEST-only verification. Never emit credentials or recipient PII."""
import importlib.util,json,re,sys,subprocess
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr30_previous',Path(__file__).with_name('FR-20-hosted.py'))
previous=importlib.util.module_from_spec(spec);spec.loader.exec_module(previous)
b=previous.b;ROOT=previous.ROOT;query=previous.query
OUT=ROOT/'.fr21-local/fr30';OUT.mkdir(parents=True,exist_ok=True)
MIGRATION=ROOT/'supabase/migrations/202610150004_fr30_admin_broadcasts.sql'
STATE=b.PRIVATE/'fr30-accounts.bin'
state=json.loads(b.crypt(STATE.read_bytes(),True))if STATE.exists()else {'accounts':{},'broadcasts':{}}

def save():STATE.write_bytes(b.crypt(json.dumps(state).encode()))

def fixture(label,role):
 import secrets
 account=state['accounts'].setdefault(label,{'email':'fr30-'+label+'@example.test','password':secrets.token_urlsafe(28)+'aA7!'});save()
 if 'auth_id'not in account:
  c,row=b.api('/auth/v1/admin/users','POST',{'email':account['email'],'password':account['password'],'email_confirm':True,'user_metadata':{'fr30_fixture':True,'role':role}},admin=True)
  assert c in(200,201),'Synthetic FR30 Auth fixture';account['auth_id']=row['id'];save()
 if 'profile_id'not in account:
  c,rows=b.api('/rest/v1/users','POST',{'email':account['email'],'name':'FR30 synthetic '+label,'role':role,'verification_status':'approved'},admin=True)
  assert c==201,'Synthetic FR30 profile fixture';account['profile_id']=rows[0]['id'];save()
 return account

def safe_audience(audience):
 assert audience in('CUSTOMERS','VENDORS'),'Committed hosted ALL/RIDERS forbidden: unrelated rider exists'
 role={'CUSTOMERS':'customer','VENDORS':'vendor'}[audience]
 result=query(write('cohort-'+role+'.sql',"""select count(*)as unmarked from public.users u join auth.users a on a.id=u.auth_user_id
 where u.role='"""+role+"""'and not u.is_blocked and a.email_confirmed_at is not null and not exists(
 select 1 from jsonb_each(coalesce(a.raw_user_meta_data,'{}'))e where e.key like '%fixture'and e.value='true'::jsonb);"""))['rows'][0]
 assert result['unmarked']==0,'Recipient cohort must be entirely explicitly synthetic'

def tests():
 import concurrent.futures,uuid,threading
 checks=[]
 def ok(value,label):
  assert value,label;checks.append({'check':label,'result':'PASS'})
 for label,role in [('admin','admin'),('race-admin','admin'),('customer','customer'),('other-customer','customer'),('vendor','vendor'),('blocked','customer')]:fixture(label,role)
 tokens={label:b.login(a)for label,a in state['accounts'].items()}
 blocked=state['accounts']['blocked']['profile_id']
 c,_=b.api('/rest/v1/users?id=eq.'+str(blocked),'PATCH',{'is_blocked':True},admin=True);ok(c==200,'block own synthetic recipient')
 try:
  safe_audience('CUSTOMERS');safe_audience('VENDORS')
  request={'p_request_id':str(uuid.uuid4()),'p_title':'FR30 synthetic concurrency','p_message':'Literal <b>plain text</b>','p_audience':'CUSTOMERS'}
  barrier=threading.Barrier(4)
  def send(_):barrier.wait(timeout=10);return b.rpc('admin_send_broadcast',request,tokens['admin'])
  with concurrent.futures.ThreadPoolExecutor(max_workers=4)as executor:results=list(executor.map(send,range(4)))
  ok(all(c==200 for c,r in results),'four genuine concurrent HTTP responses')
  ok(sorted(r['code']for c,r in results)==['ALREADY_SENT']*3+['SENT'],'one send and three authoritative concurrent replays')
  ok(len({r['id']for c,r in results})==1,'concurrent requests share one broadcast UUID')
  bid=request['p_request_id'];count=results[0][1]['recipient_count'];state['broadcasts']['concurrent']={'id':bid,'request':request,'count':count};save()
  c,rows=b.api('/rest/v1/notifications?broadcast_id=eq.'+bid+'&select=id,user_id,is_read,message,type',admin=True)
  ok(c==200 and len(rows)==count,'authoritative recipient count matches committed fan-out')
  ok(len({r['user_id']for r in rows})==count,'no duplicate recipient')
  ok(blocked not in[r['user_id']for r in rows],'blocked recipient excluded')
  ok(state['accounts']['vendor']['profile_id']not in[r['user_id']for r in rows],'other role excluded')
  ok(all(r['type']=='broadcast'and r['message']==request['p_message']for r in rows),'literal plain text stored with broadcast type')
  c,audits=b.api('/rest/v1/security_audit_log?broadcast_id=eq.'+bid+'&select=actor_id,action,broadcast_id',admin=True)
  ok(c==200 and len(audits)==1 and audits[0]['actor_id']==state['accounts']['admin']['profile_id'],'exactly one trusted audit')
  c,res=b.rpc('admin_send_broadcast',{**request,'p_title':'changed'},tokens['admin']);ok(c==200 and res['code']=='IDEMPOTENCY_CONFLICT','changed-payload replay conflicts')
  c,res=b.rpc('admin_send_broadcast',{**request,'p_request_id':str(uuid.uuid4())},tokens['admin']);ok(c==200 and res['code']=='COOLDOWN','hosted cooldown enforced')
  c,res=b.rpc('admin_send_broadcast',request,tokens['customer']);ok(c==200 and res['code']=='FORBIDDEN','customer cannot send')
  c,res=b.rpc('admin_send_broadcast',request,tokens['vendor']);ok(c==200 and res['code']=='FORBIDDEN','vendor cannot send')
  c,res=b.rpc('admin_send_broadcast',request);ok(c>=400,'anonymous cannot send')
  for label in ['customer','vendor']:
   c,res=b.api('/rest/v1/admin_broadcasts?select=id&limit=25',token=tokens[label]);ok(c==200 and res==[],label+' cannot enumerate history')
  c,history=b.api('/rest/v1/admin_broadcasts?select=id,title,audience,recipient_count,created_at,status&order=created_at.desc,id.desc&limit=25',token=tokens['admin'])
  ok(c==200 and any(r['id']==bid and r['recipient_count']==count for r in history),'admin history reflects accepted broadcast')
  c,own=b.api('/rest/v1/notifications?broadcast_id=eq.'+bid+'&select=id,user_id,is_read',token=tokens['customer'])
  ok(c==200 and len(own)==1 and own[0]['user_id']==state['accounts']['customer']['profile_id'],'recipient sees own delivery only')
  c,changed=b.api('/rest/v1/notifications?id=eq.'+str(own[0]['id']),'PATCH',{'is_read':True},tokens['vendor']);ok(c==200 and changed==[],'other role cannot change read state')
  c,changed=b.api('/rest/v1/notifications?id=eq.'+str(own[0]['id']),'PATCH',{'is_read':True},tokens['customer']);ok(c==200 and len(changed)==1 and changed[0]['is_read'],'own read state confirmed')
  c,res=b.api('/rest/v1/notifications','POST',{'user_id':state['accounts']['customer']['profile_id'],'title':'forged','message':'forged'},tokens['customer']);ok(c>=400,'client notification forgery denied')
  # A user created after send cannot acquire an old notification.
  late=fixture('late-'+uuid.uuid4().hex[:8],'customer');c,res=b.api('/rest/v1/notifications?broadcast_id=eq.'+bid+'&select=id',token=b.login(late));ok(c==200 and res==[],'new recipient does not acquire old broadcast')
  c,res=b.api('/rest/v1/notifications?broadcast_id=eq.'+bid+'&select=id',token=b.login(state['accounts']['other-customer']));ok(c==200 and len(res)==1,'offline non-subscriber retrieves broadcast after fresh login')
  # Different keys racing one administrator must not bypass cooldown.
  barrier=threading.Barrier(2)
  def distinct(_):
   barrier.wait(timeout=10);return b.rpc('admin_send_broadcast',{**request,'p_request_id':str(uuid.uuid4()),'p_audience':'VENDORS'},tokens['race-admin'])
  with concurrent.futures.ThreadPoolExecutor(max_workers=2)as executor:races=list(executor.map(distinct,range(2)))
  ok(all(c==200 for c,r in races)and sorted(r['code']for c,r in races)==['COOLDOWN','SENT'],'different-key concurrent sends cannot bypass cooldown')
 finally:
  c,_=b.api('/rest/v1/users?id=eq.'+str(blocked),'PATCH',{'is_blocked':False},admin=True);assert c==200,'Restore own synthetic recipient'
 result={'passed':len(checks),'checks':checks,'real_concurrent_http':True,'project_ref':b.REF,'unrelated_recipients':0}
 (OUT/'hosted-tests.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({k:result[k]for k in('passed','real_concurrent_http','unrelated_recipients')}))

def realtime():
 import uuid,time,urllib.parse
 sys.path.insert(0,str(ROOT/'build/fr21-python'))
 from websockets.sync.client import connect
 safe_audience('CUSTOMERS');admin=fixture('realtime-admin-'+uuid.uuid4().hex[:6],'admin')
 recipient=state['accounts']['customer'];vendor=state['accounts']['vendor'];bid=str(uuid.uuid4());sockets=[]
 def subscribe(label,account):
  ws=connect('wss://'+b.REF+'.supabase.co/realtime/v1/websocket?'+urllib.parse.urlencode({'apikey':b.ANON,'vsn':'1.0.0'}),open_timeout=15,close_timeout=3);sockets.append(ws)
  ws.send(json.dumps({'topic':'realtime:fr30-'+label+'-'+bid,'event':'phx_join','ref':'1','payload':{'config':{'broadcast':{'self':False},'presence':{'key':''},'postgres_changes':[{'event':'INSERT','schema':'public','table':'notifications','filter':'user_id=eq.'+str(recipient['profile_id'])}]},'access_token':b.login(account)}}))
  until=time.monotonic()+20
  while time.monotonic()<until:
   data=json.loads(ws.recv(timeout=20))
   if data['event']=='system':assert data['payload'].get('status')=='ok','Realtime readiness';return ws
   if data['event']=='phx_reply'and data['payload'].get('status')=='error':raise AssertionError('Realtime subscription rejected')
  raise AssertionError('Realtime readiness timed out')
 def events(ws,seconds):
  total=0;until=time.monotonic()+seconds
  while time.monotonic()<until:
   try:data=json.loads(ws.recv(timeout=max(.1,until-time.monotonic())))
   except TimeoutError:break
   if data['event']=='postgres_changes'and data['payload'].get('data',{}).get('record',{}).get('broadcast_id')==bid:total+=1
  return total
 try:
  own=subscribe('own',recipient);spy=subscribe('intruder',vendor)
  c,res=b.rpc('admin_send_broadcast',{'p_request_id':bid,'p_title':'FR30 synthetic Realtime','p_message':'Synthetic websocket verification.','p_audience':'CUSTOMERS'},b.login(admin));assert c==200 and res['code']=='SENT','Synthetic broadcast accepted'
  received=events(own,5);exposed=events(spy,3)
  assert received==1 and exposed==0,'Realtime receipt or privacy failed'
  result={'passed':3,'subscription_ready':True,'own_insert_events':received,'unauthorized_events':exposed,'native_push_tested':False}
  (OUT/'realtime.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))
 finally:
  for ws in sockets:ws.close()

def regression21():
 spec=importlib.util.spec_from_file_location('fr30_regression21',ROOT/'tests/integration/FR-21-hosted.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 calls=[];original=module.rpc
 def tracked(name,params,token=None,expected=(200,)):
  # FR20 now requires a fresh GPS fix as well as a presence heartbeat. The
  # legacy suite does many HTTP probes after its initial fix; model ongoing
  # device GPS without weakening any original authorization/race assertions.
  if name=='fr21_set_presence'and params.get('p_online')is True and expected==(200,):
   original('fr21_update_location',{'p_lat':31.52,'p_lng':74.35},token,(204,))
  result=original(name,params,token,expected)
  if name=='fr21_ready_and_assign':calls.append({k:result.get(k)for k in ['code','rider_id','search_radius_m','manual_assignment']})
  return result
 module.rpc=tracked
 original_row=module.row
 def ready_secondary(table,payload):
  # Seed the unrelated owner's line ready, as required by accepted FR20
  # shared-parent readiness, before racing assignment for the other line.
  if table=='vendor_orders'and payload.get('vendor_id')==module.state['accounts'].get('other-vendor',{}).get('profile_id'):
   payload={**payload,'status':'ready'}
  return original_row(table,payload)
 module.row=ready_secondary
 try:module.main()
 finally:(OUT/'regression21-assignment-results.json').write_text(json.dumps(calls,indent=2),encoding='utf-8')

def inspect21():
 saved=json.loads(b.crypt((b.PRIVATE/'accounts.bin').read_bytes(),True));accounts=saved['accounts']
 ids=','.join(str(a['profile_id'])for a in accounts.values()if 'profile_id'in a)
 result=query(write('regression21-inspect.sql',"""select jsonb_build_object(
 'riders',(select jsonb_agg(jsonb_build_object('approved',u.verification_status='approved','blocked',u.is_blocked,'online',r.is_online,'available',r.is_available,'legacy_available',r.isavailable,'presence_age_s',extract(epoch from now()-r.last_seen),'location_age_s',extract(epoch from now()-r.location_updated_at),'at_fixture_position',r.latitude=31.52 and r.longitude=74.35,'active_assignments',(select count(*)from public.rider_assignments a where a.riderid=u.id and a.status in('Pending','Accepted'))))from public.users u join public.riders r on r.userid=u.id where u.id in("""+ids+""")),
 'vendors',(select jsonb_agg(jsonb_build_object('at_fixture_position',v.latitude=31.52 and v.longitude=74.35))from public.vendors v where v.user_id in("""+ids+""")))as inspection;"""))['rows'][0]['inspection']
 print(json.dumps(result));(OUT/'regression21-fixtures.json').write_text(json.dumps(result,indent=2),encoding='utf-8')

def native_fixture():
 # Explicit synthetic fixture for existing personal-notification rendering.
 # Production notification creation paths are not replaced or bypassed.
 customer=state['accounts']['customer'];blocked=state['accounts']['blocked']
 c,user=b.api('/auth/v1/admin/users/'+blocked['auth_id'],admin=True);assert c==200 and user['user_metadata'].get('fr30_fixture')is True
 c,_=b.api('/rest/v1/users?id=eq.'+str(blocked['profile_id']),'PATCH',{'is_blocked':True},admin=True);assert c==200
 if 'personal_notification'not in state:
  c,rows=b.api('/rest/v1/notifications','POST',{'user_id':customer['profile_id'],'title':'FR30 synthetic personal notice','message':'Personal-notification display fixture.','type':'system'},admin=True);assert c==201 and len(rows)==1
  state['personal_notification']=rows[0]['id'];save()
 print(json.dumps({'synthetic_personal_fixture':True,'blocked_synthetic_recipient':True}))

def native_vendor():
 state['accounts']['native-vendor']=previous.state['accounts']['vendor'];save()
 print(json.dumps({'existing_synthetic_vendor_reused':True}))

def verify_native():
 import urllib.parse
 checks=[]
 def ok(value,label):assert value,label;checks.append({'check':label,'result':'PASS'})
 c,rows=b.api('/rest/v1/admin_broadcasts?title=eq.'+urllib.parse.quote('FR30 final vendor broadcast')+'&select=id,recipient_count',admin=True)
 ok(c==200 and len(rows)==1,'physical confirmation double tap created exactly one broadcast')
 bid=rows[0]['id'];c,notices=b.api('/rest/v1/notifications?broadcast_id=eq.'+bid+'&select=user_id',admin=True)
 ok(c==200 and len(notices)==rows[0]['recipient_count']==9,'native vendor count and unique snapshot match')
 c,own=b.api('/rest/v1/notifications?broadcast_id=eq.'+bid+'&select=id',token=b.login(state['accounts']['native-vendor']))
 ok(c==200 and len(own)==1,'actual native vendor owns final vendor delivery')
 c,wrong=b.api('/rest/v1/notifications?broadcast_id=eq.'+bid+'&select=id',token=b.login(state['accounts']['customer']))
 ok(c==200 and wrong==[],'customer cannot see final vendor broadcast')
 c,wrong=b.api('/rest/v1/notifications?broadcast_id=eq.'+state['offline_broadcast']['id']+'&select=id',token=b.login(state['accounts']['native-vendor']))
 ok(c==200 and wrong==[],'native vendor cannot see customer offline broadcast')
 c,personal=b.api('/rest/v1/notifications?id=eq.'+str(state['personal_notification'])+'&select=is_read',token=b.login(state['accounts']['customer']))
 ok(c==200 and len(personal)==1 and personal[0]['is_read'],'physical mark-all persisted personal read state')
 c,offline=b.api('/rest/v1/notifications?broadcast_id=eq.'+state['offline_broadcast']['id']+'&select=is_read',token=b.login(state['accounts']['customer']))
 ok(c==200 and len(offline)==1 and offline[0]['is_read'],'physical individual read persisted after reconnect')
 c,audits=b.api('/rest/v1/security_audit_log?broadcast_id=eq.'+bid+'&select=id',admin=True)
 ok(c==200 and len(audits)==1,'physical double-tap audit exactly once')
 result={'passed':len(checks),'checks':checks,'device':'AESWNRBAEUPNTGJZ','final_apk':True}
 (OUT/'native-persistence.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({'passed':len(checks),'physical_persistence_verified':True}))

def history_pages():
 import urllib.parse
 token=b.login(state['accounts']['admin']);fields='id,title,audience,recipient_count,created_at,status'
 c,all_rows=b.api('/rest/v1/admin_broadcasts?'+urllib.parse.urlencode({'select':fields,'order':'created_at.desc,id.desc','limit':100}),token=token)
 assert c==200 and len(all_rows)<100,'Bounded synthetic admin history baseline'
 seen=[];cursor=None;pages=0
 while pages<50:
  params={'select':fields,'order':'created_at.desc,id.desc','limit':2}
  if cursor:params['or']='(created_at.lt.'+cursor['created_at']+',and(created_at.eq.'+cursor['created_at']+',id.lt.'+cursor['id']+'))'
  c,rows=b.api('/rest/v1/admin_broadcasts?'+urllib.parse.urlencode(params),token=token);assert c==200,'Exact history keyset query'
  pages+=1;seen.extend(rows)
  if len(rows)<2:break
  cursor=rows[-1]
 assert [r['id']for r in seen]==[r['id']for r in all_rows]and len({r['id']for r in seen})==len(seen),'Stable complete history without duplicate/drop'
 result={'passed':3,'actual_postgrest_pages':pages,'page_size':2,'records':len(seen),'duplicates':0,'dropped':0}
 (OUT/'history-pages.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))

def offline_send():
 import uuid
 safe_audience('CUSTOMERS')
 request=state.setdefault('offline_request',{'p_request_id':str(uuid.uuid4()),'p_title':'FR30 offline recovery','p_message':'Sent while the synthetic phone was offline.','p_audience':'CUSTOMERS'});save()
 c,res=b.rpc('admin_send_broadcast',request,b.login(state['accounts']['admin']));assert c==200 and res['code']in('SENT','ALREADY_SENT'),'Offline broadcast acceptance'
 c,rows=b.api('/rest/v1/notifications?broadcast_id=eq.'+res['id']+'&select=user_id',admin=True);assert c==200 and len(rows)==res['recipient_count']
 assert state['accounts']['blocked']['profile_id']not in[r['user_id']for r in rows],'Blocked recipient exclusion'
 assert state['accounts']['vendor']['profile_id']not in[r['user_id']for r in rows],'Other role exclusion'
 result={'code':res['code'],'recipient_count':res['recipient_count'],'blocked_excluded':True,'other_role_excluded':True,'database_accepted':True,'native_receipt_pending':True}
 state['offline_broadcast']=res;save();(OUT/'native-offline-send.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))

def verify():
 result=query(write('verify.sql',"""select jsonb_build_object(
 'versions',(select jsonb_agg(version order by version)from supabase_migrations.schema_migrations),
 'policies',(select jsonb_agg(jsonb_build_object('name',policyname,'command',cmd,'using',qual,'check',with_check))from pg_policies where schemaname='public'and tablename='admin_broadcasts'),
 'definers',(select jsonb_agg(jsonb_build_object('name',proname,'definer',prosecdef,'settings',proconfig,'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),'auth_execute',has_function_privilege('authenticated',p.oid,'EXECUTE')))from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and proname in('admin_send_broadcast','fr30_estimate')),
 'sender_lock_correct',(select position('for no key update;'in pg_get_functiondef('public.admin_send_broadcast(uuid,text,text,text)'::regprocedure))>0),
 'client_insert',has_table_privilege('authenticated','public.admin_broadcasts','INSERT'),
 'client_update',has_table_privilege('authenticated','public.admin_broadcasts','UPDATE'),
 'client_delete',has_table_privilege('authenticated','public.admin_broadcasts','DELETE'),
 'client_notification_insert',has_table_privilege('authenticated','public.notifications','INSERT'),
 'client_audit_insert',has_table_privilege('authenticated','public.security_audit_log','INSERT'),
 'count_mismatch',(select count(*)from public.admin_broadcasts b where b.recipient_count<>(select count(*)from public.notifications n where n.broadcast_id=b.id)),
 'audit_mismatch',(select count(*)from public.admin_broadcasts b where 1<>(select count(*)from public.security_audit_log a where a.broadcast_id=b.id and a.action='SEND_BROADCAST'and a.actor_id=b.sender_id and a.target_id=b.audit_number)),
 'duplicate_recipients',(select count(*)from(select broadcast_id,user_id from public.notifications where broadcast_id is not null group by broadcast_id,user_id having count(*)>1)s),
 'unmarked_recipient_count',(select count(*)from public.notifications n join public.users u on u.id=n.user_id join auth.users a on a.id=u.auth_user_id where n.broadcast_id is not null and not exists(select 1 from jsonb_each(coalesce(a.raw_user_meta_data,'{}'))e where e.key like '%fixture'and e.value='true'::jsonb)),
 'limits',(select to_jsonb(l)from fr30_private.limits l),
 'indexes',(select jsonb_agg(indexdef)from pg_indexes where indexname like 'fr30_%')
 )as verification;"""))['rows'][0]['verification']
 assert result['versions']==sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
 assert result['sender_lock_correct']and len(result['policies'])==2
 assert all(f['definer']and not f['anon_execute']and f['auth_execute']and 'search_path=""'in f['settings']for f in result['definers'])
 assert not any(result[k]for k in ['client_insert','client_update','client_delete','client_notification_insert','client_audit_insert','count_mismatch','audit_mismatch','duplicate_recipients','unmarked_recipient_count'])
 (OUT/'final-verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({'verified':True,'versions':len(result['versions']),'duplicate_or_audit_mismatches':0,'unrelated_recipients':0,'client_forgery_denied':True}))

def cleanup():
 blocked=state['accounts']['blocked'];c,user=b.api('/auth/v1/admin/users/'+blocked['auth_id'],admin=True);assert c==200 and user['user_metadata'].get('fr30_fixture')is True
 c,_=b.api('/rest/v1/users?id=eq.'+str(blocked['profile_id']),'PATCH',{'is_blocked':False},admin=True);assert c==200
 print(json.dumps({'synthetic_block_restored':True,'unrelated_records_modified':False}))

def security_scan():
 previous.security_scan()
 names=set()
 for args in [['git','diff','--name-only','-z'],['git','diff','--cached','--name-only','-z'],['git','ls-files','--others','--exclude-standard','-z']]:
  names.update(filter(None,subprocess.check_output(args,cwd=ROOT).decode().split('\0')))
 for name in names-{'.gitignore'}:
  p=ROOT/name
  assert p.stat().st_size<5*1024*1024,'Unexpected file over 5MB'
  assert not any(a['password'].encode()in p.read_bytes()for a in state['accounts'].values()),'FR30 fixture credential in changed file'
  assert p.suffix.lower()not in('.apk','.jks','.keystore','.p12','.p8'), 'Unexpected binary/credential artifact'
 result={'files_scanned':len(names-{'.gitignore'}),'credential_matches':0,'unexpected_large_files':0,'unrelated_gitignore_excluded':True}
 (OUT/'security-scan.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))


def write(name,sql):
 p=OUT/name;p.write_text(sql,encoding='utf-8',newline='\n');return p

def device():exec(compile((ROOT/'tests/integration/FR-30-device.py').read_text(encoding='utf-8'),'FR-30-device.py','exec'),{'backend':sys.modules[__name__]})

def artifact():
 import shutil,zipfile,hashlib,subprocess
 mirror=Path('C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-auth-debug/android-build-20261012-125502');sources=list((ROOT/'lib').rglob('*.dart'))
 assert all(p.read_bytes()==(mirror/p.relative_to(ROOT)).read_bytes()for p in sources),'Build mirror source mismatch'
 apk=OUT/'TezRider-FR30-Test-debug.apk';shutil.copyfile(mirror/'build/app/outputs/flutter-apk/app-fr21test-debug.apk',apk)
 secrets=[b.SERVICE]+[a['password']for a in state['accounts'].values()]
 endpoint_found=False
 with zipfile.ZipFile(apk)as z:
  for n in z.namelist():
   if n.endswith('/'):continue
   payload=z.read(n);endpoint_found=endpoint_found or b.BASE.encode()in payload
   assert b'https://arrqsvejrfdbacfwtpcc.supabase.co'not in payload and not any(v.encode()in payload for v in secrets),'Artifact endpoint/credential guard'
 assert endpoint_found,'Compiled TEST endpoint required'
 r=subprocess.run(['C:/Users/urreh/AppData/Local/Android/Sdk/build-tools/36.0.0/aapt.exe','dump','badging',str(apk)],capture_output=True,text=True,timeout=30);assert r.returncode==0 and "package: name='com.example.flutter_application_1.fr21test'"in r.stdout
 with apk.open('rb')as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
 result={'sha256':digest,'bytes':apk.stat().st_size,'source_files_matched':len(sources),'test_only':True,'credentials_absent':True};(OUT/'artifact.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))

def inspect():
 result=query(write('inspect.sql',"""select jsonb_build_object(
 'versions',(select jsonb_agg(version order by version)from supabase_migrations.schema_migrations),
 'cohorts',(select jsonb_agg(s)from(select u.role,count(*)as total,count(*)filter(where
 not exists(select 1 from jsonb_each(coalesce(a.raw_user_meta_data,'{}'))e where e.key like '%fixture'and e.value='true'::jsonb))as unmarked
 from public.users u join auth.users a on a.id=u.auth_user_id where not u.is_blocked and a.email_confirmed_at is not null group by u.role)s),
 'notification_columns',(select jsonb_agg(column_name)from information_schema.columns where table_schema='public'and table_name='notifications'),
 'realtime',(select jsonb_agg(tablename)from pg_publication_tables where pubname='supabase_realtime'and tablename='notifications'))as inspection;"""))['rows'][0]['inspection']
 (OUT/'inspection.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))

def sql(review=False,patch=False):
 rules=(ROOT/'supabase/tests/FR-30.sql').read_text(encoding='utf-8')
 if review:
  migration=(ROOT/'supabase/migrations/202610150005_fr30_sender_lock.sql'if patch else MIGRATION).read_text(encoding='utf-8');migration=re.sub(r'^begin;\s*','',migration,flags=re.M);migration=re.sub(r'^commit;\s*','',migration,flags=re.M)
  rules=rules.replace('begin;','begin;\n'+migration,1)
 result=query(write('review.sql'if review else 'rules.sql',rules))
 (OUT/('migration-review.json'if review else 'sql-tests.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
 print(json.dumps({'passed':len(result['rows'][0]['results']),'rolled_back':True,'migration_applied':False}))

def deploy(patch=False,push=False):
 migration=ROOT/'supabase/migrations/202610150006_fr30_android_push.sql'if push else ROOT/'supabase/migrations/202610150005_fr30_sender_lock.sql'if patch else MIGRATION
 b.target();history=write('history.sql','select version from supabase_migrations.schema_migrations order by version;')
 versions=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
 assert [r['version']for r in query(history)['rows']]==[v for v in versions if v!=migration.name.split('_')[0]],'History mismatch; never replay'
 def command(args):
  p=subprocess.run(['C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe',*args],cwd=ROOT,capture_output=True,text=True,timeout=150)
  (OUT/'deployment-last.log').write_text(p.stdout+p.stderr,encoding='utf-8')
  assert p.returncode==0,'Guarded FR30 TEST deployment failed';return p.stdout+p.stderr
 plan=command(['db','push','--linked','--dry-run'])
 assert sorted(set(re.findall(r'2026\d{8}_[a-z0-9_]+\.sql',plan)))==[migration.name],'Unexpected migration plan'
 command(['db','push','--linked'])
 assert [r['version']for r in query(history)['rows']]==versions
 result={'project_ref':b.REF,'migration':migration.name,'versions':len(versions),'production_touched':False,'replayed':False}
 (OUT/'deployment.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))

if __name__=='__main__':
 try:{'inspect':inspect,'review':lambda:sql(True),'sql':sql,'deploy':deploy,'patch-review':lambda:sql(True,True),'patch-deploy':lambda:deploy(True),'tests':tests,'realtime':realtime,'regression21':regression21,'inspect21':inspect21,'artifact':artifact,'device':device,'native-fixture':native_fixture,'native-vendor':native_vendor,'verify-native':verify_native,'history-pages':history_pages,'offline-send':offline_send,'verify':verify,'cleanup':cleanup,'security-scan':security_scan}[sys.argv[1]]()
 except Exception as e:
  print(json.dumps({'failed':1,'type':type(e).__name__,'reason':str(e)if isinstance(e,AssertionError)else 'Guarded FR30 check failed'}));sys.exit(1)
