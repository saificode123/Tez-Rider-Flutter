"""Prepare marked LOCAL JWT/assignment fixtures. No hosted connection or email."""
import base64,hashlib,hmac,importlib.util,json,secrets,subprocess,sys,time,uuid
from pathlib import Path
spec=importlib.util.spec_from_file_location('db',Path(__file__).with_name('FR-32-db.py'))
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
OUT=d.ROOT/'.fr21-local/checklist';FILE=OUT/'load-fixture.json'
def inspect(name):
 p=subprocess.run(['docker','inspect',name],capture_output=True,text=True,timeout=20)
 assert p.returncode==0;obj=json.loads(p.stdout)[0];assert obj['Name']=='/'+name;return obj
def b64(data):return base64.urlsafe_b64encode(data).decode().rstrip('=')
if sys.argv[1]=='prepare':
 assert not FILE.exists(),'Finish previous LOCAL run first'
 kong=inspect('supabase_kong_tezrider-fr30-local');auth=inspect('supabase_auth_tezrider-fr30-local')
 config=subprocess.run(['docker','exec','supabase_kong_tezrider-fr30-local','cat','/home/kong/kong.yml'],capture_output=True,text=True,timeout=20);assert config.returncode==0
 import re
 keys=[]
 for key in re.findall(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',config.stdout):
  try:claims=json.loads(base64.urlsafe_b64decode(key.split('.')[1]+'==='))
  except Exception:continue
  if claims.get('role')=='service_role':keys.append(key)
 assert len(set(keys))==1,'Canonical LOCAL API key required'
 env=dict(e.split('=',1)for e in auth['Config']['Env']if'='in e);secret=env['GOTRUE_JWT_SECRET'].encode()
 count=22;prefix=str(uuid.uuid4());customer=str(uuid.uuid4());rows=[]
 q="begin;create schema if not exists checklist_load;create table if not exists checklist_load.fixtures(run uuid,oid bigint,aid bigint,rid bigint,auth_id uuid,session_id uuid);"
 q+=f"insert into auth.users(id,email,email_confirmed_at,role,aud)values('{customer}','checklist-load-customer-{prefix}@example.test',now(),'authenticated','authenticated');insert into public.users(email,name,role,verification_status)values('checklist-load-customer-{prefix}@example.test','CHECKLIST LOCAL LOAD SYNTHETIC','customer','approved');"
 for i in range(count):
  aid=str(uuid.uuid4());sid=str(uuid.uuid4());mail=f'checklist-load-{prefix}-{i}@example.test'
  q+=f"do $$declare u bigint;o bigint;a bigint;begin insert into auth.users(id,email,email_confirmed_at,role,aud)values('{aid}','{mail}',now(),'authenticated','authenticated');insert into public.users(email,name,role,verification_status)values('{mail}','CHECKLIST LOCAL LOAD SYNTHETIC','rider','approved')returning id into u;insert into auth.sessions(id,user_id,created_at,updated_at)values('{sid}','{aid}',now(),now());insert into public.orders(user_id,rider_id,order_status,amount,payment_method,delivery_address)values((select id from public.users where auth_user_id='{customer}'),u,'ready',1,'COD','CHECKLIST LOCAL LOAD SYNTHETIC')returning id into o;insert into public.rider_assignments(orderid,riderid,status)values(o,u,'Accepted')returning id into a;insert into checklist_load.fixtures values('{prefix}',o,a,u,'{aid}','{sid}');end$$;"
 q+=f"commit;select jsonb_agg(to_jsonb(f))from checklist_load.fixtures f where run='{prefix}';"
 result=d.local(q);records=json.loads(next(l for l in result.splitlines()if l.startswith('[{')))
 issuer=json.loads(base64.urlsafe_b64decode(keys[0].split('.')[1]+'==='))['iss']
 for record in records:
  payload={'role':'authenticated','sub':record['auth_id'],'session_id':record['session_id'],'aud':'authenticated','iss':issuer,'iat':int(time.time()),'exp':int(time.time())+3600}
  wire=b64(b'{"alg":"HS256","typ":"JWT"}')+'.'+b64(json.dumps(payload).encode());token=wire+'.'+b64(hmac.new(secret,wire.encode(),hashlib.sha256).digest())
  rows.append({'order_id':record['oid'],'assignment_id':record['aid'],'token':token})
 FILE.write_text(json.dumps({'synthetic_only':True,'project':'tezrider-fr30-local','base':'http://127.0.0.1:54321','api_key':keys[0],'run':prefix,'fixtures':rows}))
 print(json.dumps({'local_assignments':len(rows),'real_emails_enabled':False}))
elif sys.argv[1]=='cleanup':
 f=json.loads(FILE.read_text());run=str(uuid.UUID(f['run']))
 d.local("begin;update public.orders set order_status='cancelled'where id in(select oid from checklist_load.fixtures where run='"+run+"')and delivery_address='CHECKLIST LOCAL LOAD SYNTHETIC'and order_status not in('cancelled','delivered');commit;")
 FILE.unlink();print('Only marked LOCAL synthetic load fixtures closed; evidence preserved; no quota changes')
else:raise ValueError('Choose prepare or cleanup')
