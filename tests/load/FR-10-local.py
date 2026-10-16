"""Guarded local HTTP benchmark; never accepts a hosted URL or hosted keys."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fr30local', Path(__file__).with_name('FR-30-local.py'))
local = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local)
local.guard()
OUT = ROOT / '.fr21-local/fr10'
profile = sys.argv[1] if len(sys.argv) > 1 else 'small'
assert profile in ('small', 'full')
available = local.memory()
if available < (1024 if profile == 'full' else 350)*1024*1024:
    result = {'profile':profile,'status':'NOT EXECUTED','reason':'Insufficient available memory for safe local benchmark','available_bytes':available}
    (OUT/('load-'+profile+'.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))
    sys.exit(0)
local.run([local.DOCKER,'start','supabase_auth_'+local.PROJECT,'supabase_rest_'+local.PROJECT,'supabase_kong_'+local.PROJECT])
status = json.loads(local.run([local.CLI,'status','--workdir',str(local.STACK),'--output','json']))
assert status['API_URL'] == 'http://127.0.0.1:54321'
container = json.loads(local.run([local.DOCKER,'inspect','supabase_auth_'+local.PROJECT]))[0]
env = dict(v.split('=',1)for v in container['Config']['Env']if '='in v)
person = json.loads(local.sql("select row_to_json(p)from fr10_test.people p where role='vendor';").strip())
ids = json.loads(local.sql("""begin;create temp table bench(id bigint);
with o as(insert into public.orders(user_id,amount,fare,order_status,payment_method,checkout_finalized_at,acceptance_deadline_at)
select (select id from fr10_test.people where role='customer'),200,120,'pending','COD',clock_timestamp(),clock_timestamp()+interval '3 minutes'from generate_series(1,100)returning id)
insert into bench select id from o;
insert into public.vendor_orders(order_id,vendor_id,sub_total,status,acceptance_started_at,acceptance_deadline_at)
select o.id,(select id from fr10_test.people where role='vendor'),80,'pending',clock_timestamp(),o.acceptance_deadline_at from public.orders o join bench b on b.id=o.id;
commit;select jsonb_agg(v.id)from public.vendor_orders v join bench b on b.id=v.order_id;
""").strip())
fixture = {'synthetic_only':True,'project':local.PROJECT,'anon_key':status['ANON_KEY'],
           'vendor_token':local.jwt(person['auth_id'],person['email'],person['session_id'],env['GOTRUE_JWT_SECRET']),'vendor_order_ids':ids}
private = Path(os.environ['LOCALAPPDATA'])/'TezRider-FR21/fr10-local-session.json'
private.write_text(json.dumps(fixture),encoding='utf-8')
summary = OUT/('load-'+profile+'-summary.json')
executable = next((ROOT/'.fr21-local/fr04/k6').rglob('k6.exe'))
runtime = dict(os.environ,FR10_LOCAL_URL=status['API_URL'],FR10_FIXTURE_FILE=str(private),FR10_PROFILE=profile)
for key in ['FR21_TEST_KEYS_JSON','FR21_PRIVATE_DIRECTORY']:runtime.pop(key,None)
try:
    minimum = available
    aborted = False
    with (OUT/('load-'+profile+'.log')).open('w',encoding='utf-8')as output:
        process = subprocess.Popen([str(executable),'run','--summary-export',str(summary),str(ROOT/'tests/load/FR-10.js')],env=runtime,stdout=output,stderr=subprocess.STDOUT)
        start = time.monotonic()
        while process.poll() is None:
            minimum = min(minimum,local.memory())
            if minimum < 256*1024*1024 or time.monotonic()-start>90:
                aborted=True
                process.terminate()
                break
            time.sleep(1)
        code = process.wait(timeout=20)
    metrics = json.loads(summary.read_text())['metrics'] if summary.exists() and not aborted else {}
    result = {'profile':profile,'exit_code':code,'resource_aborted':aborted,'minimum_available_bytes':minimum,
              'metrics':{name:metrics.get(name)for name in ['vendor_acceptance_ms','unexpected_errors','checks','http_reqs','vus_max']},'local_only':True}
    (OUT/('load-'+profile+'.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))
    assert code == 0, 'Local benchmark did not pass; see recorded result'
finally:
    private.unlink(missing_ok=True)
