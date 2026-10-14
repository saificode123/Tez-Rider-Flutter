"""Loopback-only SQL rule fixtures and k6. No hosted fallback or database reset.

Local JWTs are signed using the isolated server key and verified by actual Auth.
Evidence metadata fixtures serve read/decision load only, not Storage proof.
"""
import ctypes,importlib.util,json,os,subprocess,sys,time,urllib.request,uuid
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr25_local',Path(__file__).with_name('FR-25-local.py'))
local=importlib.util.module_from_spec(spec);spec.loader.exec_module(local)
ROOT=local.ROOT;OUT=ROOT/'.fr21-local/fr26';OUT.mkdir(parents=True,exist_ok=True)
def fixtures(count):
 local.guard();assert 1<=count<=1000
 sql="""begin;
 create temporary table fr26_load_people(label text,auth_id uuid,email text,profile_id bigint);
 create temporary table fr26_load_cases(auth_id uuid,email text,same_id bigint,conflict_id bigint);
 do $$ declare i integer; j integer; identity uuid; actor bigint; owner bigint; address text; role_name text; label text; order_id bigint; d bigint; first_id bigint; begin
 for i in 1..COUNT+2 loop
  label:=case when i<=2 then 'admin-'||i else 'customer-'||(i-2) end;
  address:='fr26-local-'||label||'@example.test';role_name:=case when i<=2 then 'admin' else 'customer' end;
  select a.id into identity from auth.users a where a.email=address and a.raw_user_meta_data->>'fr26_fixture'='true';
  if identity is null then
   if exists(select 1 from auth.users where email=address) then raise exception 'Unknown local account collision';end if;
   identity:=gen_random_uuid();
   insert into auth.users(id,instance_id,email,email_confirmed_at,role,aud,raw_user_meta_data,raw_app_meta_data,
    confirmation_token,recovery_token,email_change_token_new,email_change_token_current,email_change,reauthentication_token,
    phone_change,phone_change_token,encrypted_password,created_at,updated_at)
   values(identity,'00000000-0000-0000-0000-000000000000',address,now(),'authenticated','authenticated',
    jsonb_build_object('fr26_fixture',true,'role',role_name),'{"provider":"email","providers":["email"]}'::jsonb,
    '','','','','','','','','',now(),now());
  end if;
  select u.id into actor from public.users u where u.email=address;
  if actor is null then insert into public.users(email,name,role,verification_status)
   values(address,'FR26 local synthetic',role_name,case when i<=2 then 'approved' else 'pending' end) returning id into actor;end if;
  insert into fr26_load_people values(label,identity,address,actor);
 end loop;
 for i in 1..COUNT loop
  select p.profile_id,p.auth_id,p.email into owner,identity,address from fr26_load_people p where p.label='customer-'||i;
  for j in 1..2 loop
   insert into public.orders(user_id,amount,order_status,payment_method,delivery_address)
    values(owner,25,'delivered','COD','FR26 LOCAL SQL RULE FIXTURE')returning id into order_id;
   insert into public.disputes(type,by,customer_id,order_id,reason,description,request_id,evidence_paths)
    values('Other','Customer',owner,order_id,'Other','FR26 local rule fixture',gen_random_uuid(),array['FR26-local-rule-fixture.png'])returning id into d;
   insert into public.payments(orderid,customerid,paymentid,method,status,amount,paidat)
    values(order_id::text,owner::text,'FR26-LOCAL-SYNTHETIC-'||order_id,'COD','PAID',25,clock_timestamp());
   if j=1 then first_id:=d;else insert into fr26_load_cases values(identity,address,first_id,d);end if;
  end loop;
 end loop;
 end $$;
 commit;
 select jsonb_build_object('admins',(select jsonb_agg(to_jsonb(p)) from fr26_load_people p where label like 'admin-%'),
 'cases',(select jsonb_agg(to_jsonb(c)) from fr26_load_cases c));
 """.replace('COUNT',str(count))
 raw=local.run([str(local.DOCKER),'exec','-i','supabase_db_'+local.PROJECT,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atq'],sql)
 return json.loads(next(line for line in raw.splitlines() if line.startswith('{')))
def run(profile):
 local.guard();assert profile in ('smoke','full')
 count=10 if profile=='smoke' else 1000
 anon,secret=local.keys();data=fixtures(count)
 def verified(person):
  token=local.token(person['auth_id'],person['email'],secret)
  req=urllib.request.Request(local.BASE+'/auth/v1/user',headers={'apikey':anon,'Authorization':'Bearer '+token})
  with urllib.request.urlopen(req,timeout=30) as response:assert response.status==200 and json.load(response)['id']==person['auth_id']
  return token
 admins=[verified(p) for p in data['admins']]
 cases=[{'same_id':p['same_id'],'conflict_id':p['conflict_id'],'customer_token':verified(p)} for p in data['cases']]
 assert len(cases)==count and len(admins)==2
 local.PRIVATE.mkdir(exist_ok=True);file=local.PRIVATE/'fr26-local-k6-session.json'
 file.write_text(json.dumps({'project_id':local.PROJECT,'anon_key':anon,'admins':admins,'cases':cases}))
 executable=next((ROOT/'.fr21-local/fr04/k6').rglob('k6.exe'))
 env=dict(os.environ);env.update(FR26_LOCAL_URL=local.BASE,FR26_FIXTURE_FILE=str(file),FR26_LOAD_PROFILE=profile)
 env.pop('FR21_TEST_KEYS_JSON',None)
 summary=OUT/('local-'+profile+'-summary.json');aborted=False;minimum=None
 try:
  with (OUT/('local-'+profile+'-k6.log')).open('w') as output:
   process=subprocess.Popen([str(executable),'run','--summary-export',str(summary),str(ROOT/'tests/load/FR-26.js')],env=env,stdout=output,stderr=subprocess.STDOUT)
   class Memory(ctypes.Structure):
    _fields_=[('length',ctypes.c_ulong),('load',ctypes.c_ulong),('total',ctypes.c_ulonglong),('available',ctypes.c_ulonglong),('page_total',ctypes.c_ulonglong),('page_available',ctypes.c_ulonglong),('virtual_total',ctypes.c_ulonglong),('virtual_available',ctypes.c_ulonglong),('extended',ctypes.c_ulonglong)]
   started=time.monotonic()
   while process.poll() is None:
    memory=Memory();memory.length=ctypes.sizeof(memory)
    if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(memory)):
     minimum=memory.available if minimum is None else min(minimum,memory.available)
     if memory.available<150*1024*1024:aborted=True;process.terminate();break
    if time.monotonic()-started>600:aborted=True;process.terminate();break
    time.sleep(3)
   exit_code=process.wait(timeout=30)
  result={'profile':profile,'target_vus':count,'project_id':local.PROJECT,'exit':exit_code,'resource_abort':aborted,'minimum_available_bytes':minimum,'summary_present':summary.exists()}
  (OUT/('local-'+profile+'-result.json')).write_text(json.dumps(result,indent=2));print(json.dumps(result));return exit_code
 finally:file.unlink(missing_ok=True)
if __name__=='__main__':
 try:sys.exit(run(sys.argv[1] if len(sys.argv)>1 else 'smoke'))
 except Exception as error:print(json.dumps({'result':'FAILED','reason':str(error) if isinstance(error,(AssertionError,RuntimeError)) else type(error).__name__}));sys.exit(1)
