"""Unlinked local FR20 SQL/k6. No hosted key, data, link or load fallback."""
import base64,ctypes,hashlib,hmac,json,os,subprocess,sys,time,tomllib,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/fr20';STACK=OUT/'local-stack';PROJECT='tezrider-fr20-local'
CLI='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
DOCKER=str(Path(os.environ['LOCALAPPDATA'])/'Programs/DockerDesktop/resources/bin/docker.exe')

def guard():
 config=tomllib.loads((STACK/'supabase/config.toml').read_text(encoding='utf-8'))
 assert config['project_id']==PROJECT and config['api']['port']==54321 and not(STACK/'supabase/.temp/project-ref').exists(),'Unlinked FR20 local stack required'
def run(args,text=None):
 r=subprocess.run(args,input=text,capture_output=True,text=True,encoding='utf-8',timeout=120)
 assert r.returncode==0,'Isolated local command failed'
 return r.stdout
def sql(text):
 guard();return run([DOCKER,'exec','-i','supabase_db_'+PROJECT,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atq'],text)
def rules():
 output=sql((ROOT/'supabase/tests/FR-20.sql').read_text(encoding='utf-8'))
 rows=json.loads(next(x for x in output.splitlines()if x.startswith('[{')))
 result={'passed':len(rows),'rolled_back':True,'local_only':True};(OUT/'local-sql.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))
def jwt(identity,email,session,secret):
 def encode(obj):return base64.urlsafe_b64encode(json.dumps(obj,separators=(',',':')).encode()).decode().rstrip('=')
 header=encode({'alg':'HS256','typ':'JWT'});claims=encode({'aud':'authenticated','role':'authenticated','sub':identity,'email':email,'session_id':session,'iat':int(time.time()),'exp':int(time.time())+3600})
 signature=base64.urlsafe_b64encode(hmac.new(secret.encode(),(header+'.'+claims).encode(),hashlib.sha256).digest()).decode().rstrip('=')
 return header+'.'+claims+'.'+signature
def fixture(anon,secret):
 rows=[]
 for role in ['vendor','customer','admin']:
  identity=str(uuid.uuid4());session=str(uuid.uuid4());email='fr20-local-'+identity+'@example.test'
  text="begin;set local request.jwt.claims='{\"role\":\"service_role\"}';insert into auth.users(id,email,email_confirmed_at,role,aud,raw_user_meta_data)values('"+identity+"','"+email+"',now(),'authenticated','authenticated','{\"fr20_fixture\":true}');insert into public.users(email,name,role,verification_status)values('"+email+"','FR20 local synthetic','"+role+"','approved');insert into auth.sessions(id,user_id,created_at,updated_at)values('"+session+"','"+identity+"',now(),now());commit;select id from public.users where email='"+email+"';"
  profile=int(sql(text).splitlines()[-1]);rows.append((profile,jwt(identity,email,session,secret)))
 vendor,customer,admin=[r[0]for r in rows]
 # New local-only data. Each full run has its own vendor/coordinates/order pool.
 sql("insert into public.vendors(user_id,store_name,latitude,longitude)values("+str(vendor)+",'FR20 local synthetic',-60,-140);")
 text="""begin;set local request.jwt.claims='{"role":"service_role"}';
 do $$declare uid bigint;aid uuid;p extensions.geometry;begin
 for i in 1..120 loop
  aid:=gen_random_uuid();insert into auth.users(id,email,email_confirmed_at,role,aud)values(aid,'fr20-local-rider-'||aid||'@example.test',now(),'authenticated','authenticated');
  insert into public.users(email,name,role,verification_status)values('fr20-local-rider-'||aid||'@example.test','FR20 local synthetic rider','rider','approved')returning id into uid;
  p:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(-140,-60),4326)::extensions.geography,case when i<=60 then 4900 else 7000 end,0)::extensions.geometry;
  insert into public.riders(userid,is_online,is_available,isavailable,last_seen,latitude,longitude,location_updated_at)values(uid,true,true,true,clock_timestamp(),extensions.st_y(p),extensions.st_x(p),clock_timestamp());
 end loop;end$$;
 create temp table fr20_load_ids(id bigint);do $$declare o bigint;vo bigint;begin
 for i in 1..500 loop
 insert into public.orders(user_id,order_status,amount,delivery_address)values(CUSTOMER,'accepted',25,'FR20 LOCAL SYNTHETIC')returning id into o;
 insert into public.vendor_orders(order_id,vendor_id,status,sub_total)values(o,VENDOR,'accepted',25)returning id into vo;insert into fr20_load_ids values(vo);
 end loop;end$$;commit;select jsonb_agg(id)from fr20_load_ids;
 """.replace('CUSTOMER',str(customer)).replace('VENDOR',str(vendor))
 ids=json.loads(next(x for x in sql(text).splitlines()if x.startswith('[')))
 return {'synthetic_only':True,'project_ref':PROJECT,'anon_key':anon,'vendor_token':rows[0][1],'orders':ids,'vendor_id':vendor}
class Memory(ctypes.Structure):
 _fields_=[('length',ctypes.c_ulong),('load',ctypes.c_ulong),('total',ctypes.c_ulonglong),('available',ctypes.c_ulonglong),('page_total',ctypes.c_ulonglong),('page_available',ctypes.c_ulonglong),('virtual_total',ctypes.c_ulonglong),('virtual_available',ctypes.c_ulonglong),('extended',ctypes.c_ulonglong)]
def load(profile):
 guard()
 if profile=='full':
  m=Memory();m.length=ctypes.sizeof(m);assert ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
  if m.available<1024*1024*1024:
   result={'profile':'full','status':'NOT EXECUTED','reason':'Insufficient host memory for 1000 VUs; require 1 GiB available before starting','available_bytes':m.available,'required_available_bytes':1024*1024*1024}
   (OUT/'load-full-result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result));return
 status=json.loads(run([CLI,'status','--workdir',str(STACK),'--output','json']))
 assert status['API_URL']=='http://127.0.0.1:54321'
 container=json.loads(run([DOCKER,'inspect','supabase_auth_'+PROJECT]))[0];assert container['Name']=='/supabase_auth_'+PROJECT
 env=dict(x.split('=',1)for x in container['Config']['Env']if'='in x);data=fixture(status['ANON_KEY'],env['GOTRUE_JWT_SECRET'])
 private=Path(os.environ['LOCALAPPDATA'])/'TezRider-FR21/fr20-local-session.json';private.write_text(json.dumps(data),encoding='utf-8')
 executable=next((ROOT/'.fr21-local/fr04/k6').rglob('k6.exe'));summary=OUT/('local-'+profile+'-summary.json')
 runtime=dict(os.environ,FR20_LOCAL_URL=status['API_URL'],FR20_FIXTURE_FILE=str(private),FR20_LOAD_PROFILE=profile)
 for key in ['FR21_TEST_KEYS_JSON','FR21_PRIVATE_DIRECTORY']:runtime.pop(key,None)
 try:
  with(OUT/('local-'+profile+'.log')).open('w',encoding='utf-8')as log:
   process=subprocess.Popen([str(executable),'run','--summary-export',str(summary),str(ROOT/'tests/load/FR-20.js')],env=runtime,stdout=log,stderr=subprocess.STDOUT)
   minimum=None;aborted=False;start=time.monotonic()
   while process.poll()is None:
    m=Memory();m.length=ctypes.sizeof(m);assert ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    minimum=m.available if minimum is None else min(minimum,m.available)
    if m.available<256*1024*1024 or time.monotonic()-start>240:aborted=True;process.terminate();break
    time.sleep(1)
   code=process.wait(timeout=20)
  invariant=json.loads(sql("select jsonb_build_object('duplicate_rider',(select count(*)from(select riderid from public.rider_assignments where status in('Pending','Accepted')group by riderid having count(*)>1)s),'duplicate_order',(select count(*)from(select orderid from public.rider_assignments where status in('Pending','Accepted')group by orderid having count(*)>1)s),'duplicate_notification',(select count(*)from(select user_id,assignment_order_id,assignment_event from public.notifications where assignment_event is not null group by user_id,assignment_order_id,assignment_event having count(*)>1)s));").strip())
  metrics=json.loads(summary.read_text(encoding='utf-8'))['metrics']if summary.exists()else{}
  result={'profile':profile,'exit':code,'resource_aborted':aborted,'minimum_available_bytes':minimum,'invariants':invariant,'metrics':{k:metrics.get(k)for k in ['http_req_duration','unexpected_errors','checks','vus_max','http_reqs']}}
  (OUT/('load-'+profile+'-result.json')).write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))
 finally:private.unlink(missing_ok=True)
if __name__=='__main__':
 try:rules()if sys.argv[1]=='sql'else load(sys.argv[1])
 except Exception as e:print(json.dumps({'failed':1,'type':type(e).__name__,'reason':str(e)if isinstance(e,AssertionError)else 'Guarded local operation failed'}));sys.exit(1)
