"""Bounded TEST-only HTTP/cron checks; synthetic records, no money movement."""
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import secrets
import sys
import uuid

spec = importlib.util.spec_from_file_location('fr30_shared', Path(__file__).with_name('FR-30-hosted.py'))
previous = importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)
b = previous.b
ROOT = previous.ROOT
OUT = ROOT / '.fr21-local/fr10'
FILE = b.PRIVATE / 'fr10-accounts.bin'
state = json.loads(b.crypt(FILE.read_bytes(), True)) if FILE.exists() else {'accounts': {}, 'orders': {}}
checks = []


def save():
    FILE.write_bytes(b.crypt(json.dumps(state).encode()))


def check(value, name):
    assert value, name
    checks.append({'check': name, 'result': 'PASS'})


def query(sql):
    path = OUT / 'hosted-query.sql'
    path.write_text(sql, encoding='utf-8')
    return previous.query(path)['rows']


def fixture(label, role):
    a = state['accounts'].setdefault(label, {'email': 'fr10-'+label+'@example.test', 'password': secrets.token_urlsafe(28)+'aA7!'})
    save()
    if 'auth_id' not in a:
        status, row = b.api('/auth/v1/admin/users', 'POST', {'email': a['email'], 'password': a['password'], 'email_confirm': True, 'user_metadata': {'fr10_fixture': True, 'role': role}}, admin=True)
        assert status in (200, 201), 'Synthetic Auth fixture creation'
        a['auth_id'] = row['id']
        save()
    if 'profile_id' not in a:
        status, rows = b.api('/rest/v1/users', 'POST', {'email': a['email'], 'name': 'FR10 synthetic '+label, 'role': role, 'verification_status': 'approved'}, admin=True)
        assert status == 201, 'Synthetic profile fixture creation'
        a['profile_id'] = rows[0]['id']
        save()
    return a


def make_expired(label, method='COD', payment_status='pending', customer=None):
    uid = (customer or state['accounts']['customer'])['profile_id']
    vid = state['accounts']['vendor']['profile_id']
    # Controlled timestamps are established before the order becomes managed.
    row = query(f"""begin;create temp table made(id bigint);
    with o as(insert into public.orders(user_id,amount,fare,order_status,payment_method,timeout_review_reason)
    values({uid},200,120,'pending','{method}','fr10_harness_hold')returning id)insert into made select id from o;
    insert into public.vendor_orders(order_id,vendor_id,sub_total,status,acceptance_started_at,acceptance_deadline_at)
    select id,{vid},80,'pending',clock_timestamp()-interval '1 hour',clock_timestamp()-interval '1 second'from made;
    insert into public.payments(paymentid,orderid,customerid,method,status,amount,paidat)
    select 'fr10-test-'||id,id::text,'{uid}','{method}','{payment_status}',200,
    case when '{payment_status}'='SUCCESS'then clock_timestamp()else null end from made;
    update public.orders set checkout_finalized_at=clock_timestamp(),acceptance_deadline_at=clock_timestamp()-interval '1 second'where id in(select id from made);
    select o.id,(select id from public.vendor_orders where order_id=o.id)as vendor_order_id from public.orders o join made m on m.id=o.id;commit;""")[0]
    state['orders'][label] = row
    save()
    return row


def hosted():
    for label, role in [('customer','customer'),('other','customer'),('vendor','vendor'),('other-vendor','vendor'),('rider','rider'),('admin','admin')]:
        fixture(label, role)
    tokens = {k:b.login(v) for k,v in state['accounts'].items()}
    vendor = state['accounts']['vendor']['profile_id']
    status, products = b.api('/rest/v1/products', 'POST', {'vendor_id': vendor, 'name': 'FR10 synthetic checkout', 'price': 80, 'is_available': True}, admin=True)
    check(status == 201, 'synthetic canonical product')
    request = {'p_request_id': str(uuid.uuid4()), 'p_items': [{'product_id': products[0]['id'], 'quantity': 1}], 'p_delivery': {'address':'FR10 synthetic TEST address','lat':33.68,'lng':73.04,'speed':'standard'}}
    status, result = b.rpc('fr10_checkout', request, tokens['customer'])
    check(status == 200 and result['code'] == 'PLACED' and result['amount'] == 200, 'real HTTP atomic checkout')
    oid = result['order_id']
    state['orders']['http-checkout'] = {'id':oid}
    save()
    status, again = b.rpc('fr10_checkout', request, tokens['customer'])
    check(status == 200 and again['code'] == 'ALREADY_PLACED' and again['order_id'] == oid, 'HTTP retry uses same order')
    status, rows = b.api(f'/rest/v1/vendor_orders?order_id=eq.{oid}&select=id,status', token=tokens['vendor'])
    check(status == 200 and len(rows) == 1, 'own vendor child readable')
    vid = rows[0]['id']
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: b.rpc('fr10_vendor_transition', {'p_vendor_order_id':vid,'p_status':'accepted'},tokens['vendor']), range(2)))
    check(all(s == 200 for s,r in results) and sorted(r['code'] for s,r in results) == ['ACCEPTED','ALREADY_ACCEPTED'], 'two simultaneous HTTP accepts commit once')
    status, denied = b.rpc('fr10_vendor_transition', {'p_vendor_order_id':vid,'p_status':'accepted'},tokens['other-vendor'])
    check(status == 200 and denied['code'] == 'FORBIDDEN', 'other vendor HTTP acceptance denied')
    for label in ['customer','vendor','rider','admin']:
        status, _ = b.rpc('cancel_timed_out_orders', {'p_limit':1}, tokens[label])
        check(status in (401,403,404), label+' cannot call scheduler RPC')
    status, _ = b.rpc('cancel_timed_out_orders', {'p_limit':1})
    check(status in (401,403,404), 'anonymous cannot call scheduler')
    for label,method,pay in [('cod','COD','pending'),('captured','CARD','SUCCESS'),('authorized','CARD','AUTHORIZED')]:
        o = make_expired(label,method,pay)
        status, expired = b.rpc('fr10_vendor_transition', {'p_vendor_order_id':o['vendor_order_id'],'p_status':'accepted'}, tokens['vendor'])
        check(status == 200 and expired['code'] == 'ORDER_EXPIRED', label+' expired independently of scheduler')
    ids = ','.join(str(state['orders'][k]['id']) for k in ['cod','captured','authorized'])
    query(f"begin;update public.orders set timeout_review_reason=null where id in({ids});select public.cancel_timed_out_orders();commit;")
    for label in ['cod','captured','authorized']:
        oid = state['orders'][label]['id']
        row = query(f"select o.order_status,o.cancellation_reason,(select count(*)from public.notifications where timeout_order_id=o.id)as notices,(select count(*)from public.order_timeline_events where order_id=o.id and status='cancelled')as events,(select count(*)from public.order_refund_actions where order_id=o.id and status='PENDING'and amount=200)as refunds from public.orders o where id={oid};")[0]
        check(row['order_status'] == 'cancelled' and row['cancellation_reason'] == 'vendor_timeout' and row['notices'] == row['events'] == 1, label+' committed one cancellation/notice/timeline')
        check(row['refunds'] == (1 if label == 'captured' else 0), label+' correct financial obligation')
    status, rows = b.rpc('fr25_order_history', {}, tokens['customer'])
    check(status == 200 and any(r['id'] == state['orders']['captured']['id'] and r['order_refund_actions'][0]['status'] == 'PENDING' for r in rows), 'owned history includes refund/timeline')
    status, rows = b.api('/rest/v1/order_refund_actions?select=id', token=tokens['other'])
    check(status == 200 and rows == [], 'refund RLS other owner isolation')
    status, rows = b.api('/rest/v1/order_timeline_events?select=id', token=tokens['other'])
    check(status == 200 and rows == [], 'timeline RLS other owner isolation')
    status, _ = b.api('/rest/v1/order_refund_actions','POST',{'order_id':oid,'payment_id':1,'customer_id':1,'amount':1,'reason':'vendor_timeout'},token=tokens['customer'])
    check(status in (401,403), 'client cannot forge refund')
    (OUT/'hosted-tests.json').write_text(json.dumps({'passed':len(checks),'checks':checks,'project':b.REF,'actual_money_movement':False},indent=2),encoding='utf-8')
    print(json.dumps({'passed':len(checks),'project':b.REF,'synthetic_only':True}))


def verify():
    result = query("""select jsonb_build_object('versions',(select jsonb_agg(version order by version)from supabase_migrations.schema_migrations),
    'config',(select vendor_acceptance_timeout_seconds from fr10_private.configuration),
    'jobs',(select jsonb_agg(jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'active',active))from cron.job where jobname in('fr10-order-timeout','fr30-android-push')),
    'worker_anonymous_execute',has_function_privilege('anon','public.cancel_timed_out_orders(integer)','EXECUTE'),
    'worker_authenticated_execute',has_function_privilege('authenticated','public.cancel_timed_out_orders(integer)','EXECUTE'),
    'worker_service_execute',has_function_privilege('service_role','public.cancel_timed_out_orders(integer)','EXECUTE'),
    'cron_runs',(select coalesce(jsonb_agg(x),'[]'::jsonb)from(select status,start_time,end_time from cron.job_run_details where jobid in(select jobid from cron.job where jobname='fr10-order-timeout')order by start_time desc limit 5)x))as verification;""")[0]['verification']
    check(result['config'] == 180, 'approved default restored')
    check(len([j for j in result['jobs'] if j['name']=='fr10-order-timeout' and j['active'] and j['schedule']=='* * * * *']) == 1, 'exactly one active minute job')
    check(not result['worker_anonymous_execute'] and not result['worker_authenticated_execute'] and not result['worker_service_execute'], 'no client/service scheduler execute')
    (OUT/'hosted-verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({'verification':checks,'cron_runs':result['cron_runs']}))


def cron_seed():
    o=make_expired('autonomous-cron','CARD','SUCCESS')
    row=query(f"update public.orders set timeout_review_reason=null where id={o['id']} returning clock_timestamp()as released_at;")[0]
    state['cron_released_at']=row['released_at']
    save()
    print(json.dumps({'synthetic_eligible_order_created':True,'manual_worker_call':False,'scheduler_result':'PENDING'}))


def cron_verify():
    oid=state['orders']['autonomous-cron']['id']
    row=query(f"""select o.order_status,o.cancellation_reason,
    (select count(*)from public.notifications where timeout_order_id=o.id)as notices,
    (select count(*)from public.order_refund_actions where order_id=o.id and status='PENDING'and amount=200)as refunds,
    (select count(*)from public.order_timeline_events where order_id=o.id and status='cancelled')as events,
    exists(select 1 from cron.job_run_details where jobid in(select jobid from cron.job where jobname='fr10-order-timeout')
    and start_time>='{state['cron_released_at']}'::timestamptz and status='succeeded')as cron_succeeded
    from public.orders o where o.id={oid};""")[0]
    if row['order_status']!='cancelled':
        print(json.dumps({'scheduler_result':'PENDING','manual_worker_call':False}))
        return
    assert row['cron_succeeded']and row['notices']==row['refunds']==row['events']==1,'Autonomous cron cancellation invariant'
    result={'result':'PASS','autonomous_cron':True,'manual_worker_call':False,'verified':row}
    (OUT/'autonomous-cron.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        if sys.argv[1]=='hosted':hosted()
        elif sys.argv[1]=='verify':verify()
        elif sys.argv[1]=='cron-seed':cron_seed()
        elif sys.argv[1]=='cron-verify':cron_verify()
        else:raise ValueError('Unknown guarded TEST phase')
    except Exception as error:
        print(json.dumps({'failed':True,'type':type(error).__name__,'reason':str(error)if isinstance(error,AssertionError)else 'Guarded TEST operation failed; no credentials emitted'}))
        sys.exit(1)
