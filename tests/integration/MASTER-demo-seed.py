"""Idempotent additive TEST demo seed. No deletion, mail approval, fake GPS/proof.

Credentials and record IDs remain in Windows user-bound private storage.
Admin-confirmed Auth fixtures are not evidence of inbox verification.
"""
from pathlib import Path
import datetime as dt
import importlib.util
import json
import msvcrt
import secrets
import sys
import urllib.parse
import uuid

ROOT = Path(__file__).resolve().parents[2]
NAMESPACE = 'tezrider-owner-demo-v1'
PEOPLE = [
    ('ayesha', 'Ayesha Malik', 'customer', ''),
    ('hamza', 'Hamza Ahmed', 'customer', ''),
    ('bilal', 'Bilal Khan', 'rider', ''),
    ('usman', 'Usman Tariq', 'rider', ''),
    ('sana', 'Sana Foods', 'vendor', 'Demo Food Court, Campus Block A (fictional)'),
    ('green', 'Green Basket Mart', 'vendor', 'Demo Market, Campus Block B (fictional)'),
    ('mariam', 'Mariam Shah (Demo Admin)', 'admin', ''),
]
PRODUCTS = [
    ('sana', 'Chicken Biryani', 'Food', 350, 30, 'A single serving of fragrant rice and chicken.'),
    ('sana', 'Vegetable Rice', 'Food', 240, 25, 'Seasonal vegetables with lightly spiced rice.'),
    ('sana', 'Chicken Wrap', 'Food', 290, 35, 'Grilled chicken and salad in a soft wrap.'),
    ('sana', 'Daal with Rice', 'Food', 220, 25, 'Lentils served with steamed rice.'),
    ('sana', 'Fresh Roti Pack', 'Food', 100, 40, 'Four freshly prepared plain rotis.'),
    ('sana', 'Mint Lemonade', 'Food', 160, 40, 'A 300ml serving of mint and lemon refreshment.'),
    ('green', 'Fresh Milk 1 Litre', 'Groceries', 280, 60, 'One litre of chilled packaged milk.'),
    ('green', 'Farm Eggs (6 Pack)', 'Groceries', 210, 45, 'Six eggs packed for careful transport.'),
    ('green', 'Basmati Rice 1 kg', 'Groceries', 420, 50, 'One kilogram of dry basmati rice.'),
    ('green', 'Whole Wheat Flour 2 kg', 'Groceries', 360, 35, 'Two kilograms of whole wheat flour.'),
    ('green', 'Tea 190 g', 'Groceries', 390, 40, 'A 190 gram pack of black tea.'),
    ('green', 'Seasonal Apples 1 kg', 'Groceries', 320, 30, 'One kilogram of seasonal apples.'),
]


def main(mode):
    assert mode in ('plan', 'apply', 'verify')
    if mode == 'plan':
        print(json.dumps({'project': 'igeisilhtmglgnqvllrx', 'additive_only': True,
                          'accounts': [{'name': n, 'role': r} for _, n, r, _ in PEOPLE],
                          'products': len(PRODUCTS), 'saved_addresses': 2,
                          'riders': 'Pending CNIC verification; no fabricated approval',
                          'historical_deliveries_payments_disputes': 'Not fabricated',
                          'new_product_images': 'Not supplied; actual empty image state retained'}))
        return
    spec = importlib.util.spec_from_file_location('seed_backend', Path(__file__).with_name('FR-04-hosted.py'))
    b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
    b.target()
    assert b.REF == 'igeisilhtmglgnqvllrx'
    backup = json.loads((ROOT / 'docs/evidence/MASTER-backup.json').read_text(encoding='utf-8-sig'))
    restored = json.loads((ROOT / 'docs/evidence/MASTER-restore.json').read_text(encoding='utf-8-sig'))
    storage = json.loads((ROOT / 'docs/evidence/MASTER-storage-backup.json').read_text(encoding='utf-8-sig'))
    assert all(v['project'] == b.REF for v in (backup, restored, storage))
    assert all(x['encrypted_round_trip'] for x in backup['exports'])
    assert restored['isolated_restore_verified'] and storage['object_bytes_integrity_verified']
    private = b.PRIVATE / 'master-demo-credentials.dpapi'
    state = json.loads(b.crypt(private.read_bytes(), True)) if private.exists() else {
        'namespace': NAMESPACE, 'accounts': {}, 'products': {}, 'addresses': {}}
    assert state['namespace'] == NAMESPACE
    checks = []
    created = 0

    def save():
        temporary = private.with_suffix('.dpapi.tmp')
        temporary.write_bytes(b.crypt(json.dumps(state).encode()))
        temporary.replace(private)

    def check(ok, name):
        assert ok, name
        checks.append({'check': name, 'result': 'PASS'})
        print(json.dumps(checks[-1]), flush=True)

    def gateway(name, token, params):
        code, result = b.api('/functions/v1/security-gateway', 'POST', {
            'method': 'POST', 'path': '/rpc/' + name, 'query': '',
            'headers': {'content-type': 'application/json'}, 'body': json.dumps(params),
        }, token)
        assert code == 200, name + ': HTTP ' + str(code) + ' / ' + str(result.get('code') if isinstance(result, dict) else 'invalid response')
        return result

    def find_auth(email):
        for page in range(1, 21):
            code, result = b.api('/auth/v1/admin/users?page=' + str(page) + '&per_page=100', admin=True)
            assert code == 200
            users = result['users']
            found = [u for u in users if u.get('email', '').lower() == email]
            if found: return found[0]
            if len(users) < 100: return None
        raise RuntimeError('Auth inventory exceeded the bounded seed search')

    tokens = {}
    # Bootstrap only this explicitly requested synthetic Admin through trusted
    # Auth administration. Ordinary registration remains unable to create Admins.
    ordered = sorted(PEOPLE, key=lambda p: p[2] != 'admin')
    for label, name, role, address in ordered:
        email = 'tez-demo-v1-' + label + '@example.test'
        account = state['accounts'].get(label)
        existing = find_auth(email)
        if existing:
            assert existing.get('app_metadata', {}).get('tezrider_demo_namespace') == NAMESPACE, 'Email collision with an unowned account'
            assert account is not None, 'Private credentials missing; no password reset or account overwrite performed'
            account['auth_id'] = existing['id']
        elif mode == 'apply':
            account = state['accounts'].setdefault(label, {
                'email': email, 'password': secrets.token_urlsafe(30) + 'aA7!', 'role': role})
            save()  # Survive a lost create response without generating a new password.
            code, existing = b.api('/auth/v1/admin/users', 'POST', {
                'email': email, 'password': account['password'], 'email_confirm': True,
                'app_metadata': {'tezrider_demo_namespace': NAMESPACE, 'fictional': True},
                'user_metadata': {'name': name, 'phone': '0000000000', 'role': role,
                                  'store_name': name if role == 'vendor' else '',
                                  'store_address': address},
            }, admin=True)
            assert code in (200, 201), 'Auth fixture creation not confirmed'
            account['auth_id'] = existing['id']; created += 1; save()
        else:
            raise RuntimeError('Requested demo identity has not been seeded')
        assert account['email'] == email and account['role'] == role
        code, profiles = b.api('/rest/v1/users?auth_user_id=eq.' + account['auth_id'] + '&select=id,role,verification_status', admin=True)
        assert code == 200 and len(profiles) <= 1
        if role == 'admin' and not profiles:
            assert mode == 'apply'
            code, profiles = b.api('/rest/v1/users', 'POST', {
                'auth_user_id': account['auth_id'], 'name': name, 'email': email,
                'phone': '0000000000', 'role': 'admin', 'verification_status': 'approved'}, admin=True)
            assert code == 201 and len(profiles) == 1
        token = b.login(account); tokens[label] = token
        if mode == 'verify':
            assert len(profiles) == 1, 'Missing profile; verification will not recreate it'
            profile = {'code': 'OK', **profiles[0]}
        else:
            profile = gateway('final2_complete_registration', token, {
                'p_name': name, 'p_phone': '0000000000', 'p_role': role,
                'p_store_name': name if role == 'vendor' else '', 'p_store_address': address,
                'p_update_profile': False})
        check(profile.get('code') == 'OK' and profile.get('role') == role,
              label + ': real Auth login and canonical profile role confirmed')
        account['profile_id'] = profile['id']; save()
        if role == 'rider':
            check(profile['verification_status'] == 'pending', label + ': no invented CNIC approval')
            code, riders = b.api('/rest/v1/riders?userid=eq.' + str(profile['id']) + '&select=userid,is_online', admin=True)
            assert code == 200
            if not riders and mode == 'apply':
                code, riders = b.api('/rest/v1/riders', 'POST', {'userid': profile['id'], 'is_online': False}, admin=True)
                assert code == 201
            check(len(riders) == 1 and not riders[0]['is_online'], label + ': actual offline rider profile confirmed')
        if role == 'vendor' and profile['verification_status'] == 'pending':
            assert mode == 'apply'
            result = gateway('final2_review_vendor', tokens['mariam'], {
                'p_user_id': profile['id'], 'p_status': 'approved'})
            check(result['verification_status'] == 'approved', label + ': canonical Admin vendor review confirmed')

    # Shared reference categories are reused by exact name, never overwritten.
    for category in ('Food', 'Groceries'):
        code, rows = b.api('/rest/v1/categories?name=eq.' + urllib.parse.quote(category) + '&select=id,name', admin=True)
        assert code == 200
        if not rows and mode == 'apply':
            code, rows = b.api('/rest/v1/categories', 'POST', {'name': category,
                'description': 'Fictional TEST demonstration catalogue category'}, admin=True)
            assert code == 201
        check(bool(rows), category + ': actual category reference exists')
    for vendor, name, category, price, stock, description in PRODUCTS:
        request_id = str(uuid.uuid5(uuid.NAMESPACE_URL, NAMESPACE + ':product:' + vendor + ':' + name))
        params = {'p_request_id': request_id, 'p_product_id': None,
                  'p_data': {'name': name, 'category': category, 'price': price,
                             'description': description + ' Fictional TEST demonstration item.',
                             'image_url': '', 'is_available': True},
                  'p_stock': stock, 'p_threshold': 5, 'p_expected_version': None}
        if mode == 'apply':
            product = gateway('fr17_save_product', tokens[vendor], params)
            check(product.get('code') in ('UPDATED', 'ALREADY_UPDATED'), name + ': idempotent real inventory operation')
            state['products'][name] = {'id': product['product_id'], 'vendor': vendor}; save()
        item = state['products'][name]
        code, rows = b.api('/rest/v1/products?id=eq.' + str(item['id']) + '&select=id,vendor_id,name,price,stock_qty,is_available', admin=True)
        check(code == 200 and len(rows) == 1 and rows[0]['vendor_id'] == state['accounts'][vendor]['profile_id']
              and rows[0]['name'] == name and float(rows[0]['price']) == price and rows[0]['is_available'],
              name + ': stored price and vendor association verified')
    for label in ('ayesha', 'hamza'):
        if mode == 'apply':
            # Address receipts require UUIDv4. Persist it before the call so
            # interrupted runs replay the exact supported request, not a UUIDv5.
            request_id = state.setdefault('address_requests', {}).setdefault(label, str(uuid.uuid4()))
            save()
            result = gateway('final2_change_address', tokens[label], {
                'p_request_id': request_id,
                'p_operation': 'create', 'p_id': None, 'p_expected_revision': None,
                'p_label': 'Demo Home', 'p_address': 'Fictional demo residence, Campus Block C. Not a real delivery destination.'})
            check(result.get('code') in ('APPLIED', 'ALREADY_APPLIED'), label + ': idempotent saved address confirmed')
            state['addresses'][label] = result['address_id']; save()
        addresses = gateway('final2_saved_addresses', tokens[label], {'p_before': None, 'p_limit': 50})
        check(any(r['id'] == state['addresses'][label] for r in addresses['items']), label + ': owned saved address readable')
    ids = ','.join(str(a['profile_id']) for a in state['accounts'].values())
    code, mail = b.api('/rest/v1/email_outbox?recipient_user_id=in.(' + ids + ')&test_approved=eq.true&select=id', admin=True)
    check(code == 200 and mail == [], 'No new demo account email is approved for external dispatch')
    catalogue = gateway('final2_catalog', tokens['ayesha'], {'p_query': 'Chicken Biryani', 'p_category': None, 'p_after': None, 'p_limit': 20})
    check(any(p['id'] == state['products']['Chicken Biryani']['id'] for p in catalogue['items']), 'Customer search returns the actual seeded catalogue product')
    other = gateway('final2_saved_addresses', tokens['hamza'], {'p_before': None, 'p_limit': 50})
    check(all(a['id'] != state['addresses']['ayesha'] for a in other['items']), 'Customer saved-address RLS isolation confirmed')
    result = {'project': b.REF, 'namespace': NAMESPACE, 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'mode': mode, 'accounts_created_this_run': created, 'accounts_total': len(state['accounts']),
              'products': len(state['products']), 'saved_addresses': len(state['addresses']), 'checks': checks,
              'limitations': 'Additive fictional data. Two Riders remain pending CNIC; no proof/payment/delivery/dispute/earnings fabricated. Product imagery not supplied. Existing records retained; cleanup requires exact owner approval.'}
    (ROOT / ('docs/evidence/MASTER-demo-' + mode + '.json')).write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ('mode', 'accounts_created_this_run', 'accounts_total', 'products', 'saved_addresses')}))


if __name__ == '__main__':
    mode = sys.argv[1]
    if mode == 'plan':
        main(mode)
    else:
        # Serialize partial/repeated seeds; no competing password or product creations.
        import os
        private = Path(os.environ['FR21_PRIVATE_DIRECTORY'])
        with (private / 'master-demo-seed.lock').open('a+b') as lock:
            lock.seek(0); lock.write(b'0'); lock.flush(); lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            try: main(mode)
            finally:
                lock.seek(0); msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
