"""Review/deploy only the session-bound tracking fix, with exact TEST history."""
import base64
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

def module(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

d = module('db', 'FINAL-security.py')
h = module('tracking', 'FR-13-hosted.py')
b = h.b
b.target()
out = b.ROOT / '.fr21-local/final03'
h.OUT = out / 'tracking-db'; h.OUT.mkdir(exist_ok=True)
registry = sys.argv[2].startswith('registry-')
action = sys.argv[2].removeprefix('registry-')
assert action in ('review', 'deploy', 'edge', 'post')
version = '202610230003' if registry else '202610230002'
name = 'final03_active_tracking_readers' if registry else 'final03_tracking_session_topics'
prefix = 'tracking-registry' if registry else 'tracking'
migration = b.ROOT / ('supabase/migrations/' + version + '_' + name + '.sql')
history = out / 'tracking-history.sql'
history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')
versions = [r['version'] for r in d.query(history)]
expected = sorted(p.name.split('_')[0] for p in (b.ROOT / 'supabase/migrations').glob('*.sql'))
source = migration.read_text()
if action in ('deploy', 'edge'):
    if action == 'deploy':
        assert versions == [v for v in expected if v != version]
        rows = json.loads((out / (prefix + '-review-results.json')).read_text())
        assert len(rows) == 8 and all(r['result'] == 'PASS' for r in rows)
        assert source.count('commit;') == 1 and 'drop ' not in source.lower()
        path = out / (prefix + '-deploy.sql')
        path.write_text(source.replace('commit;', "insert into supabase_migrations.schema_migrations(version,name)values('" + version + "','" + name + "');commit;"))
        d.query(path)
        assert [r['version'] for r in d.query(history)] == expected
        (out / (prefix + '-deployment.json')).write_text(json.dumps({'project': b.REF, 'migration': migration.name, 'versions': len(expected), 'replayed': False, 'production_modified': False}, indent=2))
    else:
        assert versions == expected and (out / 'tracking-deployment.json').exists()
        result = subprocess.run([d.CLI, 'functions', 'deploy', 'fr13-location', '--project-ref', b.REF, '--use-api', '--no-verify-jwt'], cwd=b.ROOT, capture_output=True, text=True, timeout=180)
        (out / 'tracking-edge.private.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0, 'TEST tracking Edge deployment unconfirmed'
        (out / 'tracking-edge-deployment.json').write_text(json.dumps({'project': b.REF, 'function': 'fr13-location', 'deployment': 'PASS', 'docker': False}))
    print(json.dumps({'project': b.REF, 'action': action, 'confirmed': True, 'versions': len(expected)}))
    raise SystemExit(0)
assert versions == (expected if action == 'post' else [v for v in expected if v != version])
original = b.api
def api(path, method='GET', body=None, token=None, admin=False, mime='application/json'):
    if path.startswith('/rest/v1/') and token and not admin:
        route, _, query = path[len('/rest/v1'):].partition('?')
        return original('/functions/v1/security-gateway', 'POST', {'method': method, 'path': route, 'query': query,
            'headers': {'content-type': mime, 'prefer': 'return=representation'}, 'body': '' if body is None else json.dumps(body)}, token)
    return original(path, method, body, token, admin, mime)
b.api = api
def claims(token):
    part = token.split('.')[1]; return json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
def quote(value): return "'" + value.replace("'", "''") + "'"
row, rider = h.new_order()
try:
    context = h.start(row, rider)
    reader = b.login(h.state['accounts']['customer'])
    rc = claims(reader); wc = claims(rider)
    base = context['topic']
    if base.endswith(':' + wc['session_id']): base = base.rsplit(':', 1)[0]
    sender = base + ':' + wc['session_id']; own = base + ':' + rc['session_id']
    tests = """
create temporary table final03_result(label text);
do $test$ declare topics text[];ctx jsonb;begin
 perform set_config('request.jwt.claims',CLAIMS,true);
 ctx:=public.fr13_tracking_context(ORDERID);
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 topics:=public.fr13_live_topics(SENDER);
 if not OWN=any(topics) then raise exception 'Live recipient missing';end if;
 insert into final03_result values('live permitted customer session is an explicit publication destination');
 perform set_config('request.jwt.claims',CLAIMS,true);
 if not public.fr13_can_receive(OWN) or public.fr13_can_receive(SENDER) then raise exception 'Session binding failed';end if;
 insert into final03_result values('customer can join its own session topic but cannot join assigned rider session topic');
 ctx:=public.fr13_tracking_context(ORDERID);
 if ctx->>'topic' is distinct from OWN then raise exception 'Client context mismatch';end if;
 insert into final03_result values('existing context API returns the caller session topic without a Flutter protocol change');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 update auth.sessions set created_at=clock_timestamp()-interval '169 hours' where id=SID::uuid;
 if OWN=any(public.fr13_live_topics(SENDER)) then raise exception 'Expired recipient retained';end if;
 insert into final03_result values('expired reader is omitted from the next publication, independently of cached channel policy');
 delete from auth.sessions where id=SID::uuid;
 if OWN=any(public.fr13_live_topics(SENDER)) then raise exception 'Revoked recipient retained';end if;
 insert into final03_result values('revoked reader is omitted from the next publication');
 perform set_config('request.jwt.claims',CLAIMS,true);
 if public.fr13_can_receive(OWN) then raise exception 'Revoked topic join accepted';end if;
 insert into final03_result values('revoked live claims cannot regain a private topic');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 if cardinality(public.fr13_live_topics('fr13:forged'))<>0 then raise exception 'Forged sender accepted';end if;
 insert into final03_result values('invented sender topic cannot enumerate or publish destinations');
 if has_function_privilege('authenticated','public.fr13_live_topics(text)','EXECUTE') or has_function_privilege('anon','public.fr13_live_topics(text)','EXECUTE') then raise exception 'Recipient enumeration exposed';end if;
 insert into final03_result values('recipient enumeration RPC is service-only, not callable by application or anonymous roles');
end $test$;
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','live-claim SQL and session fault injection; full rollback')) as results from final03_result;
rollback;
"""
    if registry:
        probe = """
 begin
  update public.users set role='vendor' where auth_user_id=SUBJECT::uuid;
  if OWN=any(public.fr13_live_topics(SENDER)) then raise exception 'Changed role retained tracking access';end if;
  raise no_data_found;
 exception when no_data_found then insert into final03_result values('canonical role change removes the former customer from subsequent publication; probe rolled back');end;
 begin
  update public.users set is_blocked=true where auth_user_id=SUBJECT::uuid;
  if cardinality(public.fr13_live_topics(SENDER))<>0 then raise exception 'Blocked delivery recipient retained tracking access';end if;
  raise no_data_found;
 exception when no_data_found then insert into final03_result values('blocked account closes the private delivery publication path; probe rolled back');end;
"""
        tests = tests.replace(' update auth.sessions set created_at=', probe + ' update auth.sessions set created_at=')
    for key, value in [('SENDER', quote(sender)), ('OWN', quote(own)), ('CLAIMS', quote(json.dumps(rc))), ('ORDERID', str(row['oid'])), ('SID', quote(rc['session_id'])), ('SUBJECT', quote(rc['sub']))]: tests = tests.replace(key, value)
    path = out / 'tracking-review.private.sql'
    path.write_text('begin;\n' + (source.replace('begin;', '').replace('commit;', '') if action == 'review' else '') + '\n' + tests)
    rows = d.query(path)[0]['results']
    assert len(rows) == (10 if registry else 8)
    (out / (prefix + '-' + action + '-results.json')).write_text(json.dumps(rows, indent=2))
    print(json.dumps({'project': b.REF, 'action': action, 'passed': len(rows), 'rolled_back': True}))
finally:
    h.close(row)
