"""Start only preserved local services; protected environment never printed."""
import json,secrets,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/fr13'
def command(args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=90)
 if p.returncode:raise RuntimeError('Local service operation failed; no credentials emitted')
 return p.stdout
def inspect(name):return json.loads(command(['docker','inspect',name]))[0]
def env(name):return dict(v.split('=',1)for v in inspect(name)['Config']['Env']if'='in v)
db='supabase_db_tezrider-fr30-local';auth='supabase_auth_tezrider-fr30-local'
assert inspect(db)['Name']=='/'+db
for name in ['supabase_rest_tezrider-fr30-local','supabase_kong_tezrider-fr30-local']:
 if not inspect(name)['State']['Running']:command(['docker','start',name])
name='realtime-dev.fr13-local'
p=subprocess.run(['docker','inspect',name],capture_output=True,text=True)
if p.returncode:
 e={'PORT':'4000','DB_HOST':db,'DB_PORT':'5432','DB_USER':'supabase_admin','DB_PASSWORD':env(db)['POSTGRES_PASSWORD'],'DB_NAME':'postgres',
 'DB_AFTER_CONNECT_QUERY':'SET search_path TO _realtime','DB_ENC_KEY':'supabaserealtime','API_JWT_SECRET':env(auth)['GOTRUE_JWT_SECRET'],
 'SECRET_KEY_BASE':secrets.token_hex(64),'METRICS_JWT_SECRET':env(auth)['GOTRUE_JWT_SECRET'],'ERL_AFLAGS':'-proto_dist inet_tcp',
 'DNS_NODES':"''",'RLIMIT_NOFILE':'10000','APP_NAME':'realtime','SEED_SELF_HOST':'true','RUN_JANITOR':'true','DISABLE_HEALTHCHECK_LOGGING':'true'}
 with tempfile.NamedTemporaryFile(mode='w',delete=False,suffix='.env')as f:
  path=Path(f.name);f.write('\n'.join(k+'='+v for k,v in e.items()))
 try:
  command(['docker','run','-d','--name',name,'--network','supabase_network_tezrider-fr30-local',
   '--network-alias','realtime-dev','--network-alias','supabase_realtime_tezrider-fr30-local','--network-alias','realtime-dev.supabase_realtime_tezrider-fr30-local',
   '-p','127.0.0.1:54327:4000','--env-file',str(path),'public.ecr.aws/supabase/realtime:v2.140.10'])
 finally:path.unlink()
elif not inspect(name)['State']['Running']:command(['docker','start',name])
network='supabase_network_tezrider-fr30-local'
if 'realtime-dev'not in(inspect(name)['NetworkSettings']['Networks'][network].get('Aliases')or[]):
 command(['docker','network','disconnect',network,name])
 command(['docker','network','connect','--alias','realtime-dev','--alias','supabase_realtime_tezrider-fr30-local',network,name])
print(json.dumps({'local_only':True,'services':['preserved db','REST','gateway','Realtime'],'credentials_printed':False,'business_migrations_replayed':False}))
