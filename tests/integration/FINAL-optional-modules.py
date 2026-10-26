"""Hash-reviewed isolated TEST optional-module checks; no secrets in output."""
import base64, hashlib, importlib.util, json, re, subprocess, sys, uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.fr21-local/final-delivery/optional'
OUT.mkdir(parents=True, exist_ok=True)
REF = 'igeisilhtmglgnqvllrx'
VERSION = '202610250008'
MIGRATION = ROOT / 'supabase/migrations/202610250008_final_optional_modules.sql'
def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value
db = module('optional_guarded_db', 'FINAL-security.py'); db.OUT = OUT
assert (ROOT / 'supabase/.temp/project-ref').read_text().strip() == REF
action = sys.argv[1]
assert action in ('review', 'deploy', 'post', 'edge-deploy', 'hosted', 'assistant')
def query(name, source):
    path = OUT / (name + '.sql'); path.write_text(source, encoding='utf-8'); return db.query(path)
known = sorted(p.name.split('_')[0] for p in (ROOT / 'supabase/migrations').glob('*.sql'))
if action in ('edge-deploy', 'assistant'):
    deployed = json.loads((ROOT / 'docs/evidence/FINAL-optional-deployment.json').read_text())
    assert deployed['project'] == REF and deployed['version'] == VERSION
    history = [v for v in known if v <= VERSION]
else:
    history = [r['version'] for r in query('history', 'begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')]
assert history == [v for v in known if v <= history[-1]], 'Unknown migration prefix; never replay'
digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
if action in ('review', 'post'):
    assert (VERSION in history) == (action == 'post')
    source = (ROOT / 'supabase/tests/FINAL-optional-modules.sql').read_text(encoding='utf-8')
    if action == 'review':
        source = source.replace('-- OPTIONAL_CANDIDATE', re.sub(r'(?m)^(begin|commit);\s*$', '', MIGRATION.read_text(encoding='utf-8')))
    results = query(action + '-operation', source)[0]['results']
    assert results and all(r['result'] == 'PASS' for r in results)
    proof = {'project': REF, 'action': action, 'migration_sha256': digest, 'passed': len(results), 'rolled_back': True, 'checks': results}
    (OUT / (action + '-proof.json')).write_text(json.dumps(proof, indent=2) + '\n')
    (ROOT / ('docs/evidence/FINAL-optional-' + action + '.json')).write_text(json.dumps(proof, indent=2) + '\n')
    print(json.dumps({k: v for k, v in proof.items() if k != 'checks'}))
elif action == 'deploy':
    assert VERSION not in history and history == [v for v in known if v < VERSION]
    proof = json.loads((OUT / 'review-proof.json').read_text())
    assert proof['rolled_back'] and proof['passed'] >= 25 and proof['migration_sha256'] == digest
    source = MIGRATION.read_text(encoding='utf-8')
    assert source.count('\ncommit;') == 1 and not re.search(r'\b(drop|truncate)\b', source, re.I)
    source = source.replace('\ncommit;', "\ninsert into supabase_migrations.schema_migrations(version,name)values('202610250008','final_optional_modules');\ncommit;")
    query('deploy-operation', source)
    after = [r['version'] for r in query('history-after', 'begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')]
    assert after == history + [VERSION]
    proof = {'project': REF, 'version': VERSION, 'migration_sha256': digest, 'versions': len(after), 'replayed': False, 'production_modified': False}
    (ROOT / 'docs/evidence/FINAL-optional-deployment.json').write_text(json.dumps(proof, indent=2) + '\n')
    print(json.dumps(proof))
elif action == 'edge-deploy':
    assert VERSION in history
    result = subprocess.run([db.CLI, 'functions', 'deploy', 'optional-private-media', '--project-ref', REF, '--no-verify-jwt', '--use-api'], cwd=ROOT, capture_output=True, text=True, timeout=120)
    (OUT / 'edge-deploy.private.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    assert result.returncode == 0, 'TEST Edge deployment failed; private log retained'
    print(json.dumps({'project': REF, 'function': 'optional-private-media', 'deployed': True, 'production_modified': False}))
elif action == 'assistant':
    b = module('optional_assistant_backend', 'FR-04-hosted.py'); b.target()
    original = json.loads(b.crypt((ROOT / '.fr21-local/final2/onboarding-accounts.dpapi').read_bytes(), True))
    token = b.login(original['accounts']['review-customer'])
    status, result = b.api('/functions/v1/shopping-assistant', 'POST', {'prompt':'Suggest one general grocery item without claiming catalogue availability or a price.'}, token)
    confirmed = status == 200 and isinstance(result, dict) and result.get('code') == 'OK' and isinstance(result.get('text'), str) and bool(result['text'].strip())
    proof = {'project':REF,'http_status':status,'confirmed_provider_response':confirmed,'result_code':result.get('code') if isinstance(result,dict) else 'INVALID_RESPONSE','secret_or_provider_text_printed':False,'production_modified':False}
    (ROOT/'docs/evidence/FINAL-optional-assistant.json').write_text(json.dumps(proof,indent=2)+'\n')
    print(json.dumps(proof))
elif action == 'hosted':
    assert VERSION in history
    b = module('optional_hosted_backend', 'FR-04-hosted.py'); b.target()
    original = json.loads(b.crypt((ROOT / '.fr21-local/final2/onboarding-accounts.dpapi').read_bytes(), True))
    legacy = json.loads(b.crypt((b.PRIVATE / 'fr28-accounts.bin').read_bytes(), True))['accounts']
    customer = b.login(original['accounts']['review-customer']); vendor = b.login(original['accounts']['live-vendor']); other = b.login(legacy['customer'])
    vendor_id = original['live_vendor_profile_id']
    checks = []
    def check(ok, label):
        assert ok, label
        row = {'check': label, 'result': 'PASS', 'surface': 'actual authenticated TEST HTTP and persisted readback'}
        checks.append(row); print(json.dumps(row), flush=True)
        (OUT / 'hosted-results.json').write_text(json.dumps(checks, indent=2) + '\n')
    def gateway(name, token, args):
        return b.api('/functions/v1/security-gateway', 'POST', {'method': 'POST', 'path': '/rpc/' + name, 'query': '', 'headers': {'content-type':'application/json'}, 'body': json.dumps(args)}, token)
    code, customer_id = gateway('fr21_actor', customer, {})
    assert code == 200 and isinstance(customer_id, int) and customer_id > 0
    fixture_path = OUT / 'fixture.dpapi'
    if fixture_path.exists():
        fixture = json.loads(b.crypt(fixture_path.read_bytes(), True))
    else:
        marker = 'FINAL OPTIONAL SYNTHETIC ' + uuid.uuid4().hex
        q = "'" + marker + "'"
        fixture = query('new-fixture', "begin;with o as(insert into public.orders(user_id,order_status,amount,payment_method,delivery_address,checkout_finalized_at)values(" + str(customer_id) + ",'pending',1,'COD'," + q + ",clock_timestamp())returning id),v as(insert into public.vendor_orders(order_id,vendor_id,sub_total,status,requires_prescription)select id," + str(vendor_id) + ",1,'pending_prescription',true from o returning id,order_id)select id as vendor_order_id,order_id from v;commit;")[0]
        fixture['marker'] = marker; fixture['request'] = str(uuid.uuid4()); fixture['save_request'] = str(uuid.uuid4()); fixture['tailor_request'] = str(uuid.uuid4())
        fixture_path.write_bytes(b.crypt(json.dumps(fixture).encode()))
    oid, vid = fixture['order_id'], fixture['vendor_order_id']
    png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
    payload = {'action':'upload','kind':'prescription','order_id':vid,'request_id':fixture['request'],'mime_type':'image/png','image_base64':base64.b64encode(png).decode()}
    status, result = b.api('/functions/v1/optional-private-media','POST',payload,customer)
    check(status == 200 and result.get('reference') == 'tezphoto:' + fixture['request'], 'Customer uploads server-decoded private prescription image')
    reference = result['reference']
    status, retry = b.api('/functions/v1/optional-private-media','POST',payload,customer)
    check(status == 200 and retry.get('reference') == reference, 'Identical image retry returns same private reference')
    status, _ = b.api('/functions/v1/optional-private-media','POST',{**payload,'request_id':str(uuid.uuid4())},other)
    check(status == 403, 'Foreign Customer cannot upload to another order')
    status, _ = b.api('/functions/v1/optional-private-media','POST',{**payload,'request_id':str(uuid.uuid4()),'image_base64':base64.b64encode(b'not an image').decode()},customer)
    check(status in (400,415,422), 'Server rejects fake image bytes without accepting metadata')
    save = {'p_vendor_order_id':vid,'p_reference':reference,'p_request_id':fixture['save_request']}
    status, saved = gateway('optional_save_prescription',customer,save)
    check(status == 200 and saved['vendor_order_id'] == vid and saved['prescription_image_url'] == reference, 'Owner links confirmed image to persisted prescription')
    status, again = gateway('optional_save_prescription',customer,save)
    check(status == 200 and again['id'] == saved['id'], 'Prescription retry persists exactly one record')
    for token, label, allowed in [(customer,'owner',True),(vendor,'assigned Vendor',True),(other,'foreign Customer',False)]:
        status, view = b.api('/functions/v1/optional-private-media','POST',{'action':'view','image_id':fixture['request']},token)
        check((status == 200 and base64.b64decode(view['image_base64']) == png and 0 < view['expires_in'] <= 900) if allowed else status == 403, label + ' private prescription byte authorization')
    status, rows = gateway('optional_list_prescriptions',vendor,{})
    check(status == 200 and any(r['id'] == saved['id'] for r in rows), 'Assigned Vendor receives real pending prescription')
    status, review = gateway('optional_review_prescription',vendor,{'p_id':saved['id'],'p_status':'approved','p_notes':None})
    check(status == 200 and review['status'] == 'approved' and review['reviewed_by'] == vendor_id, 'Vendor approval confirms returned persisted identity and status')
    data = query('read-persistence', 'begin read only;select status,prescription_id,acceptance_started_at is not null and acceptance_deadline_at>acceptance_started_at as timer from public.vendor_orders where id=' + str(vid) + ';rollback;')[0]
    check(data['status'] == 'pending' and data['prescription_id'] == saved['id'] and data['timer'], 'Approval unlocks actual vendor acceptance and starts canonical timeout')
    status, tailor = gateway('optional_submit_tailoring',customer,{'p_instructions':'FINAL OPTIONAL SYNTHETIC stitching','p_measurements':{'length':'40'},'p_reference':None,'p_request_id':fixture['tailor_request']})
    check(status == 200 and tailor['status'] == 'pickup_requested' and tailor['measurements']['length'] == '40' and tailor['vendor_id'] is None, 'Tailoring instructions and measurements persist without invented assignment')
    status, _ = b.api('/rest/v1/prescriptions','POST',{'vendor_order_id':vid},customer)
    check(status == 403, 'Direct prescription insert cannot bypass scoped trusted API')
    status, _ = b.api('/functions/v1/optional-private-media','POST',{'action':'view','image_id':fixture['request']})
    check(status in (401,403), 'Anonymous private image access denied')
    # Only this new unpaid synthetic fixture is retired; images/history/audits stay.
    query('retire-new-fixture', "begin;do $$begin if not exists(select 1 from public.orders where id=" + str(oid) + " and user_id=" + str(customer_id) + " and delivery_address='" + fixture['marker'] + "' and order_status='pending' and rider_id is null)then raise exception 'Exact unused fixture required';end if;perform fr10_private.cancel_locked(" + str(oid) + ",'customer_cancelled');end$$;commit;")
    check(query('retired-read','begin read only;select order_status from public.orders where id=' + str(oid) + ';rollback;')[0]['order_status'] == 'cancelled','Exact new unpaid synthetic order retired with history retained')
    proof = {'project':REF,'passed':len(checks),'checks':checks,'real_payment_or_delivery':False,'objects_and_audits_retained':True,'production_modified':False}
    (ROOT/'docs/evidence/FINAL-optional-hosted.json').write_text(json.dumps(proof,indent=2)+'\n')
