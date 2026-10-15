"""Dedicated TEST FR28 checks; credentials remain in the existing protected runner."""
import importlib.util,json,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr33',Path(__file__).with_name('FR-33-hosted.py'));previous=importlib.util.module_from_spec(spec);spec.loader.exec_module(previous)
b=previous.b;ROOT=previous.ROOT;OUT=ROOT/'.fr21-local/fr28';OUT.mkdir(exist_ok=True,parents=True)
def inspect():
 file=OUT/'inspect.sql';file.write_text("""select jsonb_build_object(
 'versions',(select jsonb_agg(version order by version)from supabase_migrations.schema_migrations),
 'user_columns',(select jsonb_agg(jsonb_build_object('name',column_name,'type',udt_name,'nullable',is_nullable))from information_schema.columns where table_schema='public' and table_name='users'),
 'tables',(select jsonb_agg(jsonb_build_object('table',c.relname,'rls',c.relrowsecurity))from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'),
 'policies',(select jsonb_agg(to_jsonb(p))from pg_policies p where schemaname in ('public','storage')),
 'functions',(select jsonb_agg(jsonb_build_object('name',p.proname,'definition',pg_get_functiondef(p.oid),'client',has_function_privilege('authenticated',p.oid,'EXECUTE')))from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','fr04_private','fr25_private')and p.prosecdef),
 'auth_columns',(select jsonb_agg(jsonb_build_object('table',table_name,'column',column_name,'type',udt_name))from information_schema.columns where table_schema='auth' and table_name in ('sessions','refresh_tokens')),
 'pre_request',(select jsonb_agg(setconfig)from pg_db_role_setting where setrole=(select oid from pg_roles where rolname='authenticator')),
 'extensions',(select jsonb_agg(extname)from pg_extension),
 'bindings',(select jsonb_build_object('users',count(*),'matching_auth',count(a.id),'case_conflicts',count(*)filter(where u.email<>a.email))from public.users u left join auth.users a on lower(a.email)=lower(u.email))
 )as inspection;""")
 data=previous.query(file)['rows'][0]['inspection'];(OUT/'schema-inspection.json').write_text(json.dumps(data,indent=2));print(json.dumps({'migration_count':len(data['versions']),'existing_block_columns':[c for c in data['user_columns']if any(x in c['name']for x in ('block','status','auth'))],'tables':len(data['tables']),'policies':len(data['policies']),'definer_functions':len(data['functions']),'pre_request':data['pre_request'],'bindings':data['bindings'],'extensions':data['extensions']}))
def review():
 import re
 source=(ROOT/'supabase/migrations/202610140003_fr28_account_blocking.sql').read_text();source=re.sub(r'^begin;\s*','',source,flags=re.M);source=re.sub(r'^commit;\s*','',source,flags=re.M)
 file=OUT/'review.sql';file.write_text('begin;\n'+source+"\nselect jsonb_build_object('users',(select count(*)from public.users),'bindings',(select count(*)from public.users where auth_user_id is not null),'operations',(select count(*)from public.fr28_operations),'policies',(select count(*)from pg_policies where policyname like 'fr28_%'))as reviewed;\nrollback;")
 rules=(ROOT/'supabase/tests/FR-28.sql').read_text();rules=re.sub(r'^begin;\s*','',rules,flags=re.M);rules=re.sub(r'^rollback;\s*','',rules,flags=re.M);file.write_text('begin;\n'+source+'\n'+rules+'\nrollback;')
 data=previous.query(file);(OUT/'migration-review.json').write_text(json.dumps(data,indent=2));print(json.dumps({'reviewed':data['rows'],'rolled_back':True,'auth_api_called':False,'session_revocations':'synthetic SQL fixtures only, all rolled back'}))
def deploy():
 import subprocess,re
 b.target()
 exe='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
 expected='202610140003_fr28_account_blocking.sql'
 history=OUT/'history.sql';history.write_text('select version from supabase_migrations.schema_migrations order by version;')
 existing=[r['version']for r in previous.query(history)['rows']]
 files=sorted(p.name.split('_')[0]for p in (ROOT/'supabase/migrations').glob('*.sql'))
 assert existing==[v for v in files if v!=expected.split('_')[0]],'Accepted migration history mismatch or FR28 already applied'
 def command(args):
  b.target();r=subprocess.run([exe,*args],cwd=ROOT,capture_output=True,text=True,timeout=180)
  assert r.returncode==0,'Guarded TEST deployment command failed'
  return r.stdout+r.stderr
 plan=command(['db','push','--linked','--dry-run'])
 assert sorted(set(re.findall(r'2026\d{8}_[a-z0-9_]+\.sql',plan)))==[expected],'Unexpected migration plan'
 command(['db','push','--linked'])
 assert [r['version']for r in previous.query(history)['rows']]==files,'Post-application migration history mismatch'
 for name in ['admin-user-status','fr04-cnic','fr25-evidence','send-delivery-otp']:
  command(['functions','deploy',name,'--project-ref',b.REF,'--no-verify-jwt'])
 result={'project_ref':b.REF,'new_migrations':[expected],'edge_functions':['admin-user-status','fr04-cnic','fr25-evidence','send-delivery-otp'],'production_touched':False,'reset':False,'prior_migrations_replayed':False}
 (OUT/'deployment.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))

def tests():
 import uuid,secrets,concurrent.futures,datetime
 store=b.PRIVATE/'fr28-accounts.bin'
 state=json.loads(b.crypt(store.read_bytes(),True))if store.exists()else {'accounts':{},'orders':{}}
 def save():store.write_bytes(b.crypt(json.dumps(state).encode()))
 checks=[]
 def check(ok,label):
  assert ok,label
  checks.append({'check':label,'result':'PASS'});print(json.dumps(checks[-1]),flush=True)
 def fixture(label,role):
  a=state['accounts'].setdefault(label,{'email':'fr28-'+label+'@example.test','password':secrets.token_urlsafe(28)+'aA7!'});save()
  if 'auth_id'not in a:
   code,row=b.api('/auth/v1/admin/users','POST',{'email':a['email'],'password':a['password'],'email_confirm':True,'user_metadata':{'fr28_fixture':True}},admin=True)
   assert code in(200,201),'Synthetic Auth fixture creation';a['auth_id']=row['id'];save()
  if 'profile_id'not in a:
   code,rows=b.api('/rest/v1/users','POST',{'email':a['email'],'name':'FR28 synthetic '+label,'role':role,'verification_status':'approved'},admin=True)
   assert code==201,'Synthetic profile fixture creation: HTTP '+str(code)+' code '+str(rows.get('code')if isinstance(rows,dict)else None)+' '+__import__('re').sub(r'\S+@\S+','[redacted]',str(rows.get('message',''))if isinstance(rows,dict)else '')[:140];a['profile_id']=rows[0]['id'];save()
  return a,b.login(a)
 def change(token,a,blocked,request=None):return b.api('/functions/v1/admin-user-status','POST',{'target_id':a['profile_id'],'blocked':blocked,'request_id':request or str(uuid.uuid4())},token=token)
 def profile(a):
  code,rows=b.api('/rest/v1/users?id=eq.'+str(a['profile_id'])+'&select=id,is_blocked&limit=1',admin=True);assert code==200 and len(rows)==1;return rows[0]
 admin,at=fixture('admin','admin');admin2,at2=fixture('admin2','admin')
 customer,ct=fixture('customer','customer');vendor,vt=fixture('vendor','vendor');rider,rt=fixture('rider','rider')
 code,rows=b.api('/rest/v1/riders?userid=eq.'+str(rider['profile_id'])+'&select=id&limit=1',admin=True);assert code==200
 if not rows:assert b.api('/rest/v1/riders','POST',{'userid':rider['profile_id'],'is_online':False},admin=True)[0]==201
 if 'active'not in state['orders']:
  code,rows=b.api('/rest/v1/orders','POST',{'user_id':customer['profile_id'],'vendor_id':vendor['profile_id'],'rider_id':rider['profile_id'],'order_status':'on_the_way','amount':25,'payment_method':'COD','delivery_address':'FR28 SYNTHETIC TEST ONLY'},admin=True);assert code==201;state['orders']['active']=rows[0]['id'];save()
 if 'product'not in state:
  code,rows=b.api('/rest/v1/products','POST',{'vendor_id':vendor['profile_id'],'name':'FR28 SYNTHETIC PRODUCT','price':25,'is_available':True},admin=True);assert code==201;state['product']=rows[0]['id'];save()
 check(change('invalid',customer,True)[0]==401,'invalid JWT denied')
 check(change(ct,rider,True)[0]==403,'non-admin denied')
 check(change(at,admin,True)[1]['code']=='SELF_FORBIDDEN','self block denied')
 check(change(at,admin2,True)[1]['code']=='ADMIN_PROTECTED','other-admin block denied')
 check(change(at,{'profile_id':999999999},True)[0]==404,'unknown target denied')
 code,page=b.rpc('fr28_user_list',{'p_search':'FR28 synthetic','p_limit':2},at)
 check(code==200 and len(page)==2 and page[0]['id']>page[1]['id'],'bounded newest-first pagination')
 code,nextpage=b.rpc('fr28_user_list',{'p_search':'FR28 synthetic','p_limit':2,'p_before_at':page[-1]['created_at'],'p_before_id':page[-1]['id']},at)
 check(code==200 and len(nextpage)==2 and not({u['id']for u in page}&{u['id']for u in nextpage}),'cursor next page disjoint')
 check(b.rpc('fr28_user_list',{},ct)[0]==403,'ordinary directory denied')
 check(b.api('/rest/v1/users?id=eq.'+str(customer['profile_id']),'PATCH',{'role':'admin'},token=ct)[0]==403,'client role escalation denied')
 check(b.api('/rest/v1/users?id=eq.'+str(customer['profile_id']),'PATCH',{'is_blocked':True},token=ct)[0]==403,'client blocked-state update denied')
 for label,a,token in [('customer',customer,ct),('vendor',vendor,vt),('rider',rider,rt)]:
  request=str(uuid.uuid4());code,result=change(at,a,True,request)
  check(code==200 and result['code']=='OK'and profile(a)['is_blocked'],label+' real Auth ban/session sync confirmed')
  check(state['orders']['active']in result['active_orders']['order_ids'],label+' active order warning surfaced')
  for path,method,body in [('/rest/v1/orders?select=id&limit=1','GET',None),('/rest/v1/orders','POST',{'user_id':a['profile_id'],'amount':25}),('/rest/v1/rpc/fr26_options','POST',{})]:
   c,r=b.api(path,method,body,token=token);check(c==403 and r['message']=='FR28_ACCOUNT_BLOCKED',label+' existing JWT '+method+' protected API explicit 403')
  check(b.rpc('fr28_account_status',{},token)[1]['code']=='FR28_ACCOUNT_BLOCKED',label+' narrow own blocked status')
  check(b.api('/auth/v1/token?grant_type=password','POST',{'email':a['email'],'password':a['password']})[1].get('error_code')=='user_banned',label+' banned login rejected')
  check(change(at,a,True,request)[1]['code']=='ALREADY_APPLIED',label+' completed UUID idempotent')
  check(change(at,a,True)[1]['code']=='NO_CHANGE',label+' new same-action no-op')
  if label=='vendor':check(b.api('/rest/v1/products?id=eq.'+str(state['product'])+'&select=id',token=at2)[1]==[{'id':state['product']}],'admin retains product review')
  if label=='vendor':check(b.api('/rest/v1/products?id=eq.'+str(state['product'])+'&select=id',token=b.login(customer))[1]==[], 'blocked vendor products hidden')
  if label=='rider':check(b.rpc('fr21_set_presence',{'p_online':True,'p_epoch':1,'p_sequence':1},token)[0]==403,'blocked rider cannot go online')
  if label=='vendor':
   c,r=b.api('/rest/v1/vendor_orders?order_id=eq.'+str(state['orders']['active'])+'&vendor_id=eq.'+str(a['profile_id']),'PATCH',{'status':'accepted'},token=token)
   check(c==403 and r['message']=='FR28_ACCOUNT_BLOCKED','blocked vendor new-order acceptance explicit 403')
  if label=='rider':
   for endpoint,body in [('fr21_accept_order',{'p_order_id':state['orders']['active']}),('verify_delivery_otp',{'p_order_id':state['orders']['active'],'p_otp':'000000','p_request_id':str(uuid.uuid4())})]:
    c,r=b.rpc(endpoint,body,token);check(c==403 and r['message']=='FR28_ACCOUNT_BLOCKED','blocked rider '+endpoint+' explicit 403')
   for edge in ['fr04-cnic','send-delivery-otp']:
    c,r=b.api('/functions/v1/'+edge,'POST',{},token=token);check(c==403 and r['code']=='FR28_ACCOUNT_BLOCKED','blocked rider Edge '+edge+' explicit 403')
   c,r=b.api('/storage/v1/object/list/rider-cnic','POST',{'prefix':a['auth_id'],'limit':1},token=token)
   check((c==200 and r==[])or c in(400,401,403),'direct Storage list denies protected data')
   (OUT/'storage-status.json').write_text(json.dumps({'endpoint':'POST /storage/v1/object/list/rider-cnic','http_status':c,'protected_data_returned':False,'explicit_403':c==403,'mobile_path':'fr04-cnic explicitly returns 403','signed_url_caveat':'Existing capability URLs remain usable to TTL'},indent=2))
  if label=='customer':
   c,r=b.api('/functions/v1/fr25-evidence','POST',{},token=token);check(c==403 and r['code']=='FR28_ACCOUNT_BLOCKED','blocked customer evidence Edge explicit 403')
  code,result=change(at,a,False);check(code==200 and result['code']=='OK'and not profile(a)['is_blocked'],label+' Auth unban synchronization confirmed')
  check(b.api('/rest/v1/orders?select=id&limit=1',token=token)[0]==401,label+' old JWT stays revoked after unblock')
  fresh=b.login(a);check(b.api('/rest/v1/orders?select=id&limit=1',token=fresh)[0]==200,label+' fresh login protected access restored')
  code,audits=b.api('/rest/v1/security_audit_log?user_operation_id=eq.'+request+'&select=action,actor_id&limit=2',admin=True)
  check(code==200 and audits==[{'action':'BLOCK_USER','actor_id':admin['profile_id']}],label+' block audit exactly once authenticated actor')
 ct=b.login(customer)
 code,products=b.api('/rest/v1/products?id=eq.'+str(state['product'])+'&select=id',token=ct);check(code==200 and len(products)==1,'unblock vendor product visibility restored')
 request=str(uuid.uuid4())
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:results=list(pool.map(lambda _:change(at,customer,True,request),range(2)))
 check(all(c in(200,202)and r['code']in('OK','ALREADY_APPLIED','AUTH_SYNC_PENDING')for c,r in results),'genuine concurrent same UUID requests consistent')
 check(change(at,customer,True,request)[1]['code']=='ALREADY_APPLIED','concurrent same request reconciled')
 code,audits=b.api('/rest/v1/security_audit_log?user_operation_id=eq.'+request+'&select=id&limit=3',admin=True);check(code==200 and len(audits)==1,'concurrent duplicate audit once')
 check(change(at,customer,False)[1]['code']=='OK','race fixture restored')
 requests=[str(uuid.uuid4()),str(uuid.uuid4())]
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:results=list(pool.map(lambda request:change(at,customer,True,request),requests))
 check(all(c in(200,202,409)and r['code']in('OK','NO_CHANGE','AUTH_SYNC_PENDING','BUSY')for c,r in results),'genuine concurrent same action with distinct UUIDs consistent')
 code,rows=b.rpc('fr28_user_list',{'p_search':customer['email']},at);assert code==200 and len(rows)==1
 if rows[0]['operation_id']:assert change(at,customer,True,rows[0]['operation_id'])[1]['code']in('OK','ALREADY_APPLIED')
 check(profile(customer)['is_blocked'],'same-action race settles blocked')
 code,audits=b.api('/rest/v1/security_audit_log?user_operation_id=in.('+','.join(requests)+')&select=id&limit=3',admin=True)
 check(code==200 and len(audits)==1,'different-UUID same-action race audit exactly once')
 assert change(at,customer,False)[1]['code']=='OK'
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:results=list(pool.map(lambda blocked:change(at if blocked else at2,customer,blocked),[True,False]))
 check(all(c in(200,202,409)for c,r in results),'genuine opposite requests serialized or pending conflict')
 code,rows=b.rpc('fr28_user_list',{'p_search':customer['email']},at);assert code==200 and len(rows)==1
 if rows[0]['operation_id']:assert change(at,customer,rows[0]['desired_blocked'],rows[0]['operation_id'])[1]['code']in('OK','ALREADY_APPLIED')
 if profile(customer)['is_blocked']:assert change(at,customer,False)[1]['code']=='OK'
 check(not profile(customer)['is_blocked'],'conflicting race converged to confirmed restored account')
 request=str(uuid.uuid4());code,result=b.rpc('admin_set_user_blocked',{'p_actor':admin['auth_id'],'p_target':customer['profile_id'],'p_blocked':True,'p_request':request},admin=True)
 check(code==200 and result['code']=='PENDING','simulated worker interruption commits denial before Auth')
 check(b.rpc('fr28_account_status',{},b.login(customer))[1]['code']=='FR28_ACCOUNT_BLOCKED','pending worker cannot restore protected access')
 check(change(at,customer,True,request)[1]['code']=='OK','same UUID reconciles interrupted worker')
 assert change(at,customer,False)[1]['code']=='OK'
 code,orders=b.api('/rest/v1/orders?id=eq.'+str(state['orders']['active'])+'&select=order_status,rider_id,vendor_id,user_id',admin=True)
 check(code==200 and orders==[{'order_status':'on_the_way','rider_id':rider['profile_id'],'vendor_id':vendor['profile_id'],'user_id':customer['profile_id']}],'all active order state and assignments unchanged')
 code,rows=b.api('/rest/v1/riders?userid=eq.'+str(rider['profile_id'])+'&select=is_online&limit=1',admin=True);check(code==200 and rows[0]['is_online']==False,'unblocked rider remains offline')
 (OUT/'hosted-tests.json').write_text(json.dumps({'passed':len(checks),'checks':checks,'project_ref':b.REF,'real_auth_api':True,'synthetic_only':True},indent=2));print(json.dumps({'passed':len(checks)}))

def grants():
 file=OUT/'grants.sql';file.write_text("select r.rolname,has_table_privilege(r.rolname,'public.users','SELECT')as sel,has_table_privilege(r.rolname,'public.users','INSERT')as ins,has_table_privilege(r.rolname,'public.users','UPDATE')as upd,has_table_privilege(r.rolname,'public.fr28_operations','SELECT')as ops from pg_roles r where rolname in('anon','authenticated','service_role');")
 print(json.dumps(previous.query(file)['rows']))

def repair(expected='202610140004_fr28_identity_trigger_context.sql'):
 import subprocess
 history=OUT/'history.sql';history.write_text('select version from supabase_migrations.schema_migrations order by version;')
 files=sorted(p.name.split('_')[0]for p in (ROOT/'supabase/migrations').glob('*.sql'))
 assert [r['version']for r in previous.query(history)['rows']]==[v for v in files if v!=expected.split('_')[0]],'Repair history mismatch'
 source=(ROOT/'supabase/migrations'/expected).read_text()
 if expected=='202610140007_fr28_canonical_service_identity.sql':
  rules=(ROOT/'supabase/tests/FR-28.sql').read_text()
  rules=__import__('re').sub(r'^begin;\s*|^rollback;\s*','',rules,flags=__import__('re').M)
  source=source.replace('commit;',rules+'\nrollback;')
 else:source=source.replace('commit;','rollback;')
 file=OUT/'repair-review.sql';file.write_text(source)
 previous.query(file)
 b.target();r=subprocess.run(['C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe','db','push','--linked'],capture_output=True,text=True,timeout=120)
 assert r.returncode==0,'TEST additive trigger repair failed'
 assert [r['version']for r in previous.query(history)['rows']]==files,'Repair history verification mismatch'
 print(json.dumps({'applied':expected,'production_touched':False}))

def device():
 exec(compile((ROOT/'tests/integration/FR-28-device.py').read_text(),str(ROOT/'tests/integration/FR-28-device.py'),'exec'),{'backend':sys.modules[__name__]})

def sql():
 result=previous.query(ROOT/'supabase/tests/FR-28.sql');(OUT/'sql-tests.json').write_text(json.dumps(result,indent=2));print(json.dumps({'passed':len(result['rows'][0]['results']),'rolled_back':True}))

def performance():
 file=OUT/'explain.sql';file.write_text("""begin;
 select set_config('request.jwt.claims',(select jsonb_build_object('role','authenticated','sub',u.auth_user_id,'session_id',s.id)::text from public.users u join auth.sessions s on s.user_id=u.auth_user_id where u.email='fr28-admin@example.test' order by s.created_at desc limit 1),true);
 set local role authenticated;
 explain (analyze,buffers,format json) select id from public.orders order by id desc limit 25;
 rollback;""")
 result=previous.query(file);(OUT/'explain.json').write_text(json.dumps(result,indent=2))
 print(json.dumps({'explain_executed':True,'read_only_transaction':True,'rows_bound':25,'evidence':'explain.json'}))

def artifact():
 import hashlib,zipfile,subprocess,shutil
 mirror=Path('C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-auth-debug/android-build-20261012-125502')
 sources=list((ROOT/'lib').rglob('*.dart'))
 assert all((mirror/p.relative_to(ROOT)).read_bytes()==p.read_bytes()for p in sources),'Android source mirror mismatch'
 apk=OUT/'TezRider-FR28-Test-debug.apk';shutil.copyfile(mirror/'build/app/outputs/flutter-apk/app-fr21test-debug.apk',apk)
 protected=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))
 with zipfile.ZipFile(apk)as z:payload=b''.join(z.read(n)for n in z.namelist()if not n.endswith('/'))
 assert b.BASE.encode()in payload and b'https://arrqsvejrfdbacfwtpcc.supabase.co'not in payload,'TEST-only compiled backend required'
 assert all(x.encode()not in payload for x in[b.SERVICE]+[a['password']for a in protected['accounts'].values()]),'Privileged data in Android artifact'
 r=subprocess.run(['C:/Users/urreh/AppData/Local/Android/Sdk/build-tools/36.0.0/aapt.exe','dump','badging',str(apk)],capture_output=True,text=True,timeout=30)
 assert r.returncode==0 and "package: name='com.example.flutter_application_1.fr21test'"in r.stdout,'TEST package required'
 result={'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'bytes':apk.stat().st_size,'source_files_matched':len(sources),'test_only':True,'credentials_absent':True}
 (OUT/'artifact.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))

def physical_fixtures():
 file=b.PRIVATE/'fr28-accounts.bin';state=json.loads(b.crypt(file.read_bytes(),True));found={}
 for source in ['accounts.bin','fr04-accounts.bin','fr33-accounts.bin']:
  original=json.loads(b.crypt((b.PRIVATE/source).read_bytes(),True))
  for label,a in original.get('accounts',{}).items():
   if 'auth_id'not in a or 'profile_id'not in a:continue
   c,rows=b.api('/rest/v1/users?id=eq.'+str(a['profile_id'])+'&select=role,verification_status,is_blocked,cnic_submission_status&limit=1',admin=True)
   if c!=200 or len(rows)!=1:continue
   u=rows[0];role=u['role']
   if role not in('vendor','rider')or u['is_blocked']or u['verification_status']!='approved'or role in found:continue
   if role=='rider':
    c,status=b.rpc('fr04_application_status',{},b.login(a))
    if c!=200 or status.get('document_valid')is not True:continue
   found[role]={k:a[k]for k in('email','password','auth_id','profile_id')}
 if 'rider'in found:state['accounts']['physical-rider']=found['rider']
 if 'vendor'in found:state['accounts']['physical-vendor']=found['vendor']
 file.write_bytes(b.crypt(json.dumps(state).encode()));print(json.dumps({'prepared_roles':list(found),'synthetic_sources_only':True}))

def verify():
 file=OUT/'final-verify.sql';file.write_text("""select jsonb_build_object(
 'versions',(select jsonb_agg(version order by version)from supabase_migrations.schema_migrations),
 'pending_operations',(select count(*)from public.fr28_operations where state<>'SYNCED'),
 'duplicate_audits',(select count(*)from(select user_operation_id,action from public.security_audit_log where user_operation_id is not null group by user_operation_id,action having count(*)>1)s),
 'incomplete_audits',(select count(*)from public.security_audit_log where user_operation_id is not null and(actor_id is null or action is null or target_type is null or target_id is null or created_at is null)),
 'blocked_synthetic_accounts',(select count(*)from public.users where is_blocked and(name like 'FR28 %'or name like 'FR21 %'or name like 'FR04 %'or name like 'FR33 %')),
 'role_update_grant',has_column_privilege('authenticated','public.users','role','UPDATE'),
 'block_update_grant',has_column_privilege('authenticated','public.users','is_blocked','UPDATE'),
 'worker_client_execute',has_function_privilege('authenticated','public.fr28_finish(uuid,text)','EXECUTE'),
 'missing_guard_rls',(select count(*)from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'and c.relkind='r'and c.relrowsecurity and c.relname not in('users','fr28_operations')and not exists(select 1 from pg_policies p where p.schemaname='public'and p.tablename=c.relname and p.policyname='fr28_session_guard')),
 'auth_bindings',(select count(*)from public.users where auth_user_id is null)
 )as verification;""")
 result=previous.query(file)['rows'][0]['verification']
 assert result['versions']==sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql')),'Final migration history mismatch'
 assert all(result[k]==0 for k in['pending_operations','duplicate_audits','incomplete_audits','blocked_synthetic_accounts','missing_guard_rls','auth_bindings']),'Final reconciliation/security verification failed'
 assert not any(result[k]for k in['role_update_grant','block_update_grant','worker_client_execute']),'Unauthorized privilege grant'
 (OUT/'final-verification.json').write_text(json.dumps(result,indent=2));print(json.dumps({'verification':'PASS','migration_versions':len(result['versions']),'pending_operations':0,'duplicate_audits':0,'all_synthetic_accounts_restored':True}))

def security_scan():
 import subprocess
 names=set()
 for args in [['git','diff','--name-only','-z'],['git','diff','--cached','--name-only','-z'],['git','ls-files','--others','--exclude-standard','-z']]:
  names.update(subprocess.check_output(args,cwd=ROOT).decode().split('\0'))
 names.discard('')
 secrets=[b.SERVICE]
 for filename in ['accounts.bin','fr04-accounts.bin','fr25-accounts.bin','fr26-accounts.bin','fr28-accounts.bin','fr33-accounts.bin']:
  data=json.loads(b.crypt((b.PRIVATE/filename).read_bytes(),True))
  secrets.extend(a['password']for a in data.get('accounts',{}).values()if a.get('password'))
 env=ROOT/'supabase/functions/.env.test.local'
 if env.exists():
  for line in env.read_text().splitlines():
   key,sep,value=line.partition('=')
   if sep and key.strip()=='BREVO_API_KEY':secrets.append(value.strip().strip('"\''))
 for name in names:
  if name=='.gitignore':continue
  path=ROOT/name
  if not path.is_file():continue
  assert not(name.startswith(('build/','.fr21-local/'))or path.suffix in('.apk','.aab','.dpapi','.bin')or path.name.startswith('.env')),'Unexpected private/build candidate'
  payload=path.read_bytes()
  assert not any(secret.encode()in payload for secret in secrets if secret),'Protected credential found in changed files'
 result={'files_scanned':len(names),'credential_matches':0,'build_private_files':0,'gitignore_excluded_from_commit':True}
 (OUT/'security-scan.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))

if __name__=='__main__':
 try:{'inspect':inspect,'review':review,'deploy':deploy,'tests':tests,'grants':grants,'repair':repair,'policy-repair':lambda:repair('202610140005_fr28_order_policy_cycle.sql'),'bounds':lambda:repair('202610140006_fr28_active_order_bounds.sql'),'identity':lambda:repair('202610140007_fr28_canonical_service_identity.sql'),'device':device,'sql':sql,'performance':performance,'artifact':artifact,'physical-fixtures':physical_fixtures,'verify':verify,'security-scan':security_scan}[sys.argv[1]]()
 except Exception as e:print(json.dumps({'failed':1,'error_type':type(e).__name__,'reason':str(e)if isinstance(e,AssertionError)else 'Guarded FR28 TEST check failed'}));sys.exit(1)
