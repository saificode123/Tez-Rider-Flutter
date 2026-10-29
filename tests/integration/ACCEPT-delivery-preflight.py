"""Read-only preflight for the owner's single authorized COD TEST delivery.

No email, push, order, identity approval or lifecycle write. Private checkpoint
retains the original order inventory to detect a resumed/duplicate checkout.
"""
import datetime as dt
import argparse
import importlib.util
import hashlib
import json
from pathlib import Path
import uuid

HERE = Path(__file__).resolve().parent


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


h = load('accept_customer', 'FR-14-hosted.py')
b = h.b


def read(path):
    status, value = b.api(path, admin=True)
    assert status == 200 and isinstance(value, (dict, list)), 'TEST preflight read unconfirmed'
    return value


def main(evidence='ACCEPT-delivery-preflight.json'):
    b.target()
    account = h.state['accounts']['physical-customer']
    rider_checkpoint = b.PRIVATE / 'rider-auth-verification.dpapi'
    rider_status = 'WAITING: owner chose to provide a genuinely verified Rider; synthetic fixtures excluded'
    if rider_checkpoint.exists():
        rider = json.loads(b.crypt(rider_checkpoint.read_bytes(), True))
        assert account['auth_id'] != rider['auth_id'], 'Never use a stored fixture password for the owner Rider'
        live = read('/auth/v1/admin/users/' + str(uuid.UUID(rider['auth_id'])))
        rider_rows = read('/rest/v1/users?auth_user_id=eq.' + rider['auth_id'] +
            '&select=id,role,verification_status,is_blocked,cnic_submission_status,cnic_submitted_at')
        proof_path = b.ROOT / 'docs/evidence/AUTH-rider-state.json'
        if proof_path.exists() and len(rider_rows) == 1:
            proof = json.loads(proof_path.read_text(encoding='utf-8-sig'))
            row = rider_rows[0]
            if (row['id'] == proof['rider_profile_id'] == 999 and row['role'] == 'rider'
                and row['verification_status'] == 'approved' and not row['is_blocked']
                and row['cnic_submission_status'] == 'submitted' and live.get('email_confirmed_at')
                and proof['document_exists'] and proof['admin_approval_after_current_submission']
                and dt.datetime.fromisoformat(row['cnic_submitted_at']) == dt.datetime.fromisoformat(proof['submitted_at'])):
                rider_status = 'Owner-identified Rider 999: confirmed email, current private document and canonical Admin approval verified; no agent password login'
    identity = read('/auth/v1/admin/users/' + str(uuid.UUID(account['auth_id'])))
    config = {}
    for line in (b.ROOT / 'supabase/functions/.env.test.local').read_text().splitlines():
        key, sep, value = line.partition('=')
        if sep and key.strip() == 'BREVO_TEST_RECIPIENT':
            config[key.strip()] = value.strip().strip('\"\'')
    recipient = config.get('BREVO_TEST_RECIPIENT', '')
    assert recipient and recipient.lower() == identity['email'].lower() == account['email'].lower()
    assert identity.get('email_confirmed_at') and not recipient.lower().endswith('@example.test')
    secret_list = (b.ROOT / '.fr21-local/accept-test-secrets.private.json').read_text(encoding='utf-8-sig')
    remote = json.JSONDecoder().raw_decode(secret_list[secret_list.index('['):])[0]
    allowed = [s for s in remote if s.get('name') == 'BREVO_TEST_RECIPIENT']
    assert len(allowed) == 1, 'Remote TEST recipient metadata missing'
    remote_digest = allowed[0].get('digest', allowed[0].get('value', ''))
    assert isinstance(remote_digest, str) and remote_digest.lower() == hashlib.sha256(recipient.encode()).hexdigest(), 'Remote TEST recipient digest mismatch'
    customer_id = int(account['profile_id'])
    customer = read(f'/rest/v1/users?id=eq.{customer_id}&select=role,verification_status,is_blocked')[0]
    assert customer == {'role': 'customer', 'verification_status': 'approved', 'is_blocked': False}
    token = b.login(account)
    status, cart = b.api('/functions/v1/security-gateway', 'POST', {
        'method': 'POST', 'path': '/rpc/final2_cart_get', 'query': '',
        'headers': {'content-type': 'application/json'}, 'body': '{}',
    }, token)
    assert status == 200 and cart.get('code') == 'OK'
    assert len(cart['items']) == 1 and str(cart['items'][0]['product_id']) == '224' and cart['items'][0]['qty'] == 1
    product = read('/rest/v1/products?id=eq.224&select=id,name,price,stock_qty,is_available,vendor_id')[0]
    assert product['name'] == 'Chicken Biryani' and product['price'] == 350 and product['is_available']
    assert product['stock_qty'] >= 1 and product['vendor_id'] == 997
    vendor = read('/rest/v1/users?id=eq.997&select=role,verification_status,is_blocked')[0]
    assert vendor == {'role': 'vendor', 'verification_status': 'approved', 'is_blocked': False}
    shop = read('/rest/v1/vendors?user_id=eq.997&select=is_active,latitude,longitude')
    assert len(shop) == 1 and shop[0]['is_active']
    orders = read(f'/rest/v1/orders?user_id=eq.{customer_id}&select=id,order_status,created_at&order=id&limit=1000')
    assert len(orders) < 1000
    reviewed_order_ids = set()
    if orders:
        order_ids = ','.join(str(int(o['id'])) for o in orders)
        vendor_orders = read('/rest/v1/vendor_orders?order_id=in.(' + order_ids + ')&select=id,order_id&limit=1000')
        assert len(vendor_orders) < 1000
        if vendor_orders:
            vendor_order_ids = ','.join(str(int(o['id'])) for o in vendor_orders)
            items = read('/rest/v1/order_items?product_id=eq.224&vendor_order_id=in.(' + vendor_order_ids + ')&select=vendor_order_id&limit=1000')
            assert len(items) < 1000
            matching = {int(i['vendor_order_id']) for i in items}
            reviewed_order_ids = {int(o['order_id']) for o in vendor_orders if int(o['id']) in matching}
    private = b.PRIVATE / 'accept-single-delivery.dpapi'
    if private.exists():
        checkpoint = json.loads(b.crypt(private.read_bytes(), True))
        assert checkpoint['customer_id'] == customer_id and checkpoint['product_id'] == 224
    else:
        checkpoint = {'project': b.REF, 'customer_id': customer_id, 'product_id': 224,
                      'created_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
                      'baseline_order_ids': [o['id'] for o in orders],
                      'message_limits': {'otp': 2, 'order_confirmation': 1, 'paid_invoice': 1},
                      'order_id': None}
        private.write_bytes(b.crypt(json.dumps(checkpoint).encode()))
        assert json.loads(b.crypt(private.read_bytes(), True)) == checkpoint
    new_orders = [o for o in orders if o['id'] not in checkpoint['baseline_order_ids']]
    approved = read('/rest/v1/email_outbox?test_approved=eq.true&status=in.(pending,deferred,sending)&select=id,email_type,entity_id&limit=1000')
    assert len(approved) < 1000
    demo = json.loads(b.crypt((b.PRIVATE / 'master-demo-credentials.dpapi').read_bytes(), True))
    pending = []
    for label in ('bilal', 'usman'):
        pending += read('/rest/v1/users?id=eq.' + str(int(demo['accounts'][label]['profile_id'])) + '&select=role,verification_status')
    assert len(pending) == 2 and all(p['role'] == 'rider' and p['verification_status'] == 'pending' for p in pending)
    result = {'project': b.REF, 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'owner_recipient_matches_confirmed_auth_and_test_configuration': True,
              'remote_test_recipient_digest_matches': True,
              'recipient_mask': recipient[:2] + '***@' + recipient.split('@')[1],
              'customer_auth_and_canonical_cart_verified': True,
              'product': product, 'vendor_eligible': True,
              'vendor_pickup_coordinates_present': all(shop[0][k] is not None for k in ('latitude', 'longitude')),
              'orders_created_since_durable_checkpoint': len(new_orders),
              'existing_customer_orders_containing_reviewed_product': len(reviewed_order_ids),
              'duplicate_checkout_guard': 'CLEAR: no existing reviewed-product order' if not reviewed_order_ids and not new_orders else 'STOP: reconcile existing orders before any placement',
              'existing_approved_sendable_email_jobs': len(approved),
              'demo_rider_statuses': pending,
              'genuine_rider': rider_status,
              'address_and_charge': 'NOT YET CONFIRMED through the physical checkout',
              'phone': 'Physical foreground and installed-build evidence are checked separately; no phone action performed by this script',
              'checkout': 'NOT EXECUTED', 'external_messages_sent': 0,
              'ready_for_checkout': False,
              'remaining_preconditions': ([] if rider_status.startswith('Owner-identified') else ['Owner-provided genuinely verified Rider']) + ['Physical pickup and destination/charge confirmation', 'Current TEST phone push-capability match'],
              'scope': 'Read-only hosted preflight and encrypted local baseline only. Existing approved pending email jobs must be reconciled before invoking any batch worker. No blanket approval or synthetic identity acceptance.'}
    (b.ROOT / 'docs/evidence' / evidence).write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))
    if reviewed_order_ids or new_orders:
        raise SystemExit('Existing checkout requires reconciliation; do not place another order.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', choices=('ACCEPT-delivery-preflight.json', 'AUTH-delivery-preflight.json'), default='ACCEPT-delivery-preflight.json')
    main(parser.parse_args().evidence)
