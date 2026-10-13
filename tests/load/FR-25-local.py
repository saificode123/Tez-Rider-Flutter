"""Prepare/run k6 only against an unlinked isolated local Supabase stack.

Synthetic confirmed Auth identities and delivered orders are owner-created test
fixtures. Every evidence file then passes the real authenticated Edge decoder.
No hosted keys, user records, schema reset, rate-limit change or paid service.
"""
import base64,concurrent.futures,ctypes,hashlib,hmac,io,json,os,subprocess,sys,time,tomllib,urllib.request,urllib.error,uuid
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/fr25';STACK=OUT/'local-stack'
CLI=Path('C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe')
DOCKER=Path(os.environ['LOCALAPPDATA'])/'Programs/DockerDesktop/resources/bin/docker.exe'
PRIVATE=Path(os.environ['LOCALAPPDATA'])/'TezRider-FR21'
PROJECT='tezrider-fr25-local';BASE='http://127.0.0.1:54321'
def guard():
 config=tomllib.loads((STACK/'supabase/config.toml').read_text())
 assert config['project_id']==PROJECT and config['api']['port']==54321,'Wrong isolated stack'
 assert not (STACK/'supabase/.temp/project-ref').exists(),'Local stack must be unlinked'
 assert BASE=='http://127.0.0.1:54321'
def run(command,input=None):
 result=subprocess.run(command,input=input,capture_output=True,text=True,encoding='utf-8',timeout=120)
 if result.returncode:raise RuntimeError('Isolated local operation failed; no hosted fallback is permitted')
 return result.stdout
def keys():
 guard();raw=run([str(CLI),'status','--workdir',str(STACK),'--output','json']);data=json.loads(raw[raw.index('{'):])
 assert data['API_URL']==BASE,'CLI must report loopback API'
 raw=run([str(DOCKER),'inspect','supabase_auth_'+PROJECT]);container=json.loads(raw)[0]
 assert container['Name']=='/supabase_auth_'+PROJECT
 env=dict(line.split('=',1) for line in container['Config']['Env'] if '=' in line)
 return data['ANON_KEY'],env['GOTRUE_JWT_SECRET']
def token(auth_id,email,secret):
 def encode(value):return base64.urlsafe_b64encode(json.dumps(value,separators=(',',':')).encode()).decode().rstrip('=')
 header=encode({'alg':'HS256','typ':'JWT'});claims=encode({'aud':'authenticated','role':'authenticated','sub':auth_id,'email':email,'iss':'supabase','iat':int(time.time()),'exp':int(time.time())+3600})
 signature=base64.urlsafe_b64encode(hmac.new(secret.encode(),(header+'.'+claims).encode(),hashlib.sha256).digest()).decode().rstrip('=')
 return header+'.'+claims+'.'+signature
def api(path,body,anon,bearer):
 guard()
 for attempt in range(3):
  request=urllib.request.Request(BASE+path,data=json.dumps(body).encode(),headers={'apikey':anon,'Authorization':'Bearer '+bearer,'Content-Type':'application/json'})
  try:
   with urllib.request.urlopen(request,timeout=45) as response:return json.load(response)
  except urllib.error.HTTPError as e:
   if e.code<500:raise RuntimeError('Local fixture rejected: HTTP '+str(e.code))
  except (urllib.error.URLError,TimeoutError):pass
  time.sleep(.4*(2**attempt))
 raise RuntimeError('Local fixture operation was not confirmed: '+path)
def bootstrap(count):
 guard();assert 1<=count<=1000
 query="""begin;
do $$ declare i integer; fixture_email text; aid uuid; actor bigint; begin
 for i in 1..COUNT loop
  fixture_email:='fr25-local-'||i||'@example.test';
  select id into aid from auth.users where auth.users.email=fixture_email and raw_user_meta_data->>'fr25_fixture'='true';
  if aid is null then
   aid:=gen_random_uuid();
   insert into auth.users(id,instance_id,email,email_confirmed_at,role,aud,raw_user_meta_data)
    values(aid,'00000000-0000-0000-0000-000000000000',fixture_email,now(),'authenticated','authenticated','{"fr25_fixture":true,"role":"customer"}'::jsonb);
  end if;
  -- GoTrue expects these string fields to be empty, not SQL NULL. These are
  -- only tagged synthetic fixtures in this unlinked local database.
  update auth.users set confirmation_token='',recovery_token='',email_change_token_new='',email_change_token_current='',
    email_change='',reauthentication_token='',phone_change='',phone_change_token='',encrypted_password='',
    created_at=coalesce(created_at,now()),updated_at=now(),raw_app_meta_data='{"provider":"email","providers":["email"]}'::jsonb
    where id=aid and raw_user_meta_data->>'fr25_fixture'='true';
  select id into actor from public.users where public.users.email=fixture_email;
  if actor is null then insert into public.users(email,name,role,verification_status)values(fixture_email,'FR25 local synthetic','customer','pending')returning id into actor;end if;
  if not exists(select 1 from public.orders where user_id=actor and delivery_address='FR25 LOCAL SYNTHETIC') then
   insert into public.orders(user_id,amount,order_status,delivery_address)values(actor,1,'delivered','FR25 LOCAL SYNTHETIC');end if;
 end loop;
 -- Include a genuine approved synthetic admin recipient in the write load.
 if not exists(select 1 from auth.users where email='fr25-local-admin@example.test') then
  insert into auth.users(id,email,email_confirmed_at,role,aud,raw_user_meta_data)
   values(gen_random_uuid(),'fr25-local-admin@example.test',now(),'authenticated','authenticated','{"fr25_fixture":true,"role":"admin"}'::jsonb);
 end if;
 insert into public.users(email,name,role,verification_status)
 values('fr25-local-admin@example.test','FR25 local synthetic admin','admin','approved') on conflict(email)do nothing;
end $$;
commit;
select jsonb_agg(jsonb_build_object('auth_id',a.id,'email',a.email,'order_id',o.id))
 from auth.users a join public.users u on u.email=a.email join public.orders o on o.user_id=u.id
 where a.raw_user_meta_data->>'fr25_fixture'='true' and a.email like 'fr25-local-%@example.test' and o.delivery_address='FR25 LOCAL SYNTHETIC';
""".replace('COUNT',str(count))
 raw=run([str(DOCKER),'exec','-i','supabase_db_'+PROJECT,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atq'],query)
 rows=json.loads(next(line for line in raw.splitlines() if line.startswith('[')))
 assert len(rows)==count,'Wrong local fixture count';return rows
def prepare():
 anon,secret=keys();rows=bootstrap(1000)
 picture=Image.new('RGB',(120,70),'green');ImageDraw.Draw(picture).text((3,20),'FR25 LOCAL TEST',fill='white');buffer=io.BytesIO();picture.save(buffer,format='PNG');encoded=base64.b64encode(buffer.getvalue()).decode()
 # Request IDs are durable metadata; JWTs and signing secrets stay in memory.
 file=OUT/'local-fixture-metadata.json';existing=json.loads(file.read_text()) if file.exists() else {}
 ids={r['auth_id']:existing.get(r['auth_id'],str(uuid.uuid4())) for r in rows};file.write_text(json.dumps(ids))
 def one(row):
  bearer=token(row['auth_id'],row['email'],secret);rid=ids[row['auth_id']]
  status=api('/rest/v1/rpc/fr25_request_status',{'p_request_id':rid},anon,bearer)
  if status is not None:raise RuntimeError('Existing load fixture is already submitted. Reuse it only for explicit idempotency qualification, not fresh creation.')
  api('/rest/v1/rpc/fr25_prepare',{'p_request_id':rid,'p_order_id':row['order_id']},anon,bearer)
  result=api('/functions/v1/fr25-evidence',{'action':'upload','request_id':rid,'mime_type':'image/png','image_base64':encoded},anon,bearer)
  return {'auth_id':row['auth_id'],'email':row['email'],'order_id':row['order_id'],'request_id':rid,'paths':[result['path']]}
 prepared=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
  for result in pool.map(one,rows):
   prepared.append(result)
   if len(prepared)%50==0:print('Prepared local synthetic customers:',len(prepared),flush=True)
 (OUT/'local-prepared.json').write_text(json.dumps(prepared))
 print('All 1000 local synthetic evidence uploads confirmed',flush=True)
def load():
 anon,secret=keys();rows=json.loads((OUT/'local-prepared.json').read_text());assert len(rows)==1000
 fixtures={'project_id':PROJECT,'anon_key':anon,'accounts':[]}
 for row in rows:
  fixtures['accounts'].append({'token':token(row['auth_id'],row['email'],secret),'submissions':[{
   'request_id':row['request_id'],'order_id':row['order_id'],'reason':'Other','description':'FR25 LOCAL SYNTHETIC EVIDENCE',
   'paths':row['paths'],'negative_request_id':str(uuid.uuid4())}]})
 bootstrap(1000)
 PRIVATE.mkdir(exist_ok=True);file=PRIVATE/'fr25-local-k6-session.json';file.write_text(json.dumps(fixtures))
 executable=next((ROOT/'.fr21-local/fr04/k6').rglob('k6.exe'))
 env=dict(os.environ);env.update(FR25_LOCAL_URL=BASE,FR25_FIXTURE_FILE=str(file))
 for name in ['FR21_TEST_KEYS_JSON','FR21_PRIVATE_DIRECTORY']:env.pop(name,None)
 try:
  guard()
  with (OUT/'local-load.log').open('w') as log:
   process=subprocess.Popen([str(executable),'run','--summary-export',str(OUT/'local-load-summary.json'),str(ROOT/'tests/load/FR-25.js')],env=env,stdout=log,stderr=subprocess.STDOUT)
   class Memory(ctypes.Structure):
    _fields_=[('length',ctypes.c_ulong),('load',ctypes.c_ulong),('total',ctypes.c_ulonglong),('available',ctypes.c_ulonglong),('page_total',ctypes.c_ulonglong),('page_available',ctypes.c_ulonglong),('virtual_total',ctypes.c_ulonglong),('virtual_available',ctypes.c_ulonglong),('extended',ctypes.c_ulonglong)]
   started=time.monotonic();minimum=None;aborted=False
   while process.poll() is None:
    memory=Memory();memory.length=ctypes.sizeof(memory)
    if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(memory)):
     minimum=memory.available if minimum is None else min(minimum,memory.available)
     if memory.available<150*1024*1024:
      aborted=True;process.terminate();break
    if time.monotonic()-started>600:aborted=True;process.terminate();break
    time.sleep(3)
   code=process.wait(timeout=30)
  (OUT/'local-load-result.json').write_text(json.dumps({'exit':code,'target_vus':1000,'project_id':PROJECT,'aborted_for_resource_safety':aborted,'minimum_available_bytes':minimum},indent=2))
  print('Isolated k6 exit:',code,'resource safety abort:',aborted);sys.exit(code if code else (1 if aborted else 0))
 finally:file.unlink(missing_ok=True)
if __name__=='__main__':
 try:{'prepare':prepare,'load':load}[sys.argv[1]]()
 except Exception as e:print(json.dumps({'result':'FAILED','reason':str(e) if isinstance(e,(AssertionError,RuntimeError)) else type(e).__name__}));sys.exit(1)
