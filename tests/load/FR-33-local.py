"""Unlinked loopback FR33 load runner; synthetic fixtures, mock mail only."""
import ctypes,importlib.util,json,os,subprocess,sys,time,uuid,urllib.request
from pathlib import Path
spec=importlib.util.spec_from_file_location('local',Path(__file__).with_name('FR-25-local.py'));local=importlib.util.module_from_spec(spec);spec.loader.exec_module(local)
ROOT=local.ROOT;OUT=ROOT/'.fr21-local/fr33';DENO='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/deno/deno.exe'
class Memory(ctypes.Structure):
 _fields_=[('length',ctypes.c_ulong),('load',ctypes.c_ulong),('total',ctypes.c_ulonglong),('available',ctypes.c_ulonglong),('page_total',ctypes.c_ulonglong),('page_available',ctypes.c_ulonglong),('virtual_total',ctypes.c_ulonglong),('virtual_available',ctypes.c_ulonglong),('extended',ctypes.c_ulonglong)]
def available():
 m=Memory();m.length=ctypes.sizeof(m);assert ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m));return m.available
def sql(text):
 local.guard();return local.run([str(local.DOCKER),'exec','-i','supabase_db_'+local.PROJECT,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atq'],text)
def fixtures(count,service):
 # This database is isolated and synthetic; never import hosted identities.
 people=[]
 for role in ('customer','admin','rider'):
  for i in range(count if role=='rider' else 1):
   address='fr33-local-'+role+'-'+str(i)+'@example.test';identity=str(uuid.uuid4())
   query="""begin;
   insert into auth.users(id,instance_id,email,email_confirmed_at,role,aud,raw_user_meta_data,raw_app_meta_data,confirmation_token,recovery_token,email_change_token_new,email_change_token_current,email_change,reauthentication_token,phone_change,phone_change_token,encrypted_password,created_at,updated_at)
   values('IDENTITY','00000000-0000-0000-0000-000000000000','ADDRESS',now(),'authenticated','authenticated','{"fr33_fixture":true}','{"provider":"email","providers":["email"]}','','','','','','','','','',now(),now()) on conflict(id)do nothing;
   insert into public.users(email,name,role,verification_status)values('ADDRESS','FR33 local synthetic','ROLE','approved')on conflict(email)do nothing;
   commit;select jsonb_build_object('id',(select id from auth.users where email='ADDRESS'),'profile',(select id from public.users where email='ADDRESS'));
   """.replace('IDENTITY',identity).replace('ADDRESS',address).replace('ROLE',role)
   # Reuse tagged identities only; duplicate Auth email must never create a new identity.
   prior=sql("select id from auth.users where email='"+address+"' and raw_user_meta_data->>'fr33_fixture'='true';").strip()
   if prior:query=query.replace(identity,prior)
   row=json.loads(next(l for l in sql(query).splitlines() if l.startswith('{')));people.append(dict(row,email=address,role=role))
 customer=next(p for p in people if p['role']=='customer');cases=[];anon,secret=local.keys()
 for rider in (p for p in people if p['role']=='rider'):
  sql('insert into public.riders(userid,is_online)values('+str(rider['profile'])+',false)on conflict do nothing;')
  token=local.token(rider['id'],rider['email'],secret)
  req=urllib.request.Request(local.BASE+'/auth/v1/user',headers={'apikey':anon,'Authorization':'Bearer '+token})
  with urllib.request.urlopen(req,timeout=20)as r:assert json.load(r)['id']==rider['id']
  orders=[]
  for _ in range(2):
   orders.append(int(sql("insert into public.orders(user_id,rider_id,amount,order_status,payment_method,delivery_address)values("+str(customer['profile'])+','+str(rider['profile'])+",25,'on_the_way','COD','FR33 LOCAL SYNTHETIC')returning id;").strip()))
  request=str(uuid.uuid4());issued=local.api('/rest/v1/rpc/issue_delivery_otp',{'p_order_id':orders[0],'p_request_id':request,'p_actor':rider['id']},anon,service);assert issued['code']=='SEND'
  assert local.api('/rest/v1/rpc/fr33_start_send',{'p_id':request},anon,service) is True
  assert local.api('/rest/v1/rpc/fr33_finish_send',{'p_id':request,'p_result':'ACCEPTED','p_provider_id':'FR33-LOCAL-MOCK-FIXTURE'},anon,service)['code']=='EMAIL_ACCEPTED'
  cases.append({'token':token,'verify_order':orders[0],'issue_order':orders[1],'code':issued['otp'],'wrong':'111111' if issued['otp']=='000000' else '000000','verify_requests':[str(uuid.uuid4()),str(uuid.uuid4())],'issue_requests':[str(uuid.uuid4())for _ in range(6)]})
 return {'project_id':local.PROJECT,'real_email_enabled':False,'anon_key':anon,'cases':cases}
def run(profile):
 local.guard();assert profile in ('smoke','full');OUT.mkdir(exist_ok=True,parents=True)
 minimum_start=available();required=512*1024**2 if profile=='smoke' else 2*1024**3
 if minimum_start<required:
  result={'result':'NOT EXECUTED','profile':profile,'available_bytes':minimum_start,'required_available_bytes':required,'reason':'Insufficient RAM for safe isolated load; no hosted fallback','real_emails_sent':0};(OUT/('local-'+profile+'-result.json')).write_text(json.dumps(result,indent=2));print(json.dumps(result));return 2
 # Apply only the two reviewed FR33 migrations, locally, once; no reset/db push.
 existing=set(sql('select version from supabase_migrations.schema_migrations;').splitlines())
 for name in ('202610140001_fr33_email_delivery_otp.sql','202610140002_fr33_dispatch_recovery.sql'):
  version=name.split('_')[0]
  if version not in existing:
   text=(ROOT/'supabase/migrations'/name).read_text();text=text.rsplit('commit;',1)[0]+"insert into supabase_migrations.schema_migrations(version,name)values('"+version+"','"+name+"');commit;";sql(text)
 status=json.loads(local.run([str(local.CLI),'status','--workdir',str(local.STACK),'--output','json']));assert status['API_URL']==local.BASE
 file=local.PRIVATE/'fr33-local-session.json';processes=[];env={k:v for k,v in os.environ.items()if not k.startswith(('BREVO_','FR21_TEST_','SUPABASE_'))}
 try:
  file.write_text(json.dumps(fixtures(5 if profile=='smoke' else 500,status['SERVICE_ROLE_KEY'])))
  env.update(SUPABASE_URL=local.BASE,SUPABASE_ANON_KEY=status['ANON_KEY'],SUPABASE_SERVICE_ROLE_KEY=status['SERVICE_ROLE_KEY'],FR33_LOCAL_TEST='true',FR33_MOCK_EMAIL_URL='http://127.0.0.1:8789/send',FR33_LOCAL_URL=local.BASE,FR33_LOCAL_ISSUE_URL='http://127.0.0.1:8000',FR33_FIXTURE_FILE=str(file),FR33_LOAD_PROFILE=profile)
  with (OUT/'local-mock-runtime.log').open('w')as runtime:
   processes.append(subprocess.Popen([DENO,'run','--allow-net=127.0.0.1:8789',str(ROOT/'tests/load/FR-33-mail-mock.ts')],env=env,stdout=runtime,stderr=runtime))
   processes.append(subprocess.Popen([DENO,'run','--allow-env','--allow-net=127.0.0.1:54321,127.0.0.1:8000,127.0.0.1:8789',str(ROOT/'supabase/functions/send-delivery-otp/index.ts')],env=env,stdout=runtime,stderr=runtime))
   time.sleep(2);assert all(p.poll() is None for p in processes),'Local mock runtime unavailable'
   executable=next((ROOT/'.fr21-local/fr04/k6').rglob('k6.exe'));summary=OUT/('local-'+profile+'-summary.json')
   with (OUT/('local-'+profile+'-k6.log')).open('w')as output:
    process=subprocess.Popen([str(executable),'run','--summary-export',str(summary),str(ROOT/'tests/load/FR-33.js')],env=env,stdout=output,stderr=output);processes.append(process);start=time.monotonic();aborted=False;minimum=available()
    while process.poll() is None:
     minimum=min(minimum,available())
     if minimum<150*1024**2 or time.monotonic()-start>600:aborted=True;process.terminate();break
     time.sleep(3)
    code=process.wait(timeout=30)
   result={'profile':profile,'target_vus':10 if profile=='smoke' else 1000,'exit':code,'resource_abort':aborted,'minimum_available_bytes':minimum,'real_emails_sent':0};(OUT/('local-'+profile+'-result.json')).write_text(json.dumps(result,indent=2));print(json.dumps(result));return code
 finally:
  file.unlink(missing_ok=True)
  for p in reversed(processes):
   if p.poll() is None:p.terminate();p.wait(timeout=30)
if __name__=='__main__':
 try:sys.exit(run(sys.argv[1]if len(sys.argv)>1 else 'smoke'))
 except Exception as e:print(json.dumps({'result':'FAILED','reason':str(e)if isinstance(e,(AssertionError,RuntimeError))else type(e).__name__,'real_emails_sent':0}));sys.exit(1)
