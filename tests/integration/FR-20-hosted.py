"""FR20 guarded TEST checks; protected fixture data never enters output."""
import importlib.util,json,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr20_previous',Path(__file__).with_name('FR-28-hosted.py'))
previous=importlib.util.module_from_spec(spec);spec.loader.exec_module(previous)
b=previous.b;ROOT=previous.ROOT;OUT=ROOT/'.fr21-local/fr20';OUT.mkdir(parents=True,exist_ok=True)
query=previous.previous.query
STATE=b.PRIVATE/'fr20-accounts.bin'
state=json.loads(b.crypt(STATE.read_bytes(),True))if STATE.exists()else {'accounts':{},'orders':{}}
def save():STATE.write_bytes(b.crypt(json.dumps(state).encode()))

def deploy(patch=False,shared=False):
 import subprocess,re
 b.target();expected='202610150003_fr20_shared_parent_ready.sql'if shared else '202610150002_fr20_escalation_receipt.sql'if patch else '202610150001_fr20_radius_assignment.sql';file=OUT/'history.sql';file.write_text('select version from supabase_migrations.schema_migrations order by version;',encoding='utf-8')
 before=[r['version']for r in query(file)['rows']];versions=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
 assert before==[v for v in versions if v!=expected.split('_')[0]],'Accepted history mismatch or migration already applied; never replay'
 def command(args):
  result=subprocess.run(['C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe',*args],cwd=ROOT,capture_output=True,text=True,timeout=150)
  assert result.returncode==0,'Guarded FR20 TEST deployment failed'
  return result.stdout+result.stderr
 plan=command(['db','push','--linked','--dry-run'])
 assert sorted(set(re.findall(r'2026\d{8}_[a-z0-9_]+\.sql',plan)))==[expected],'Unexpected migration plan'
 command(['db','push','--linked'])
 assert [r['version']for r in query(file)['rows']]==versions,'Post-deployment history mismatch'
 result={'project_ref':b.REF,'migration':expected,'versions':len(versions),'production_touched':False,'reset':False,'replayed':False}
 (OUT/'deployment.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))

def fixture(label,role):
 import secrets
 a=state['accounts'].setdefault(label,{'email':'fr20-'+label+'@example.test','password':secrets.token_urlsafe(28)+'aA7!'});save()
 if 'auth_id'not in a:
  c,row=b.api('/auth/v1/admin/users','POST',{'email':a['email'],'password':a['password'],'email_confirm':True,'user_metadata':{'fr20_fixture':True}},admin=True)
  assert c in(200,201),'Synthetic FR20 Auth fixture';a['auth_id']=row['id'];save()
 if 'profile_id'not in a:
  c,rows=b.api('/rest/v1/users','POST',{'email':a['email'],'name':'FR20 synthetic '+label,'role':role,'verification_status':'approved'},admin=True)
  assert c==201,'Synthetic FR20 profile fixture';a['profile_id']=rows[0]['id'];save()
 return a

def setup():
 for label,role in [('vendor','vendor'),('other-vendor','vendor'),('customer','customer'),('rider','rider'),('rider2','rider'),('admin','admin')]:fixture(label,role)
 for label in ['rider','rider2']:
  c,rows=b.api('/rest/v1/riders?userid=eq.'+str(state['accounts'][label]['profile_id'])+'&select=id&limit=1',admin=True)
  if not rows:
   c,_=b.api('/rest/v1/riders','POST',{'userid':state['accounts'][label]['profile_id']},admin=True);assert c==201
 c,rows=b.api('/rest/v1/vendors?user_id=eq.'+str(state['accounts']['vendor']['profile_id'])+'&select=id&limit=1',admin=True)
 if not rows:
  c,_=b.api('/rest/v1/vendors','POST',{'user_id':state['accounts']['vendor']['profile_id'],'store_name':'FR20 synthetic store','latitude':-60,'longitude':-140},admin=True);assert c==201

def position(meters=4900,second=20000):
 # Owner-operated, explicitly tagged synthetic stored locations only. Real
 # account locations and availability are never touched by this fixture helper.
 file=OUT/('position-'+str(__import__('uuid').uuid4())+'.sql');ids=[state['accounts'][x]['profile_id']for x in ['rider','rider2']]
 file.write_text("begin; set local request.jwt.claims='{\"role\":\"service_role\"}';\n"+'\n'.join("do $$declare p extensions.geometry;begin if not exists(select 1 from public.users where id="+str(rid)+" and name='FR20 synthetic "+label+"')then raise exception 'Synthetic fixture required';end if;p:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(-140,-60),4326)::extensions.geography,"+str(distance)+",0)::extensions.geometry;update public.riders set latitude=extensions.st_y(p),longitude=extensions.st_x(p),location_updated_at=clock_timestamp(),last_seen=clock_timestamp(),is_online=true,is_available=true,isavailable=true where userid="+str(rid)+";update public.users set verification_status='approved'where id="+str(rid)+";end$$;"for rid,label,distance in zip(ids,['rider','rider2'],[meters,second]))+'\ncommit;select true as prepared;',encoding='utf-8')
 query(file)

def order(label):
 c,rows=b.api('/rest/v1/orders','POST',{'user_id':state['accounts']['customer']['profile_id'],'order_status':'accepted','amount':25,'payment_method':'COD','delivery_address':'FR20 SYNTHETIC TEST ONLY'},admin=True);assert c==201
 oid=rows[0]['id'];c,rows=b.api('/rest/v1/vendor_orders','POST',{'order_id':oid,'vendor_id':state['accounts']['vendor']['profile_id'],'status':'accepted','sub_total':25},admin=True);assert c==201
 state['orders'][label]={'id':oid,'vendor_order_id':rows[0]['id']};save();return state['orders'][label]

def cancel(row):
 c,rows=b.api('/rest/v1/orders?id=eq.'+str(row['id'])+'&delivery_address=eq.FR20%20SYNTHETIC%20TEST%20ONLY','PATCH',{'order_status':'cancelled'},admin=True);assert c==200 and len(rows)==1,'Only own tagged synthetic order may be released'
 c,_=b.api('/rest/v1/vendor_orders?id=eq.'+str(row['vendor_order_id'])+'&order_id=eq.'+str(row['id']),'PATCH',{'status':'cancelled'},admin=True);assert c==200,'Synthetic child status cleanup'

def native_fixture(which):
 assert which in('5km','10km','none','offline','blocked')
 for label,row in state['orders'].items():
  if label.startswith('native-'):cancel(row)
 if 'physical-rider'not in state['accounts']:
  saved=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True));state['accounts']['physical-rider']=saved['accounts']['physical-rider'];save()
 rider=state['accounts']['physical-rider'];c,status=b.rpc('fr04_application_status',{},b.login(rider))
 assert c==200 and status['document_valid']is True and status['verification_status']=='approved','Existing valid synthetic CNIC required'
 position(20000,20000)
 meters={'5km':4900,'10km':7000,'none':11000,'offline':4900,'blocked':4900}[which]
 file=OUT/('native-'+which+'.sql');file.write_text("begin;do $$declare p extensions.geometry;begin if not exists(select 1 from auth.users where id='"+rider['auth_id']+"'and(raw_user_meta_data->>'fr04_fixture'='true'or raw_user_meta_data->>'fr21_fixture'='true'or raw_user_meta_data->>'fr33_fixture'='true'))then raise exception 'Synthetic rider required';end if;p:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(-140,-60),4326)::extensions.geography,"+str(meters)+",0)::extensions.geometry;update public.riders set latitude=extensions.st_y(p),longitude=extensions.st_x(p),location_updated_at=clock_timestamp(),last_seen=clock_timestamp(),is_online="+('false'if which=='offline'else'true')+",is_available=true,isavailable=true where userid="+str(rider['profile_id'])+";end$$;commit;select true as prepared;",encoding='utf-8');query(file)
 if which=='blocked':
  c,result=b.api('/functions/v1/admin-user-status','POST',{'target_id':rider['profile_id'],'blocked':True,'request_id':str(__import__('uuid').uuid4())},b.login(state['accounts']['admin']));assert c==200 and result['code']=='OK'
 row=order('native-'+which);print(json.dumps({'native_case':which,'synthetic_order_id':row['id'],'vendor_order_id':row['vendor_order_id']}))

def device():exec(compile((ROOT/'tests/integration/FR-20-device.py').read_text(encoding='utf-8'),'FR-20-device.py','exec'),{'backend':sys.modules[__name__]})

def artifact():
 import shutil,zipfile,hashlib,subprocess
 mirror=Path('C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-auth-debug/android-build-20261012-125502');sources=list((ROOT/'lib').rglob('*.dart'))
 assert all(p.read_bytes()==(mirror/p.relative_to(ROOT)).read_bytes()for p in sources),'Build mirror source mismatch'
 apk=OUT/'TezRider-FR20-Test-debug.apk';shutil.copyfile(mirror/'build/app/outputs/flutter-apk/app-fr21test-debug.apk',apk)
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

def verify():
 file=OUT/'verify.sql';file.write_text("""select jsonb_build_object(
 'versions',(select jsonb_agg(version order by version)from supabase_migrations.schema_migrations),
 'duplicate_riders',(select count(*)from(select riderid from public.rider_assignments where status in('Pending','Accepted')group by riderid having count(*)>1)s),
 'duplicate_orders',(select count(*)from(select orderid from public.rider_assignments where status in('Pending','Accepted')group by orderid having count(*)>1)s),
 'duplicate_notifications',(select count(*)from(select user_id,assignment_order_id,assignment_event from public.notifications where assignment_event is not null group by user_id,assignment_order_id,assignment_event having count(*)>1)s),
 'duplicate_audits',(select count(*)from(select assignment_order_id,action from public.security_audit_log where assignment_order_id is not null group by assignment_order_id,action having count(*)>1)s),
 'pending_block_operations',(select count(*)from public.fr28_operations where state<>'SYNCED'),
 'blocked_fr20_fixtures',(select count(*)from public.users where name like 'FR20 synthetic %'and is_blocked),
 'assignment_client_insert',has_table_privilege('authenticated','public.rider_assignments','INSERT'),
 'notification_client_insert',has_table_privilege('authenticated','public.notifications','INSERT'),
 'audit_client_insert',has_table_privilege('authenticated','public.security_audit_log','INSERT'),
 'manual_flag_client_update',has_column_privilege('authenticated','public.orders','requires_manual_assignment','UPDATE'),
 'anonymous_assignment_execute',has_function_privilege('anon','public.fr21_ready_and_assign(bigint)','EXECUTE'),
 'max_connections',current_setting('max_connections'),
 'indexes',(select jsonb_agg(indexdef)from pg_indexes where indexname like 'fr20_%'),
 'policies',(select jsonb_agg(jsonb_build_object('table',tablename,'name',policyname,'command',cmd,'using',qual,'check',with_check))from pg_policies where schemaname='public'and tablename in('riders','orders','rider_assignments','notifications','security_audit_log')),
 'definers',(select jsonb_agg(jsonb_build_object('name',proname,'definer',prosecdef,'settings',proconfig,'grants',proacl))from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and proname in('fr21_ready_and_assign','fr20_assignment_status','fr21_update_location','fr21_accept_order','fr20_guard_manual_flag'))
 )as verification;""",encoding='utf-8')
 result=query(file)['rows'][0]['verification'];assert result['versions']==sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql')),'Migration history mismatch'
 assert all(result[x]==0 for x in ['duplicate_riders','duplicate_orders','duplicate_notifications','duplicate_audits','pending_block_operations','blocked_fr20_fixtures']),'Unreconciled duplicate/account state'
 assert not any(result[x]for x in ['assignment_client_insert','notification_client_insert','audit_client_insert','manual_flag_client_update','anonymous_assignment_execute']),'Unexpected client privilege'
 assert len(result['indexes'])==5,'Missing assignment indexes'
 (OUT/'final-verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({'verification':'PASS','versions':len(result['versions']),'duplicate_invariants':0,'client_privileges_denied':True}))

def security_scan():
 import subprocess
 previous.security_scan()
 names=set()
 for args in [['git','diff','--name-only','-z'],['git','diff','--cached','--name-only','-z'],['git','ls-files','--others','--exclude-standard','-z']]:names.update(filter(None,subprocess.check_output(args,cwd=ROOT).decode().split('\0')))
 for name in names-{'.gitignore'}:
  p=ROOT/name
  assert p.stat().st_size<5*1024*1024,'Unexpected file over 5MB'
  assert not any(a['password'].encode()in p.read_bytes()for a in state['accounts'].values()),'FR20 fixture credential in changed file'
 result={'files_scanned':len(names),'credential_matches':0,'unexpected_large_files':0,'gitignore_excluded':True}
 (OUT/'security-scan.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))

def cleanup():
 customer=state['accounts']['customer']['profile_id'];vendor=state['accounts']['vendor']['profile_id']
 c,rows=b.api('/rest/v1/orders?user_id=eq.'+str(customer)+'&delivery_address=eq.FR20%20SYNTHETIC%20TEST%20ONLY&order_status=not.in.(delivered,cancelled)&select=id&limit=200',admin=True)
 assert c==200 and len(rows)<200,'Bounded own-fixture cleanup required'
 for row in rows:
  c,children=b.api('/rest/v1/vendor_orders?order_id=eq.'+str(row['id'])+'&vendor_id=eq.'+str(vendor)+'&select=id&limit=2',admin=True);assert c==200 and len(children)==1
  cancel({'id':row['id'],'vendor_order_id':children[0]['id']})
 for label in ['rider','rider2']:
  c,_=b.api('/rest/v1/riders?userid=eq.'+str(state['accounts'][label]['profile_id']),'PATCH',{'is_online':False},admin=True);assert c==200
 rider=state['accounts'].get('physical-rider')
 if rider:
  c,profiles=b.api('/rest/v1/users?id=eq.'+str(rider['profile_id'])+'&select=is_blocked',admin=True);assert c==200 and not profiles[0]['is_blocked'],'Physical synthetic rider must be restored'
 result={'new_tagged_active_orders_released':len(rows),'unrelated_orders_modified':False,'fr20_synthetic_riders_offline':True,'physical_rider_unblocked':True}
 (OUT/'cleanup.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))

def shared_parent():
 position();row=order('shared-final');vendor=b.login(state['accounts']['vendor']);other=b.login(state['accounts']['other-vendor']);checks=[];child=None
 def check(value,label):assert value,label;checks.append({'check':label,'result':'PASS'})
 try:
  c,first=b.rpc('fr21_ready_and_assign',{'p_vendor_order_id':row['vendor_order_id']},vendor);check(c==200 and first['code']=='ASSIGNED_5KM','initial parent assignment')
  c,rows=b.api('/rest/v1/vendor_orders','POST',{'order_id':row['id'],'vendor_id':state['accounts']['other-vendor']['profile_id'],'status':'accepted','sub_total':25},admin=True);assert c==201;child=rows[0]['id']
  c,result=b.rpc('fr21_ready_and_assign',{'p_vendor_order_id':child},other);check(c==200 and result['code']=='ALREADY_ASSIGNED'and result['assignment_id']==first['assignment_id']and result['rider_id']==first['rider_id'],'second owning vendor reuses same assignment')
  c,rows=b.api('/rest/v1/vendor_orders?order_id=eq.'+str(row['id'])+'&select=status',admin=True);check(c==200 and len(rows)==2 and all(r['status']=='on_the_way'for r in rows),'both vendor child states preserved')
  c,assignments=b.api('/rest/v1/rider_assignments?orderid=eq.'+str(row['id'])+'&select=id',admin=True);c2,notices=b.api('/rest/v1/notifications?assignment_order_id=eq.'+str(row['id'])+'&assignment_event=eq.rider_assigned&select=id',admin=True);check(c==c2==200 and len(assignments)==len(notices)==1,'one assignment and rider notice after second vendor ready')
  c,result=b.rpc('fr21_ready_and_assign',{'p_vendor_order_id':row['vendor_order_id']},other);check(c==200 and result['code']=='FORBIDDEN','shared parent does not authorize another vendor child')
 finally:
  cancel(row)
  if child is not None:b.api('/rest/v1/vendor_orders?id=eq.'+str(child),'PATCH',{'status':'cancelled'},admin=True)
 (OUT/'shared-parent-tests.json').write_text(json.dumps({'passed':len(checks),'checks':checks},indent=2),encoding='utf-8');print(json.dumps({'passed':len(checks),'shared_parent_live_test':True}))

def tests(races_only=False):
 import concurrent.futures,threading,uuid
 setup();checks=[]
 def check(ok,label):
  assert ok,label
  checks.append({'check':label,'result':'PASS'});print(json.dumps(checks[-1]),flush=True)
 tokens={k:b.login(a)for k,a in state['accounts'].items()}
 def assign(row,token=None):return b.rpc('fr21_ready_and_assign',{'p_vendor_order_id':row['vendor_order_id']},token or tokens['vendor'])
 def effects(row,rider=True):
  c,assignments=b.api('/rest/v1/rider_assignments?orderid=eq.'+str(row['id'])+'&select=id,riderid,status',admin=True)
  check(c==200 and len(assignments)==(1 if rider else 0),'assignment count '+str(row['id']))
  c,notices=b.api('/rest/v1/notifications?assignment_order_id=eq.'+str(row['id'])+'&assignment_event=eq.rider_assigned&select=id,message,user_id,rider_assignment_id',admin=True)
  check(c==200 and len(notices)==(1 if rider else 0),'rider notice exactly once '+str(row['id']))
  if rider:check(notices[0]['message']=='New delivery job assigned.'and notices[0]['user_id']==assignments[0]['riderid']and notices[0]['rider_assignment_id']==assignments[0]['id'],'correct rider message/references')
  c,audits=b.api('/rest/v1/security_audit_log?assignment_order_id=eq.'+str(row['id'])+'&action=eq.RIDER_ASSIGNED&select=id,actor_id,target_id',admin=True)
  check(c==200 and len(audits)==(1 if rider else 0),'assignment audit exactly once '+str(row['id']))
 if not races_only:
  row=order('authorization');position()
  for who in ['other-vendor','customer','rider','admin']:
   c,res=assign(row,tokens[who]);check(c==200 and res['code']=='FORBIDDEN',who+' denied vendor assignment')
  c,_=b.rpc('fr21_ready_and_assign',{'p_vendor_order_id':row['vendor_order_id']});check(c in(401,403),'anonymous assignment denied')
  for table,body in [('rider_assignments',{'orderid':row['id'],'riderid':state['accounts']['rider']['profile_id']}),('notifications',{'user_id':state['accounts']['rider']['profile_id'],'title':'forged','message':'forged'}),('security_audit_log',{'action':'forged','target_type':'order','target_id':row['id']})]:
   c,_=b.api('/rest/v1/'+table,'POST',body,tokens['vendor']);check(c in(401,403),'direct '+table+' forgery denied')
  cancel(row)
  for meters,expected in [(4900,'ASSIGNED_5KM'),(5000,'ASSIGNED_5KM'),(5100,'ASSIGNED_10KM'),(7000,'ASSIGNED_10KM'),(10000,'ASSIGNED_10KM'),(10001,'NO_RIDER_AVAILABLE')]:
   position(meters);row=order('meters-'+str(meters));c,res=assign(row);check(c==200 and res['code']==expected,'hosted distance '+str(meters))
   c,replay=assign(row);check(c==200 and replay['code']==('ALREADY_ASSIGNED'if meters<=10000 else expected),'safe retry '+str(meters));effects(row,meters<=10000)
   if meters>10000:
    c,notices=b.api('/rest/v1/notifications?assignment_order_id=eq.'+str(row['id'])+'&assignment_event=eq.manual_assignment&select=user_id',admin=True)
    c2,admins=b.api('/rest/v1/users?role=eq.admin&verification_status=eq.approved&is_blocked=eq.false&select=id',admin=True)
    check(c==c2==200 and sorted(n['user_id']for n in notices)==sorted(a['id']for a in admins),'all and only eligible admins receive one escalation')
    position();c,res=assign(row);check(c==200 and res['code']=='ASSIGNED_5KM','later retry assigns')
    c,orders=b.api('/rest/v1/orders?id=eq.'+str(row['id'])+'&select=requires_manual_assignment',admin=True);check(c==200 and not orders[0]['requires_manual_assignment'],'manual flag resolved')
   cancel(row)
 # Real separate HTTP requests synchronized at a barrier, never a hosted load run.
 for mode in ['same-order','one-rider','two-riders']:
  position(4900,4800 if mode=='two-riders'else 20000);a=order(mode+'-a');other=a if mode=='same-order'else order(mode+'-b');barrier=threading.Barrier(2)
  def compete(target):barrier.wait(timeout=10);return assign(target)
  with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:results=list(pool.map(compete,[a,other]))
  check(all(c==200 for c,_ in results),'concurrent '+mode+' structured outcomes')
  codes=[r['code']for _,r in results]
  if mode=='same-order':check(sorted(codes)==['ALREADY_ASSIGNED','ASSIGNED_5KM'],'same order has one winner/replay');effects(a)
  elif mode=='one-rider':check(codes.count('ASSIGNED_5KM')==1 and all(c in('ASSIGNED_5KM','NO_RIDER_AVAILABLE','RETRYABLE_CONFLICT')for c in codes),'one rider claimed by at most one order')
  else:check(codes.count('ASSIGNED_5KM')==2,'two distinct riders claimed concurrently')
  c,rows=b.api('/rest/v1/rider_assignments?orderid=in.('+','.join(str(x['id'])for x in[a,other])+')&status=in.(Pending,Accepted)&select=riderid,orderid',admin=True)
  check(c==200 and len({r['riderid']for r in rows})==len(rows)and len({r['orderid']for r in rows})==len(rows),'concurrent active rider/order uniqueness '+mode)
  cancel(a)
  if other!=a:cancel(other)
 for mode in ['offline','block']:
  position();row=order('race-'+mode);rider=state['accounts']['rider'];rt=b.login(rider)
  c,presence=b.rpc('fr21_begin_presence',{},rt);check(c==200,'race rider presence session')
  c,_=b.rpc('fr21_set_presence',{'p_online':True,'p_epoch':presence['epoch'],'p_sequence':1},rt);check(c==200,'race rider online')
  barrier=threading.Barrier(2)
  def change():
   barrier.wait(timeout=10)
   if mode=='offline':return b.rpc('fr21_set_presence',{'p_online':False,'p_epoch':presence['epoch'],'p_sequence':2},rt)
   return b.api('/functions/v1/admin-user-status','POST',{'target_id':rider['profile_id'],'blocked':True,'request_id':str(uuid.uuid4())},tokens['admin'])
  def race_assignment():barrier.wait(timeout=10);return assign(row)
  try:
   with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
    change_future=pool.submit(change);assignment_future=pool.submit(race_assignment);changed=change_future.result();assigned=assignment_future.result()
   check(changed[0]==200 and(mode=='offline'or changed[1]['code']=='OK'),'concurrent '+mode+' confirmed')
   check(assigned[0]==200 and assigned[1]['code']in('ASSIGNED_5KM','NO_RIDER_AVAILABLE','RETRYABLE_CONFLICT'),'assignment/'+mode+' safely linearizes')
   c,rows=b.api('/rest/v1/riders?userid=eq.'+str(rider['profile_id'])+'&select=is_online',admin=True);check(c==200 and rows[0]['is_online']is False,'rider ends offline after '+mode)
   if mode=='block':
    c,_=b.rpc('fr21_update_location',{'p_lat':-60,'p_lng':-140},rt);check(c==403,'blocked race old JWT denied location write')
  finally:
   if mode=='block':
    c,res=b.api('/functions/v1/admin-user-status','POST',{'target_id':rider['profile_id'],'blocked':False,'request_id':str(uuid.uuid4())},tokens['admin']);assert c==200 and res['code']in('OK','NO_CHANGE'),'Restore synthetic rider'
   cancel(row)
 result={'passed':len(checks),'checks':checks,'real_concurrent_http':True,'project_ref':b.REF};(OUT/'hosted-tests.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
 print(json.dumps({'passed':len(checks),'real_concurrent_http':True}))

def sql(review=False,patch=False,shared=False):
 import re
 rules=(ROOT/'supabase/tests/FR-20.sql').read_text(encoding='utf-8')
 source=(ROOT/'supabase/migrations'/('202610150003_fr20_shared_parent_ready.sql'if shared else '202610150002_fr20_escalation_receipt.sql'if patch else '202610150001_fr20_radius_assignment.sql')).read_text(encoding='utf-8')if review else ''
 if review:
  source=re.sub(r'^begin;\s*','',source,flags=re.M);source=re.sub(r'^commit;\s*','',source,flags=re.M)
  rules=re.sub(r'^begin;\s*','',rules,flags=re.M);rules='begin;\n'+source+'\n'+rules
 file=OUT/('migration-review.sql'if review else 'rules.sql');file.write_text(rules,encoding='utf-8')
 result=query(file);(OUT/('migration-review.json'if review else 'sql-tests.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
 print(json.dumps({'passed':len(result['rows'][0]['results']),'rolled_back':True,'migration_applied':False}))

def inspect():
 b.target();file=OUT/'inspect.sql'
 file.write_text("""select jsonb_build_object(
 'versions',(select jsonb_agg(version order by version)from supabase_migrations.schema_migrations),
 'extensions',(select jsonb_agg(jsonb_build_object('name',e.extname,'schema',n.nspname))from pg_extension e join pg_namespace n on n.oid=e.extnamespace),
 'spatial_available',(select jsonb_agg(name)from pg_available_extensions where name in('postgis','cube','earthdistance')),
 'columns',(select jsonb_agg(jsonb_build_object('table',table_name,'column',column_name,'type',data_type))from information_schema.columns where table_schema='public'and table_name in('orders','vendor_orders','riders','vendors','rider_assignments','notifications','security_audit_log','gps_locations')),
 'indexes',(select jsonb_agg(jsonb_build_object('table',tablename,'definition',indexdef))from pg_indexes where schemaname='public'and tablename in('riders','rider_assignments','orders','notifications')),
 'triggers',(select jsonb_agg(jsonb_build_object('table',c.relname,'name',t.tgname,'definition',pg_get_triggerdef(t.oid),'function',pg_get_functiondef(t.tgfoid)))from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'and not t.tgisinternal and c.relname in('orders','vendor_orders','riders','rider_assignments')),
 'functions',(select jsonb_agg(jsonb_build_object('name',p.proname,'definition',pg_get_functiondef(p.oid)))from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and p.proname in('fr21_ready_and_assign','fr21_accept_order','fr21_update_location','fr21_set_presence','fr21_approved_rider','fr26_is_admin','fr28_begin','fr28_revoke_sessions')),
 'active_duplicates',(select count(*)from(select riderid from public.rider_assignments where status in('Pending','Accepted')group by riderid having count(*)>1)s),
 'order_duplicates',(select count(*)from(select orderid from public.rider_assignments where status in('Pending','Accepted')group by orderid having count(*)>1)s)
 )as inspection;""",encoding='utf-8')
 result=query(file)['rows'][0]['inspection'];(OUT/'inspection.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
 print(json.dumps({k:result[k]for k in('versions','extensions','spatial_available','active_duplicates','order_duplicates')}))

if __name__=='__main__':
 try:{'inspect':inspect,'review':lambda:sql(True),'receipt-review':lambda:sql(True,True),'receipt-deploy':lambda:deploy(True),'shared-review':lambda:sql(True,False,True),'shared-deploy':lambda:deploy(False,True),'shared-test':shared_parent,'sql':sql,'deploy':deploy,'tests':tests,'races':lambda:tests(True),'artifact':artifact,'device':device,'verify':verify,'security-scan':security_scan,'cleanup':cleanup}[sys.argv[1]]()
 except Exception as e:print(json.dumps({'failed':1,'type':type(e).__name__,'frames':[(Path(f.filename).name,f.lineno)for f in __import__('traceback').extract_tb(e.__traceback__)][-4:],'reason':str(e)if isinstance(e,AssertionError)else 'Guarded FR20 TEST check failed'}));sys.exit(1)
