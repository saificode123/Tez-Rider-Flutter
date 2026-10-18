"""Bounded isolated TEST checklist checks. Never production or hosted load."""
import contextlib,importlib.util,io,json,os,re,runpy,secrets,sys,uuid
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr32',Path(__file__).with_name('FR-32-hosted.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
b=h.b;ROOT=h.ROOT;OUT=ROOT/'.fr21-local/checklist';OUT.mkdir(parents=True,exist_ok=True)
MIGRATION='202610170001_pre_delivery_checklist.sql'
STATE=b.PRIVATE/'checklist-accounts.bin'
state=json.loads(b.crypt(STATE.read_bytes(),True))if STATE.exists()else{'accounts':{}}
def save():STATE.write_bytes(b.crypt(json.dumps(state).encode()))
def check(ok,label):
 assert ok,label
 with(OUT/'checks.jsonl').open('a')as f:f.write(json.dumps({'result':'PASS','check':label})+'\n')
 print(json.dumps({'result':'PASS','check':label}),flush=True)
def deploy():
 expected=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
 versions=[r['version']for r in h.query('select version from supabase_migrations.schema_migrations order by version;')]
 assert versions==[v for v in expected if v!='202610170001'],'Unexpected history; never replay/reset'
 jobs=h.query('select jobid,jobname,schedule,active,md5(command)as command_hash from cron.job order by jobid;')
 preview=h.command(['db','push','--linked','--dry-run'])
 assert sorted(set(re.findall(r'2026\d{8}_[a-z0-9_]+\.sql',preview)))==[MIGRATION],'Unexpected migration plan'
 h.command(['db','push','--linked'])
 assert[r['version']for r in h.query('select version from supabase_migrations.schema_migrations order by version;')]==expected
 after=h.query('select jobid,jobname,schedule,active,md5(command)as command_hash from cron.job order by jobid;')
 assert after==jobs,'Accepted scheduler configuration changed'
 result={'target':h.REF,'applied':[MIGRATION],'migration_versions':len(expected),'accepted_jobs_unchanged':True,'production_modified':False}
 (OUT/'deployment.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
def verify():
 rows=h.query("select jsonb_build_object('response_rls',(select relrowsecurity from pg_class where oid='public.pre_delivery_checklists'::regclass),'ordinary_insert',has_table_privilege('authenticated','public.pre_delivery_checklists','insert'),'anonymous_submit',has_function_privilege('anon','public.submit_pre_delivery_checklist(bigint,integer,jsonb)','execute'),'private_schema',has_schema_privilege('authenticated','checklist_private','usage'),'legacy_orders',(select count(*)from checklist_private.legacy_transit),'legacy_fake_completions',(select count(*)from checklist_private.legacy_transit l join public.rider_assignments a on a.id=l.assignment_id where a.checklist_completed),'otp_gate',position('CHECKLIST_REQUIRED'in pg_get_functiondef('public.verify_delivery_otp(bigint,text,uuid)'::regprocedure))>0)as result;")
 result=rows[0]['result'];check(result['response_rls']and not any(result[k]for k in('ordinary_insert','anonymous_submit','private_schema','legacy_fake_completions'))and result['otp_gate'],'hosted evidence RLS/grants/private legacy and OTP gate')
 (OUT/'verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
def sql():
 rows=h.query((ROOT/'supabase/tests/CHECKLIST.sql').read_text())
 result=next(iter(rows[0].values()));assert isinstance(result,list)
 (OUT/'hosted-sql.json').write_text(json.dumps(result,indent=2));print(json.dumps({'hosted_rollback_assertions':len(result)}))
def fixture(label,role):
 a=state['accounts'].setdefault(label,{'email':'checklist-'+label+'@example.test','password':secrets.token_urlsafe(28)+'aA7!'})
 save()
 if'auth_id'not in a:
  status,user=b.api('/auth/v1/admin/users','POST',{'email':a['email'],'password':a['password'],'email_confirm':True,'user_metadata':{'checklist_fixture':True,'role':role}},admin=True)
  assert status in(200,201),'Synthetic Auth creation not confirmed';a['auth_id']=user['id'];save()
 if'profile_id'not in a:
  status,rows=b.api('/rest/v1/users','POST',{'email':a['email'],'name':'CHECKLIST SYNTHETIC '+label,'role':role,'verification_status':'approved'},admin=True)
  assert status==201,'Synthetic profile creation not confirmed';a['profile_id']=rows[0]['id'];save()
 return a
def fixtures():
 for label,role in [('rider','rider'),('other-rider','rider'),('vendor','vendor')]:fixture(label,role)
 for label in('rider','other-rider'):
  uid=state['accounts'][label]['profile_id'];status,rows=b.api(f'/rest/v1/riders?userid=eq.{uid}&select=id',admin=True)
  assert status==200
  if not rows:
   status,_=b.api('/rest/v1/riders','POST',{'userid':uid},admin=True);assert status==201
 vendor=state['accounts']['vendor'];status,rows=b.api('/rest/v1/vendors?user_id=eq.'+str(vendor['profile_id'])+'&select=id',admin=True);assert status==200
 if not rows:
  status,_=b.api('/rest/v1/vendors','POST',{'user_id':vendor['profile_id'],'store_name':'CHECKLIST SYNTHETIC PICKUP','latitude':33.7,'longitude':73.05},admin=True);assert status==201
 if'product_id'not in state:
  status,result=b.rpc('fr17_save_product',{'p_request_id':str(uuid.uuid4()),'p_product_id':None,'p_data':{'name':'CHECKLIST SYNTHETIC PICKUP','price':80,'is_available':True},'p_stock':20,'p_threshold':5,'p_expected_version':None},b.login(vendor))
  assert status==200 and result['code']=='UPDATED';state['product_id']=result['product_id'];save()
 if'physical_order_id'not in state:
  rider=state['accounts']['rider'];token=b.login(rider)
  status,result=b.rpc('fr21_begin_presence',{},token);assert status==200
  status,_=b.rpc('fr21_update_location',{'p_lat':33.7,'p_lng':73.05},token);assert status in(200,204)
  status,_=b.rpc('fr21_set_presence',{'p_online':True,'p_epoch':result['epoch'],'p_sequence':1},token);assert status==200
  customer=h.f.state['accounts']['customer']
  status,result=b.rpc('fr10_checkout',{'p_request_id':str(uuid.uuid4()),'p_items':[{'product_id':state['product_id'],'quantity':1}],'p_delivery':{'address':'CHECKLIST SYNTHETIC TEST ONLY','lat':33.701,'lng':73.051,'speed':'standard'}},b.login(customer))
  assert status==200 and result['code']=='PLACED';state['physical_order_id']=result['order_id'];save()
  status,rows=b.api('/rest/v1/vendor_orders?order_id=eq.'+str(result['order_id'])+'&select=id',admin=True);assert status==200 and len(rows)==1
  vo=rows[0]['id'];status,result=b.rpc('fr10_vendor_transition',{'p_vendor_order_id':vo,'p_status':'accepted'},b.login(vendor));assert status==200 and result['code']in('UPDATED','ACCEPTED')
  status,result=b.rpc('fr21_ready_and_assign',{'p_vendor_order_id':vo},b.login(vendor));assert status==200 and result.get('rider_id')==rider['profile_id'],'Own physical rider must be assigned'
  state['physical_assignment_id']=result['assignment_id'];save()
 check(True,'synthetic stocked checkout ready and assigned through FR20 for physical pickup')
def tests():
 aid=state['physical_assignment_id'];oid=state['physical_order_id'];valid=[{'id':x,'confirmed':True}for x in('items_match','packaging_intact','details_confirmed')]
 for label,account in [('other-rider',state['accounts']['other-rider']),('vendor',state['accounts']['vendor']),('customer',h.f.state['accounts']['customer']),('admin',h.state['accounts']['admin'])]:
  status,result=b.rpc('submit_pre_delivery_checklist',{'p_assignment_id':aid,'p_version':1,'p_confirmations':valid},b.login(account))
  check(status==200 and result['code']=='FORBIDDEN',label+' cannot submit assigned rider checklist over HTTP')
 status,_=b.rpc('submit_pre_delivery_checklist',{'p_assignment_id':aid,'p_version':1,'p_confirmations':valid})
 check(status in(401,403),'anonymous checklist RPC denied over HTTP')
 owner=b.login(state['accounts']['rider']);status,result=b.rpc('pre_delivery_checklist',{'p_order_id':oid},owner)
 check(status==200 and result['code']=='OK'and result['completed']is False and len(result['items'])==3,'assigned rider sees authoritative incomplete definition over HTTP')
 status,result=b.rpc('start_checklisted_delivery',{'p_assignment_id':aid},owner)
 check(status==200 and result['code']in('PICKUP_REQUIRED','CHECKLIST_REQUIRED'),'incomplete pickup cannot start over HTTP')
 status,_=b.api('/rest/v1/rider_assignments?id=eq.'+str(aid),'PATCH',{'checklist_completed':True},owner)
 check(status in(401,403),'direct completion flag update forbidden over HTTP')
 status,_=b.api('/rest/v1/pre_delivery_checklists','POST',{'assignment_id':aid,'rider_id':state['accounts']['rider']['profile_id'],'checklist_version':1,'confirmations':valid,'definition_snapshot':[]},owner)
 check(status in(401,403),'direct evidence insertion forbidden over HTTP')
 status,result=b.api('/rest/v1/orders?id=eq.'+str(oid),'PATCH',{'order_status':'on_the_way'},owner)
 check(status in(401,403)or(status==200 and result==[]),'ordinary direct status bypass denied over HTTP')
 status,rows=b.api('/rest/v1/orders?id=eq.'+str(oid)+'&select=order_status',admin=True)
 check(status==200 and rows==[{'order_status':'ready'}],'failed bypass leaves actual parent at pickup')
def regression21():
 spec=importlib.util.spec_from_file_location('checklist_fr21',ROOT/'tests/integration/FR-21-hosted.py')
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 original_rpc=module.rpc;original_row=module.row;original_request=module.request;prepared=set()
 def tracked(name,params,token=None,expected=(200,)):
  if name=='fr21_set_presence'and params.get('p_online')is True and expected==(200,):
   original_rpc('fr21_update_location',{'p_lat':31.52,'p_lng':74.35},token,(204,))
  return original_rpc(name,params,token,expected)
 def row(table,payload):
  if table=='vendor_orders'and payload.get('vendor_id')==module.state['accounts'].get('other-vendor',{}).get('profile_id'):
   payload={**payload,'status':'ready'}
  return original_row(table,payload)
 def request(path,method='GET',body=None,token=None,expected=(200,201,204),admin=False):
  if path=='/rest/v1/rpc/issue_delivery_otp'and admin and body['p_order_id']not in prepared:
   oid=body['p_order_id'];orders=original_request('/rest/v1/orders?id=eq.'+str(oid)+'&select=rider_id',admin=True)
   actor=next(a for a in module.state['accounts'].values()if a.get('profile_id')==orders[0]['rider_id'])
   original_rpc('fr21_accept_order',{'p_order_id':oid},b.login(actor))
   from checklist_fixtures import start
   start(b,oid,actor);prepared.add(oid)
  return original_request(path,method,body,token,expected,admin)
 module.rpc=tracked;module.row=row;module.request=request;module.main()
def regressions(profile='all'):
 os.environ['CHECKLIST_REGRESSION_FIXTURES']='true'
 suites=[('FR21',None,None),('FR04','FR-04-hosted.py','tests'),('FR25','FR-25-hosted.py','tests'),
 ('FR26','FR-26-hosted.py','tests'),('FR33','FR-33-hosted.py','tests'),('FR28','FR-28-hosted.py','tests'),
 ('FR20','FR-20-hosted.py','tests'),('FR30-sql','FR-30-hosted.py','sql'),('FR30-http','FR-30-hosted.py','tests'),
 ('FR30-realtime','FR-30-hosted.py','realtime'),('FR10','FR-10-hosted.py','hosted'),('FR17','FR-17-hosted.py','hosted'),('FR32','FR-32-db.py','hosted-sql')]
 if profile and profile!='all':suites=[s for s in suites if s[0]in profile.split(',')]
 results=[]
 for label,script,mode in suites:
  output=io.StringIO();old_args=sys.argv
  try:
   with contextlib.redirect_stdout(output),contextlib.redirect_stderr(output):
    if script is None:regression21()
    else:
     path=ROOT/'tests/integration'/script;sys.argv=[str(path),mode]
     try:runpy.run_path(str(path),run_name='__main__')
     except SystemExit as e:
      if e.code not in(None,0):raise AssertionError('Existing regression runner failed')
   text=output.getvalue();counts=[int(x)for x in re.findall(r'"passed"\s*:\s*(\d+)',text)]
   result={'FR':label,'result':'PASS','passed':counts[-1]if counts else sum('PASS'in l for l in text.splitlines())}
  except Exception as e:result={'FR':label,'result':'FAIL','error':str(e)if isinstance(e,(AssertionError,RuntimeError))else type(e).__name__}
  finally:
   sys.argv=old_args;(OUT/('regression-'+label+'.log')).write_text(output.getvalue(),encoding='utf-8')
  results.append(result);(OUT/('regressions-'+(profile or'all').replace(',','-')+'.json')).write_text(json.dumps(results,indent=2));print(json.dumps(result),flush=True)
 if any(r['result']!='PASS'for r in results):raise AssertionError('Regression failures require review; no acceptance claim')
if __name__=='__main__':
 mode=sys.argv[1]
 if mode=='deploy':deploy()
 elif mode=='verify':verify()
 elif mode=='sql':sql()
 elif mode=='regressions':regressions(sys.argv[2]if len(sys.argv)>2 else'all')
 elif mode=='fixtures':fixtures()
 elif mode=='artifact':runpy.run_path(str(ROOT/'tests/integration/CHECKLIST-artifact.py'),run_name='__main__')
 elif mode=='tests':tests()
 elif mode=='native':
  sys.argv=[str(ROOT/'tests/integration/CHECKLIST-native.py'),sys.argv[2]];runpy.run_path(sys.argv[0],run_name='__main__')
 else:raise ValueError('Unsupported safe action')
