"""Real independent PostgreSQL sessions; exclusively preserved LOCAL database."""
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import threading
import uuid

spec = importlib.util.spec_from_file_location('fr32db', Path(__file__).with_name('FR-32-db.py'))
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)
sql = d.local
checks = []
def scalar(q): return sql(q).strip().splitlines()[-1]
def check(value, label):
    assert value, label
    checks.append({'check': label, 'result': 'PASS'})
def pair(queries):
    gate = threading.Barrier(len(queries))
    def run(q):
        gate.wait(timeout=20)
        return sql(q)
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(queries)) as pool:
        return list(pool.map(run, queries))

cfg = json.loads(scalar('select row_to_json(c)from fr32_private.configuration c;'))
label = str(uuid.uuid4())
# A DO block avoids psql command tags in returned fixture identity.
sql("create schema if not exists fr32_test;create table if not exists fr32_test.fixtures(label text primary key,user_id bigint);create table if not exists fr32_test.quota_keys(id uuid primary key);")
sql("do $$declare a uuid:=gen_random_uuid();u bigint;begin insert into auth.users(id,email,email_confirmed_at,role,aud)values(a,'fr32-local-"+label+"@example.test',now(),'authenticated','authenticated');insert into public.users(email,name,role,verification_status)values('fr32-local-"+label+"@example.test','FR32 LOCAL synthetic','customer','approved')returning id into u;insert into fr32_test.fixtures values('"+label+"',u);end$$;")
uid = int(scalar("select user_id from fr32_test.fixtures where label='"+label+"';"))
try:
    # One stable event under two simultaneously open transactions.
    event = "select fr32_private.enqueue('order_confirmation',"+str(uid)+",'local','race','fr32-local:"+label+"');"
    r = pair(['begin;'+event+'select pg_sleep(0.5);commit;', 'begin;'+event+'commit;'])
    check(scalar("select count(*)from public.email_outbox where dedupe_key='fr32-local:"+label+"';") == '1', 'simultaneous enqueue conflict creates exactly one intent')
    sql("update public.email_outbox set status='skipped_test'where dedupe_key='fr32-local:"+label+"';do $$declare j uuid;begin for i in 1..12 loop j:=fr32_private.enqueue('order_confirmation',"+str(uid)+",'local','claim-'||i,'fr32-claim:"+label+":'||i);update public.email_outbox set test_approved=true where id=j;end loop;end$$;")
    outputs = pair(["begin;select jsonb_agg(j)from fr32_private.claim(6)j;select pg_sleep(0.5);commit;"] * 2)
    jobs = [json.loads(next(line for line in o.splitlines() if line.startswith('[{'))) for o in outputs]
    ids = [[j['id'] for j in group] for group in jobs]
    check(len(ids[0]) == len(ids[1]) == 6 and not set(ids[0]) & set(ids[1]), 'two independent overlapping workers claim disjoint six-job batches')
    check(scalar("select count(*)from public.email_outbox where recipient_user_id="+str(uid)+" and status='sending';") == '12', 'all twelve active leases persisted once')
    sql("update fr32_private.configuration set quota_mode='rolling_26h',daily_budget=10,otp_reserve=3;")
    def reserve(kind):
        key = str(uuid.uuid4())
        sql("insert into fr32_test.quota_keys values('"+key+"');")
        return scalar("select fr32_private.reserve_quota('"+kind+"','"+key+"','2095-01-01Z')->>'code';")
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        values = list(pool.map(lambda _: reserve('transactional'), range(40)))
    check(values.count('RESERVED') == 7 and values.count('QUOTA_EXCEEDED') == 33, '40 concurrent non-OTP reservations admit exactly7 and protect3')
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        values = list(pool.map(lambda _: reserve('otp'), range(20)))
    check(values.count('RESERVED') == 3 and values.count('QUOTA_EXCEEDED') == 17, '20 concurrent OTP reservations use exactly remaining3; combined10')
    check(scalar("select sum(units)from fr32_private.quota_reservations where attempt_key in(select id from fr32_test.quota_keys);") == '10', 'actual shared quota ledger not oversubscribed')
    result = {'checks': checks, 'local_only': True, 'independent_sessions': True, 'real_email_sent': False}
    (d.OUT / 'local-concurrency.json').write_text(json.dumps(result, indent=2))
    print(json.dumps({'passed': len(checks), 'independent_sessions': True, 'local_only': True}))
finally:
    # Remove only explicitly marked LOCAL synthetic quota reservations, never real accounting.
    sql("delete from fr32_private.quota_reservations where attempt_key in(select id from fr32_test.quota_keys);delete from fr32_test.quota_keys;update fr32_private.configuration set daily_budget="+str(cfg['daily_budget'])+",otp_reserve="+str(cfg['otp_reserve'])+",quota_mode='"+cfg['quota_mode']+"',provider_timezone="+('null' if cfg['provider_timezone'] is None else "'"+cfg['provider_timezone']+"'")+";update public.email_outbox set status='skipped_test',lease_token=null,lease_expires_at=null where recipient_user_id="+str(uid)+" and status='sending';")
