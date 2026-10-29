"""Read-only match of current TEST phone FCM capability; never publish credentials."""
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = Path('C:/Users/urreh/AppData/Local/TezRider-FR21/auth-review')
REF = 'igeisilhtmglgnqvllrx'
assert (ROOT / 'supabase/.temp/project-ref').read_text().strip() == REF
adb = 'C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
raw = subprocess.run([adb, '-s', 'AESWNRBAEUPNTGJZ', 'exec-out', 'run-as',
    'com.example.flutter_application_1.fr21test', 'cat', 'shared_prefs/com.google.android.gms.appid.xml'],
    capture_output=True, timeout=20, check=True).stdout
tokens = []
for entry in ET.fromstring(raw):
    if '|T|' in entry.get('name', ''):
        item = json.loads(entry.text)
        if isinstance(item, dict) and isinstance(item.get('token'), str):
            tokens.append(item['token'])
assert len(tokens) == 1 and re.fullmatch(r'[A-Za-z0-9:_-]{16,4096}', tokens[0]), 'Unique current TEST FCM capability required'
digest = hashlib.sha256(tokens[0].encode()).hexdigest()
query = PRIVATE / 'phone-push-check.private.sql'
query.write_text("begin read only;set local statement_timeout='15s';select jsonb_build_object("
    "'enabled',(select android_push_enabled from fr30_private.limits where singleton),"
    "'current_phone_registrations',(select count(*)from fr30_private.push_devices where token_hash='" + digest + "'),"
    "'current_phone_owner_ids',(select coalesce(jsonb_agg(user_id),'[]')from fr30_private.push_devices where token_hash='" + digest + "'),"
    "'current_phone_live_sessions',(select count(*)from fr30_private.push_devices d join auth.sessions s on s.id=d.session_id where d.token_hash='" + digest + "'),"
    "'other_device_registrations',(select count(*)from fr30_private.push_devices where token_hash<>'" + digest + "'),"
    "'other_device_owners',(select coalesce(jsonb_agg(jsonb_build_object('user_id',d.user_id,'role',u.role,'live_session',s.id is not null)),'[]')from fr30_private.push_devices d join public.users u on u.id=d.user_id left join auth.sessions s on s.id=d.session_id where d.token_hash<>'" + digest + "'),"
    "'authenticated_cannot_read_credentials',not has_table_privilege('authenticated','fr30_private.push_devices','SELECT'))as capability;rollback;", encoding='utf-8')
response = subprocess.run([str(ROOT / '.fr21-local/tools/supabase.exe'), 'db', 'query', '--linked', '--project-ref', REF,
    '--file', str(query), '--output', 'json'], capture_output=True, text=True, timeout=90)
assert response.returncode == 0, 'Read-only push inspection unconfirmed; no raw CLI output exposed'
result = json.JSONDecoder().raw_decode(response.stdout[response.stdout.index('{'):])[0]['rows'][0]['capability']
result.update(project=REF, utc=dt.datetime.now(dt.timezone.utc).isoformat(),
    scope='Read-only current physical TEST FCM token hash match and live session. No push sent. No token, hash, installation credential or session ID published.')
(ROOT / 'docs/evidence/AUTH-phone-push.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
