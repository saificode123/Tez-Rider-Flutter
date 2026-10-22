"""Real private-media deadline check; no URL, object path or token output.

Changes only created_at of one freshly logged-in fr28 synthetic Admin session,
selected by exact subject/session and a five-minute age guard. No phone session
or business record is touched. Existing synthetic encrypted CNIC is reused.
"""
import base64
import importlib.util
import json
import time
import urllib.error
import urllib.parse
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
assert (out / 'deployment-202610220004.json').exists()
accounts = json.loads(b.crypt((b.PRIVATE / 'fr28-accounts.bin').read_bytes(), True))['accounts']
account = accounts['admin']
assert account['email'].startswith('fr28-') and account['email'].endswith('@example.test')
token = b.login(account)
part = token.split('.')[1]
claims = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
sid = str(uuid.UUID(claims['session_id']))
uid = str(uuid.UUID(account['auth_id']))
checks = []


def check(ok, label):
    assert ok, label
    checks.append({'check': label, 'result': 'PASS'})
    (out / 'media-deadline-results.json').write_text(json.dumps(checks, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(checks[-1]), flush=True)


sql = out / 'media-clock.private.sql'
sql.write_text("begin;update auth.sessions s set created_at=clock_timestamp()-interval '168 hours'+interval '45 seconds' "
               "from auth.users u where s.user_id=u.id and u.id='" + uid + "'::uuid and s.id='" + sid + "'::uuid "
               "and u.email like 'fr28-%@example.test' and exists(select 1 from public.users p where p.auth_user_id=u.id and p.role='admin') "
               "and s.created_at>clock_timestamp()-interval '5 minutes' returning true as changed;commit;", encoding='utf-8')
check(d.query(sql) == [{'changed': True}], 'only one fresh synthetic Admin session given a controlled45second deadline')
rider = b.fr04['accounts']['rider-a']
assert rider['email'].startswith('fr04-') and rider['email'].endswith('@example.test')
code, value = b.api('/functions/v1/fr04-cnic', 'POST', {'action': 'view', 'user_id': rider['profile_id']}, token)
check(code == 200 and 0 < value.get('expires_in', 0) <= 45,
      'authorized real CNIC URL lifetime is bounded by remaining application authorization')
url = value['url']
parsed = urllib.parse.urlsplit(url)
assert parsed.scheme == 'https' and parsed.hostname == b.REF + '.supabase.co'
with urllib.request.urlopen(url, timeout=15) as response:
    check(response.status == 200 and bool(response.read()), 'near-deadline authorized CNIC URL retrieves protected bytes')
deadline = time.monotonic() + value['expires_in'] + 5
while time.monotonic() < deadline:
    time.sleep(min(10, deadline - time.monotonic()))
try:
    with urllib.request.urlopen(url, timeout=15) as response:
        status = response.status
except urllib.error.HTTPError as error:
    status = error.code
check(status in (400, 401, 403), 'same actual signed CNIC URL denied after its short deadline')
code, value = b.api('/functions/v1/fr04-cnic', 'POST', {'action': 'view', 'user_id': rider['profile_id']}, token)
check(code == 401 and value.get('code') == 'FR28_SESSION_REVOKED', 'expired synthetic Admin session cannot renew CNIC authorization')
print(json.dumps({'project': b.REF, 'checks': len(checks), 'provider_calls': 0,
                  'physical_device_session_modified': False, 'real_short_wall_clock_expiry': True,
                  'seven_day_wall_clock_test': False}))
