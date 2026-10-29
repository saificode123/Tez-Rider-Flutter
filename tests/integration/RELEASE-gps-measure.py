"""Bounded real TEST GPS/route measurements; never saves coordinates or tokens."""
import datetime as dt
import http.client
import importlib.util
import json
from pathlib import Path
import re
import socket
import statistics
import sys
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('release_observer', HERE / 'MASTER-gps-observe.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
OUT = m.delivery.b.ROOT / '.fr21-local/release-gps'
OUT.mkdir(parents=True, exist_ok=True)
m.observer.h.OUT = OUT


def summarize(values):
    ordered = sorted(values)
    return {'samples': len(values), 'p50_ms': round(statistics.median(values), 2),
            'p95_ms': ordered[max(0, __import__('math').ceil(len(values) * .95) - 1)],
            'worst_ms': max(values)} if values else {'samples': 0}


def routes():
    b = m.delivery.b
    token = b.login(m.delivery.state['accounts']['physical-customer'])
    host = b.REF + '.supabase.co'
    started = time.perf_counter()
    socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    dns = round((time.perf_counter() - started) * 1000, 2)
    connection = http.client.HTTPSConnection(host, timeout=40)
    started = time.perf_counter()
    connection.connect()
    connect = round((time.perf_counter() - started) * 1000, 2)
    body = json.dumps({'orderId': m.delivery.state['physical_order']['oid']})
    records = []
    try:
        for _ in range(12):
            started = time.perf_counter()
            connection.request('POST', '/functions/v1/get-delivery-route', body, {
                'apikey': b.ANON, 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
            response = connection.getresponse()
            raw = response.read(2_000_001)
            duration = round((time.perf_counter() - started) * 1000, 2)
            assert len(raw) <= 2_000_000, 'Bounded route response exceeded'
            decoded = time.perf_counter()
            data = json.loads(raw)
            decoding = round((time.perf_counter() - decoded) * 1000, 2)
            route = data.get('route') or {}
            timing = response.getheader('Server-Timing', '')
            stages = {name: float(value) for name, value in re.findall(r'([a-z_]+);dur=([0-9.]+)', timing)}
            records.append({'http_status': response.status, 'code': data.get('code'),
                            'request_ms': duration, 'json_decode_ms': decoding, 'server_stages_ms': stages,
                            'response_bytes': len(raw), 'request_bytes': len(body.encode()),
                            'connection_closed_by_server': response.will_close,
                            'road_geometry': route.get('geometry') is not None,
                            'source': route.get('source'), 'is_stale': route.get('isStale'),
                            'is_approximate': route.get('isApproximate')})
            time.sleep(1)
    finally:
        connection.close()
    result = {'project': b.REF, 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'dns_probe_ms': dns, 'initial_connect_tls_ms': connect, 'requests': records,
              'summary': summarize([r['request_ms'] for r in records]),
              'scope': '12 sequential authorized TEST HTTP requests with a reusable HTTPS connection; initial DNS/connect measured separately. No injected network impairment. Not Flutter rendering or load qualification; timing outside handler includes security and transport, not pure network.'}
    (OUT / 'routes.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))


def delivery_preflight():
    """Read fixture eligibility only; never approve identity or create an order."""
    b = m.delivery.b
    known = {}
    for filename in ('fr04-accounts.bin', 'fr13-accounts.bin', 'fr14-accounts.bin', 'fr33-accounts.bin'):
        path = b.PRIVATE / filename
        if not path.exists():
            continue
        state = json.loads(b.crypt(path.read_bytes(), True))
        for label, account in state.get('accounts', {}).items():
            if isinstance(account, dict) and all(account.get(k) for k in ('auth_id', 'profile_id', 'password')):
                known[account['auth_id']] = {'label': label, 'file': filename, **account}
    code, profiles = b.api('/rest/v1/users?select=id,auth_user_id,role,is_blocked,verification_status,cnic_submission_status,cnic_image_url', admin=True)
    assert code == 200 and len(profiles) < 1000
    code, orders = b.api('/rest/v1/orders?select=rider_id,order_status&order_status=not.in.(delivered,cancelled)&limit=1000', admin=True)
    assert code == 200 and len(orders) < 1000
    candidates = []
    for profile in profiles:
        account = known.get(profile['auth_user_id'])
        if not account or profile['role'] != 'rider' or not account['email'].endswith('@example.test'):
            continue
        candidates.append({'fixture': account['file'] + ':' + account['label'],
                           'approved': profile['verification_status'] == 'approved',
                           'blocked': profile['is_blocked'],
                           'existing_cnic_submission': profile['cnic_submission_status'] == 'submitted' and bool(profile['cnic_image_url']),
                           'active_orders': sum(o['rider_id'] == profile['id'] for o in orders)})
    customer = m.delivery.state['accounts']['physical-customer']
    code, identity = b.api('/auth/v1/admin/users/' + customer['auth_id'], admin=True)
    assert code == 200 and identity['id'] == customer['auth_id']
    result = {'project': b.REF, 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'retained_rider_candidates': candidates,
              'existing_owner_test_customer_contactable': not identity['email'].endswith('@example.test'),
              'existing_owner_test_customer_email_confirmed': bool(identity.get('email_confirmed_at')),
              'owner_test_recipient_mask': identity['email'][:2] + '***@' + identity['email'].split('@',1)[1],
              'scope': 'Read-only protected fixture eligibility. Existing canonical approval is not a new genuine identity verification. No approval, lifecycle mutation or external notification.'}
    demo = json.loads(b.crypt((b.PRIVATE / 'master-demo-credentials.dpapi').read_bytes(), True))
    product_id = demo['products']['Chicken Biryani']['id']
    code, products = b.api('/rest/v1/products?select=id,name,price,stock_qty,is_available,vendor_id&id=eq.' + str(product_id), admin=True)
    assert code == 200 and len(products) == 1 and products[0]['vendor_id'] == demo['accounts']['sana']['profile_id']
    product = products[0]
    assert product['is_available'] and product['stock_qty'] >= 1
    proposal = {'project': b.REF, 'prepared_utc': result['utc'], 'status': 'REVIEWABLE; NOT EXECUTED',
                'product': product, 'quantity': 1, 'payment': 'COD; no provider charge or payout',
                'customer': 'Existing confirmed owner-controlled TEST customer',
                'recipient_mask': result['owner_test_recipient_mask'],
                'rider_fixture': 'fr04-accounts.bin:rider-a',
                'rider_scope': 'Retained canonical TEST approval and existing submitted document; no new identity approval or claim of genuine identity verification',
                'prerequisites': ['Pickup/destination confirmed through the app using actual device/map input',
                                  'Retained rider eligible/online through normal APIs', 'Owner physical proof and received OTP'],
                'requested_external_message_scope': {'otp_emails_max': 2, 'confirmation_emails_max': 1,
                    'invoice_emails_max': 1, 'push': 'Order-related messages only to the connected owner TEST phone'},
                'preserved': ['Two pending demo Riders', 'All existing orders and historical earnings', '47 approved unavailable products'],
                'failure_recovery': 'Cancel only this new order through canonical role APIs if unfinished; confirm stock restoration and record cancellation without inventing delivery/earnings.',
                'backup': 'Encrypted post-seed snapshot, recovered secrets/Storage/Auth and separately captured runtime ledgers; no production target.'}
    (b.ROOT / 'docs/evidence/RELEASE-delivery-proposal.json').write_text(json.dumps(proposal, indent=2) + '\n', encoding='utf-8')
    (OUT / 'delivery-preflight.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))


def customer_runtime():
    """Read the actual app-saved cart; no checkout or lifecycle mutation."""
    b = m.delivery.b
    account = m.delivery.state['accounts']['physical-customer']
    token = b.login(account)
    def rpc(name, params):
        status, value = b.api('/functions/v1/security-gateway', 'POST', {
            'method': 'POST', 'path': '/rpc/' + name, 'query': '',
            'headers': {'content-type': 'application/json'}, 'body': json.dumps(params),
        }, token)
        assert status == 200 and value.get('code') == 'OK', 'Customer runtime read failed'
        return value
    cart = rpc('final2_cart_get', {})
    ratings = rpc('final2_rating_summary', {'p_target_id': 997})
    assert cart['items'] == [] or all(str(i['product_id']) == '224' and i['qty'] == 1 for i in cart['items']), 'Unexpected saved cart; do not overwrite it'
    code, product = b.api('/rest/v1/products?id=eq.224&select=stock_qty,is_available', admin=True)
    assert code == 200 and len(product) == 1 and product[0]['stock_qty'] == 30
    code, profiles = b.api('/rest/v1/users?id=eq.' + str(account['profile_id']) + '&select=role,verification_status,is_blocked', admin=True)
    assert code == 200 and profiles == [{'role': 'customer', 'verification_status': 'approved', 'is_blocked': False}]
    result = {'project': b.REF, 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'customer_completion_confirmed': True, 'canonical_cart_read': 'OK',
              'reviewed_product_saved_quantity': sum(i['qty'] for i in cart['items'] if str(i['product_id']) == '224'),
              'stock_quantity': product[0]['stock_qty'], 'ratings_read': ratings['code'],
              'scope': 'Actual Customer-authorized reads after physical completion/sign-in. Saved quantity reflects app action only. No order, feedback, payment, earning or identity approval submitted.'}
    (b.ROOT / 'docs/evidence/RELEASE-customer-runtime.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))


def feedback_probe():
    b = m.delivery.b
    account = m.delivery.state['accounts']['physical-customer']
    token = b.login(account)
    code, profiles = b.api('/rest/v1/users?select=role,verification_status,is_blocked&id=eq.' + str(account['profile_id']), admin=True)
    assert code == 200 and len(profiles) == 1
    status, value = b.api('/functions/v1/security-gateway', 'POST', {
        'method': 'POST', 'path': '/rpc/final2_rating_summary', 'query': '',
        'headers': {'content-type': 'application/json'}, 'body': json.dumps({'p_target_id': 997}),
    }, token)
    result = {'project': b.REF, 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'customer_profile': profiles[0], 'http_status': status,
              'server_code': value.get('code'), 'count': value.get('count'),
              'average': value.get('average'),
              'approved_account_required': value.get('message') == 'Approved account required',
              'scope': 'Actual customer-authorized summary for reviewed Sana Foods fixture; no feedback or identity mutation.'}
    (OUT / 'feedback-probe.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    mode = sys.argv[1]
    assert mode in ('foreground', 'background', 'recovery', 'routes', 'delivery-preflight', 'feedback-probe', 'customer-runtime')
    if mode == 'routes':
        routes()
    elif mode == 'delivery-preflight':
        delivery_preflight()
    elif mode == 'feedback-probe':
        feedback_probe()
    elif mode == 'customer-runtime':
        customer_runtime()
    else:
        m.observer.main(60, mode)
