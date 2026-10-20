"""Synthetic isolated TEST checks; credentials remain in private encrypted state."""
import importlib.util,json,secrets,sys,uuid,subprocess,os,time,datetime as dt,threading,urllib.request
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr13',Path(__file__).with_name('FR-13-hosted.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
b=h.b;db=h.db;ROOT=h.ROOT;OUT=ROOT/'.fr21-local/fr14';OUT.mkdir(parents=True,exist_ok=True)
STATE=b.PRIVATE/'fr14-accounts.bin'
state=json.loads(b.crypt(STATE.read_bytes(),True))if STATE.exists()else{'accounts':{}}
checks=[]
def save():STATE.write_bytes(b.crypt(json.dumps(state).encode()))
def check(v,label):
 assert v,label
 checks.append({'check':label,'result':'PASS'});print(json.dumps(checks[-1]),flush=True)
def fixture(label,role):
 a=state['accounts'].setdefault(label,{'email':'fr14-'+label+'@example.test','password':secrets.token_urlsafe(28)+'aA7!'})
 save()
 if'auth_id'not in a:
  code,u=b.api('/auth/v1/admin/users','POST',{'email':a['email'],'password':a['password'],'email_confirm':True,'user_metadata':{'fr14_fixture':True,'role':role}},admin=True)
  assert code in(200,201);a['auth_id']=u['id'];save()
 if'profile_id'not in a:
  code,r=b.api('/rest/v1/users','POST',{'email':a['email'],'name':'FR14 SYNTHETIC '+label,'role':role,'verification_status':'approved'},admin=True)
  assert code==201;a['profile_id']=r[0]['id'];save()
 if role=='rider':
  code,r=b.api('/rest/v1/riders?userid=eq.'+str(a['profile_id'])+'&select=id',admin=True);assert code==200
  if not r:assert b.api('/rest/v1/riders','POST',{'userid':a['profile_id']},admin=True)[0]==201
 return a
def edge(oid,token):return b.api('/functions/v1/get-delivery-route','POST',{'orderId':oid},token)
def deploy_function():
 assert(ROOT/'supabase/.temp/project-ref').read_text().strip()==b.REF=='igeisilhtmglgnqvllrx'
 # Read only this key. Never upload unrelated email/notification secrets.
 values={}
 for line in(ROOT/'supabase/functions/.env.test.local').read_text().splitlines():
  if line.startswith('ROUTING_API_KEY='):values['ROUTING_API_KEY']=line.split('=',1)[1].strip().strip('"').strip("'")
 assert values.get('ROUTING_API_KEY'),'ROUTING_API_KEY required in ignored TEST file'
 private=OUT/'routing-secret.env';private.write_text('ROUTING_API_KEY='+values['ROUTING_API_KEY']+'\n')
 cli='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
 try:
  p=subprocess.run([cli,'secrets','set','--env-file',str(private),'--project-ref',b.REF],capture_output=True,text=True,timeout=120)
  assert p.returncode==0,'TEST secret configuration failed; no raw output exposed'
 finally:private.unlink(missing_ok=True)
 p=subprocess.run([cli,'functions','deploy','get-delivery-route','--project-ref',b.REF,'--no-verify-jwt','--use-api'],capture_output=True,text=True,timeout=180)
 (OUT/'function-deploy.log').write_text(p.stdout+p.stderr);assert p.returncode==0,'TEST deploy failed; protected log retained'
 check(True,'routing secret configured and Edge deployed to isolated TEST only')
def setup():
 for label,role in [('customer','customer'),('other-customer','customer'),('rider','rider'),('other-rider','rider'),('vendor','vendor'),('admin','admin')]:fixture(label,role)
 check(True,'dedicated marked synthetic TEST accounts prepared without mail')
def physical_accounts():
 fixture('physical-rider','rider')
 assert'physical-customer'in h.state['accounts'],'Existing authorized verified TEST inbox required'
 state['accounts']['physical-customer']=dict(h.state['accounts']['physical-customer']);save()
 vendor=state['accounts']['vendor']
 if'physical_product_id'not in state:
  code,r=b.rpc('fr17_save_product',{'p_request_id':str(uuid.uuid4()),'p_product_id':None,'p_data':{'name':'FR14 PHYSICAL WALK TEST','price':1,'is_available':True},'p_stock':20,'p_threshold':5,'p_expected_version':None},b.login(vendor))
  assert code==200 and r['code']=='UPDATED';state['physical_product_id']=r['product_id'];save()
 check(True,'separate physical rider, existing authorized TEST inbox and stocked synthetic walk-test product prepared')
def physical_accept():
 # Discover only the actual checkout containing our dedicated fixture item.
 cid=int(state['accounts']['physical-customer']['profile_id']);pid=int(state['physical_product_id'])
 rows=db.query(f"select o.id,vo.id as vo,o.destination_confirmed_at is not null as confirmed from public.orders o join public.vendor_orders vo on vo.order_id=o.id join public.order_items i on i.vendor_order_id=vo.id where o.user_id={cid} and i.product_id={pid} and o.order_status='pending' and o.created_at>clock_timestamp()-interval '10 minutes' order by o.id desc limit 2;")
 assert len(rows)==1 and rows[0]['confirmed'],'Exactly one recent customer-confirmed physical TEST checkout required'
 row=rows[0];code,r=b.rpc('fr10_vendor_transition',{'p_vendor_order_id':row['vo'],'p_status':'accepted'},b.login(state['accounts']['vendor']))
 assert code==200 and r['code']in('ACCEPTED','UPDATED'),'Actual vendor acceptance required'
 state['physical_order']={'oid':row['id'],'vo':row['vo']};save()
 check(True,'actual confirmed physical TEST checkout accepted by its vendor; destination unchanged')

def physical_assign():
 row=state['physical_order'];rid=int(state['accounts']['physical-rider']['profile_id'])
 rows=db.query('select latitude,longitude,is_online,location_updated_at>clock_timestamp()-interval\'2 minutes\'as fresh from public.riders where userid='+str(rid))
 assert len(rows)==1 and rows[0]['is_online']and rows[0]['fresh'],'Real phone must supply fresh idle GPS while online'
 vendor=state['accounts']['vendor'];vid=int(vendor['profile_id'])
 # Synthetic pickup follows the real rider fix; never alter the delivery pin.
 code,_=b.api('/rest/v1/vendors?user_id=eq.'+str(vid),'PATCH',{'latitude':rows[0]['latitude'],'longitude':rows[0]['longitude']},admin=True);assert code in(200,204)
 code,r=b.rpc('fr21_ready_and_assign',{'p_vendor_order_id':row['vo']},b.login(vendor))
 assert code==200 and r.get('rider_id')==rid,'Exact physical rider assignment required'
 row['aid']=r['assignment_id'];save()
 check(True,'physical TEST order assigned through accepted FR20 flow using fresh real rider GPS')

def physical_security():
 oid=int(state['physical_order']['oid']);token=b.login(state['accounts']['other-customer'])
 code,r=b.rpc('fr13_tracking_context',{'p_order_id':oid},token)
 check(code==200 and r['code']=='FORBIDDEN','second customer denied actual physical order GPS context')
 for table,projection in [('delivery_latest_locations','assignment_id'),('delivery_route_cache','order_id')]:
  code,r=b.api('/rest/v1/'+table+'?order_id=eq.'+str(oid)+'&select='+projection,token=token)
  check(code==200 and r==[],'second customer receives zero physical order '+table+' rows')
 code,r=edge(oid,token)
 check(code==403 and'route'not in r,'second customer denied actual physical route Edge endpoint')
 (OUT/'physical-security.json').write_text(json.dumps(checks,indent=2))

def physical_terminal():
 oid=int(state['physical_order']['oid'])
 rows=db.query(f"select order_status,route_estimated_arrival_at is null as eta_cleared,(select count(*)from public.delivery_route_cache where order_id={oid})as route_rows,(select count(*)from public.delivery_latest_locations where order_id={oid})as location_rows,(select count(*)from fr13_private.sessions where order_id={oid})as tracking_sessions,(select count(*)from fr14_private.attempts where order_id={oid})as route_leases from public.orders where id={oid}")
 assert len(rows)==1;row=rows[0]
 check(row['order_status']=='delivered','actual native email-code flow committed delivered status')
 check(row['eta_cleared']and all(row[k]==0 for k in('route_rows','location_rows','tracking_sessions','route_leases')),'terminal physical delivery clears route/ETA/live GPS/session/lease')
 token=b.login(state['accounts']['physical-customer']);code,r=edge(oid,token)
 check(code==403 and'route'not in r,'completed physical delivery cannot retrieve route')
 (OUT/'physical-terminal.json').write_text(json.dumps(checks,indent=2))

def physical_observe():
 oid=int(state['physical_order']['oid'])
 rows=db.query(f"select o.order_status,o.destination_source,o.destination_confirmed_at is not null as confirmed,o.route_estimated_arrival_at is not null as eta_persisted,l.received_at>clock_timestamp()-interval '30 seconds' as gps_fresh,l.accuracy<=100 as accurate,c.computed_at,c.data->>'source' as route_source,c.data->>'distanceMeters' as route_meters,c.data->>'durationSeconds' as route_seconds from public.orders o left join public.delivery_latest_locations l on l.order_id=o.id left join public.delivery_route_cache c on c.order_id=o.id where o.id={oid}")
 assert len(rows)==1
 record={'physical_order':oid,**rows[0],'observed_at':dt.datetime.now(dt.timezone.utc).isoformat()}
 record['quota']=db.query("select coalesce(sum(units),0)as reserved_credits,count(*)filter(where not settled)as unsettled_requests,min(reserved_at)filter(where not settled)as oldest_unsettled from fr14_private.quota_reservations where reserved_at>clock_timestamp()-interval '24 hours'")[0]
 with(OUT/'physical-observations.jsonl').open('a')as f:f.write(json.dumps(record)+'\n')
 print(json.dumps(record),flush=True)

def route_fixture():
 rider=state['accounts']['rider'];customer=state['accounts']['customer'];vendor=state['accounts']['vendor'];rt=b.login(rider);ct=b.login(customer);vt=b.login(vendor)
 # Only these synthetic accounts are touched. Coordinates are public-road test
 # inputs deliberately selected for this synthetic checkout, never device data.
 code,p=b.rpc('fr21_begin_presence',{},rt);assert code==200
 assert b.rpc('fr21_update_location',{'p_lat':33.7,'p_lng':73.05},rt)[0]in(200,204)
 code,p=b.rpc('fr21_set_presence',{'p_online':True,'p_epoch':p['epoch'],'p_sequence':1},rt);assert code==200 and p['is_online']
 code,rows=b.api('/rest/v1/vendors?user_id=eq.'+str(vendor['profile_id'])+'&select=id',admin=True);assert code==200
 if not rows:assert b.api('/rest/v1/vendors','POST',{'user_id':vendor['profile_id'],'store_name':'FR14 SYNTHETIC PICKUP','latitude':33.7,'longitude':73.05},admin=True)[0]==201
 if'product_id'not in state:
  code,r=b.rpc('fr17_save_product',{'p_request_id':str(uuid.uuid4()),'p_product_id':None,'p_data':{'name':'FR14 SYNTHETIC ROUTING TEST','price':80,'is_available':True},'p_stock':30,'p_threshold':5,'p_expected_version':None},vt)
  assert code==200 and r['code']=='UPDATED';state['product_id']=r['product_id'];save()
 if'order'not in state:
  delivery={'address':'FR14 SYNTHETIC CONFIRMED TEST PIN','lat':33.71,'lng':73.06,'speed':'standard','destination_confirmed':True,'destination_source':'map_pin'}
  code,r=b.rpc('fr10_checkout',{'p_request_id':str(uuid.uuid4()),'p_items':[{'product_id':state['product_id'],'quantity':1}],'p_delivery':delivery},ct);assert code==200 and r['code']=='PLACED';state['order']={'oid':r['order_id']};save()
  oid=r['order_id'];code,rows=b.api('/rest/v1/vendor_orders?order_id=eq.'+str(oid)+'&select=id',admin=True);assert code==200
  vo=rows[0]['id'];state['order']['vo']=vo;save()
  code,r=b.rpc('fr10_vendor_transition',{'p_vendor_order_id':vo,'p_status':'accepted'},vt);assert code==200 and r['code']in('ACCEPTED','UPDATED')
  code,r=b.rpc('fr21_ready_and_assign',{'p_vendor_order_id':vo},vt);assert code==200 and r.get('rider_id')==rider['profile_id'],'Exact synthetic rider required'
  state['order']['aid']=r['assignment_id'];save()
 return state['order'],rt,ct
def http_tests():
 row,rt,ct=route_fixture();oid=row['oid'];aid=row['aid']
 # The existing acceptance RPC, checklist and delivery start are used unchanged.
 current=db.query('select order_status from public.orders where id='+str(oid))[0]['order_status']
 if current!='on_the_way':
  code,r=b.rpc('fr21_accept_order',{'p_order_id':oid},rt)
  if code!=200 or r.get('order_status')!='ready':raise AssertionError('Assignment acceptance requires current accepted RPC contract')
 valid=[{'id':i,'confirmed':True}for i in('items_match','packaging_intact','details_confirmed')]
 code,r=b.rpc('submit_pre_delivery_checklist',{'p_assignment_id':aid,'p_version':1,'p_confirmations':valid},rt);assert code==200 and r['code']in('COMPLETED','ALREADY_COMPLETED')
 code,r=b.rpc('start_checklisted_delivery',{'p_assignment_id':aid},rt);assert code==200 and r['code']in('STARTED','ALREADY_STARTED')
 assert b.rpc('fr13_tracking_context',{'p_order_id':oid,'p_enable':True},rt)[1]['code']=='OK'
 gps={'order_id':oid,'latitude':33.7,'longitude':73.05,'accuracy':5,'device_at':dt.datetime.now(dt.timezone.utc).isoformat(),'request_id':str(uuid.uuid4())}
 code,r=b.api('/functions/v1/fr13-location','POST',gps,rt);check(code==200 and r['code']=='PUBLISHED','FR13 genuine authenticated synthetic GPS path still publishes')
 stop=threading.Event()
 def keep_gps():
  while not stop.wait(5):
   try:
    fix={**gps,'device_at':dt.datetime.now(dt.timezone.utc).isoformat(),'request_id':str(uuid.uuid4())}
    b.api('/functions/v1/fr13-location','POST',fix,rt)
   except Exception:pass
 updater=threading.Thread(target=keep_gps,daemon=True);updater.start()
 try:route_checks(oid,ct)
 finally:stop.set();updater.join(timeout=15)
def route_checks(oid,ct):
 code,r=edge(oid,ct);check(code==200 and r.get('code')=='OK'and r.get('route',{}).get('source')=='geoapify','customer receives actual provider road route')
 version=r['route']['routeVersion'];before=db.query('select count(*)as n from fr14_private.quota_reservations;')[0]['n']
 for label in('customer','rider','admin'):
  code,r=edge(oid,b.login(state['accounts'][label]));check(code==200 and (r.get('route')or{}).get('routeVersion')==version,label+' reuses authorized cache ('+str(r.get('code'))+')')
 check(db.query('select count(*)as n from fr14_private.quota_reservations;')[0]['n']==before,'cache hits do not call provider')
 for label in('other-customer','other-rider','vendor'):
  code,r=edge(oid,b.login(state['accounts'][label]));check(code==403 and'route'not in r,label+' cannot retrieve another order route')
 code,r=edge(oid,b.ANON);check(code==401,'anonymous route denied')
 rows=db.query('select route_estimated_arrival_at is not null as persisted,destination_source from public.orders where id='+str(oid))
 check(rows[0]['persisted']and rows[0]['destination_source']=='map_pin','confirmed checkout provenance and authoritative ETA persisted')
 customer_id=int(state['accounts']['customer']['profile_id'])
 try:
  db.query("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);update public.users set is_blocked=true where id="+str(customer_id)+";commit;")
  code,r=edge(oid,ct);check(code==403 and r.get('code')=='FR28_ACCOUNT_BLOCKED','FR28 blocked customer denied by deployed Edge boundary')
 finally:
  db.query("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);update public.users set is_blocked=false where id="+str(customer_id)+";commit;")
 (OUT/'hosted-http.json').write_text(json.dumps(checks,indent=2));save()
def regressions():
 # Older HTTP suites explicitly choose synthetic coordinates but predate the
 # confirmation field. Adapt their client inputs, never responses or assertions.
 original=urllib.request.Request
 class ConfirmedSyntheticRequest(original):
  def __init__(self,url,data=None,*args,**kwargs):
   if url=='https://igeisilhtmglgnqvllrx.supabase.co/rest/v1/rpc/fr10_checkout'and data:
    value=json.loads(data);delivery=value.get('p_delivery')
    if isinstance(delivery,dict)and delivery.get('lat')is not None and delivery.get('lng')is not None and'destination_source'not in delivery:
     delivery.update(destination_confirmed=True,destination_source='map_pin');data=json.dumps(value).encode()
   super().__init__(url,data,*args,**kwargs)
 urllib.request.Request=ConfirmedSyntheticRequest
 try:
  h.h.OUT=OUT
  profile=sys.argv[2]if len(sys.argv)>2 and sys.argv[2]else'FR21,FR04,FR25,FR26,FR33,FR28,FR20,FR30-sql,FR30-http,FR30-realtime,FR10,FR17'
  assert all(s in('FR21','FR04','FR25','FR26','FR33','FR28','FR20','FR30-sql','FR30-http','FR30-realtime','FR10','FR17')for s in profile.split(','))
  h.h.regressions(profile)
 finally:urllib.request.Request=original
if __name__=='__main__':
 assert b.REF=='igeisilhtmglgnqvllrx'
 {'deploy-function':deploy_function,'fixtures':setup,'http':http_tests,'regressions':regressions,'physical-accounts':physical_accounts,'physical-accept':physical_accept,'physical-assign':physical_assign,'physical-observe':physical_observe,'physical-security':physical_security,'physical-terminal':physical_terminal}[sys.argv[1]]()
