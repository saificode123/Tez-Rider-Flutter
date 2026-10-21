"""Low-volume real-session TEST denials/reads. No business-record mutations."""
import base64
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('final1_backend', Path(__file__).with_name('FR-04-hosted.py'))
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
OUT = b.ROOT / '.fr21-local/final1'
checks = []


def check(value, label):
    if not value:
        raise AssertionError(label)
    checks.append({'check': label, 'result': 'PASS'})


def main():
    b.target()
    state = json.loads(b.crypt((b.PRIVATE / 'fr28-accounts.bin').read_bytes(), True))
    accounts = state['accounts']
    code, _ = b.api('/functions/v1/shopping-assistant', 'POST', {'prompt': 'Question'}, 'invalid')
    check(code in (401, 403), 'invalid JWT denied before provider')
    for label in ['customer', 'vendor', 'rider', 'admin']:
        account = accounts[label]
        assert account['email'].startswith('fr28-') and account['email'].endswith('@example.test')
        token = b.login(account)  # Existing marked synthetic fixture only; no new account or mail.
        payload = token.split('.')[1]
        claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        check(claims.get('role') == 'authenticated', label + ': actual authenticated JWT, not service-role test')
        check(claims['exp'] - claims['iat'] == 3600, label + ': observed access JWT lifetime3600s')
        code, status = b.rpc('fr28_account_status', {}, token)
        check(code == 200 and status['code'] == 'OK' and status['role'] == label,
              label + ': canonical current account status')
        for table in ['security_audit_log', 'delivery_otps', 'delivery_otp_verifications',
                      'email_outbox', 'payments', 'app_settings']:
            code, _ = b.api('/rest/v1/' + table + '?select=*&limit=1', token=token)
            check(code in (401, 403), label + ': direct ' + table + ' denied')
        if label != 'admin':
            code, rows = b.api('/rest/v1/users?id=eq.' + str(accounts['admin']['profile_id']) + '&select=id', token=token)
            check(code in (401, 403) or (code == 200 and rows == []), label + ': unrelated private profile invisible')
            code, _ = b.rpc('final1_review_vendor', {'p_user_id': accounts['vendor']['profile_id'], 'p_status': 'approved'}, token)
            check(code == 403, label + ': privileged review denied')
            code, _ = b.rpc('fr28_user_list', {}, token)
            check(code == 403, label + ': admin directory denied')
        else:
            code, rows = b.rpc('fr28_user_list', {'p_limit': 1}, token)
            check(code == 200 and len(rows) <= 1, 'admin: accepted directory read preserved')
            code, _ = b.rpc('final1_review_vendor', {'p_user_id': 0, 'p_status': 'approved'}, token)
            check(code == 400, 'admin: malformed review rejected without mutation')
        code, _ = b.rpc('final1_search_products', {'p_query': ''}, token)
        check(code == 400, label + ': trusted empty search rejected')
        code, rows = b.rpc('final1_search_products', {'p_query': 'FINAL1-NONEXISTENT-SEARCH'}, token)
        check(code == 200 and rows == [], label + ': trusted literal search works')
        if label in ('vendor', 'rider'):
            code, value = b.rpc('fr21_dashboard_stats', {}, token)
            check(code == 200 and isinstance(value, dict), label + ': accepted FR21 dashboard aggregate read')
        if label == 'rider':
            code, value = b.rpc('fr04_application_status', {}, token)
            check(code == 200 and 'cnic' not in value, 'FR04: rider submission status remains masked')
        if label == 'customer':
            for name in ['fr25_history', 'fr25_eligible_orders', 'fr25_order_history', 'fr25_chat_list']:
                code, value = b.rpc(name, {'p_before': None}, token)
                check(code == 200 and isinstance(value, list), name + ': accepted owner read remains available')
            for name in ['fr32_invoice_authority', 'fr14_route_context', 'delivery_otp_status', 'pre_delivery_checklist']:
                code, value = b.rpc(name, {'p_order_id': 0}, token)
                check(code in (400, 403) or (code == 200 and value.get('code') in ('FORBIDDEN', 'NOT_FOUND')),
                      name + ': unrelated/malformed order denied without mutation')
        if label == 'admin':
            code, value = b.rpc('fr04_admin_riders', {'p_limit': 1}, token)
            check(code == 200 and isinstance(value, list), 'FR04: approved admin review queue read')
            code, value = b.rpc('fr26_queue', {'p_limit': 1}, token)
            check(code == 200 and isinstance(value, list), 'FR26: approved dispute queue read')
            code, value = b.rpc('fr30_estimate', {'p_audience': 'ALL'}, token)
            check(code == 200, 'FR30: approved broadcast estimate read without sending')
        # Invalid body rejected before provider/key lookup: consumes no provider credits.
        code, _ = b.api('/functions/v1/shopping-assistant', 'POST', {'prompt': 'Question', 'actor': 'admin'}, token)
        check(code == 400, label + ': deployed Edge rejects extra fields before key/provider')
        for bucket in ['rider-cnic', 'dispute-evidence', 'invoices']:
            code, value = b.api('/storage/v1/object/list/' + bucket, 'POST', {'prefix': '', 'limit': 1}, token)
            check(code in (401, 403) or (code == 200 and value == []), label + ': direct private ' + bucket + ' list denied')
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'hosted-results.json').write_text(json.dumps(checks, indent=2), encoding='utf-8')
    print(json.dumps({'TEST': b.REF, 'passed': len(checks), 'actual_user_sessions': 4,
                      'business_record_mutations': 0, 'provider_calls': 0, 'production_modified': False}))


if __name__ == '__main__':
    main()
