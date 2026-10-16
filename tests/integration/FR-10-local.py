"""Real separate-session races and 5,000-order batches, local container ONLY."""
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import threading
import time

spec = importlib.util.spec_from_file_location('fr10db', Path(__file__).with_name('FR-10-db.py'))
db = importlib.util.module_from_spec(spec)
spec.loader.exec_module(db)
checks = []


def scalar(sql):
    return db.local(sql).strip().splitlines()[-1]


def check(value, label):
    assert value, label
    checks.append({'check': label, 'result': 'PASS'})


def claim():
    return "select set_config('request.jwt.claims',(select jsonb_build_object('sub',auth_id,'role','authenticated','session_id',session_id,'email',email)::text from fr10_test.people where role='vendor'),true);"


def pair(a, b):
    barrier = threading.Barrier(2)
    def run(sql):
        barrier.wait(timeout=10)
        return db.local(sql)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(run, sql) for sql in [a, b]]
        return [future.result() for future in futures]


db.local("""create schema if not exists fr10_test;
create table if not exists fr10_test.people(role text primary key,id bigint,auth_id uuid,session_id uuid,email text);
do $$declare who text;aid uuid;sid uuid;uid bigint;mail text;begin
foreach who in array array['customer','vendor']loop
if exists(select 1 from fr10_test.people where role=who)then continue;end if;
aid:=gen_random_uuid();sid:=gen_random_uuid();mail:='fr10-local-'||aid||'@example.test';
insert into auth.users(id,email,email_confirmed_at,role,aud,raw_user_meta_data)values(aid,mail,now(),'authenticated','authenticated','{"fr10_fixture":true}');
insert into public.users(email,name,role,verification_status)values(mail,'FR10 LOCAL SYNTHETIC',who,'approved')returning id into uid;
insert into auth.sessions(id,user_id,created_at,updated_at)values(sid,aid,now(),now());
insert into fr10_test.people values(who,uid,aid,sid,mail);end loop;end$$;
create or replace function fr10_test.make_order(seconds numeric)returns bigint language plpgsql as $$declare oid bigint;t timestamptz:=clock_timestamp();begin
insert into public.orders(user_id,amount,fare,order_status,payment_method)values((select id from fr10_test.people where role='customer'),200,120,'pending','COD')returning id into oid;
insert into public.vendor_orders(order_id,vendor_id,sub_total,status,acceptance_started_at,acceptance_deadline_at)
values(oid,(select id from fr10_test.people where role='vendor'),80,'pending',t-interval '1 hour',t+seconds*interval '1 second');
update public.orders set checkout_finalized_at=t,acceptance_deadline_at=t+seconds*interval '1 second'where id=oid;return oid;end$$;
select cron.alter_job(jobid,active:=false)from cron.job where jobname='fr10-order-timeout';
""")
try:
    # An accepted commit holds the parent across expiry; worker must skip it.
    oid = int(scalar('select fr10_test.make_order(2);'))
    vid = int(scalar(f'select id from public.vendor_orders where order_id={oid};'))
    a = f"begin;select id from public.orders where id={oid} for update;" + claim() + f"select public.fr10_vendor_transition({vid},'accepted');select pg_sleep(2.5);commit;"
    b = 'select pg_sleep(2.1);select public.cancel_timed_out_orders();'
    results = pair(a, b)
    check('ACCEPTED' in results[0] and scalar(f"select order_status from public.orders where id={oid}") == 'accepted', 'separate sessions: acceptance wins before deadline, worker skips locked parent')
    check(scalar(f'select count(*)from public.notifications where timeout_order_id={oid}') == '0', 'accepted winner has no cancellation side effects')
    # Worker locks first; acceptance must observe the final cancellation.
    oid = int(scalar('select fr10_test.make_order(-1);'))
    vid = int(scalar(f'select id from public.vendor_orders where order_id={oid};'))
    a = f'begin;select id from public.orders where id={oid} for update;select public.cancel_timed_out_orders();select pg_sleep(0.5);commit;'
    b = 'begin;select pg_sleep(0.1);' + claim() + f"select public.fr10_vendor_transition({vid},'accepted');commit;"
    results = pair(a, b)
    check('ORDER_CANCELLED' in results[1] and scalar(f"select order_status from public.orders where id={oid}") == 'cancelled', 'separate sessions: timeout winner blocks later acceptance')
    # Two truly overlapping workers for one parent, exactly one outcome.
    oid = int(scalar('select fr10_test.make_order(-1);'))
    pair('begin;select public.cancel_timed_out_orders();select pg_sleep(0.3);commit;', 'select public.cancel_timed_out_orders();')
    check(scalar(f'select count(*)from public.notifications where timeout_order_id={oid}') == '1', 'concurrent duplicate workers create one notification')
    check(scalar(f"select count(*)from public.order_timeline_events where order_id={oid} and status='cancelled'") == '1', 'concurrent duplicate workers create one cancellation event')
    # Local only. Set-based fixtures; every order has a captured synthetic payment.
    start = time.monotonic()
    db.local("""create temp table bulk_ids(id bigint primary key);
with made as(insert into public.orders(user_id,amount,fare,order_status,payment_method,checkout_finalized_at,acceptance_deadline_at)
select (select id from fr10_test.people where role='customer'),200,120,'pending','CARD',clock_timestamp(),
'2020-01-01'::timestamptz+n*interval '1 microsecond'from generate_series(1,5000)n returning id)
insert into bulk_ids select id from made;
insert into public.vendor_orders(order_id,vendor_id,sub_total,status,acceptance_started_at,acceptance_deadline_at)
select o.id,(select id from fr10_test.people where role='vendor'),80,'pending','2019-01-01',o.acceptance_deadline_at from public.orders o join bulk_ids b on b.id=o.id;
insert into public.payments(paymentid,orderid,customerid,method,status,amount,paidat)
select 'fr10-bulk-'||o.id,o.id::text,o.user_id::text,'CARD','SUCCESS',200,clock_timestamp()from public.orders o join bulk_ids b on b.id=o.id;
create table if not exists fr10_test.bulk_ids(id bigint primary key);
truncate fr10_test.bulk_ids;insert into fr10_test.bulk_ids select id from bulk_ids;
""")
    first = json.loads(scalar('select public.cancel_timed_out_orders(500);'))
    check(first['processed'] == first['cancelled'] == 500, '500-order batch limit honored among 5000')
    check(scalar("select bool_and(o.order_status='cancelled')from(select o.*from public.orders o join fr10_test.bulk_ids b on b.id=o.id order by o.id limit 500)o") == 't', 'oldest expired first')
    batch_times = []
    def batch(_):
        begin = time.monotonic()
        result = json.loads(scalar('select public.cancel_timed_out_orders(500);'))
        return {'milliseconds': round((time.monotonic()-begin)*1000, 2), **result}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        batch_times = list(pool.map(batch, range(12)))
    stats = json.loads(scalar("""select jsonb_build_object('orders',count(*),'cancelled',count(*)filter(where o.order_status='cancelled'),
'notifications',(select count(*)from public.notifications where timeout_order_id in(select id from fr10_test.bulk_ids)),
'refunds',(select count(*)from public.order_refund_actions where order_id in(select id from fr10_test.bulk_ids)),
'events',(select count(*)from public.order_timeline_events where status='cancelled'and order_id in(select id from fr10_test.bulk_ids)))
from public.orders o join fr10_test.bulk_ids b on b.id=o.id;"""))
    check(all(stats[k] == 5000 for k in ['orders', 'cancelled', 'notifications', 'refunds', 'events']), '5000 orders drained with exactly one notice refund and cancellation event each')
    check(all(t['processed'] <= 500 for t in batch_times), 'overlapping bounded workers never exceed batch cap')
    result = {'checks': checks, 'bulk': stats, 'total_seconds_including_fixture_creation': round(time.monotonic()-start, 2), 'scheduler_batches': batch_times, 'interactive_p95': 'NOT MEASURED by SQL transport', 'full_1000_vus': 'NOT EXECUTED', 'local_container': db.CONTAINER}
    (db.OUT / 'local-races-bulk.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result))
finally:
    db.local("select cron.alter_job(jobid,active:=true)from cron.job where jobname='fr10-order-timeout';")
