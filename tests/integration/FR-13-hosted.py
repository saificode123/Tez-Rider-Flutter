"""FR13 isolated TEST harness; no production/reset/history replay."""
import importlib.util,json,sys,re,secrets,uuid,time,datetime as dt,urllib.parse
from pathlib import Path
spec=importlib.util.spec_from_file_location('checklist',Path(__file__).with_name('CHECKLIST-hosted.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
b=h.b;ROOT=h.ROOT;OUT=ROOT/'.fr21-local/fr13';OUT.mkdir(parents=True,exist_ok=True)
db=h.h;MIGRATION='202610180001_fr13_live_gps.sql';STATE=b.PRIVATE/'fr13-accounts.bin'
state=json.loads(b.crypt(STATE.read_bytes(),True))if STATE.exists()else{'accounts':{},'orders':[]}
checks=[]
def save():STATE.write_bytes(b.crypt(json.dumps(state).encode()))
def check(ok,label):
 assert ok,label
 record={'result':'PASS','check':label};checks.append(record)
 with(OUT/'checks.jsonl').open('a')as file:file.write(json.dumps(record)+'\n')
 print(json.dumps(record),flush=True)
def review():
 versions=[r['version']for r in db.query('select version from supabase_migrations.schema_migrations order by version;')]
 assert'202610180001'not in versions
 migration=re.sub(r'^begin;\s*|^commit;\s*','',(ROOT/'supabase/migrations'/MIGRATION).read_text(),flags=re.M)
 rules=(ROOT/'supabase/tests/FR-13.sql').read_text().replace('begin;','begin;\n'+migration,1)
 rows=db.query(rules);result=next(iter(rows[0].values()));assert all(r['result']=='PASS'for r in result)
 (OUT/'hosted-review.json').write_text(json.dumps(result,indent=2));print(json.dumps({'hosted_rollback':True,'passed':len(result)}))
def deploy():
 expected=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
 versions=[r['version']for r in db.query('select version from supabase_migrations.schema_migrations order by version;')]
 assert versions==[v for v in expected if v!='202610180001'],'Never replay accepted migrations'
 jobs=db.query('select jobid,jobname,schedule,active,md5(command)as command_hash from cron.job order by jobid;')
 plan=db.command(['db','push','--linked','--dry-run']);assert sorted(set(re.findall(r'2026\d{8}_[a-z0-9_]+\.sql',plan)))==[MIGRATION]
 db.command(['db','push','--linked'])
 assert[r['version']for r in db.query('select version from supabase_migrations.schema_migrations order by version;')]==expected
 after=db.query("select jobid,jobname,schedule,active,md5(command)as command_hash from cron.job where jobname<>'fr13-location-cleanup'order by jobid;");assert after==jobs
 db.command(['functions','deploy','fr13-location','--project-ref',b.REF,'--no-verify-jwt'])
 (OUT/'deployment.json').write_text(json.dumps({'target':b.REF,'migration':MIGRATION,'versions':len(expected),'accepted_jobs_unchanged':True,'function':'fr13-location','production_modified':False},indent=2))
 print('FR13 migration applied once and protected endpoint deployed only to isolated TEST; accepted jobs unchanged')
def sql():
 result=db.query((ROOT/'supabase/tests/FR-13.sql').read_text())[0]['results']
 assert all(r['result']=='PASS'for r in result)
 (OUT/'hosted-sql.json').write_text(json.dumps(result,indent=2));print(json.dumps({'hosted_sql_passed':len(result)}))
 prior=next(iter(db.query((ROOT/'supabase/tests/CHECKLIST.sql').read_text())[0].values()));assert all(r['result']=='PASS'for r in prior)
 (OUT/'checklist-regression.json').write_text(json.dumps(prior,indent=2));print(json.dumps({'checklist_regression_passed':len(prior)}))
def fixture(label,role):
 a=state['accounts'].setdefault(label,{'email':'fr13-'+label+'@example.test','password':secrets.token_urlsafe(28)+'aA7!'});save()
 if'auth_id'not in a:
  code,user=b.api('/auth/v1/admin/users','POST',{'email':a['email'],'password':a['password'],'email_confirm':True,'user_metadata':{'fr13_fixture':True,'role':role}},admin=True)
  assert code in(200,201);a['auth_id']=user['id'];save()
 if'profile_id'not in a:
  code,rows=b.api('/rest/v1/users','POST',{'email':a['email'],'name':'FR13 SYNTHETIC '+label,'role':role,'verification_status':'approved'},admin=True)
  assert code==201;a['profile_id']=rows[0]['id'];save()
 if role=='rider':
  code,rows=b.api('/rest/v1/riders?userid=eq.'+str(a['profile_id'])+'&select=id',admin=True);assert code==200
  if not rows:code,_=b.api('/rest/v1/riders','POST',{'userid':a['profile_id']},admin=True);assert code==201
 return a
def fixtures():
 for who,role in [('rider','rider'),('other-rider','rider'),('customer','customer'),('other-customer','customer'),('vendor','vendor'),('admin','admin')]:fixture(who,role)
 check(True,'marked synthetic TEST roles created without email')
def physical_accounts():
 fixture('physical-rider','rider')
 state['accounts']['physical-customer']=dict(db.f.state['accounts']['customer']);save()
 check(True,'separate physical rider prepared; customer reuses authorized configured TEST inbox; no GPS coordinates seeded')
def physical_fixture():
 rider=state['accounts']['physical-rider'];rid=int(rider['profile_id']);vendor=state['accounts']['vendor']
 rows=db.query('select latitude,longitude,is_online,last_seen,location_updated_at,location_updated_at>clock_timestamp()-interval\'2 minutes\'as fresh from public.riders where userid='+str(rid)+';')
 assert len(rows)==1 and rows[0]['is_online']and rows[0]['fresh'],'Real phone must first supply a fresh idle GPS fix while online'
 lat=float(rows[0]['latitude']);lng=float(rows[0]['longitude']);assert -90<=lat<=90 and -180<=lng<=180
 code,rows=b.api('/rest/v1/vendors?user_id=eq.'+str(vendor['profile_id'])+'&select=id',admin=True);assert code==200
 if not rows:
  code,_=b.api('/rest/v1/vendors','POST',{'user_id':vendor['profile_id'],'store_name':'FR13 SYNTHETIC PHYSICAL PICKUP','latitude':lat,'longitude':lng},admin=True);assert code==201
 else:
  code,_=b.api('/rest/v1/vendors?user_id=eq.'+str(vendor['profile_id']),'PATCH',{'latitude':lat,'longitude':lng},admin=True);assert code in(200,204)
 if'physical_product_id'not in state:
  code,r=b.rpc('fr17_save_product',{'p_request_id':str(uuid.uuid4()),'p_product_id':None,'p_data':{'name':'FR13 SYNTHETIC PHYSICAL PICKUP','price':80,'is_available':True},'p_stock':20,'p_threshold':5,'p_expected_version':None},b.login(vendor));assert code==200 and r['code']=='UPDATED';state['physical_product_id']=r['product_id'];save()
 if'physical_order_id'not in state:
  customer=state['accounts']['physical-customer']
  code,r=b.rpc('fr10_checkout',{'p_request_id':str(uuid.uuid4()),'p_items':[{'product_id':state['physical_product_id'],'quantity':1}],'p_delivery':{'address':'FR13 SYNTHETIC PHYSICAL GPS TEST','lat':lat+.0005,'lng':lng+.0005,'speed':'standard'}},b.login(customer));assert code==200 and r['code']=='PLACED'
  state['physical_order_id']=r['order_id'];save()
  code,rows=b.api('/rest/v1/vendor_orders?order_id=eq.'+str(r['order_id'])+'&select=id',admin=True);assert code==200 and len(rows)==1
  vo=rows[0]['id'];state['physical_vendor_order_id']=vo;save()
  code,r=b.rpc('fr10_vendor_transition',{'p_vendor_order_id':vo,'p_status':'accepted'},b.login(vendor));assert code==200 and r['code']in('UPDATED','ACCEPTED')
  code,r=b.rpc('fr21_ready_and_assign',{'p_vendor_order_id':vo},b.login(vendor));assert code==200 and r.get('rider_id')==rid,'Exact physical rider must be assigned'
  state['physical_assignment_id']=r['assignment_id'];save()
 check(True,'actual stocked TEST checkout assigned through FR20 to separate real-GPS rider; no rider coordinates fabricated')
def online():
 token=b.login(state['accounts']['rider']);code,p=b.rpc('fr21_begin_presence',{},token);assert code==200
 code,_=b.rpc('fr21_update_location',{'p_lat':33.7,'p_lng':73.05},token);assert code in(200,204)
 code,r=b.rpc('fr21_set_presence',{'p_online':True,'p_epoch':p['epoch'],'p_sequence':1},token);assert code==200 and r['is_online']
 return token

def physical_cancel_fixture():
 # A zero-capture legacy security fixture tests GPS lifecycle only. Never
 # force-cancel a managed FR10 checkout already in irreversible fulfillment.
 if'completed_physical_order'not in state:
  oid=int(state['physical_order_id']);code,rows=b.api('/rest/v1/orders?id=eq.'+str(oid)+'&select=order_status',admin=True)
  assert code==200 and rows==[{'order_status':'delivered'}],'Finish the actual OTP delivery first'
  state['completed_physical_order']={'oid':oid,'aid':state['physical_assignment_id']};save()
 if'physical_cancel_order'not in state:
  rid=state['accounts']['physical-rider']['profile_id'];cid=state['accounts']['physical-customer']['profile_id']
  code,rows=b.api('/rest/v1/orders','POST',{'user_id':cid,'rider_id':rid,'order_status':'ready','amount':0,'payment_method':'COD','delivery_address':'FR13 SYNTHETIC SECURITY TEST ONLY'},admin=True);assert code==201
  state['physical_cancel_order']={'oid':rows[0]['id']};save()
 row=state['physical_cancel_order']
 if'aid'not in row:
  code,rows=b.api('/rest/v1/rider_assignments?orderid=eq.'+str(row['oid'])+'&select=id',admin=True);assert code==200
  if not rows:
   code,rows=b.api('/rest/v1/rider_assignments','POST',{'orderid':row['oid'],'riderid':state['accounts']['physical-rider']['profile_id'],'status':'Accepted'},admin=True);assert code==201
  assert len(rows)==1;row['aid']=rows[0]['id'];save()
 state['physical_order_id']=row['oid'];state['physical_assignment_id']=row['aid'];save()
 check(True,'zero-capture synthetic GPS cancellation fixture prepared; completed managed checkout preserved')

def physical_cancel_transition():
 row=state['physical_cancel_order'];oid=int(row['oid']);assert oid==state['physical_order_id']
 rows=db.query("select count(*)as safe from public.orders where id="+str(oid)+" and delivery_address='FR13 SYNTHETIC SECURITY TEST ONLY'and checkout_finalized_at is null and amount=0 and payment_method='COD'and order_status='on_the_way';")
 assert rows[0]['safe']==1,'Only this zero-capture synthetic lifecycle fixture may transition'
 token=b.login(state['accounts']['physical-rider']);code,context=b.rpc('fr13_tracking_context',{'p_order_id':oid},token)
 assert code==200 and context['code']=='OK'and context['sharing']and context['latest'],'Real phone must share first'
 close(row)
 rows=db.query('select (select order_status from public.orders where id='+str(oid)+')as status,(select count(*)from fr13_private.sessions where order_id='+str(oid)+')as sessions,(select count(*)from public.delivery_latest_locations where order_id='+str(oid)+')as latest,(select count(*)from public.order_refund_actions where order_id='+str(oid)+')as refunds;')
 assert rows==[{'status':'cancelled','sessions':0,'latest':0,'refunds':0}]
 check(True,'synthetic zero-capture cancellation removed GPS session/latest; no refund; managed FR10 policy unchanged')
def new_order():
 token=online();rid=state['accounts']['rider']['profile_id'];cid=state['accounts']['customer']['profile_id']
 code,rows=b.api('/rest/v1/orders','POST',{'user_id':cid,'rider_id':rid,'order_status':'ready','amount':1,'payment_method':'COD','delivery_address':'FR13 SYNTHETIC SECURITY TEST ONLY'},admin=True);assert code==201
 oid=rows[0]['id'];code,rows=b.api('/rest/v1/rider_assignments','POST',{'orderid':oid,'riderid':rid,'status':'Accepted'},admin=True);assert code==201
 row={'oid':oid,'aid':rows[0]['id']};state['orders'].append(row);save();return row,token
def start(row,token):
 valid=[{'id':i,'confirmed':True}for i in('items_match','packaging_intact','details_confirmed')]
 code,r=b.rpc('submit_pre_delivery_checklist',{'p_assignment_id':row['aid'],'p_version':1,'p_confirmations':valid},token);assert code==200 and r['code']=='COMPLETED'
 code,r=b.rpc('start_checklisted_delivery',{'p_assignment_id':row['aid']},token);assert code==200 and r['code']=='STARTED'
 code,r=b.rpc('fr13_tracking_context',{'p_order_id':row['oid'],'p_enable':True},token);assert code==200 and r['code']=='OK';return r
def body(oid):return {'order_id':oid,'latitude':33.7,'longitude':73.05,'accuracy':5,'device_at':dt.datetime.now(dt.timezone.utc).isoformat(),'request_id':str(uuid.uuid4())}
def publish(value,token):return b.api('/functions/v1/fr13-location','POST',value,token)
def close(row,status='cancelled'):
 assert status in('cancelled','delivered');oid=int(row['oid']);aid=int(row['aid'])
 db.query("begin;update public.orders set order_status='"+status+"'where id="+str(oid)+" and delivery_address='FR13 SYNTHETIC SECURITY TEST ONLY'and order_status not in('cancelled','delivered');update public.rider_assignments a set status=case when o.order_status='delivered'then'Delivered'else'Cancelled'end from public.orders o where a.id="+str(aid)+" and a.orderid=o.id and o.id="+str(oid)+" and o.delivery_address='FR13 SYNTHETIC SECURITY TEST ONLY'and o.order_status in('delivered','cancelled');commit;")
def realtime():
 sys.path.insert(0,str(ROOT/'build/fr21-python'))
 from websockets.sync.client import connect
 sockets=[]
 def join(who,topic,private=True):
  token=b.ANON if who=='anon'else b.login(state['accounts'][who])
  ws=connect('wss://'+b.REF+'.supabase.co/realtime/v1/websocket?'+urllib.parse.urlencode({'apikey':b.ANON,'vsn':'1.0.0'}),open_timeout=20,close_timeout=3);sockets.append(ws)
  ws.send(json.dumps({'topic':'realtime:'+topic,'event':'phx_join','ref':'1','payload':{'config':{'private':private,'broadcast':{'ack':True,'self':True},'presence':{'key':''},'postgres_changes':[]},'access_token':token}}))
  until=time.monotonic()+20
  while time.monotonic()<until:
   msg=json.loads(ws.recv(timeout=20))
   if msg['event']=='phx_reply'and msg.get('ref')=='1':return ws,msg['payload']['status']=='ok'
  raise AssertionError('Actual hosted channel outcome required')
 def events(ws,seconds):
  result=[];until=time.monotonic()+seconds
  while time.monotonic()<until:
   try:msg=json.loads(ws.recv(timeout=max(.1,until-time.monotonic())))
   except TimeoutError:break
   if msg['event']=='broadcast'and msg['payload'].get('event')=='location':result.append(msg['payload']['payload'])
  return result
 row,token=new_order()
 try:
  context=start(row,token);topic=context['topic'];owned={}
  for who in('rider','customer','admin'):
   ws,allowed=join(who,topic);check(allowed,who+' hosted private join allowed');owned[who]=ws
  for who in('other-rider','other-customer','vendor','anon'):
   _,allowed=join(who,topic);check(not allowed,who+' hosted private join denied')
  decoy,allowed=join('other-customer',topic,False);check(allowed,'public decoy does not grant private topic access')
  value=body(row['oid']);code,r=publish(value,token);check(code==200 and r['code']=='PUBLISHED','trusted hosted endpoint publishes real protocol message')
  for who in('rider','customer','admin'):
   received=events(owned[who],.5);check(len(received)==1 and received[0]['request_id']==value['request_id'],who+' actually receives only trusted location')
  check(events(decoy,.5)==[],'public decoy receives no private hosted location')
  for who in('rider','customer'):
   owned[who].send(json.dumps({'topic':'realtime:'+topic,'event':'broadcast','ref':'forged','payload':{'type':'broadcast','event':'location','payload':{'forged':True}}}))
   code,_=b.api('/realtime/v1/api/broadcast','POST',{'messages':[{'topic':topic,'event':'location','payload':{'forged':True},'private':True}]},b.login(state['accounts'][who]))
  check(events(owned['customer'],2)==[],'hosted direct WebSocket/REST client publish delivers no forged location')
  owned['customer'].close();own,allowed=join('customer',topic);check(allowed,'customer reconnect authorized');owned['customer']=own
  value=body(row['oid']);code,r=publish(value,token);check(code==200 and r['code']=='PUBLISHED','fresh fix publishes after reconnect')
  received=events(own,1);check(len(received)==1 and received[0]['request_id']==value['request_id'],'reconnected customer receives one event, no duplicate')
  close(row);code,r=publish(body(row['oid']),token);check(code==200 and r['code']=='INELIGIBLE','cancellation blocks hosted publication')
  check(events(own,1)==[],'cached subscriber gets no new location after cancellation')
  _,allowed=join('customer',topic);check(not allowed,'cancelled topic denies fresh join')
  row,token=new_order();context=start(row,token);own,allowed=join('customer',context['topic']);check(allowed,'second synthetic active delivery subscribes')
  close(row,'delivered')
  code,r=publish(body(row['oid']),token);check(code==200 and r['code']=='INELIGIBLE','delivered synthetic fixture blocks publication (not physical OTP proof)')
  check(events(own,1)==[],'cached subscriber gets no new location after completion')
  _,allowed=join('customer',context['topic']);check(not allowed,'delivered topic denies fresh join')
 finally:
  close(row)
  for ws in sockets:ws.close()
 (OUT/'hosted-realtime.json').write_text(json.dumps({'passed':len(checks),'checks':checks,'actual_websocket':True,'real_emails_sent':0},indent=2))
def http_tests():
 row,token=new_order();oid=row['oid']
 try:
  code,r=publish(body(oid),token);check(code==200 and r['code']=='INELIGIBLE','hosted missing checklist/start rejected')
  context=start(row,token)
  for who in('other-rider','customer','other-customer','vendor','admin'):
   code,r=publish(body(oid),b.login(state['accounts'][who]));check(code in(200,403)and r['code']=='FORBIDDEN',who+' cannot publish GPS')
  code,_=publish(body(oid),None);check(code in(401,403),'anonymous endpoint denied')
  for changes in({'latitude':91},{'longitude':181},{'accuracy':-1},{'accuracy':101},{'device_at':'invalid'},{'topic':'victim'}):
   code,r=publish({**body(oid),**changes},token);check(code==400 and r['code']=='INVALID_LOCATION','invalid coordinate/accuracy/timestamp/extra input rejected')
  code,r=publish({**body(oid),'device_at':(dt.datetime.now(dt.timezone.utc)-dt.timedelta(seconds=40)).isoformat()},token);check(code==200 and r['code']=='STALE_FIX','server timestamp skew rejected')
  value=body(oid);code,r=publish(value,token);check(code==200 and r['code']=='PUBLISHED','assigned rider actual hosted publisher succeeds')
  code,r=publish(value,token);check(code==200 and r['code']=='REPLAYED','hosted retry suppressed')
  # Sequential hosted calls may already exceed the 2s interval due network latency.
  # Race two fresh requests instead of mistaking elapsed network time for a bypass.
  from concurrent.futures import ThreadPoolExecutor
  time.sleep(2.05)
  with ThreadPoolExecutor(max_workers=2)as pool:outcomes=list(pool.map(lambda _:publish(body(oid),token),range(2)))
  check(all(code==200 for code,_ in outcomes)and sorted(r['code']for _,r in outcomes)==['PUBLISHED','RATE_LIMIT'],'hosted concurrent server minimum interval enforced')
  for who,expected in [('customer',1),('rider',1),('admin',1),('other-rider',0),('other-customer',0),('vendor',0)]:
   code,rows=b.api('/rest/v1/delivery_latest_locations?order_id=eq.'+str(oid)+'&select=assignment_id',token=b.login(state['accounts'][who]));check(code==200 and len(rows)==expected,who+' latest read isolated')
  code,_=b.api('/rest/v1/delivery_latest_locations?order_id=eq.'+str(oid),'PATCH',{'latitude':0},token);check(code in(401,403),'direct latest write denied')
  code,_=b.api('/rest/v1/gps_locations','POST',{'rider_id':'fr13-bypass','latitude':0,'longitude':0},token);check(code in(401,403),'legacy arbitrary write denied')
 finally:close(row)
 (OUT/'hosted-http.json').write_text(json.dumps({'passed':len(checks),'checks':checks,'real_emails_sent':0},indent=2))
def regressions():
 # Keep this run's summary/logs apart from the accepted checklist checkpoint.
 h.OUT=OUT
 h.regressions(sys.argv[2]if len(sys.argv)>2 and sys.argv[2]else'all')
def inspect():
 result=h.h.query("""select jsonb_build_object(
 'versions',(select jsonb_agg(version order by version)from supabase_migrations.schema_migrations),
 'jobs',(select jsonb_agg(jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'active',active,'command_hash',md5(command)))from cron.job),
 'policies',(select jsonb_agg(to_jsonb(p))from pg_policies p where (schemaname='public'and tablename in('gps_locations','riders'))or schemaname='realtime'),
 'gps_columns',(select jsonb_agg(jsonb_build_object('name',column_name,'type',data_type))from information_schema.columns where table_schema='public'and table_name='gps_locations'),
 'gps_grants',(select jsonb_agg(to_jsonb(g))from information_schema.role_table_grants g where table_schema='public'and table_name='gps_locations'),
 'realtime_functions',(select jsonb_agg(jsonb_build_object('name',p.proname,'args',pg_get_function_identity_arguments(p.oid)))from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='realtime'and p.proname in('send','topic')),
 'gps_rows',(select count(*)from public.gps_locations))as inspection;""")
 (OUT/'inspection.json').write_text(json.dumps(result,indent=2))
 print(json.dumps(result))

def resume_audit():
 expected=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
 actual=[r['version']for r in db.query('select version from supabase_migrations.schema_migrations order by version;')]
 assert actual==expected,'Applied history differs; never replay migrations'
 before=json.loads((OUT/'inspection.json').read_text())[0]['inspection']['jobs']
 after=db.query("select jobid as id,jobname as name,schedule,active,md5(command)as command_hash from cron.job where jobname<>'fr13-location-cleanup'order by jobid;")
 assert sorted(before,key=lambda row:row['id'])==after,'Previously accepted jobs changed'
 result={'project_ref':b.REF,'applied_versions':len(actual),'accepted_jobs_unchanged':True,'migration_replayed':False,'production_modified':False}
 (OUT/'resume-audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
if __name__=='__main__':
 actions={'inspect':inspect,'review':review,'deploy':deploy,'sql':sql,'fixtures':fixtures,'http':http_tests,'realtime':realtime,'regressions':regressions,'physical-accounts':physical_accounts,'physical-fixture':physical_fixture,'physical-cancel-fixture':physical_cancel_fixture,'physical-cancel-transition':physical_cancel_transition,'resume-audit':resume_audit}
 if sys.argv[1]=='native':
  import runpy
  sys.argv=[str(ROOT/'tests/integration/FR-13-native.py'),sys.argv[2]];runpy.run_path(sys.argv[0],run_name='__main__');sys.exit(0)
 if sys.argv[1]=='artifact':
  import runpy
  runpy.run_path(str(ROOT/'tests/integration/FR-13-artifact.py'),run_name='__main__');sys.exit(0)
 if sys.argv[1]=='observe':
  import runpy
  sys.argv=[str(ROOT/'tests/integration/FR-13-observe.py'),sys.argv[2]];runpy.run_path(sys.argv[0],run_name='__main__');sys.exit(0)
 if sys.argv[1]=='browser-login':
  import runpy
  runpy.run_path(str(ROOT/'tests/integration/FR-13-browser.py'),run_name='__main__');sys.exit(0)
 if sys.argv[1]=='physical-security':
  import runpy
  runpy.run_path(str(ROOT/'tests/integration/FR-13-physical-security.py'),run_name='__main__');sys.exit(0)
 if sys.argv[1]not in actions:raise ValueError('Unsupported safe mode')
 actions[sys.argv[1]]()
