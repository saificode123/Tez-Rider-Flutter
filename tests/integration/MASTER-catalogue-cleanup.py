"""Reviewable reversible TEST catalogue cleanup; never deletes rows/accounts.

Plan includes only vendors proven by protected fixture credentials. Active-order
products and the new demo namespace are excluded. Apply needs the exact reviewed
manifest hash AND separate human authorization before the operator invokes it.
"""
from pathlib import Path
import datetime as dt
import hashlib
import importlib.util
import json
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('cleanup_backend', Path(__file__).with_name('FR-04-hosted.py'))
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
b.target()
PUBLIC = ROOT / 'docs/evidence/MASTER-catalogue-cleanup-proposal.json'
PRIVATE = b.PRIVATE / 'master-catalogue-cleanup.dpapi'


def rows(table, query=''):
    code, result = b.api('/rest/v1/' + table + '?' + query, admin=True)
    assert code == 200 and isinstance(result, list), 'TEST inventory read failed'
    return result


def active_products():
    active = []
    cursor = 0
    for _ in range(20):
        page = rows('orders', 'select=id,order_status&id=gt.' + str(cursor) + '&order=id&limit=500')
        active += [o['id'] for o in page if o['order_status'] not in ('delivered', 'cancelled')]
        if len(page) < 500: break
        cursor = page[-1]['id']
    else: raise RuntimeError('Bounded order inventory exceeded')
    vendor_orders = []
    for start in range(0, len(active), 50):
        group = ','.join(map(str, active[start:start + 50]))
        batch = rows('vendor_orders', 'select=id&order_id=in.(' + group + ')&limit=1000')
        assert len(batch) < 1000
        vendor_orders += [v['id'] for v in batch]
    protected = set()
    for start in range(0, len(vendor_orders), 50):
        group = ','.join(map(str, vendor_orders[start:start + 50]))
        batch = rows('order_items', 'select=product_id&vendor_order_id=in.(' + group + ')&limit=1000')
        assert len(batch) < 1000
        protected.update(i['product_id'] for i in batch)
    return protected


def save(plan):
    temporary = PRIVATE.with_suffix('.dpapi.tmp')
    temporary.write_bytes(b.crypt(json.dumps(plan).encode()))
    temporary.replace(PRIVATE)


def plan_cleanup():
    assert not PRIVATE.exists(), 'A plan already exists; review/resume it instead of silently replacing its scope'
    credentials = {}
    files = ['accounts.bin', 'fr04-accounts.bin', 'fr13-accounts.bin', 'fr14-accounts.bin',
             'fr17-accounts.bin', 'fr20-accounts.bin', 'fr25-accounts.bin',
             'fr26-accounts.bin', 'fr28-accounts.bin']
    for name in files:
        path = b.PRIVATE / name
        if not path.exists(): continue
        state = json.loads(b.crypt(path.read_bytes(), True))
        for label, account in state.get('accounts', {}).items():
            if label.startswith('physical') or not isinstance(account, dict): continue
            email = account.get('email', '')
            if (not email.endswith('@example.test') or not email.startswith(('fr04-', 'fr13-', 'fr14-', 'fr17-', 'fr20-', 'fr21-', 'fr25-', 'fr26-', 'fr28-'))
                    or not all(account.get(k) for k in ('auth_id', 'password'))): continue
            identity = str(uuid.UUID(account['auth_id']))
            credentials[identity] = account
    protected = active_products()
    changes = []
    for identity, account in credentials.items():
        profiles = rows('users', 'select=id,role,is_blocked,verification_status&auth_user_id=eq.' + identity)
        if len(profiles) != 1: continue
        profile = profiles[0]
        if profile['role'] != 'vendor' or profile['is_blocked'] or profile['verification_status'] != 'approved': continue
        products = rows('products', 'select=id,vendor_id,name,description,price,category,image_url,is_available,requires_prescription,stock_qty,stock_version,low_stock_threshold&vendor_id=eq.' + str(profile['id']) + '&is_available=eq.true&order=id&limit=1000')
        assert len(products) < 1000
        for product in products:
            if product['id'] in protected: continue
            changes.append({'product': product, 'account': account,
                            'request_id': str(uuid.uuid4())})
    proposal = {
        'project': b.REF, 'created_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
        'action': 'Set the listed old fixture products unavailable through their owning Vendor inventory RPCs',
        'deletes': 0, 'auth_accounts_deleted': 0, 'records': len(changes),
        'active_order_products_excluded': len(protected),
        'rollback': 'Restore availability through the same owner RPC, preserving current stock and metadata. No database-wide restore required for this catalogue-only operation.',
        'impact': 'These fixtures stop appearing in the Customer catalogue. Historical/Auth/audit/order records are retained. Legacy regression harnesses may need fixture reactivation before reuse. New demo products excluded.',
        'approval': 'NOT APPROVED. Exact SHA-256 authorization required before apply.',
        'products': [{'product_id': c['product']['id'], 'name': c['product']['name'],
                      'vendor_profile_id': c['product']['vendor_id'],
                      'fixture_email': c['account']['email'],
                      'stock_qty': c['product']['stock_qty'],
                      'stock_version': c['product']['stock_version']} for c in changes],
    }
    PUBLIC.write_text(json.dumps(proposal, indent=2) + '\n')
    digest = hashlib.sha256(PUBLIC.read_bytes()).hexdigest()
    save({'sha256': digest, 'changes': changes, 'results': [], 'rollback_payloads': {}})
    print(json.dumps({'project': b.REF, 'proposed_products': len(changes), 'sha256': digest,
                      'executed': False, 'deletes': 0}))


def execute(mode, approved):
    plan = json.loads(b.crypt(PRIVATE.read_bytes(), True))
    digest = hashlib.sha256(PUBLIC.read_bytes()).hexdigest()
    assert approved == digest == plan['sha256'], 'Exact reviewed manifest hash required'
    protected = active_products()
    if mode == 'verify':
        results = []
        for change in plan['changes']:
            original = change['product']
            current = rows('products', 'select=id,vendor_id,is_available,stock_qty&id=eq.' + str(original['id']))
            assert len(current) == 1 and current[0]['vendor_id'] == original['vendor_id']
            assert current[0]['is_available'] is False and current[0]['stock_qty'] == original['stock_qty']
            assert current[0]['id'] not in protected
            results.append({'product_id': original['id'], 'unavailable': True, 'stock_unchanged': True})
        result = {'project': b.REF, 'manifest_sha256': digest,
                  'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
                  'verified_products': len(results), 'results': results, 'deletes': 0}
        (ROOT / 'docs/evidence/MASTER-catalogue-verify.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({'verified_products': len(results), 'all_quantities_retained': True, 'deletes': 0}))
        return
    tokens = {}
    for change in plan['changes']:
        original, account = change['product'], change['account']
        key = str(original['id'])
        current = rows('products', 'select=*&id=eq.' + key)
        assert len(current) == 1 and current[0]['vendor_id'] == original['vendor_id']
        current = current[0]
        wanted = mode == 'rollback'
        if current['is_available'] == wanted:
            if mode == 'apply':
                assert current['stock_qty'] == original['stock_qty'], 'Stock changed during cleanup; stop and review'
            if not any(r['product_id'] == current['id'] and r['mode'] == mode for r in plan['results']):
                record = {'product_id': current['id'], 'mode': mode, 'result': 'PASS',
                          'reconciled_current_state': True,
                          'utc': dt.datetime.now(dt.timezone.utc).isoformat()}
                plan['results'].append(record); save(plan)
                print(json.dumps(record), flush=True)
            continue
        if mode == 'apply':
            assert current['id'] not in protected, 'A product now belongs to active work; stop and review'
            assert current['stock_version'] == original['stock_version'], 'Inventory changed after review; stop instead of overwriting it'
        identity = account['auth_id']
        if identity not in tokens: tokens[identity] = b.login(account)
        data = {k: current.get(k) for k in ('name', 'description', 'price', 'category', 'image_url', 'requires_prescription')}
        data['is_available'] = wanted
        payload = {'p_request_id': change['request_id'], 'p_product_id': current['id'],
                   'p_data': data, 'p_stock': current['stock_qty'],
                   'p_threshold': current['low_stock_threshold'],
                   'p_expected_version': current['stock_version']}
        if mode == 'rollback':
            payload = plan['rollback_payloads'].setdefault(key, {**payload, 'p_request_id': str(uuid.uuid4())})
            save(plan)
        code, result = b.api('/functions/v1/security-gateway', 'POST', {
            'method': 'POST', 'path': '/rpc/fr17_save_product', 'query': '',
            'headers': {'content-type': 'application/json'}, 'body': json.dumps(payload),
        }, tokens[identity])
        assert code == 200 and result.get('code') in ('UPDATED', 'ALREADY_UPDATED'), 'Owner inventory change not confirmed; partial results retained'
        confirmed = rows('products', 'select=id,is_available,stock_qty&id=eq.' + key)
        assert len(confirmed) == 1 and confirmed[0]['is_available'] == wanted and confirmed[0]['stock_qty'] == current['stock_qty']
        record = {'product_id': current['id'], 'mode': mode, 'result': 'PASS', 'utc': dt.datetime.now(dt.timezone.utc).isoformat()}
        plan['results'].append(record); save(plan)
        print(json.dumps(record), flush=True)
    (ROOT / ('docs/evidence/MASTER-catalogue-' + mode + '.json')).write_text(json.dumps({
        'project': b.REF, 'manifest_sha256': digest, 'mode': mode,
        'results': plan['results'], 'deletes': 0}, indent=2) + '\n')


if __name__ == '__main__':
    if sys.argv[1] == 'plan': plan_cleanup()
    else:
        assert sys.argv[1] in ('apply', 'rollback', 'verify') and len(sys.argv) == 3
        execute(sys.argv[1], sys.argv[2])
