"""Actual independent PostgreSQL sessions, exclusively preserved LOCAL DB."""
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import threading
import uuid

spec=importlib.util.spec_from_file_location('fr17db',Path(__file__).with_name('FR-17-db.py'))
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
checks=[]
def sql(value):return d.local(value)
def scalar(value):return sql(value).strip().splitlines()[-1]
def check(value,label):
    assert value,label
    checks.append({'check':label,'result':'PASS'})
def pair(a,b):
    gate=threading.Barrier(2)
    def run(q):gate.wait(timeout=20);return sql(q)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
        f=[pool.submit(run,q)for q in(a,b)]
        return [x.result()for x in f]
def buy(who,pid,qty=1,items=None):
    cart=items or [{'product_id':pid,'quantity':qty}]
    return "select fr17_test.claim('"+who+"');select public.fr10_checkout('"+str(uuid.uuid4())+"','"+json.dumps(cart)+"','{\"address\":\"FR17 LOCAL synthetic\",\"lat\":33.68,\"lng\":73.04,\"speed\":\"standard\"}');"
def transaction(q):return 'begin;'+q+'commit;'
def product(qty,threshold=5):return int(scalar(f"select fr17_test.product({qty},{threshold});"))
def one_json(output):return json.loads(next(line for line in output.splitlines()if line.startswith('{')))

sql("""create schema if not exists fr17_test;
create table if not exists fr17_test.people(label text primary key,id bigint,auth_id uuid,session_id uuid,email text);
do $$declare who text;a uuid;s uuid;uid bigint;mail text;begin
foreach who in array array['vendor','customer0','customer1','customer2','customer3','customer4','customer5','customer6','customer7','customer8','customer9']loop
if exists(select 1 from fr17_test.people where label=who)then continue;end if;
a:=gen_random_uuid();s:=gen_random_uuid();mail:='fr17-local-'||a||'@example.test';
insert into auth.users(id,email,email_confirmed_at,role,aud,raw_user_meta_data)values(a,mail,now(),'authenticated','authenticated','{"fr17_fixture":true}');
insert into public.users(email,name,role,verification_status)values(mail,'FR17 LOCAL SYNTHETIC',case when who='vendor'then'vendor'else'customer'end,'approved')returning id into uid;
insert into auth.sessions(id,user_id,created_at,updated_at)values(s,a,now(),now());
insert into fr17_test.people values(who,uid,a,s,mail);end loop;end$$;
create or replace function fr17_test.claim(who text)returns void language plpgsql as $$declare p fr17_test.people;begin
select * into p from fr17_test.people where label=who;
perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id,'email',p.email)::text,true);end$$;
create or replace function fr17_test.product(qty integer,threshold integer)returns bigint language plpgsql as $$declare r jsonb;begin
perform fr17_test.claim('vendor');r:=public.fr17_save_product(gen_random_uuid(),null,'{"name":"FR17 LOCAL synthetic","price":80,"is_available":true}',qty,threshold,null);
if r->>'code'<>'UPDATED'then raise exception 'Local fixture creation failed';end if;return(r->>'product_id')::bigint;end$$;
create or replace function fr17_test.wait_for(k integer)returns void language plpgsql as $$begin
for i in 1..500 loop
if exists(select 1 from pg_locks where locktype='advisory'and objid=k::oid and granted)then return;end if;
perform pg_sleep(0.01);end loop;raise exception 'Actual first-session lock signal not observed';end$$;
select cron.alter_job(jobid,active:=false)from cron.job where jobname='fr10-order-timeout';
""")
try:
    p=product(1,0)
    results=pair(transaction(buy('customer0',p)),transaction(buy('customer1',p)))
    check(sorted(one_json(x)['code']for x in results)==['INSUFFICIENT_STOCK','PLACED'],'two real buyers: last unit sold exactly once')
    check(scalar(f'select stock_qty from public.products where id={p};')=='0','last unit ends at zero')
    check(scalar(f"select count(*)from public.inventory_movements where product_id={p} and movement_type='ORDER_DECREMENT';")=='1','last unit one decrement')

    p=product(100,5)
    def many(n):
        return sql("begin;select fr17_test.claim('customer"+str(n)+"');do $$declare r jsonb;begin for i in 1..20 loop r:=public.fr10_checkout(gen_random_uuid(),'[{\"product_id\":"+str(p)+",\"quantity\":1}]','{\"address\":\"FR17 local\",\"lat\":33.68,\"lng\":73.04,\"speed\":\"standard\"}');if r->>'code'not in('PLACED','INSUFFICIENT_STOCK')then raise exception 'Unexpected concurrent result %',r->>'code';end if;end loop;end$$;commit;")
    with concurrent.futures.ThreadPoolExecutor(max_workers=10)as pool:list(pool.map(many,range(10)))
    check(scalar(f"select count(*)from public.inventory_movements where product_id={p} and movement_type='ORDER_DECREMENT';")=='100','200 valid attempts across10 independent buyers: exactly100 purchases')
    check(scalar(f'select stock_qty from public.products where id={p};')=='0','popular product never oversold')
    check(scalar(f'select count(*)from public.notifications where stock_product_id={p};')=='1','concurrent threshold crossing emits exactly one alert')

    p=product(10);q=product(10)
    carts=[[{'product_id':p,'quantity':1},{'product_id':q,'quantity':1}],[{'product_id':q,'quantity':1},{'product_id':p,'quantity':1}]]
    results=pair(transaction(buy('customer0',p,items=carts[0])),transaction(buy('customer1',p,items=carts[1])))
    check(all(one_json(x)['code']=='PLACED'for x in results),'opposite multi-product input ordering completes without deadlock')
    check(scalar(f'select sum(stock_qty)from public.products where id in({p},{q});')=='16','multi-product exact decrements')

    p=product(5);version=int(scalar(f'select stock_version from public.products where id={p};'))
    a=transaction(buy('customer0',p)+"select pg_advisory_xact_lock(171701);select pg_sleep(1);")
    b=transaction("select fr17_test.wait_for(171701);select fr17_test.claim('vendor');"+f"select public.vendor_adjust_stock({p},5,'set','FR17 concurrent count',gen_random_uuid(),null,{version});")
    results=pair(a,b)
    check(one_json(results[1])['code']=='STOCK_CHANGED'and scalar(f'select stock_qty from public.products where id={p};')=='4','absolute vendor count waiting behind checkout rejects stale version')

    p=product(5);r=one_json(sql(transaction(buy('customer0',p,2))));oid=r['order_id']
    vid=int(scalar(f'select id from public.vendor_orders where order_id={oid};'))
    a=transaction(buy('customer1',p,3)+"select pg_advisory_xact_lock(171702);select pg_sleep(1);")
    b=transaction(f"select fr17_test.wait_for(171702);select fr17_test.claim('vendor');select public.fr10_vendor_transition({vid},'cancelled');")
    results=pair(a,b)
    check(one_json(results[0])['code']=='PLACED'and one_json(results[1])['code']=='ORDER_CANCELLED','checkout and cancellation use compatible locks')
    check(scalar(f'select stock_qty from public.products where id={p};')=='2','concurrent cancellation restores exactly consumed two units')

    p=product(5);r=one_json(sql(transaction(buy('customer0',p,2))));oid=r['order_id'];vid=int(scalar(f'select id from public.vendor_orders where order_id={oid};'))
    cancel=transaction(f"select fr17_test.claim('vendor');select public.fr10_vendor_transition({vid},'cancelled');")
    results=pair(cancel,cancel)
    check(all(one_json(x)['code']=='ORDER_CANCELLED'for x in results),'concurrent cancellation retries return confirmed cancelled')
    check(scalar(f"select count(*)from public.inventory_movements where order_id={oid} and movement_type='ORDER_RESTORE';")=='1'and scalar(f'select stock_qty from public.products where id={p};')=='5','concurrent cancellation restores once')

    p=product(7,5)
    results=pair(transaction(buy('customer0',p)),transaction(buy('customer1',p)))
    check(all(one_json(x)['code']=='PLACED'for x in results)and scalar(f'select count(*)from public.notifications where stock_product_id={p};')=='1','two simultaneous purchases crossing7 to5 notify once')
    check(scalar(f"select stock_qty-(select coalesce(sum(quantity_delta),0)from public.inventory_movements where product_id={p})from public.products where id={p};")=='0','real concurrent movements reconcile opening0 to final stock')
    result={'checks':checks,'independent_sessions':True,'local_only':True,'popular_product_attempts':200,'popular_product_purchases':100,'optional_1000_VUs':'NOT EXECUTED by SQL runner'}
    (d.OUT/'local-concurrency.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({'passed':len(checks),'local_only':True,'popular_product':'100/200 purchased; stock0; one crossing notice'}))
finally:
    sql("select cron.alter_job(jobid,active:=true)from cron.job where jobname='fr10-order-timeout';")
