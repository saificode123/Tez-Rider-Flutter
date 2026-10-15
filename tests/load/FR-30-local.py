"""Unlinked local FR30 SQL/k6. No hosted key, data, link or load fallback."""
import base64,ctypes,hashlib,hmac,json,os,subprocess,sys,time,tomllib,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/fr30';STACK=OUT/'local-stack';PROJECT='tezrider-fr30-local'
CLI='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
DOCKER=str(Path(os.environ['LOCALAPPDATA'])/'Programs/DockerDesktop/resources/bin/docker.exe')

def guard():
 config=tomllib.loads((STACK/'supabase/config.toml').read_text(encoding='utf-8'))
 assert config['project_id']==PROJECT and config['api']['port']==54321 and not(STACK/'supabase/.temp/project-ref').exists(),'Unlinked FR30 local stack required'
def run(args,text=None):
 r=subprocess.run(args,input=text,capture_output=True,text=True,encoding='utf-8',timeout=120)
 assert r.returncode==0,'Isolated local command failed'
 return r.stdout
def sql(text):
 guard();return run([DOCKER,'exec','-i','supabase_db_'+PROJECT,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atq'],text)
def rules():
 output=sql((ROOT/'supabase/tests/FR-30.sql').read_text(encoding='utf-8'))
 rows=json.loads(next(x for x in output.splitlines()if x.startswith('[{')))
 result={'passed':len(rows),'rolled_back':True,'local_only':True};(OUT/'local-sql.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))
def jwt(identity,email,session,secret):
 def encode(obj):return base64.urlsafe_b64encode(json.dumps(obj,separators=(',',':')).encode()).decode().rstrip('=')
 header=encode({'alg':'HS256','typ':'JWT'});claims=encode({'aud':'authenticated','role':'authenticated','sub':identity,'email':email,'session_id':session,'iat':int(time.time()),'exp':int(time.time())+3600})
 signature=base64.urlsafe_b64encode(hmac.new(secret.encode(),(header+'.'+claims).encode(),hashlib.sha256).digest()).decode().rstrip('=')
 return header+'.'+claims+'.'+signature
class Memory(ctypes.Structure):
 _fields_=[('length',ctypes.c_ulong),('load',ctypes.c_ulong),('total',ctypes.c_ulonglong),('available',ctypes.c_ulonglong),('page_total',ctypes.c_ulonglong),('page_available',ctypes.c_ulonglong),('virtual_total',ctypes.c_ulonglong),('virtual_available',ctypes.c_ulonglong),('extended',ctypes.c_ulonglong)]

def memory():
 m=Memory();m.length=ctypes.sizeof(m);assert ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m));return m.available

def fixture(anon,secret):
 rows=json.loads(sql("""begin;set local request.jwt.claims='{"role":"service_role"}';
 create temp table fr30_local_people(id bigint,auth_id uuid,session_id uuid,email text,role text);
 do $$declare aid uuid;sid uuid;uid bigint;email text;r text;begin
 for i in 0..1000 loop
 aid:=gen_random_uuid();sid:=gen_random_uuid();email:='fr30-local-'||aid||'@example.test';r:=case when i=0 then 'admin'else 'customer'end;
 insert into auth.users(id,email,email_confirmed_at,role,aud,raw_user_meta_data)values(aid,email,now(),'authenticated','authenticated','{"fr30_fixture":true}');
 insert into public.users(email,name,role,verification_status)values(email,'FR30 local synthetic',r,'approved')returning id into uid;
 insert into auth.sessions(id,user_id,created_at,updated_at)values(sid,aid,now(),now());
 insert into fr30_local_people values(uid,aid,sid,email,r);
 end loop;end$$;commit;select jsonb_agg(t)from fr30_local_people t;""").strip())
 for row in rows:row['token']=jwt(row['auth_id'],row['email'],row['session_id'],secret)
 admin=next(r for r in rows if r['role']=='admin');recipients=[{'id':r['id'],'token':r['token']}for r in rows if r['role']=='customer']
 # This fresh stack may contain earlier own load fixtures. Target ALL customers
 # deliberately, and calculate expected count from its entirely synthetic schema.
 count=int(sql("select count(*)from public.users where role='customer'and not is_blocked;").strip())
 return {'synthetic_only':True,'project_ref':PROJECT,'anon_key':anon,'admin_token':admin['token'],'recipients':recipients,'recipient_count':count,
  'request':{'p_request_id':str(uuid.uuid4()),'p_title':'FR30 local load','p_message':'Local synthetic load only.','p_audience':'CUSTOMERS'}}

def load(profile):
 guard();available=memory()
 if profile=='full'and available<1024*1024*1024:
  result={'profile':'full','status':'NOT EXECUTED','reason':'Require 1 GiB available host RAM for safe 1000 VU preflight','available_bytes':available,'required_available_bytes':1024*1024*1024}
  (OUT/'load-full-result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result));return
 status=json.loads(run([CLI,'status','--workdir',str(STACK),'--output','json']));assert status['API_URL']=='http://127.0.0.1:54321'
 container=json.loads(run([DOCKER,'inspect','supabase_auth_'+PROJECT]))[0];assert container['Name']=='/supabase_auth_'+PROJECT
 env=dict(v.split('=',1)for v in container['Config']['Env']if'='in v)
 data=fixture(status['ANON_KEY'],env['GOTRUE_JWT_SECRET']);before=int(sql("select pg_total_relation_size('public.notifications');").strip())
 private=Path(os.environ['LOCALAPPDATA'])/'TezRider-FR21/fr30-local-session.json';private.write_text(json.dumps(data),encoding='utf-8')
 executable=next((ROOT/'.fr21-local/fr04/k6').rglob('k6.exe'));run_id=uuid.uuid4().hex
 summary=OUT/('local-'+profile+'-'+run_id+'-summary.json')
 runtime=dict(os.environ,FR30_LOCAL_URL=status['API_URL'],FR30_FIXTURE_FILE=str(private),FR30_LOAD_PROFILE=profile)
 for key in ['FR21_TEST_KEYS_JSON','FR21_PRIVATE_DIRECTORY']:runtime.pop(key,None)
 try:
  with(OUT/('local-'+profile+'.log')).open('w',encoding='utf-8')as log:
   process=subprocess.Popen([str(executable),'run','--summary-export',str(summary),str(ROOT/'tests/load/FR-30.js')],env=runtime,stdout=log,stderr=subprocess.STDOUT)
   minimum=available;aborted=False;start=time.monotonic()
   while process.poll()is None:
    current=memory();minimum=min(minimum,current)
    if current<256*1024*1024 or time.monotonic()-start>240:aborted=True;process.terminate();break
    time.sleep(1)
   code=process.wait(timeout=20)
  bid=data['request']['p_request_id']
  invariant=json.loads(sql("select jsonb_build_object('broadcasts',(select count(*)from public.admin_broadcasts where id='"+bid+"'),'notifications',(select count(*)from public.notifications where broadcast_id='"+bid+"'),'audits',(select count(*)from public.security_audit_log where broadcast_id='"+bid+"'),'duplicate_recipients',(select count(*)from(select user_id from public.notifications where broadcast_id='"+bid+"'group by user_id having count(*)>1)s),'notification_payload_bytes',(select sum(pg_column_size(n))from public.notifications n where broadcast_id='"+bid+"'),'notification_relation_bytes',pg_total_relation_size('public.notifications'));").strip())
  invariant['notification_relation_growth_bytes']=invariant['notification_relation_bytes']-before
  metrics=json.loads(summary.read_text(encoding='utf-8'))['metrics']if summary.exists()and not aborted else{}
  result={'profile':profile,'exit':code,'resource_aborted':aborted,'minimum_available_bytes':minimum,'invariants':invariant,'notification_insert_events':invariant['notifications'],'transmitted_realtime_events':'NOT MEASURED: local Realtime excluded; hosted receipt separately verified','metrics':{k:metrics.get(k)for k in ['http_req_duration','notification_read_ms','unread_count_ms','broadcast_acceptance_ms','unexpected_errors','checks','vus_max','http_reqs']}}
  (OUT/('load-'+profile+'-'+run_id+'-result.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
  (OUT/('load-'+profile+'-result.json')).write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))
  if code!=0:raise AssertionError('Local load resource-aborted'if aborted else 'Local load thresholds failed')
 finally:private.unlink(missing_ok=True)

def races():
 import concurrent.futures,threading,urllib.request
 guard();status=json.loads(run([CLI,'status','--workdir',str(STACK),'--output','json']))
 container=json.loads(run([DOCKER,'inspect','supabase_auth_'+PROJECT]))[0]
 env=dict(v.split('=',1)for v in container['Config']['Env']if'='in v)
 rows=json.loads(sql("""begin;set local request.jwt.claims='{"role":"service_role"}';
 create temp table fr30_race_people(auth_id uuid,session_id uuid,email text);
 do $$declare aid uuid;sid uuid;e text;begin for i in 1..2 loop
 aid:=gen_random_uuid();sid:=gen_random_uuid();e:='fr30-race-'||aid||'@example.test';
 insert into auth.users(id,email,email_confirmed_at,role,aud)values(aid,e,now(),'authenticated','authenticated');
 insert into public.users(email,name,role,verification_status)values(e,'FR30 local synthetic admin','admin','approved');
 insert into auth.sessions(id,user_id,created_at,updated_at)values(sid,aid,now(),now());
 insert into fr30_race_people values(aid,sid,e);end loop;end$$;
 commit;select jsonb_agg(t)from fr30_race_people t;""").strip())
 barrier=threading.Barrier(2)
 def send(row):
  token=jwt(row['auth_id'],row['email'],row['session_id'],env['GOTRUE_JWT_SECRET']);bid=str(uuid.uuid4())
  req=urllib.request.Request('http://127.0.0.1:54321/rest/v1/rpc/admin_send_broadcast',data=json.dumps({'p_request_id':bid,'p_title':'Concurrent ALL','p_message':'Local two administrators.','p_audience':'ALL'}).encode(),headers={'apikey':status['ANON_KEY'],'Authorization':'Bearer '+token,'Content-Type':'application/json'},method='POST')
  barrier.wait(timeout=10)
  with urllib.request.urlopen(req,timeout=20)as response:return json.load(response)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as executor:results=list(executor.map(send,rows))
 assert all(r['code']=='SENT'for r in results),'Both ALL broadcasts must commit without FK/sender deadlock'
 assert len({r['id']for r in results})==2
 result={'passed':2,'real_concurrent_sessions':True,'local_only':True,'both_admins_send_ALL':'SENT','retryable_deadlocks':0}
 (OUT/'local-admin-races.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))

if __name__=='__main__':
 try:rules()if sys.argv[1]=='sql'else races()if sys.argv[1]=='races'else load(sys.argv[1])
 except Exception as e:print(json.dumps({'failed':1,'type':type(e).__name__,'reason':str(e)if isinstance(e,AssertionError)else 'Guarded local operation failed'}));sys.exit(1)
