"""Actual anonymous installation-secret resolution with fresh real sessions.

Two bounded synthetic notices/device/jobs belong only to the marked cancelled
order fixture. Notification INSERT has no snapshot, so fanout cannot occur; its
snapshot is then assigned only to that notice. Private jobs are due AFTER expiry
and can never be sent. No worker/provider is called and no fixture is deleted.
"""
import base64
import importlib.util
import json
import secrets
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
catalog = json.loads((out / 'final02-catalog.private.json').read_text())
triggers = [t for t in catalog['triggers'] if t['event_object_table'] == 'notifications']
assert len(triggers) == 1 and triggers[0]['trigger_name'] == 'fr30_queue_push' and triggers[0]['event_manipulation'] == 'INSERT'
fixture = json.loads(b.crypt((b.PRIVATE / 'final01-workflow.bin').read_bytes(), True))
assert fixture.get('cancelled') and fixture['email'].startswith('final01-') and fixture['email'].endswith('@example.test')
uid = str(uuid.UUID(fixture['auth_id']))
owner = int(fixture['profile_id'])
checks = []


def check(ok, label, surface='actual anonymous HTTP capability boundary'):
    assert ok, label
    checks.append({'check': label, 'result': 'PASS', 'surface': surface})
    (out / 'installation-capability-http-results.json').write_text(json.dumps(checks, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(checks[-1]), flush=True)


def sql(source):
    path = out / 'capability-http-operation.private.sql'
    path.write_text(source, encoding='utf-8')
    return d.query(path)


for mode in ('expired', 'revoked'):
    token = b.login(fixture)
    part = token.split('.')[1]
    claims = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
    sid = str(uuid.UUID(claims['session_id']))
    installation = str(uuid.uuid4())
    snapshot = str(uuid.uuid4())
    secret = secrets.token_hex(32)
    rows = sql(f"""begin;
set local lock_timeout='5s';set local statement_timeout='20s';
create temp table final02_http_fixture(notice bigint);
do $test$declare n bigint;inert_token text:='FINAL02_SYNTHETIC_{installation.replace('-', '')}';begin
 if not exists(select 1 from public.users p join auth.users u on u.id=p.auth_user_id
 join auth.sessions s on s.user_id=u.id where p.id={owner} and u.id='{uid}'::uuid
 and u.raw_user_meta_data->>'final01_fixture'='true' and not p.is_blocked
 and u.email_confirmed_at is not null and s.id='{sid}'::uuid and s.created_at>clock_timestamp()-interval '5 minutes')
 then raise exception 'Fresh marked fixture guard failed';end if;
 insert into public.notifications(user_id,title,message,type,is_read)
 values({owner},'FINAL02 SYNTHETIC CAPABILITY HTTP TEST','Synthetic fixture; never dispatched','order',false)returning id into n;
 update public.notifications set order_push_event_id='{snapshot}'::uuid where id=n and user_id={owner};
 insert into fr30_private.push_devices(id,user_id,session_id,token,token_hash,secret_hash)
 values('{installation}'::uuid,{owner},'{sid}'::uuid,inert_token,encode(extensions.digest(inert_token,'sha256'),'hex'),encode(extensions.digest('{secret}','sha256'),'hex'));
 insert into fr30_private.push_deliveries(notification_id,device_id,user_id,session_id,token_hash,secret_hash,state,due_at,expires_at)
 select n,id,user_id,session_id,token_hash,secret_hash,'PENDING',clock_timestamp()+interval '1 day',clock_timestamp()+interval '10 minutes'
 from fr30_private.push_devices where id='{installation}'::uuid;
 insert into final02_http_fixture values(n);
end $test$;
select f.notice,exists(select 1 from fr30_private.push_deliveries j where j.notification_id=f.notice and j.device_id='{installation}'::uuid and j.due_at>j.expires_at and j.expires_at>clock_timestamp()+interval '5 minutes')as cannot_dispatch
from final02_http_fixture f;
commit;
""")
    check(len(rows) == 1 and rows[0]['cannot_dispatch'] is True,
          mode + ': only marked synthetic job created with dispatch time later than expiry', 'guarded TEST fixture setup/accounting')
    notice = rows[0]['notice']
    body = {'p_installation': installation, 'p_secret': secret, 'p_broadcast': snapshot}
    code, value = b.rpc('fr30_resolve_push', body)
    check(code == 200 and value.get('code') == 'OK' and value.get('id') == notice,
          mode + ': anonymous transport resolves only the live session-bound synthetic snapshot')
    code, value = b.rpc('fr30_resolve_push', dict(body, p_secret='0' * 64))
    check(code == 200 and value.get('code') == 'FORBIDDEN', mode + ': wrong installation secret denied over actual network')
    if mode == 'expired':
        rows = sql("begin;update auth.sessions s set created_at=clock_timestamp()-interval '168 hours 1 second' "
                   "from auth.users u where s.user_id=u.id and u.id='" + uid + "'::uuid "
                   "and u.raw_user_meta_data->>'final01_fixture'='true' and s.id='" + sid + "'::uuid "
                   "and s.created_at>clock_timestamp()-interval '5 minutes' returning true as changed;commit;")
        check(rows == [{'changed': True}], 'only fresh marked capability reader session aged', 'controlled TEST clock')
    else:
        code, _ = b.api('/auth/v1/logout?scope=local', 'POST', token=token)
        check(code in (200, 204), 'only fresh marked capability reader logout confirmed', 'actual user Auth HTTP')
    code, value = b.rpc('fr30_resolve_push', body)
    check(code == 200 and value.get('code') == 'FORBIDDEN', mode + ': previously valid secret cannot resolve after session denial')
print(json.dumps({'project': b.REF, 'checks': len(checks), 'provider_calls': 0,
                  'synthetic_notices_created': 2, 'fixtures_deleted': False,
                  'dispatch_safety': 'due_at later than expires_at; inserted without snapshot to avoid trigger fanout',
                  'device_receipt_claimed': False}))
