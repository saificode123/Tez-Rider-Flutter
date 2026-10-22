"""Bounded post-activation probes. Never output JWTs, secrets or object URLs.

Only the existing marked FINAL01 cancelled-order fixture counter and one fresh
session clock are modified. No business records, blocks or provider sends.
"""
import base64
import datetime as dt
import importlib.util
import json
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


b = module('backend', 'FR-04-hosted.py')
d = module('database', 'FINAL-security.py')
b.target()
out = b.ROOT / '.fr21-local/final01'
assert json.loads((out / 'deployment-202610220004.json').read_text())['project'] == b.REF
fixture = json.loads(b.crypt((b.PRIVATE / 'final01-workflow.bin').read_bytes(), True))
assert fixture.get('cancelled') and fixture['email'].startswith('final01-') and fixture['email'].endswith('@example.test')
uid = str(uuid.UUID(fixture['auth_id']))
checks = []


def check(condition, label, surface='actual user HTTP'):
    assert condition, label
    checks.append({'check': label, 'result': 'PASS', 'surface': surface})
    (out / 'enforcement-targeted.json').write_text(json.dumps(checks, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(checks[-1]), flush=True)


def sql(source):
    path = out / 'final02-operation.private.sql'
    path.write_text(source, encoding='utf-8')
    return d.query(path)


def gateway(token, path='/users', query='select=id&limit=1', method='GET', body=None):
    return b.api('/functions/v1/security-gateway', 'POST', {
        'method': method, 'path': path, 'query': query, 'headers': {'prefer': 'return=representation', 'content-type': 'application/json'},
        'body': '' if body is None else json.dumps(body)}, token)


token = b.login(fixture)
req = urllib.request.Request(b.BASE + '/rest/v1/users?select=id&limit=1', headers={
    'apikey': b.ANON, 'Authorization': 'Bearer ' + token,
    'x-final01-proof': str(int(time.time())) + '.' + '0' * 64})
try:
    with urllib.request.urlopen(req, timeout=30) as response:
        code, value = response.status, json.load(response)
except urllib.error.HTTPError as error:
    code, value = error.code, json.load(error)
check(code == 403 and value.get('message') == 'APPLICATION_GATEWAY_REQUIRED',
      'syntactically valid forged direct REST proof denied')

# The previous race left this fixture at its cap. Move only its existing new
# limiter window past one minute; never make 100 requests to test reset.
rows = sql("begin;update final1_private.request_limits q set window_at=clock_timestamp()-interval '61 seconds' "
           "from auth.users u where q.actor=u.id and u.id='" + uid + "'::uuid "
           "and u.raw_user_meta_data->>'final01_fixture'='true' returning q.used;commit;")
check(len(rows) == 1, 'only marked fixture limiter window advanced for reset check', 'controlled TEST clock')
code, rows = gateway(token)
check(code == 200 and isinstance(rows, list), 'gateway request succeeds after controlled quota window reset')
rows = sql("begin read only;select used from final1_private.request_limits where actor='" + uid + "'::uuid;rollback;")
check(rows == [{'used': 1}], 'reset persisted exactly one charged gateway request', 'service accounting only')

# Exercise privileges/RLS through the gateway after resetting the quota, so a
# rate rejection cannot be mistaken for an audit permission denial.
for method, body in [('POST', {'action': 'final02_forged'}),
                     ('PATCH', {'action': 'final02_forged'}), ('DELETE', None)]:
    code, _ = gateway(token, '/security_audit_log', 'id=eq.0' if method != 'POST' else '', method, body)
    check(code == 403, 'classified and Admin audit client ' + method + ' denied through gateway (HTTP ' + str(code) + ')')

# New password session belongs to the marked fixture, never a device session.
code, session = b.api('/auth/v1/token?grant_type=password', 'POST', {
    'email': fixture['email'], 'password': fixture['password']})
assert code == 200
fresh = session['access_token']
part = fresh.split('.')[1]
claims = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
sid = str(uuid.UUID(claims['session_id']))
rows = sql("begin;update auth.sessions s set created_at=clock_timestamp()-interval '168 hours 1 second' "
           "from auth.users u where s.user_id=u.id and u.id='" + uid + "'::uuid "
           "and u.raw_user_meta_data->>'final01_fixture'='true' and s.id='" + sid + "'::uuid "
           "and s.created_at>clock_timestamp()-interval '5 minutes' returning true as changed;commit;")
check(rows == [{'changed': True}], 'exactly one fresh marked session aged beyond application deadline', 'controlled TEST clock')
code, value = gateway(fresh)
check(code == 401 and value.get('code') == 'FR28_SESSION_REVOKED', 'expired authorization denied by activated gateway')
code, _ = b.api('/rest/v1/users?select=id&limit=1', token=fresh)
check(code == 401, 'expired otherwise signed session denied on direct REST')
for bucket in ('rider-cnic', 'dispute-evidence', 'invoices'):
    code, value = b.api('/storage/v1/object/list/' + bucket, 'POST', {'prefix': '', 'limit': 1}, fresh)
    check(code in (401, 403) or (code == 200 and value == []),
          'expired customer reveals no private ' + bucket + ' objects (no positive owner fixture)')

# A fresh login after that expired session remains authorized; normal logout
# then revokes it without blocking or modifying any account.
live = b.login(fixture)
code, value = gateway(live)
check(code == 200, 'fresh password re-login restores application authorization')
code, _ = b.api('/auth/v1/logout?scope=local', 'POST', token=live)
check(code in (200, 204), 'server confirms local session logout')
code, value = gateway(live)
check(code == 401 and value.get('code') == 'FR28_SESSION_REVOKED', 'revoked access JWT denied by gateway')
for bucket in ('rider-cnic', 'dispute-evidence', 'invoices'):
    code, value = b.api('/storage/v1/object/list/' + bucket, 'POST', {'prefix': '', 'limit': 1}, live)
    check(code in (401, 403) or (code == 200 and value == []),
          'revoked customer reveals no private ' + bucket + ' objects (no positive owner fixture)')

# Accounting reads establish durable classified records, not caller RLS.
code, rows = b.api('/rest/v1/security_audit_log?actor_id=eq.' + str(fixture['profile_id']) +
                   '&action=in.(final01_api_authorization,final01_api_authentication)&select=action,target_type&limit=10', admin=True)
check(code == 200 and bool(rows) and all(r['action'].startswith('final01_api_') for r in rows),
      'actual denied requests have durable classified failure audits', 'service accounting only')
result = {'project': b.REF, 'observed_at': dt.datetime.now(dt.timezone.utc).isoformat(),
          'checks': len(checks), 'post_activation': True, 'provider_calls': 0,
          'limitations': ['Storage empty-list denials have no authorized positive owner fixture',
                          'Realtime, installation-secret and near-deadline signed URL lifecycle not established by this helper']}
(out / 'enforcement-targeted-summary.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
