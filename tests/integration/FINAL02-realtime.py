"""Real own-profile Postgres Changes lifecycle on the existing marked fixture.

Only unchanged own-profile name values are written. Reader clock changes select
one fresh marked session; writer and phone sessions are never aged/revoked.
No tokens, profile values or event payloads are printed.
"""
import base64
import importlib.util
import json
import sys
import time
import urllib.parse
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
sys.path.insert(0, str(b.ROOT / 'build/fr21-python'))
from websockets.sync.client import connect
from websockets.exceptions import ConnectionClosed

fixture = json.loads(b.crypt((b.PRIVATE / 'final01-workflow.bin').read_bytes(), True))
assert fixture.get('cancelled') and fixture['email'].startswith('final01-') and fixture['email'].endswith('@example.test')
uid = str(uuid.UUID(fixture['auth_id']))
checks = []


def check(ok, label):
    assert ok, label
    checks.append({'check': label, 'result': 'PASS', 'surface': 'actual user websocket/HTTP'})
    (out / 'realtime-lifecycle-results.json').write_text(json.dumps(checks, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(checks[-1]), flush=True)


def sid(token):
    part = token.split('.')[1]
    return str(uuid.UUID(json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))['session_id']))


def gateway(token, method='GET', body=None):
    return b.api('/functions/v1/security-gateway', 'POST', {
        'method': method, 'path': '/users', 'query': 'id=eq.' + str(fixture['profile_id']) + '&select=id,name',
        'headers': {'content-type': 'application/json', 'prefer': 'return=representation'},
        'body': '' if body is None else json.dumps(body)}, token)


writer = b.login(fixture)
code, rows = gateway(writer)
assert code == 200 and len(rows) == 1
name = rows[0]['name']


def update():
    code, rows = gateway(writer, 'PATCH', {'name': name})
    check(code == 200 and len(rows) == 1 and rows[0]['name'] == name,
          'marked fixture owner confirms unchanged-name update used as Realtime signal')


def event(ws, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            message = json.loads(ws.recv(timeout=max(.01, deadline - time.monotonic())))
        except (TimeoutError, ConnectionClosed):
            return False
        if message.get('event') == 'postgres_changes':
            return True
    return False


url = 'wss://' + b.REF + '.supabase.co/realtime/v1/websocket?' + urllib.parse.urlencode({'apikey': b.ANON, 'vsn': '1.0.0'})
for mode in ('expired', 'revoked'):
    reader = b.login(fixture)
    reader_sid = sid(reader)
    assert reader_sid != sid(writer)
    with connect(url, open_timeout=20, close_timeout=3) as ws:
        topic = 'realtime:final02-own-profile-' + mode
        ws.send(json.dumps({'topic': topic, 'event': 'phx_join', 'ref': '1', 'payload': {
            'config': {'private': False, 'broadcast': {'ack': False, 'self': False},
                       'presence': {'key': ''}, 'postgres_changes': [{'event': 'UPDATE', 'schema': 'public',
                           'table': 'users', 'filter': 'id=eq.' + str(fixture['profile_id'])}]},
            'access_token': reader}}))
        registered = False
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            msg = json.loads(ws.recv(timeout=max(.01, deadline - time.monotonic())))
            if msg.get('event') == 'phx_reply' and msg.get('ref') == '1':
                assert msg['payload']['status'] == 'ok'
                registered = bool(msg['payload'].get('response', {}).get('postgres_changes'))
                break
        check(registered, mode + ': live reader registered actual own-profile Postgres Changes')
        update()
        check(event(ws, 15), mode + ': live reader receives actual authorized own-profile event')
        if mode == 'expired':
            path = out / 'realtime-clock.private.sql'
            path.write_text("begin;update auth.sessions s set created_at=clock_timestamp()-interval '168 hours 1 second' "
                            "from auth.users u where s.user_id=u.id and u.id='" + uid + "'::uuid "
                            "and u.raw_user_meta_data->>'final01_fixture'='true' and s.id='" + reader_sid + "'::uuid "
                            "and s.created_at>clock_timestamp()-interval '5 minutes' returning true as changed;commit;", encoding='utf-8')
            check(d.query(path) == [{'changed': True}], 'exactly one separate marked Realtime reader session aged')
        else:
            code, _ = b.api('/auth/v1/logout?scope=local', 'POST', token=reader)
            check(code in (200, 204), 'only separate Realtime reader local logout confirmed')
        update()
        check(not event(ws, 10), mode + ': existing websocket receives no own-profile update in bounded10second observation')
print(json.dumps({'project': b.REF, 'checks': len(checks), 'provider_calls': 0,
                  'scope': 'own-profile Postgres Changes only; bounded event nondelivery, not every Realtime topic'}))
