"""Real Auth/REST/Realtime checks. Dedicated TEST only; never prints credentials."""
import concurrent.futures
import ctypes
import datetime as dt
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REF = 'igeisilhtmglgnqvllrx'
BASE = f'https://{REF}.supabase.co'
ROOT = Path(__file__).resolve().parents[2]
PRIVATE = Path(os.environ['FR21_PRIVATE_DIRECTORY'])
sys.path.insert(0, str(ROOT / 'build/fr21-python'))
from websockets.sync.client import connect


class Blob(ctypes.Structure):
    _fields_ = [('size', ctypes.c_ulong), ('data', ctypes.POINTER(ctypes.c_ubyte))]


def protect(data, decrypt=False):
    buffer = ctypes.create_string_buffer(data)
    source = Blob(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)))
    output = Blob()
    fn = ctypes.windll.crypt32.CryptUnprotectData if decrypt else ctypes.windll.crypt32.CryptProtectData
    if not fn(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(output)):
        raise RuntimeError('Windows private fixture protection failed')
    try:
        return ctypes.string_at(output.data, output.size)
    finally:
        ctypes.windll.kernel32.LocalFree(output.data)


def target():
    if (ROOT / 'supabase/.temp/project-ref').read_text().strip() != REF:
        raise RuntimeError('Linked TEST target mismatch')


keys = json.loads(os.environ['FR21_TEST_KEYS_JSON'])
ANON = next(k['api_key'] for k in keys if k['name'] == 'anon')
SERVICE = next(k['api_key'] for k in keys if k['name'] == 'service_role')
checks = []
state_file = PRIVATE / 'accounts.bin'
state = json.loads(protect(state_file.read_bytes(), True)) if state_file.exists() else {'accounts': {}, 'orders': []}


def save():
    state_file.write_bytes(protect(json.dumps(state).encode()))


def check(ok, label):
    if not ok:
        raise AssertionError(label)
    checks.append(label)


def request(path, method='GET', body=None, token=None, expected=(200, 201, 204), admin=False):
    target()  # Immediately before every hosted write, as well as reads.
    key = SERVICE if admin else ANON
    headers = {'apikey': key, 'Authorization': 'Bearer ' + (token or key),
               'Content-Type': 'application/json', 'Prefer': 'return=representation'}
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode() if body is not None else None,
                                 headers=headers, method=method)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                status, raw = response.status, response.read()
            break
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read()
            break
        except (TimeoutError, urllib.error.URLError):
            retryable = method == 'GET' or (path.startswith('/rest/v1/rpc/')
                and not path.endswith('/fr21_begin_presence'))
            if not retryable or attempt == 2:
                raise
            time.sleep(.5 * (2 ** attempt))
    result = json.loads(raw) if raw else None
    if status not in expected:
        code = result.get('code', 'unknown') if isinstance(result, dict) else 'unknown'
        raise RuntimeError(f'HTTP {status}, code {code}, endpoint {path.split("?")[0]}')
    return result


def rpc(name, params, token, expected=(200,)):
    return request('/rest/v1/rpc/' + name, 'POST', params, token, expected)


def row(table, payload):
    return request('/rest/v1/' + table, 'POST', payload, admin=True)[0]


def fixture(name, role, approved=True):
    account = state['accounts'].setdefault(name, {
        'email': f'fr21-device-{name}@example.test',
        'password': secrets.token_urlsafe(24) + 'aA7!', 'role': role,
    })
    save()  # Keep recovery credentials before creating the remote identity.
    if 'auth_id' not in account:
        user = request('/auth/v1/admin/users', 'POST', {
            'email': account['email'], 'password': account['password'], 'email_confirm': True,
            'user_metadata': {'name': 'FR21 synthetic ' + name, 'role': role, 'fr21_fixture': True},
        }, admin=True)
        account['auth_id'] = user['id']
        save()
    if 'profile_id' not in account:
        profile = row('users', {'name': 'FR21 synthetic ' + name, 'email': account['email'],
                              'role': role, 'verification_status': 'approved' if approved else 'pending'})
        account['profile_id'] = profile['id']
        save()
    login = request('/auth/v1/token?grant_type=password', 'POST', {
        'email': account['email'], 'password': account['password']})
    check(login['user']['id'] == account['auth_id'], 'real Auth login: ' + name)
    return {**account, 'token': login['access_token'], 'refresh': login['refresh_token']}


def new_order(customer, vendor):
    # Fixture parent/vendor/item rows are one server-side transaction, not
    # sequential client business writes. All interpolated identities are ints.
    customer_id, vendor_id, product_id = int(customer['profile_id']), int(vendor['profile_id']), int(state['product_id'])
    sql = f"""with o as (
      insert into public.orders(user_id,amount,order_status,delivery_address,delivery_lat,delivery_lng)
      values({customer_id},100,'accepted','FR21 synthetic device delivery',31.52,74.35) returning *
    ), v as (
      insert into public.vendor_orders(order_id,vendor_id,sub_total,status)
      select id,{vendor_id},100,'accepted' from o returning *
    ), item as (
      insert into public.order_items(vendor_order_id,product_id,quantity,price_at_time)
      select id,{product_id},1,100 from v returning id
    ) select jsonb_build_object('order',to_jsonb(o),'vendor_order',to_jsonb(v)) as fixture
      from o cross join v where exists(select 1 from item);"""
    file = ROOT/'build/fr21-hosted-evidence/synthetic-order.sql'
    file.write_text(sql, encoding='utf-8')
    target()
    cli = 'C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
    response = subprocess.run([cli,'db','query','--linked','--project-ref',REF,'--file',str(file),'--output','json'],
                              capture_output=True,text=True,encoding='utf-8',timeout=60)
    if response.returncode:
        raise RuntimeError('Atomic synthetic order fixture failed')
    data = json.loads(response.stdout[response.stdout.index('{'):])['rows'][0]['fixture']
    order, vo = data['order'], data['vendor_order']
    state['orders'].append(order['id'])
    save()
    return order, vo


class Live:
    def __init__(self, table, filter_, token):
        target()
        self.topic = 'realtime:fr21-integration-' + secrets.token_hex(4)
        self.ws = connect(f'wss://{REF}.supabase.co/realtime/v1/websocket?'
                          + urllib.parse.urlencode({'apikey': ANON, 'vsn': '1.0.0'}),
                          open_timeout=15, close_timeout=3)
        self.ws.send(json.dumps({'topic': self.topic, 'event': 'phx_join', 'ref': '1',
            'payload': {'config': {'broadcast': {'self': False}, 'presence': {'key': ''},
                'postgres_changes': [{'event': '*', 'schema': 'public', 'table': table, 'filter': filter_}]},
                'access_token': token}}))
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            message = json.loads(self.ws.recv(timeout=max(.1, deadline - time.monotonic())))
            if message['event'] == 'system':
                check(message['payload'].get('status') == 'ok', 'Realtime subscription accepted')
                return
            if message['event'] == 'phx_reply' and message['payload'].get('status') == 'error':
                raise RuntimeError('Realtime subscription rejected')
        raise RuntimeError('Realtime subscription readiness timed out')

    def receive(self, record_id, seconds=15):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                message = json.loads(self.ws.recv(timeout=max(.1, deadline-time.monotonic())))
            except TimeoutError:
                return False
            if message['event'] == 'postgres_changes':
                record = message['payload'].get('data', {}).get('record', {})
                if record.get('id') == record_id:
                    return True
        return False

    def close(self):
        self.ws.close()


def main():
    rider = fixture('approved-rider', 'rider')
    other = fixture('second-rider', 'rider')
    pending = fixture('pending-rider', 'rider', False)
    customer = fixture('customer', 'customer')
    vendor = fixture('vendor', 'vendor')
    admin = fixture('admin', 'admin')
    stranger = fixture('other-vendor', 'vendor')
    profiles = request('/rest/v1/users?select=id,role,verification_status', token=rider['token'])
    check(len(profiles) == 1 and profiles[0]['id'] == rider['profile_id'], 'own profile access only')
    for actor in (customer, vendor, admin):
        failure = rpc('fr21_begin_presence', {}, actor['token'], (403,))
        check(failure['code'] == '42501', 'non-rider presence rejected: ' + actor['role'])
    session = rpc('fr21_begin_presence', {}, pending['token'])
    failure = rpc('fr21_set_presence', {'p_online': True, 'p_epoch': session['epoch'], 'p_sequence': 1},
                  pending['token'], (403,))
    check(failure['code'] == '42501', 'pending rider cannot go online')
    for actor in (rider, other):
        rpc('fr21_update_location', {'p_lat': 31.52, 'p_lng': 74.35}, actor['token'], (204,))
    existing = request(f'/rest/v1/vendors?user_id=eq.{vendor["profile_id"]}&select=id', admin=True)
    if not existing:
        row('vendors', {'user_id': vendor['profile_id'], 'store_name': 'FR21 synthetic shop',
                        'latitude': 31.52, 'longitude': 74.35})
    product_query = urllib.parse.urlencode({'vendor_id':f'eq.{vendor["profile_id"]}',
                                            'name':'eq.FR21 Test Item','select':'id'})
    products = request('/rest/v1/products?'+product_query, admin=True)
    if not products:
        products = [row('products',{'vendor_id':vendor['profile_id'],'name':'FR21 Test Item',
                                   'category':'General','price':100,'is_available':True,
                                   'description':'Synthetic FR21 device fixture; not a real sale.'})]
    state['product_id'] = products[0]['id']
    save()
    for order_id in state['orders']:
        own = request(f'/rest/v1/orders?id=eq.{order_id}&user_id=eq.{customer["profile_id"]}&select=id', admin=True)
        if own:
            request(f'/rest/v1/orders?id=eq.{order_id}', 'PATCH', {'order_status': 'cancelled'}, admin=True)
    for actor in (rider, other):
        request(f'/rest/v1/riders?userid=eq.{actor["profile_id"]}', 'PATCH',
                {'is_online': False, 'is_available': True, 'isavailable': True}, admin=True)

    session = rpc('fr21_begin_presence', {}, rider['token'])
    check(not session['is_online'], 'offline status restored')
    params = {'p_online': True, 'p_epoch': session['epoch'], 'p_sequence': 1}
    first = rpc('fr21_set_presence', params, rider['token'])
    check(first['is_online'], 'online persisted')
    duplicate = rpc('fr21_set_presence', params, rider['token'])
    check(duplicate['last_seen'] == first['last_seen'], 'duplicate heartbeat is idempotent')
    time.sleep(1)
    params['p_sequence'] = 2
    heartbeat = rpc('fr21_set_presence', params, rider['token'])
    check(heartbeat['last_seen'] > first['last_seen'], 'server heartbeat advances')
    own = request(f'/rest/v1/riders?userid=eq.{rider["profile_id"]}&select=is_online,last_seen', token=rider['token'])
    check(own[0]['is_online'], 'real REST reads persisted online state')
    denied = request(f'/rest/v1/riders?userid=eq.{rider["profile_id"]}', 'PATCH', {'is_online': False}, other['token'])
    check(denied == [], 'other rider update affects no rows')
    forbidden = request(f'/rest/v1/riders?userid=eq.{rider["profile_id"]}', 'PATCH', {'latitude': 0},
                        rider['token'], (403,))
    check(forbidden['code'] == '42501', 'protected rider field rejected')
    request(f'/rest/v1/riders?userid=eq.{rider["profile_id"]}', 'PATCH',
            {'last_seen': (dt.datetime.now(dt.timezone.utc)-dt.timedelta(seconds=121)).isoformat()}, admin=True)
    expired_order, expired_vo = new_order(customer, vendor)
    expired = rpc('fr21_ready_and_assign', {'p_vendor_order_id': expired_vo['id']}, vendor['token'])
    check(expired.get('rider_id') is None, 'expired rider cannot be assigned')
    ready_row = request(f'/rest/v1/vendor_orders?id=eq.{expired_vo["id"]}&select=status', token=vendor['token'])[0]
    check(ready_row['status'] == 'ready', 'no rider means ready, never falsely on the way')
    session = rpc('fr21_begin_presence', {}, rider['token'])
    check(not session['is_online'], 'crash expiry restores offline')
    rpc('fr21_set_presence', {'p_online': True, 'p_epoch': session['epoch'], 'p_sequence': 1}, rider['token'])
    restored = rpc('fr21_begin_presence', {}, rider['token'])
    check(restored['is_online'], 'fresh online status restored after restart')
    conflict_started = time.monotonic()
    failure = rpc('fr21_set_presence', {'p_online': True, 'p_epoch': session['epoch'], 'p_sequence': 2}, rider['token'], (409,))
    check(failure['code'] == 'PT409' and time.monotonic()-conflict_started<8,
          'old app session returns prompt HTTP conflict without retry loop')

    order_a, vo_a = new_order(customer, vendor)
    order_b, vo_b = new_order(customer, vendor)
    row('vendor_orders',{'order_id':order_a['id'],'vendor_id':stranger['profile_id'],
                         'sub_total':20,'status':'accepted'})
    unrelated = request(f'/rest/v1/vendor_orders?id=eq.{vo_a["id"]}&select=id',token=stranger['token'])
    check(unrelated == [], 'shared parent does not expose another vendor line')
    rpc('fr21_set_presence', {'p_online': True, 'p_epoch': restored['epoch'], 'p_sequence': 1}, rider['token'])
    live = Live('vendor_orders', f'vendor_id=eq.{vendor["profile_id"]}', vendor['token'])
    spy = Live('vendor_orders', f'vendor_id=eq.{vendor["profile_id"]}', stranger['token'])
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda vo: rpc('fr21_ready_and_assign', {'p_vendor_order_id': vo['id']}, vendor['token']), (vo_a, vo_b)))
        check(sum(result.get('rider_id') == rider['profile_id'] for result in results) == 1,
              'parallel orders cannot double reserve one rider')
        check(live.receive(vo_a['id']), 'authorized Realtime event received')
        check(not spy.receive(vo_a['id'], 3), 'Realtime hides another vendor order')
    finally:
        live.close()
        spy.close()
    selected = 0 if results[0].get('rider_id') else 1
    order, vo = (order_a, vo_a) if selected == 0 else (order_b, vo_b)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        duplicates = list(pool.map(lambda _: rpc('fr21_ready_and_assign', {'p_vendor_order_id': vo['id']}, vendor['token']), range(16)))
    check(all(result['rider_id'] == rider['profile_id'] for result in duplicates), 'concurrent duplicate requests return same assignment')
    assignments = request(f'/rest/v1/rider_assignments?orderid=eq.{order["id"]}&select=id', token=rider['token'])
    check(len(assignments) == 1, 'exactly one persisted assignment')
    contacts = rpc('fr21_order_contacts', {'p_order_ids': [order['id']]}, vendor['token'])
    check(len(contacts) == 1 and set(contacts[0]) == {'order_id','name','phone'}, 'bounded customer contact projection excludes private fields')
    # FR33 intentionally removes plaintext OTP access. This trusted security
    # fixture simulates provider acceptance only; it never sends real email.
    import uuid
    issuance_id=str(uuid.uuid4())
    reserved=request('/rest/v1/rpc/issue_delivery_otp','POST',{'p_order_id':order['id'],'p_request_id':issuance_id,'p_actor':rider['auth_id']},admin=True)
    check(reserved['code']=='SEND','protected server OTP fixture reserved for delivery regression')
    request('/rest/v1/rpc/fr33_start_send','POST',{'p_id':issuance_id},admin=True)
    request('/rest/v1/rpc/fr33_finish_send','POST',{'p_id':issuance_id,'p_result':'ACCEPTED','p_provider_id':'FR21-REGRESSION-MOCK-PROVIDER'},admin=True)
    check(not rpc('fr21_complete_delivery', {'p_order_id':order['id'],'p_otp':'wrong'},rider['token']),'wrong OTP does not complete delivery')
    check(rpc('fr21_complete_delivery', {'p_order_id':order['id'],'p_otp':reserved['otp']},rider['token']),'delivery completion releases reservation')
    check(rpc('fr21_complete_delivery', {'p_order_id':order['id'],'p_otp':reserved['otp']},rider['token']),'delivery retry is idempotent')
    delivered_vo = request(f'/rest/v1/vendor_orders?id=eq.{vo["id"]}&select=status',token=vendor['token'])[0]
    check(delivered_vo['status']=='delivered','delivery status propagates to vendor history')
    receipts = request(f'/rest/v1/delivery_proof?orderid=eq.{order["id"]}&select=id,otpconfirmed,is_verified', token=rider['token'])
    check(len(receipts) == 1 and receipts[0]['otpconfirmed'] and receipts[0]['is_verified'],
          'atomic OTP receipt persists once without client fabrication')
    remaining = vo_b if selected == 0 else vo_a
    rpc('fr21_set_presence', {'p_online': True, 'p_epoch': restored['epoch'], 'p_sequence': 2}, rider['token'])
    reconnect = Live('vendor_orders', f'vendor_id=eq.{vendor["profile_id"]}', vendor['token'])
    try:
        reassigned = rpc('fr21_ready_and_assign', {'p_vendor_order_id': remaining['id']}, vendor['token'])
        check(reassigned.get('rider_id') == rider['profile_id'], 'released rider receives next order')
        check(reconnect.receive(remaining['id']), 'Realtime works after reconnection')
    finally:
        reconnect.close()
    remaining_order = order_b if selected == 0 else order_a
    cancelled = request(f'/rest/v1/orders?id=eq.{remaining_order["id"]}', 'PATCH', {'order_status': 'cancelled'}, customer['token'])
    check(len(cancelled) == 1, 'own customer cancellation confirmed')
    flags = request(f'/rest/v1/riders?userid=eq.{rider["profile_id"]}&select=is_available,isavailable', token=rider['token'])[0]
    check(flags['is_available'] and flags['isavailable'], 'cancellation releases both availability flags')
    renewed = request('/auth/v1/token?grant_type=refresh_token','POST',{'refresh_token': rider['refresh']})
    check(renewed['user']['id'] == rider['auth_id'], 'real Auth session refresh')
    offline = rpc('fr21_set_presence', {'p_online': False, 'p_epoch': restored['epoch'], 'p_sequence': 3}, rider['token'])
    check(not offline['is_online'], 'offline persisted')
    final = rpc('fr21_begin_presence', {}, rider['token'])
    check(not final['is_online'], 'offline survives next app session')
    device_order, device_vo = new_order(customer, vendor)
    state['manual_order_id'], state['manual_vendor_order_id'] = device_order['id'], device_vo['id']
    save()
    # Device credentials stay outside the repository in the user-only private directory.
    (PRIVATE / 'device-accounts.txt').write_text('\n\n'.join(
        f'{name}\nEmail: {account["email"]}\nPassword: {account["password"]}'
        for name,account in state['accounts'].items()), encoding='utf-8')
    report = {'project_ref': REF, 'passed': len(checks), 'failed': 0, 'checks': checks,
              'manual_order_id': device_order['id'], 'manual_vendor_order_id': device_vo['id']}
    (ROOT / 'build/fr21-hosted-evidence/integration.json').write_text(json.dumps(report, indent=2))
    print(json.dumps({'project_ref': REF, 'passed': len(checks), 'failed': 0}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Never dump response bodies, tokens, credentials or WebSocket URLs.
        print(json.dumps({'passed': len(checks), 'failed': 1, 'error_type': type(error).__name__,
                          'reason': str(error) if isinstance(error,(AssertionError,RuntimeError)) else 'Transport/protocol failure',
                          'last_pass': checks[-1] if checks else None}))
        sys.exit(1)
