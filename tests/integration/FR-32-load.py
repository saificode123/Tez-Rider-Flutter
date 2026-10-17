"""Prepare/clean a LOCAL k6 fixture; never opens a hosted connection."""
import base64
import importlib.util
import json
from pathlib import Path
import secrets
import re
import subprocess
import sys
spec=importlib.util.spec_from_file_location('db',Path(__file__).with_name('FR-32-db.py'))
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
if sys.argv[1]=='prepare':
 p=subprocess.run(['docker','inspect','supabase_kong_tezrider-fr30-local'],capture_output=True,text=True,timeout=20)
 assert p.returncode==0,'Preserved LOCAL Kong container required'
 container=json.loads(p.stdout)[0];assert container['Name']=='/supabase_kong_tezrider-fr30-local'
 keys=[]
 for value in container['Config']['Env']:
  name,_,key=value.partition('=')
  if name in('SUPABASE_SERVICE_KEY','SUPABASE_SERVICE_ROLE_KEY','SERVICE_ROLE_KEY'):
   try:claims=json.loads(base64.urlsafe_b64decode(key.split('.')[1]+'==='))
   except Exception:continue
   if claims.get('role')=='service_role':keys.append(key)
 if not keys:
  # CLI-managed Kong stores consumers in its container-local declarative file.
  config=subprocess.run(['docker','exec','supabase_kong_tezrider-fr30-local','cat','/home/kong/kong.yml'],capture_output=True,text=True,timeout=20)
  assert config.returncode==0,'Canonical LOCAL Kong configuration unavailable'
  for key in re.findall(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',config.stdout):
   try:claims=json.loads(base64.urlsafe_b64decode(key.split('.')[1]+'==='))
   except Exception:continue
   if claims.get('role')=='service_role':keys.append(key)
 assert len(set(keys))==1,'Canonical LOCAL service-role API key required; never substitute hosted keys'
 d.local("set fr32.local_test='true';"+(d.ROOT/'tests/load/FR-32-local.sql').read_text())
 prefix=d.local('select run_prefix from fr32_load.fixture;').strip().splitlines()[-1]
 fixture={'synthetic_only':True,'mock_brevo':True,'project':'tezrider-fr30-local','base':'http://127.0.0.1:54321','service_key':keys[0],'worker_key':secrets.token_hex(32),'run_prefix':prefix}
 (d.OUT/'load-fixture.json').write_text(json.dumps(fixture))
 print(json.dumps({'local_fixture_prepared':True,'real_email_enabled':False,'fixture_file':'.fr21-local/fr32/load-fixture.json'}))
elif sys.argv[1]=='cleanup':
 d.local("""begin;do $$declare f fr32_load.fixture;begin select *into strict f from fr32_load.fixture;
 update fr32_private.configuration set daily_budget=(f.old_configuration->>'daily_budget')::integer,otp_reserve=(f.old_configuration->>'otp_reserve')::integer,quota_mode=f.old_configuration->>'quota_mode',provider_timezone=f.old_configuration->>'provider_timezone',dispatch_enabled=(f.old_configuration->>'dispatch_enabled')::boolean;
 -- Only this marked LOCAL run's synthetic admission records are removed.
 delete from fr32_private.quota_reservations where attempt_key in(select provider_key from public.email_outbox where payload->>'local_run'=f.run_prefix);
 update public.email_outbox set status='skipped_test',lease_token=null,lease_expires_at=null where payload->>'local_run'=f.run_prefix and status<>'sent';
 delete from fr32_load.fixture;end$$;drop function public.fr32_load_enqueue(text),public.fr32_load_stats(),public.fr32_load_recover();commit;""")
 (d.OUT/'load-fixture.json').unlink(missing_ok=True)
 print('LOCAL synthetic fixture admission cleaned; prior configuration restored')
else:raise ValueError('Choose prepare or cleanup')
