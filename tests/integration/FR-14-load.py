"""LOCAL-only HTTP load runner; no hosted traffic or real routing requests."""
import base64,hashlib,hmac,importlib.util,json,os,subprocess,sys,time,urllib.request,threading,datetime as dt
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/fr14'
path=ROOT/'tests/integration/FR-13-local-test.py';source=path.read_text().split('mode=sys.argv[1]',1)[0]
scope={'__file__':str(path)};exec(compile(source,str(path),'exec'),scope)
d=scope['d'];wire=scope['wire'];keys,secret=scope['credentials']()
sql=(ROOT/'supabase/tests/FR-14.sql').read_text().split('do $$declare f fr14_fixture;who',1)[0]
sql+="select jsonb_build_object('fixture',(select row_to_json(f)from fr14_fixture f),'people',(select json_agg(p)from fr14_people p));commit;"
data=json.loads(next(s for s in d.local(sql).splitlines()if s.startswith('{')))
fixture=data['fixture'];oid=fixture['oid']
# GoTrue's user lookup includes the default instance. Raw SQL fixtures used by
# PostgREST tests do not populate it automatically.
ids=','.join("'"+str(scope['uuid'].UUID(p['auth_id']))+"'"for p in data['people'])
d.local("update auth.users set instance_id='00000000-0000-0000-0000-000000000000',created_at=clock_timestamp(),updated_at=clock_timestamp(),confirmation_token='',recovery_token='',email_change_token_new='',email_change='',email_change_token_current='',phone_change='',phone_change_token='',reauthentication_token='',encrypted_password='',raw_app_meta_data='{\"provider\":\"email\",\"providers\":[\"email\"]}',raw_user_meta_data='{\"fr14_fixture\":true}',is_super_admin=false,is_sso_user=false,is_anonymous=false where id in("+ids+');')
def token(label):
 p=next(p for p in data['people']if p['label']==label)
 claims={'role':'authenticated','sub':p['auth_id'],'session_id':p['session_id'],'aud':'authenticated','iss':'http://127.0.0.1:54321/auth/v1','iat':int(time.time()),'exp':int(time.time())+600}
 raw=wire(b'{"alg":"HS256","typ":"JWT"}')+'.'+wire(json.dumps(claims).encode())
 return raw+'.'+wire(hmac.new(secret.encode(),raw.encode(),hashlib.sha256).digest())
mode=sys.argv[2]if len(sys.argv)>2 else'normal'
assert mode in('normal','failure')
private=OUT/'load-private.json';log=(OUT/('load-server-'+mode+'.log')).open('w');server=None;stop=threading.Event();updater=None
try:
 private.write_text(json.dumps({'scope':'LOCAL only','base':'http://127.0.0.1:54330','customer':token('customer'),'other':token('other-customer'),'order':oid,'output':str(OUT/('load-results-'+mode+'.json'))}))
 def keep_gps():
  while not stop.is_set():
   body={'p_order_id':oid,'p_lat':33.7,'p_lng':73.05,'p_accuracy':5,'p_device_at':dt.datetime.now(dt.timezone.utc).isoformat(),'p_request_id':str(scope['uuid'].uuid4())}
   req=urllib.request.Request('http://127.0.0.1:54321/rest/v1/rpc/fr13_submit_location',data=json.dumps(body).encode(),headers={'apikey':keys['anon'],'Authorization':'Bearer '+token('rider'),'Content-Type':'application/json'})
   try:urllib.request.urlopen(req,timeout=5).close()
   except Exception:pass
   stop.wait(3)
 updater=threading.Thread(target=keep_gps,daemon=True);updater.start()
 req=urllib.request.Request('http://127.0.0.1:54321/rest/v1/rpc/fr14_route_context',data=json.dumps({'p_order_id':oid}).encode(),headers={'apikey':keys['anon'],'Authorization':'Bearer '+token('customer'),'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(req,timeout=10)as r:print(json.dumps({'local_context_status':r.status,'code':json.load(r).get('code')}))
 except Exception as e:
  body=json.loads(e.read())if hasattr(e,'read')else{}
  print(json.dumps({'local_context_status':getattr(e,'code',0),'code':body.get('code'),'message':body.get('message')}))
 req=urllib.request.Request('http://127.0.0.1:54321/auth/v1/user',headers={'apikey':keys['anon'],'Authorization':'Bearer '+token('customer')})
 try:
  with urllib.request.urlopen(req,timeout=10)as r:print(json.dumps({'local_auth_status':r.status}))
 except Exception as e:
  body=json.loads(e.read())if hasattr(e,'read')else{}
  print(json.dumps({'local_auth_status':getattr(e,'code',0),'code':body.get('code'),'message':body.get('msg')or body.get('message')}))
 env={**os.environ,'SUPABASE_URL':'http://127.0.0.1:54321','SUPABASE_ANON_KEY':keys['anon'],'SUPABASE_SERVICE_ROLE_KEY':keys['service_role'],'FR14_MOCK_FAILURE':'true'if mode=='failure'else'false'}
 deno='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/deno/deno.exe'
 server=subprocess.Popen([deno,'run','--allow-env','--allow-net',str(ROOT/'tests/load/FR-14-harness.ts')],env=env,stdout=log,stderr=log)
 for _ in range(30):
  try:urllib.request.urlopen('http://127.0.0.1:54330/stats',timeout=1);break
  except Exception:time.sleep(.5)
 env={**os.environ,'FR14_LOAD_CONFIG':str(private),'FR14_VUS':sys.argv[1]if len(sys.argv)>1 else'10'}
 p=subprocess.run(['node',str(ROOT/'tests/load/FR-14.js')],env=env,capture_output=True,text=True,timeout=120)
 print(p.stdout);assert p.returncode==0,'Local load target failed; result retained'
finally:
 stop.set()
 if updater:updater.join(timeout=6)
 if server:server.terminate();server.wait(timeout=10)
 log.close();private.unlink(missing_ok=True)
 # This single reservation belongs to this mock-only local fixture. No provider
 # was called; remove it as test teardown, never refund real/hosted API usage.
 d.local(f"begin;delete from fr14_private.quota_reservations where token in(select token from fr14_private.attempts where order_id={oid});update public.orders set order_status='cancelled'where id={oid} and delivery_address='FR14 SQL SYNTHETIC';update public.rider_assignments set status='Cancelled'where orderid={oid};commit;")
