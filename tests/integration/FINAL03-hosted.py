"""Bounded TEST closure checks. Reuse fixtures; never print payloads or links.

No deployment, provider sends, load test, historical object edits or production.
"""
import importlib.util
import base64
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


b = module('backend', 'FR-04-hosted.py')
d = module('database', 'FINAL-security.py')
b.target()
out = b.ROOT / '.fr21-local/final03'
out.mkdir(exist_ok=True)
checks = []
mode = sys.argv[1]


def check(ok, label, level='authenticated TEST HTTP'):
    if not ok:
        raise AssertionError(label)
    row = {'check': label, 'result': 'PASS', 'surface': level}
    checks.append(row)
    (out / (mode + '-results.json')).write_text(json.dumps(checks, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(row), flush=True)


def state(name):
    return json.loads(b.crypt((b.PRIVATE / name).read_bytes(), True))


def gateway(table, token, query='select=id&limit=1', method='GET', body=None):
    return b.api('/functions/v1/security-gateway', 'POST', {
        'method': method, 'path': '/' + table, 'query': query,
        'headers': {'content-type': 'application/json', 'prefer': 'return=representation'},
        'body': '' if body is None else json.dumps(body)}, token)


def inspect():
    catalog = d.query(b.ROOT / 'supabase/inspection/FINAL-security.sql')[0]['inspection']
    final = len(sys.argv) > 2 and sys.argv[2] == 'final'
    (out / ('catalog-final.private.json' if final else 'catalog.json')).write_text(json.dumps(catalog, indent=2), encoding='utf-8')
    if final:
        expected = sorted(p.name.split('_')[0] for p in (b.ROOT / 'supabase/migrations').glob('*.sql'))
        check(catalog['versions'] == expected and len(expected) == 45, '45 migration versions exactly match source; 0004 retained once', 'read-only TEST catalog')
        check(len(catalog['tables']) == 84 and all(t['rls'] for t in catalog['tables']), 'all84 inspected tables including private reader registry retain RLS', 'read-only TEST catalog')
        old = json.loads((out / 'catalog.json').read_text())
        key = lambda f: (f['schema'], f['name'], f['signature'])
        before = {key(f): f for f in old['functions']}; after = {key(f): f for f in catalog['functions']}
        changed = {k[1] for k in before if before[k] != after.get(k)}
        added = {k[1] for k in after if k not in before}
        check(changed == {'fr17_save_product', 'fr13_can_receive', 'fr13_tracking_context', 'fr13_submit_location'} and added == {'fr13_live_topics'}, 'only four reviewed function bodies changed; one service-only recipient function added', 'catalog preservation plus focused independent review')
        check(all(t == next(v for v in catalog['tables'] if v['schema'] == t['schema'] and v['name'] == t['name']) for t in old['tables']), 'all83 previous table grants, operation policies and column privileges preserved', 'operation-level catalog comparison')
        helper = next(f for f in catalog['functions'] if f['name'] == 'fr13_live_topics')
        check(not helper['anon_execute'] and not helper['authenticated_execute'] and helper['definer'] and 'search_path=""' in helper['config'], 'new recipient RPC has fixed search_path and no anonymous/application execute grants', 'read-only TEST catalog')
        return
    check(len(catalog['versions']) == 42 and catalog['versions'][-1] == '202610220004',
          '42 existing migrations; 0004 already applied; no deployment/replay', 'read-only TEST catalog')
    check(all(t['rls'] for t in catalog['tables']), 'all83 inspected tables retain RLS', 'read-only TEST catalog')
    old = json.loads((b.ROOT / '.fr21-local/final01/final02-catalog.private.json').read_text(encoding='utf-8-sig'))
    key = lambda f: (f['schema'], f['name'], f['signature'])
    before = {key(f): f for f in old['functions']}
    after = {key(f): f for f in catalog['functions']}
    check(before == after and len(after) == 174, '174 deployed definitions and ACLs unchanged since accepted activation', 'catalog preservation, not independent review')
    print(json.dumps({'fixture_keys': {n: {'keys': sorted(state(n)), 'accounts': sorted(state(n).get('accounts', {}))}
                                   for n in ('fr25-accounts.bin', 'fr32-accounts.bin', 'fr28-accounts.bin')}}))


def media():
    if len(sys.argv) > 2 and sys.argv[2] == 'faults':
        return media_faults()
    accounts = state('fr28-accounts.bin')['accounts']
    peers = {role: b.login(accounts[role]) for role in ('customer', 'vendor', 'rider', 'admin')}
    dispute = state('fr25-accounts.bin')
    invoice = state('fr32-accounts.bin')
    paths = [
        ('CNIC', 'rider-cnic', '/functions/v1/fr04-cnic', {'action': 'view', 'user_id': b.fr04['accounts']['rider-a']['profile_id']},
         b.login(b.fr04['accounts']['rider-a']), None),
        ('evidence', 'dispute-evidence', '/functions/v1/fr25-evidence', {'action': 'view', 'dispute_id': dispute['dispute_id'], 'index': 1},
         b.login(dispute['accounts']['customer-a']), dispute.get('path')),
        ('invoice', 'invoices', '/functions/v1/fr32-invoice-url', {'order_id': invoice['invoice_order_id']},
         b.login(invoice['accounts']['customer']), None),
    ]
    for label, bucket, endpoint, body, owner, object_path in paths:
        for who, token in [('owner', owner), ('approved Admin', peers['admin'])]:
            code, value = b.api(endpoint, 'POST', body, token)
            check(code == 200 and isinstance(value, dict) and isinstance(value.get('url'), str), label + ': ' + who + ' may sign existing legitimate object')
            ttl = value.get('expires_in', value.get('expiresIn'))
            check(isinstance(ttl, int) and 0 < ttl <= 900, label + ': signed lifetime bounded to at most900seconds')
            url = value['url']
            parsed = urllib.parse.urlsplit(url)
            assert parsed.scheme == 'https' and parsed.hostname == b.REF + '.supabase.co'
            with urllib.request.urlopen(url, timeout=20) as response:
                check(response.status == 200 and len(response.read()) > 0, label + ': ' + who + ' retrieves real protected bytes')
            # Exact object reference stays in process only.
            prefix = '/storage/v1/object/sign/' + bucket + '/'
            if parsed.path.startswith(prefix):
                object_path = urllib.parse.unquote(parsed.path[len(prefix):])
        for who, token in [('unrelated customer', peers['customer']), ('unrelated vendor', peers['vendor']), ('unrelated rider', peers['rider']), ('anonymous', None)]:
            code, _ = b.api(endpoint, 'POST', body, token)
            check(code in (400, 401, 403, 404, 422), label + ': ' + who + ' denied signing')
            code, rows = b.api('/storage/v1/object/list/' + bucket, 'POST', {'prefix': '', 'limit': 1}, token)
            check(code in (400, 401, 403, 404) or rows == [], label + ': ' + who + ' cannot list object metadata')
            assert object_path
            code, _ = b.api('/storage/v1/object/authenticated/' + bucket + '/' + urllib.parse.quote(object_path, safe='/'), token=token)
            check(code in (400, 401, 403, 404), label + ': ' + who + ' denied unsigned object read')
        code, _ = b.api('/storage/v1/object/sign/' + bucket + '/' + urllib.parse.quote(object_path, safe='/'), 'POST', {'expiresIn': 3600}, owner)
        check(code in (400, 401, 403, 404), label + ': owner cannot bypass server lifetime through direct Storage signing')
    for endpoint, body in [('/functions/v1/fr25-evidence', {'action': 'view', 'dispute_id': 'wrong-type', 'index': 1}),
                           ('/functions/v1/fr32-invoice-url', {'order_id': -1}),
                           ('/functions/v1/fr04-cnic', {'action': 'view', 'user_id': 'not-an-id'})]:
        code, _ = b.api(endpoint, 'POST', body, peers['admin'])
        check(code in (400, 403, 422), 'trusted media boundary rejects malformed reference: ' + endpoint.rsplit('/', 1)[-1])


def media_faults():
    """Real live claims, blocked-owner fault inside a full rollback only."""
    dispute = state('fr25-accounts.bin')
    invoice = state('fr32-accounts.bin')
    cases = [
        ('CNIC', b.fr04['accounts']['rider-a'], 'public.fr04_document_authority(null)'),
        ('evidence', dispute['accounts']['customer-a'], 'public.fr25_evidence_authority(' + str(int(dispute['dispute_id'])) + ',1)'),
        ('invoice', invoice['accounts']['customer'], 'public.fr32_invoice_authority(' + str(int(invoice['invoice_order_id'])) + ')'),
    ]
    for label, account, call in cases:
        token = b.login(account)
        part = token.split('.')[1]
        claims = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
        assert claims['role'] == 'authenticated'
        quoted = "'" + json.dumps(claims).replace("'", "''") + "'"
        profile = int(account['profile_id'])
        sql = """begin;
set local role authenticated;
select set_config('request.jwt.claims',CLAIMS,true) is not null as claims_set;
do $positive$ begin if CALL is null then raise exception 'Owner authority missing';end if;end $positive$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true) is not null as claims_set;
update public.users set is_blocked=true where id=PROFILE;
set local role authenticated;
select set_config('request.jwt.claims',CLAIMS,true) is not null as claims_set;
do $negative$ begin
 begin perform CALL;raise exception 'Blocked media owner accepted';
 exception when insufficient_privilege then null;end;
end $negative$;
select true as blocked_denied;
rollback;""".replace('CLAIMS', quoted).replace('CALL', call).replace('PROFILE', str(profile))
        path = out / 'media-blocked.private.sql'
        path.write_text(sql)
        result = d.query(path)
        assert result[-1]['blocked_denied'] is True
        check(True, label + ': existing live owner authority confirmed before block', 'real live-claim SQL; full rollback')
        check(True, label + ': same authenticated owner denied after blocked-account fault', 'real live-claim SQL; full rollback; no Auth ban or persistent change')


def realtime():
    """Actual row-RLS streams; no business values are changed by the signal."""
    sys.path.insert(0, str(b.ROOT / 'build/fr21-python'))
    from websockets.sync.client import connect
    from websockets.exceptions import ConnectionClosed
    fixture = state('fr25-accounts.bin')
    accounts = fixture['accounts']
    tokens = {who: b.login(accounts[who]) for who in ('customer-a', 'customer-b', 'admin', 'vendor', 'rider')}
    tokens['baseline-admin'] = b.login(b.state['accounts']['admin'])
    retained = state('fr32-accounts.bin')['accounts']
    for who in ('vendor', 'rider', 'customer'):
        tokens['fr32-' + who] = b.login(retained[who])
    tracking = state('fr13-accounts.bin')['accounts']
    for who in ('rider', 'customer'):
        tokens['fr13-' + who] = b.login(tracking[who])
    tables = [('disputes', 'id=eq.' + str(fixture['dispute_id']), 'description'),
              ('orders', 'user_id=eq.' + str(accounts['customer-a']['profile_id']), 'delivery_address'),
              ('notifications', 'dispute_id=eq.' + str(fixture['dispute_id']), 'is_read'),
              ('vendor_orders', 'vendor_id=eq.' + str(retained['vendor']['profile_id']), 'status'),
              ('rider_assignments', 'riderid=eq.' + str(tracking['rider']['profile_id']), 'status')]
    if len(sys.argv) > 2 and sys.argv[2] != 'status':
        tables = [entry for entry in tables if entry[0] == sys.argv[2]]
        assert tables, 'Known bounded Realtime surface required'
    url = 'wss://' + b.REF + '.supabase.co/realtime/v1/websocket?' + urllib.parse.urlencode({'apikey': b.ANON, 'vsn': '1.0.0'})

    def event(ws, seconds):
        until = time.monotonic() + seconds
        while time.monotonic() < until:
            try:
                msg = json.loads(ws.recv(timeout=max(.01, until - time.monotonic())))
            except (TimeoutError, ConnectionClosed):
                return False
            if msg.get('event') == 'postgres_changes':
                return True
            if msg.get('event') == 'system':
                print(json.dumps({'realtime_system': {'status': msg.get('payload', {}).get('status'), 'extension': msg.get('payload', {}).get('extension')}}), flush=True)
        return False

    def join(token, table, row_id):
        ws = connect(url, open_timeout=20, close_timeout=3)
        topic = 'realtime:final03-' + table
        ws.send(json.dumps({'topic': topic, 'event': 'phx_join', 'ref': '1', 'payload': {
            'config': {'private': False, 'broadcast': {'ack': False, 'self': False}, 'presence': {'key': ''},
                       'postgres_changes': [{'event': 'UPDATE', 'schema': 'public', 'table': table, 'filter': 'id=eq.' + str(row_id)}]},
            'access_token': token}}))
        until = time.monotonic() + 20
        while time.monotonic() < until:
            msg = json.loads(ws.recv(timeout=20))
            if msg.get('event') == 'phx_reply' and msg.get('ref') == '1':
                assert msg['payload']['status'] == 'ok' and msg['payload'].get('response', {}).get('postgres_changes'), 'Actual row subscription must register'
                return ws, topic
        raise AssertionError('Realtime registration timed out')

    for table, query, field in tables:
        code, rows = b.api('/rest/v1/' + table + '?' + query + '&select=*&limit=1', admin=True)
        assert code == 200 and len(rows) == 1, 'Existing marked resource required: ' + table
        row = rows[0]
        assert field in row
        authorized = None
        denied = []
        preferred = {'vendor_orders': 'fr32-vendor', 'rider_assignments': 'fr13-rider', 'notifications': 'baseline-admin'}.get(table, 'customer-a')
        ordered = sorted(tokens.items(), key=lambda item: item[0] != preferred)
        for who, token in ordered:
            code, values = gateway(table, token, 'id=eq.' + str(row['id']) + '&select=id')
            if code == 200 and values and authorized is None:
                authorized = (who, token)
            elif code in (401, 403) or values == []:
                denied.append((who, token))
        assert authorized and denied, 'Both real allowed and denied identities required'
        sockets = []
        try:
            own, topic = join(authorized[1], table, row['id']); sockets.append(own)
            check(True, table + ': allowed row stream registers for ' + authorized[0], 'actual user websocket')
            for who, token in denied:
                ws, _ = join(token, table, row['id']); sockets.append(ws)
            signal = not row[field] if isinstance(row[field], bool) else (row[field] or '') + ' [FINAL03 transient test]'
            if field in ('status', 'delivery_address'):
                signal = row[field]
            code, changed = b.api('/rest/v1/' + table + '?id=eq.' + str(row['id']), 'PATCH', {field: signal}, admin=True)
            if code != 200:
                print(json.dumps({'signal_failure_status': code, 'database_code': changed.get('code') if isinstance(changed, dict) else None}), flush=True)
            check(code == 200 and len(changed) == 1 and changed[0][field] == signal, table + ': bounded synthetic signal confirmed; original restored in finally')
            check(event(own, 12), table + ': permitted actual UPDATE received', 'actual user websocket')
            for (who, _), ws in zip(denied, sockets[1:]):
                check(not event(ws, 2), table + ': ' + who + ' receives no forbidden row within2seconds', 'bounded actual user websocket')
            own.send(json.dumps({'topic': topic, 'event': 'phx_leave', 'ref': 'leave', 'payload': {}}))
            until = time.monotonic() + 10
            while time.monotonic() < until:
                msg = json.loads(own.recv(timeout=10))
                if msg.get('event') == 'phx_reply' and msg.get('ref') == 'leave':
                    assert msg['payload']['status'] == 'ok'
                    break
            else:
                raise AssertionError('Unsubscribe acknowledgement required')
            code, _ = b.api('/rest/v1/' + table + '?id=eq.' + str(row['id']), 'PATCH', {field: row[field]}, admin=True)
            assert code == 200
            check(not event(own, 2), table + ': acknowledged unsubscribe receives no subsequent row event', 'bounded actual user websocket')
            own.close()
            new, _ = join(authorized[1], table, row['id']); sockets.append(new)
            code, _ = b.api('/rest/v1/' + table + '?id=eq.' + str(row['id']), 'PATCH', {field: row[field]}, admin=True)
            assert code == 200
            check(event(new, 12), table + ': reconnect requires registration and receives permitted event', 'actual user websocket')
        finally:
            code, restored = b.api('/rest/v1/' + table + '?id=eq.' + str(row['id']), 'PATCH', {field: row[field]}, admin=True)
            assert code == 200 and restored[0][field] == row[field], 'Synthetic signal restoration required'
            for ws in sockets:
                ws.close()


def legacy():
    action = sys.argv[2]
    assert action in ('review', 'deploy', 'post')
    version = '202610230001'
    migration = b.ROOT / ('supabase/migrations/' + version + '_final03_product_media_guard.sql')
    history_file = out / 'history.sql'
    history_file.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')
    versions = [r['version'] for r in d.query(history_file)]
    expected = sorted(p.name.split('_')[0] for p in (b.ROOT / 'supabase/migrations').glob('*.sql'))
    if action == 'deploy':
        assert versions == [v for v in expected if v != version] and '202610220004' in versions
        reviewed = json.loads((out / 'legacy-review-results.json').read_text())
        assert len(reviewed) == 4 and all(r['result'] == 'PASS' for r in reviewed)
        source = migration.read_text()
        assert 'drop ' not in source.lower() and 'delete ' not in source.lower() and source.count('commit;') == 1
        source = source.replace('commit;', "insert into supabase_migrations.schema_migrations(version,name)values('" + version + "','final03_product_media_guard');commit;")
        path = out / 'deploy.sql'; path.write_text(source)
        d.query(path)
        assert [r['version'] for r in d.query(history_file)] == expected
        (out / 'deployment.json').write_text(json.dumps({'project': b.REF, 'migration': migration.name, 'versions': len(expected), 'replayed': False, 'production_modified': False}, indent=2))
        print(json.dumps({'deployment': 'confirmed', 'project': b.REF, 'versions': len(expected)}))
        return
    assert versions == (expected if action == 'post' else [v for v in expected if v != version])
    token = b.login(state('fr32-accounts.bin')['accounts']['vendor'])
    part = token.split('.')[1]
    claims = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
    assert claims['role'] == 'authenticated'
    source = migration.read_text().replace('begin;', '').replace('commit;', '') if action == 'review' else ''
    tests = r"""
set local role authenticated;
do $claims$ begin perform set_config('request.jwt.claims', CLAIMS, true);end $claims$;
create temporary table final03_results(label text,result text);
do $test$ declare x jsonb;p public.products;payload jsonb:=jsonb_build_object('name','FINAL03 rollback regression','price',1,'image_url','https://example.invalid/new-media.png');begin
 begin
  x:=public.fr17_save_product(gen_random_uuid(),null,payload,1,0,null);
  raise exception 'Guard did not reject new media';
 exception when sqlstate '22023' then insert into final03_results values('new product media reference rejected on trusted RPC','PASS');end;
 x:=public.fr17_save_product(gen_random_uuid(),null,payload||jsonb_build_object('image_url',''),1,0,null);
 if x->>'code'<>'UPDATED' then raise exception 'Ordinary product save regressed';end if;
 insert into final03_results values('product save without media still confirmed (rolled back)','PASS');
 select * into p from public.products where id=(x->>'product_id')::bigint;
 begin
  x:=public.fr17_save_product(gen_random_uuid(),p.id,payload,1,0,p.stock_version);
  raise exception 'Guard did not reject replacement media';
 exception when sqlstate '22023' then insert into final03_results values('existing product cannot introduce unvalidated replacement media','PASS');end;
 x:=public.fr17_save_product(gen_random_uuid(),p.id,payload||jsonb_build_object('image_url',p.image_url),1,0,p.stock_version);
 if x->>'code'<>'UPDATED' then raise exception 'Unchanged reference regressed';end if;
 insert into final03_results values('unchanged/empty existing reference remains compatible (rolled back)','PASS');
end $test$;
select jsonb_agg(jsonb_build_object('check',label,'result',result,'surface','authenticated SQL with real live user claims; full rollback')) as results from final03_results;
rollback;
""".replace('CLAIMS', "'" + json.dumps(claims).replace("'", "''") + "'")
    path = out / 'legacy-operation.private.sql'
    path.write_text('begin;\n' + source + '\n' + tests, encoding='utf-8')
    rows = d.query(path)[0]['results']
    assert len(rows) == 4 and all(r['result'] == 'PASS' for r in rows)
    (out / ('legacy-' + action + '-results.json')).write_text(json.dumps(rows, indent=2) + '\n')
    checks.extend(rows)
    for row in rows:
        print(json.dumps(row))
    if action == 'post':
        code, value = gateway('rpc/fr17_save_product', token, '', 'POST', {
            'p_request_id': __import__('uuid').uuid4().hex,
            'p_product_id': None, 'p_data': {'name': 'FINAL03 rejected media', 'price': 1, 'image_url': 'https://example.invalid/unvalidated.png'},
            'p_stock': 1, 'p_threshold': 0, 'p_expected_version': None})
        check(code in (400, 422) and isinstance(value, dict) and value.get('code') == '22023', 'real vendor gateway request cannot bypass product media validation')


def audit():
    accounts = state('fr28-accounts.bin')['accounts']
    admin = accounts['admin']; vendor = accounts['vendor']
    token = b.login(admin)
    part = token.split('.')[1]
    claims = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
    actor = int(admin['profile_id']); target = int(vendor['profile_id'])
    sql = """begin;
create temporary table final03_audit_before as select count(*) as n from public.security_audit_log where actor_id=ACTOR and target_type='users' and target_id=TARGET and action like 'vendor_%';
set local role authenticated;
do $claims$ begin perform set_config('request.jwt.claims', CLAIMS, true);end $claims$;
do $tests$ declare previous text;desired text;begin
 select verification_status into previous from public.users where id=TARGET;
 desired:=case when previous='approved' then 'rejected' else 'approved' end;
 perform public.final1_review_vendor(TARGET,desired);
 begin perform public.final1_review_vendor(TARGET,'invented-status');raise exception 'Invalid review accepted';exception when sqlstate '22023' then null;end;
 begin insert into public.security_audit_log(action,target_type,target_id)values('forged','users',TARGET);raise exception 'Client audit forgery accepted';exception when insufficient_privilege then null;end;
 begin update public.security_audit_log set action='forged' where false;raise exception 'Client audit UPDATE privilege exists';exception when insufficient_privilege then null;end;
 begin delete from public.security_audit_log where false;raise exception 'Client audit DELETE privilege exists';exception when insufficient_privilege then null;end;
end $tests$;
reset role;
select jsonb_build_object('exactly_one', (select count(*) from public.security_audit_log where actor_id=ACTOR and target_type='users' and target_id=TARGET and action like 'vendor_%')=(select n+1 from final03_audit_before),
 'correct_action',exists(select 1 from public.security_audit_log a join public.users u on u.id=a.target_id where a.actor_id=ACTOR and a.target_id=TARGET and a.target_type='users' and a.action='vendor_'||u.verification_status)) as result;
rollback;""".replace('ACTOR', str(actor)).replace('TARGET', str(target)).replace('CLAIMS', "'" + json.dumps(claims).replace("'", "''") + "'")
    path = out / 'audit-operation.private.sql'; path.write_text(sql)
    row = d.query(path)[0]['result']
    check(row['exactly_one'] and row['correct_action'], 'Admin review records exactly one correct actor/target/result event; invalid review adds none', 'real live user claims in authenticated SQL; rollback')
    check(True, 'even approved Admin cannot INSERT/UPDATE/DELETE immutable audit history', 'three authenticated SQL permission assertions; rollback')
    code, value = gateway('rpc/final1_review_vendor', token, '', 'POST', {'p_user_id': target, 'p_status': 'invented-status'})
    check(code == 400 and value.get('code') == '22023', 'real Admin gateway rejects invalid moderation state')
    customer = b.login(accounts['customer'])
    code, value = gateway('rpc/final1_review_vendor', customer, '', 'POST', {'p_user_id': target, 'p_status': 'approved'})
    check(code == 403, 'real customer cannot use legacy Admin moderation RPC')


def chat():
    sys.path.insert(0, str(b.ROOT / 'build/fr21-python'))
    from websockets.sync.client import connect
    fixture = state('fr25-accounts.bin')['accounts']
    owner = b.login(fixture['customer-a']); other = b.login(fixture['customer-b'])
    # Retained idempotent support workflow reuses its existing room.
    code, room = gateway('rpc/fr25_support_chat', owner, '', 'POST', {})
    assert code == 200 and isinstance(room, int)
    sockets = []; inserted = None
    try:
        url = 'wss://' + b.REF + '.supabase.co/realtime/v1/websocket?' + urllib.parse.urlencode({'apikey': b.ANON, 'vsn': '1.0.0'})
        for who, token in [('participant', owner), ('unrelated customer', other)]:
            ws = connect(url, open_timeout=20, close_timeout=3); sockets.append(ws)
            ws.send(json.dumps({'topic': 'realtime:final03-chat-' + who, 'event': 'phx_join', 'ref': '1', 'payload': {
                'config': {'private': False, 'broadcast': {'ack': False, 'self': False}, 'presence': {'key': ''},
                    'postgres_changes': [{'event': 'INSERT', 'schema': 'public', 'table': 'chat_messages', 'filter': 'room_id=eq.' + str(room)}]}, 'access_token': token}}))
            while True:
                msg = json.loads(ws.recv(timeout=20))
                if msg.get('event') == 'phx_reply' and msg.get('ref') == '1':
                    assert msg['payload']['status'] == 'ok'; break
        body = {'room_id': room, 'sender_id': fixture['customer-a']['profile_id'], 'message': 'FINAL03 SYNTHETIC AUTHORIZATION CHECK'}
        code, value = gateway('chat_messages', owner, 'select=id', 'POST', body)
        assert code == 201 and len(value) == 1; inserted = value[0]['id']
        check(True, 'participant real gateway message INSERT confirms a row; temporary synthetic message removed in finally')
        for who, ws in zip(('participant', 'unrelated customer'), sockets):
            found = False; until = time.monotonic() + (12 if who == 'participant' else 3)
            while time.monotonic() < until:
                try: msg = json.loads(ws.recv(timeout=max(.01, until-time.monotonic())))
                except TimeoutError: break
                if msg.get('event') == 'postgres_changes': found = True; break
            check(found == (who == 'participant'), who + ': actual chat INSERT delivery respects room ownership', 'actual user websocket; bounded denial observation')
        for label, bad in [('unrelated sender', body), ('forged identity', {**body, 'sender_id': fixture['customer-b']['profile_id']}), ('private media bypass', {**body, 'image_url': 'https://example.invalid/private.png'})]:
            code, _ = gateway('chat_messages', other if label == 'unrelated sender' else owner, '', 'POST', bad)
            check(code in (400, 403), 'trusted chat validation denies ' + label)
    finally:
        if inserted is not None:
            code, values = b.api('/rest/v1/chat_messages?id=eq.' + str(inserted) + '&message=eq.FINAL03%20SYNTHETIC%20AUTHORIZATION%20CHECK', 'DELETE', admin=True)
            assert code == 200 and len(values) == 1
        for ws in sockets: ws.close()


if mode == 'inspect':
    inspect()
elif mode == 'media':
    media()
elif mode == 'realtime':
    realtime()
elif mode == 'legacy':
    legacy()
elif mode == 'audit':
    audit()
elif mode == 'chat':
    chat()
else:
    raise SystemExit('Unsupported check; no implicit mutating action')
print(json.dumps({'project': b.REF, 'mode': mode, 'passed': len(checks), 'provider_calls': 0}))
