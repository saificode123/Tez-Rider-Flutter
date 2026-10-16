"""Resource-gated local HTTP load; never accepts hosted URLs or credentials."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

spec=importlib.util.spec_from_file_location('local',Path(__file__).with_name('FR-30-local.py'))
local=importlib.util.module_from_spec(spec);spec.loader.exec_module(local);local.guard()
ROOT=local.ROOT;OUT=ROOT/'.fr21-local/fr17';profile=sys.argv[1]if len(sys.argv)>1 else'small'
assert profile in('small','full')
available=local.memory()
if available<(1024 if profile=='full' else 350)*1024*1024:
    result={'profile':profile,'status':'NOT EXECUTED','available_bytes':available,'reason':'Local RAM safety gate'}
    (OUT/('load-'+profile+'.json')).write_text(json.dumps(result,indent=2));print(json.dumps(result));sys.exit(0)
local.run([local.DOCKER,'start','supabase_db_'+local.PROJECT,'supabase_auth_'+local.PROJECT,'supabase_rest_'+local.PROJECT,'supabase_kong_'+local.PROJECT])
after_start=local.memory()
if after_start<(512 if profile=='full' else 350)*1024*1024:
    result={'profile':profile,'status':'NOT EXECUTED','available_bytes':after_start,'reason':'Post-start local RAM safety gate'}
    (OUT/('load-'+profile+'.json')).write_text(json.dumps(result,indent=2));print(json.dumps(result));sys.exit(0)
status=json.loads(local.run([local.CLI,'status','--workdir',str(local.STACK),'--output','json']))
assert status['API_URL']=='http://127.0.0.1:54321'
container=json.loads(local.run([local.DOCKER,'inspect','supabase_auth_'+local.PROJECT]))[0]
env=dict(v.split('=',1)for v in container['Config']['Env']if'='in v)
count=1000 if profile=='full' else 2
people=json.loads(local.sql("""begin;create temp table fr17_load_people(auth_id uuid,email text,session_id uuid);
do $$declare a uuid;s uuid;uid bigint;mail text;begin
for i in 1.."""+str(count)+"""loop a:=gen_random_uuid();s:=gen_random_uuid();mail:='fr17-k6-'||a||'@example.test';
insert into auth.users(id,email,email_confirmed_at,role,aud,raw_user_meta_data)values(a,mail,now(),'authenticated','authenticated','{"fr17_fixture":true}');
insert into public.users(email,name,role,verification_status)values(mail,'FR17 LOCAL LOAD SYNTHETIC','customer','approved')returning id into uid;
insert into auth.sessions(id,user_id,created_at,updated_at)values(s,a,now(),now());insert into fr17_load_people values(a,mail,s);end loop;end$$;
select jsonb_agg(p)from fr17_load_people p;commit;""").strip())
pid=int(local.sql('select fr17_test.product(100,5);').strip())
# The local draft history already records FR17; add only its later reviewed
# open-order index if this preserved local database predates that draft edit.
local.sql("create index if not exists fr17_open_inventory_orders_idx on public.orders(coalesce(acceptance_deadline_at,created_at),id)where checkout_finalized_at is not null and cancelled_at is null and timeout_review_reason is null;")
fixture={'synthetic_only':True,'project':local.PROJECT,'anon_key':status['ANON_KEY'],'product_id':pid,'run_prefix':uuid.uuid4().hex[:16],
 'customers':[{'token':local.jwt(p['auth_id'],p['email'],p['session_id'],env['GOTRUE_JWT_SECRET'])}for p in people]}
private=Path(os.environ['LOCALAPPDATA'])/'TezRider-FR21/fr17-local-session.json';private.write_text(json.dumps(fixture))
runtime=dict(os.environ,FR17_LOCAL_URL=status['API_URL'],FR17_FIXTURE_FILE=str(private),FR17_PROFILE=profile)
for key in['FR21_TEST_KEYS_JSON','FR21_PRIVATE_DIRECTORY']:runtime.pop(key,None)
summary=OUT/('load-'+profile+'-summary.json');executable=next((ROOT/'.fr21-local/fr04/k6').rglob('k6.exe'))
try:
    minimum=available;aborted=False
    with(OUT/('load-'+profile+'.log')).open('w',encoding='utf-8')as output:
        process=subprocess.Popen([str(executable),'run','--summary-export',str(summary),str(ROOT/'tests/load/FR-17.js')],env=runtime,stdout=output,stderr=subprocess.STDOUT)
        start=time.monotonic()
        while process.poll()is None:
            minimum=min(minimum,local.memory())
            if minimum<256*1024*1024 or time.monotonic()-start>150:aborted=True;process.terminate();break
            time.sleep(1)
        code=process.wait(timeout=20)
    metrics=json.loads(summary.read_text())['metrics']if summary.exists()and not aborted else{}
    observed=json.loads(local.sql(f"select jsonb_build_object('stock',(select stock_qty from public.products where id={pid}),'purchases',(select count(*)from public.inventory_movements where product_id={pid} and movement_type='ORDER_DECREMENT'),'negative',(select count(*)from public.inventory_movements where product_id={pid} and stock_after<0),'crossing_notices',(select count(*)from public.notifications where stock_product_id={pid}),'ledger_rows',(select count(*)from public.inventory_movements),'ledger_table_bytes',pg_table_size('public.inventory_movements'),'ledger_index_bytes',pg_indexes_size('public.inventory_movements'),'mean_tuple_bytes',(select round(avg(pg_column_size(m)))from public.inventory_movements m));").strip())
    result={'profile':profile,'exit_code':code,'resource_aborted':aborted,'minimum_available_bytes':minimum,'local_only':True,'database':observed,
      'metrics':{k:metrics.get(k)for k in['checkout_ms','unexpected_errors','purchases','expected_shortages','checks','http_reqs','vus_max']}}
    (OUT/('load-'+profile+'.json')).write_text(json.dumps(result,indent=2));print(json.dumps(result))
    assert code==0 and observed['stock']==0 and observed['purchases']==100 and observed['negative']==0 and observed['crossing_notices']==1,'Local load/inventory acceptance failed; see result'
finally:private.unlink(missing_ok=True)
