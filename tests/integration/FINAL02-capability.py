"""Nondestructive rollback-only installation capability boundary checks.

Reuses an unread notification of the marked cancelled-order fixture when one
exists, otherwise inserts one rollback-only synthetic notice. A newly logged-in
real session and two uncommitted private device/job rows are used. All fixture
rows are invisible to workers and rolled back; no existing installation changes.
No DELETE, claim, send, configuration change or migration replay occurs.
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
fixture = json.loads(b.crypt((b.PRIVATE / 'final01-workflow.bin').read_bytes(), True))
assert fixture.get('cancelled') and fixture['email'].startswith('final01-') and fixture['email'].endswith('@example.test')
token = b.login(fixture)
part = token.split('.')[1]
claims = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
sid = str(uuid.UUID(claims['session_id']))
uid = str(uuid.UUID(fixture['auth_id']))
owner = int(fixture['profile_id'])
secret = secrets.token_hex(32)
source = f"""begin;
set local statement_timeout='20s';
set local lock_timeout='5s';
create temp table final02_capability_results(check_name text,passed boolean);
do $test$
declare installation uuid:=gen_random_uuid(); notice bigint; snapshot uuid;
 credential text:='{secret}'; inert_token text; old_created timestamptz; old_bound timestamptz;
begin
 if not exists(select 1 from public.users p join auth.users u on u.id=p.auth_user_id
 where p.id={owner} and u.id='{uid}'::uuid and u.raw_user_meta_data->>'final01_fixture'='true'
 and not p.is_blocked and u.email_confirmed_at is not null)then raise exception 'Marked fixture guard failed';end if;
 select created_at,not_after into strict old_created,old_bound from auth.sessions
 where id='{sid}'::uuid and user_id='{uid}'::uuid and created_at>clock_timestamp()-interval '5 minutes';
 select id,coalesce(broadcast_id,order_push_event_id)into notice,snapshot from public.notifications
 where user_id={owner} and not is_read and coalesce(broadcast_id,order_push_event_id)is not null order by id desc limit 1;
 if notice is null then
  insert into public.notifications(user_id,title,message,type,is_read,order_push_event_id)
  values({owner},'FINAL02 SYNTHETIC CAPABILITY TEST','Rollback-only test notice; no provider delivery','order',false,gen_random_uuid())
  returning id,order_push_event_id into notice,snapshot;
 end if;
 inert_token:='FINAL02_SYNTHETIC_'||replace(installation::text,'-','');
 insert into fr30_private.push_devices(id,user_id,session_id,token,token_hash,secret_hash)
 values(installation,{owner},'{sid}'::uuid,inert_token,encode(extensions.digest(inert_token,'sha256'),'hex'),encode(extensions.digest(credential,'sha256'),'hex'));
 insert into fr30_private.push_deliveries(notification_id,device_id,user_id,session_id,token_hash,secret_hash,state,lease,leased_at,expires_at)
 select notice,id,user_id,session_id,token_hash,secret_hash,'PROCESSING',gen_random_uuid(),clock_timestamp(),clock_timestamp()+interval '5 minutes'
 from fr30_private.push_devices where id=installation;
 insert into final02_capability_results values
 ('live real-session-bound installation capability resolves existing snapshot',public.fr30_resolve_push(installation,credential,snapshot)->>'code'='OK'),
 ('wrong installation secret denied',public.fr30_resolve_push(installation,repeat('0',64),snapshot)->>'code'='FORBIDDEN'),
 ('wrong installation identifier denied',public.fr30_resolve_push(gen_random_uuid(),credential,snapshot)->>'code'='FORBIDDEN'),
 ('wrong snapshot denied',public.fr30_resolve_push(installation,credential,gen_random_uuid())->>'code'='FORBIDDEN');
 update auth.sessions set created_at=clock_timestamp()-interval '168 hours 1 second'where id='{sid}'::uuid and user_id='{uid}'::uuid;
 insert into final02_capability_results values('absolute application deadline denies installation capability',public.fr30_resolve_push(installation,credential,snapshot)->>'code'='FORBIDDEN');
 update auth.sessions set created_at=old_created where id='{sid}'::uuid and user_id='{uid}'::uuid;
 insert into final02_capability_results values('live clock control restores positive resolution within rollback transaction',public.fr30_resolve_push(installation,credential,snapshot)->>'code'='OK');
 update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id='{sid}'::uuid and user_id='{uid}'::uuid;
 insert into final02_capability_results values('earlier provider session deadline denies installation capability',public.fr30_resolve_push(installation,credential,snapshot)->>'code'='FORBIDDEN');
 update auth.sessions set not_after=old_bound where id='{sid}'::uuid and user_id='{uid}'::uuid;
 update fr30_private.push_deliveries set session_id=gen_random_uuid()where device_id=installation;
 insert into final02_capability_results values('job and installation session snapshot mismatch denied',public.fr30_resolve_push(installation,credential,snapshot)->>'code'='FORBIDDEN');
end $test$;
select jsonb_agg(jsonb_build_object('check',check_name,'result',case when passed then 'PASS' else 'FAIL'end))as results from final02_capability_results;
rollback;
"""
assert source.rstrip().endswith('rollback;') and 'delete ' not in source.lower()
path = out / 'capability-operation.private.sql'
path.write_text(source, encoding='utf-8')
rows = d.query(path)[0]['results']
(out / 'installation-capability-results.json').write_text(json.dumps(rows, indent=2) + '\n', encoding='utf-8')
assert len(rows) == 8 and all(row['result'] == 'PASS' for row in rows)
print(json.dumps({'project': b.REF, 'checks': len(rows), 'rolled_back': True,
                  'provider_calls': 0, 'persisted_business_changes': 0,
                  'scope': 'SQL function capability boundary using a real fresh session; not anonymous network delivery or device receipt',
                  'revoked_session_deletion_tested': False}))
