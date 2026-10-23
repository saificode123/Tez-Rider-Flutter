"""Recheck retained FR13 protocol through the now-mandatory TEST gateway.

Two marked synthetic delivery fixtures only; both closed by retained finally.
No phone location, provider call, production access or scale test.
"""
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('tracking', Path(__file__).with_name('FR-13-hosted.py'))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
h.b.target()
h.OUT = h.ROOT / '.fr21-local/final03/tracking'
h.OUT.mkdir(parents=True, exist_ok=True)
original = h.b.api


def application_api(path, method='GET', body=None, token=None, admin=False, mime='application/json'):
    if path.startswith('/rest/v1/') and token and not admin:
        route, _, query = path[len('/rest/v1'):].partition('?')
        return original('/functions/v1/security-gateway', 'POST', {
            'method': method, 'path': route, 'query': query,
            'headers': {'content-type': mime, 'prefer': 'return=representation'},
            'body': '' if body is None else json.dumps(body)}, token)
    return original(path, method, body, token, admin, mime)


h.b.api = application_api
import sys
import time
import urllib.parse
sys.path.insert(0, str(h.ROOT / 'build/fr21-python'))
from websockets.sync.client import connect
from websockets.exceptions import ConnectionClosed

url = 'wss://' + h.b.REF + '.supabase.co/realtime/v1/websocket?' + urllib.parse.urlencode({'apikey': h.b.ANON, 'vsn': '1.0.0'})
sockets = []

def join(token, topic, private=True):
    ws = connect(url, open_timeout=20, close_timeout=3); sockets.append(ws)
    ws.send(json.dumps({'topic': 'realtime:' + topic, 'event': 'phx_join', 'ref': '1', 'payload': {
        'config': {'private': private, 'broadcast': {'ack': True, 'self': True}, 'presence': {'key': ''}, 'postgres_changes': []}, 'access_token': token}}))
    while True:
        msg = json.loads(ws.recv(timeout=20))
        if msg.get('event') == 'phx_reply' and msg.get('ref') == '1':
            return ws, msg['payload']['status'] == 'ok'

def events(ws, seconds):
    until = time.monotonic() + seconds; result = []
    while time.monotonic() < until:
        try: msg = json.loads(ws.recv(timeout=max(.01, until-time.monotonic())))
        except (TimeoutError, ConnectionClosed): break
        if msg.get('event') == 'broadcast' and msg['payload'].get('event') == 'location': result.append(msg['payload']['payload'])
    return result

row, rider = h.new_order()
try:
    h.start(row, rider)
    tokens = {who: h.b.login(h.state['accounts'][who]) for who in ('customer', 'rider', 'admin', 'other-customer', 'other-rider', 'vendor')}
    contexts = {}; owned = {}
    for who in ('customer', 'rider', 'admin'):
        code, ctx = h.b.rpc('fr13_tracking_context', {'p_order_id': row['oid']}, tokens[who])
        assert code == 200 and ctx['code'] == 'OK'
        contexts[who] = ctx
        ws, allowed = join(tokens[who], ctx['topic']); owned[who] = ws
        h.check(allowed, who + ': own session-bound private topic join allowed')
    h.check(len({v['topic'] for v in contexts.values()}) == 3, 'authorized roles have distinct session-bound topics')
    for who in ('other-customer', 'other-rider', 'vendor'):
        _, allowed = join(tokens[who], contexts['customer']['topic'])
        h.check(not allowed, who + ': customer private session topic denied')
    _, allowed = join(h.b.ANON, contexts['customer']['topic'])
    h.check(not allowed, 'anonymous private session topic denied')
    _, allowed = join(tokens['admin'], contexts['customer']['topic'])
    h.check(not allowed, 'even related Admin cannot join another session topic')
    decoy, _ = join(tokens['other-customer'], contexts['customer']['topic'], False)
    def publish():
        value = h.body(row['oid']); code, result = h.publish(value, rider)
        h.check(code == 200 and result['code'] == 'PUBLISHED', 'trusted location publication confirmed')
        return value['request_id']
    request = publish()
    for who, ws in owned.items():
        h.check(any(e['request_id'] == request for e in events(ws, 5)), who + ': actual permitted fix received')
    h.check(events(decoy, 1) == [], 'public decoy receives no private session fix')
    # Remove only this test reader's session; no phone/account-global revocation.
    code, _ = h.b.api('/auth/v1/logout?scope=local', 'POST', token=tokens['customer'])
    h.check(code in (200, 204), 'separate private customer reader local revocation confirmed')
    time.sleep(2)
    request = publish()
    h.check(events(owned['customer'], 5) == [], 'already subscribed revoked private reader receives no subsequent trusted fix')
    h.check(any(e['request_id'] == request for e in events(owned['admin'], 5)), 'unrevoked Admin still receives after peer revocation')
    _, allowed = join(tokens['customer'], contexts['customer']['topic'])
    h.check(not allowed, 'revoked private reader cannot reconnect to its previous topic')
    tokens['customer'] = h.b.login(h.state['accounts']['customer'])
    code, ctx = h.b.rpc('fr13_tracking_context', {'p_order_id': row['oid']}, tokens['customer'])
    assert code == 200 and ctx['code'] == 'OK'
    h.check(ctx['topic'] != contexts['customer']['topic'], 'fresh password session receives a new topic')
    new, allowed = join(tokens['customer'], ctx['topic'])
    h.check(allowed, 'fresh customer session reconnects through current authorization')
    request = publish()
    h.check(any(e['request_id'] == request for e in events(new, 5)), 'fresh customer session receives after recovery')
    # A malicious authenticated publisher still lacks INSERT permission.
    code, _ = h.b.api('/realtime/v1/api/broadcast', 'POST', {'messages': [{'topic': ctx['topic'], 'event': 'location', 'payload': {'forged': True}, 'private': True}]}, tokens['customer'])
    h.check(events(new, 2) == [], 'direct authenticated REST publish cannot inject a fix')
    h.close(row)
    time.sleep(2)
    code, result = h.publish(h.body(row['oid']), rider)
    h.check(code == 200 and result['code'] == 'INELIGIBLE', 'cancelled delivery cannot publish')
    h.check(events(new, 2) == [], 'cached subscriber receives no location after delivery cancellation')
    _, allowed = join(tokens['customer'], ctx['topic'])
    h.check(not allowed, 'cancelled delivery topic cannot regain private access')
finally:
    h.close(row)
    for ws in sockets: ws.close()
(h.OUT / 'session-topic-results.json').write_text(json.dumps(h.checks, indent=2))
print(json.dumps({'project': h.b.REF, 'passed': len(h.checks), 'actual_websocket': True, 'phone_session_modified': False}))
