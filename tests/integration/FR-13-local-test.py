"""Actual LOCAL HTTP/WebSocket proof; synthetic coordinates, not device evidence."""
import base64,hashlib,hmac,importlib.util,json,os,re,subprocess,sys,time,urllib.error,urllib.parse,urllib.request,uuid
from pathlib import Path
spec=importlib.util.spec_from_file_location('db',Path(__file__).with_name('FR-17-db.py'))
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
ROOT=d.ROOT;OUT=ROOT/'.fr21-local/fr13';FILE=OUT/'local-state.json';BASE='http://127.0.0.1:54321'
sys.path.insert(0,str(ROOT/'build/fr21-python'))
from websockets.sync.client import connect
def inspect(name):
 p=subprocess.run(['docker','inspect',name],capture_output=True,text=True,timeout=20);assert p.returncode==0
 return json.loads(p.stdout)[0]
def env(name):return dict(v.split('=',1)for v in inspect(name)['Config']['Env']if'='in v)
def credentials():
 config=subprocess.run(['docker','exec','supabase_kong_tezrider-fr30-local','cat','/home/kong/kong.yml'],capture_output=True,text=True,timeout=20);assert config.returncode==0
 keys={}
 for token in re.findall(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',config.stdout):
  claims=json.loads(base64.urlsafe_b64decode(token.split('.')[1]+'==='));keys[claims['role']]=token
 return keys,env('supabase_auth_tezrider-fr30-local')['GOTRUE_JWT_SECRET']
def wire(data):return base64.urlsafe_b64encode(data).decode().rstrip('=')
def api(path,body=None,token=None,base=BASE,method=None):
 headers={'apikey':state['keys']['anon'],'Authorization':'Bearer '+(token or state['keys']['anon']),'Content-Type':'application/json'}
 req=urllib.request.Request(base+path,data=json.dumps(body).encode()if body is not None else None,headers=headers,method=method)
 try:
  with urllib.request.urlopen(req,timeout=12)as response:return response.status,json.loads(response.read()or b'{}')
 except urllib.error.HTTPError as error:return error.code,json.loads(error.read()or b'{}')
def rpc(name,body,who='rider'):return api('/rest/v1/rpc/'+name,body,state['people'][who]['token'])
def prepare():
 assert not FILE.exists(),'Preserve previous LOCAL fixture; cleanup before another run'
 keys,secret=credentials();people={};run=str(uuid.uuid4());q='begin;create schema if not exists fr13_test;create table if not exists fr13_test.fixtures(run uuid,oid bigint,aid bigint,rid bigint);'
 for who in ['rider','other-rider','customer','other-customer','vendor','admin']:
  auth=str(uuid.uuid4());sid=str(uuid.uuid4());role=who.removeprefix('other-');mail=f'fr13-{who}-{run}@example.test'
  q+=f"insert into auth.users(id,email,email_confirmed_at,role,aud)values('{auth}','{mail}',now(),'authenticated','authenticated');insert into public.users(email,name,role,verification_status)values('{mail}','FR13 LOCAL SYNTHETIC','{role}','approved');insert into auth.sessions(id,user_id,created_at,updated_at)values('{sid}','{auth}',now(),now());"
  claims={'role':'authenticated','sub':auth,'session_id':sid,'aud':'authenticated','iss':'supabase-demo','iat':int(time.time()),'exp':int(time.time())+3600}
  raw=wire(b'{"alg":"HS256","typ":"JWT"}')+'.'+wire(json.dumps(claims).encode());people[who]={'auth':auth,'session':sid,'token':raw+'.'+wire(hmac.new(secret.encode(),raw.encode(),hashlib.sha256).digest())}
 rider=people['rider']['auth'];customer=people['customer']['auth']
 q+=f"do $$declare r bigint;c bigint;o bigint;a bigint;begin select id into r from public.users where auth_user_id='{rider}';select id into c from public.users where auth_user_id='{customer}';insert into public.riders(userid,is_online,is_available,isavailable,last_seen)values(r,true,false,false,clock_timestamp());insert into public.orders(user_id,rider_id,order_status,amount,payment_method,delivery_address)values(c,r,'ready',1,'COD','FR13 LOCAL SYNTHETIC')returning id into o;insert into public.rider_assignments(orderid,riderid,status)values(o,r,'Accepted')returning id into a;insert into fr13_test.fixtures values('{run}',o,a,r);end$$;commit;select row_to_json(f)from fr13_test.fixtures f where run='{run}';"
 result=d.local(q);record=json.loads(next(line for line in result.splitlines()if line.startswith('{')))
 data={'scope':'LOCAL only','run':run,'keys':keys,'people':people,**record};FILE.write_text(json.dumps(data))
 print('LOCAL synthetic users/assignment prepared; credentials suppressed; no email')
def edge():
 keys,_=credentials();e=os.environ.copy();e.update({'SUPABASE_URL':BASE,'SUPABASE_ANON_KEY':keys['anon'],'SUPABASE_SERVICE_ROLE_KEY':keys['service_role'],'FR13_LOCAL_TEST':'true'})
 p=subprocess.run(['C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/deno/deno.exe','run','--allow-env','--allow-net',str(ROOT/'supabase/functions/fr13-location/index.ts')],env=e)
 sys.exit(p.returncode)
checks=[]
def ok(value,label):
 assert value,label;checks.append({'result':'PASS','check':label});print(json.dumps(checks[-1]),flush=True)
def join(who,topic,private=True,selfsend=True):
 ws=connect('ws://127.0.0.1:54321/realtime/v1/websocket?'+urllib.parse.urlencode({'apikey':state['keys']['anon'],'vsn':'1.0.0'}),open_timeout=12,close_timeout=2)
 ws.send(json.dumps({'topic':'realtime:'+topic,'event':'phx_join','ref':'1','payload':{'config':{'private':private,'broadcast':{'ack':True,'self':selfsend},'presence':{'key':''},'postgres_changes':[]},'access_token':state['people'][who]['token']}}))
 until=time.monotonic()+15
 while time.monotonic()<until:
  row=json.loads(ws.recv(timeout=15))
  if row['event']=='phx_reply'and row.get('ref')=='1':return ws,row['payload']['status']=='ok'
 raise AssertionError('LOCAL join outcome not confirmed')
def events(ws,seconds):
 rows=[];until=time.monotonic()+seconds
 while time.monotonic()<until:
  try:r=json.loads(ws.recv(timeout=max(.1,until-time.monotonic())))
  except TimeoutError:break
  if r['event']=='broadcast'and r['payload'].get('event')=='location':rows.append(r['payload']['payload'])
 return rows
def tests():
 oid=state['oid'];aid=state['aid'];token=state['people']['rider']['token'];sockets=[]
 code,p=rpc('fr21_begin_presence',{});assert code==200
 code,r=rpc('fr21_set_presence',{'p_online':True,'p_epoch':p['epoch'],'p_sequence':1});assert code==200 and r['is_online']
 valid=[{'id':i,'confirmed':True}for i in('items_match','packaging_intact','details_confirmed')]
 code,r=rpc('submit_pre_delivery_checklist',{'p_assignment_id':aid,'p_version':1,'p_confirmations':valid});ok(code==200 and r['code']=='COMPLETED','real LOCAL checklist submission')
 code,r=rpc('start_checklisted_delivery',{'p_assignment_id':aid});ok(code==200 and r['code']=='STARTED','real LOCAL guarded start')
 code,r=rpc('fr13_tracking_context',{'p_order_id':oid,'p_enable':True});ok(code==200 and r['code']=='OK','real LOCAL enabled context');topic=r['topic']
 try:
  for who in ['rider','customer','admin']:
   ws,allowed=join(who,topic);sockets.append(ws);ok(allowed,who+' private channel authorized')
  own=sockets[1]
  for who in ['other-customer','other-rider','vendor']:
   ws,allowed=join(who,topic);sockets.append(ws);ok(not allowed,who+' private channel denied')
   ws,allowed=join(who,topic,selfsend=False);sockets.append(ws);ok(not allowed,who+' private channel denied with self disabled')
  public,allowed=join('other-customer',topic,False);sockets.append(public);ok(allowed,'public channel decoy joined separately')
  payload={'order_id':oid,'latitude':33.7,'longitude':73.05,'accuracy':5,'device_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'request_id':str(uuid.uuid4())}
  before=time.monotonic();code,r=api('',payload,token,base='http://127.0.0.1:54328');ok(code==200 and r['code']=='PUBLISHED','actual Edge validates and REST Broadcast publishes')
  delivered=events(own,1);ok(len(delivered)==1 and delivered[0]['assignment_id']==aid,'authorized customer actually receives location');latency=(time.monotonic()-before)*1000
  ok(events(public,.3)==[],'public decoy receives no private GPS')
  for who,ws in zip(['rider','customer','admin'],sockets[:3]):
   ws.send(json.dumps({'topic':'realtime:'+topic,'event':'broadcast','ref':'publish','payload':{'type':'broadcast','event':'location','payload':{'forged':True}}}))
  ok(events(own,.5)==[],'direct client GPS publishing cannot reach customer')
  for who in('rider','customer','other-customer'):
   code,r=api('/realtime/v1/api/broadcast',{'messages':[{'topic':topic,'event':'location','payload':{'forged':True},'private':True}]},state['people'][who]['token'])
   received=events(own,.5)
   print(json.dumps({'direct_rest_actor':who,'http_status':code,'received_events':len(received),'forged_events':sum(row.get('forged')is True for row in received)}),flush=True)
   ok(received==[],who+' direct REST Broadcast cannot reach customer')
  code,r=api('',payload,token,base='http://127.0.0.1:54328');ok(code==200 and r['code']=='REPLAYED','actual retry does not duplicate broadcast')
  code,r=rpc('fr13_tracking_context',{'p_order_id':oid,'p_enable':False});ok(code==200 and r['code']=='STOPPED','explicit stop closes active session')
  ws,allowed=join('customer',topic);sockets.append(ws);ok(not allowed,'ended topic cannot rejoin')
  code,r=api('',{**payload,'request_id':str(uuid.uuid4())},token,base='http://127.0.0.1:54328');ok(code==200 and r['code']=='SHARING_STOPPED','server publishes nothing after stop')
  ok(events(own,.3)==[],'old cached subscriber receives no new locations after stop')
  (OUT/'local-realtime.json').write_text(json.dumps({'passed':len(checks),'checks':checks,'actual_websocket':True,'latency_upper_bound_ms':latency,'coordinates':'synthetic LOCAL only'},indent=2))
 finally:
  for ws in sockets:ws.close()
mode=sys.argv[1]
if mode=='prepare':prepare()
elif mode=='edge':edge()
else:
 state=json.loads(FILE.read_text());assert state['scope']=='LOCAL only'
 if mode=='test':tests()
 elif mode=='cleanup':
  run=str(uuid.UUID(state['run']));d.local("update public.orders set order_status='cancelled'where id in(select oid from fr13_test.fixtures where run='"+run+"')and delivery_address='FR13 LOCAL SYNTHETIC'and order_status not in('delivered','cancelled');")
  d.local("update public.rider_assignments set status='Cancelled'where orderid in(select oid from fr13_test.fixtures where run='"+run+"')and status in('Pending','Accepted');")
  FILE.unlink();print('Only marked LOCAL fixture closed; private token file removed')
 else:raise ValueError('Unsupported safe mode')
