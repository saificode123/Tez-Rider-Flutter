"""Guarded TEST-only rating-policy review/deployment; never emit secrets."""
import hashlib, importlib.util, json, re, subprocess, sys, uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.fr21-local/final-delivery/rating'
OUT.mkdir(parents=True, exist_ok=True)
REF = 'igeisilhtmglgnqvllrx'
VERSION = '202610250007'
MIGRATION = ROOT / 'supabase/migrations/202610250007_final_delivery_rating_policy.sql'
spec = importlib.util.spec_from_file_location('guarded_rating_db', Path(__file__).with_name('FINAL-security.py'))
db = importlib.util.module_from_spec(spec)
spec.loader.exec_module(db)
db.OUT = OUT
assert (ROOT / 'supabase/.temp/project-ref').read_text().strip() == REF
action = sys.argv[1]
assert action in ('review', 'deploy', 'post', 'worker-deploy', 'status', 'hosted', 'reconcile')

def query(name, source):
    path = OUT / (name + '.sql')
    path.write_text(source, encoding='utf-8')
    try:
        return db.query(path)
    except subprocess.TimeoutExpired:
        # Retry only read-only operations. Never replay an uncertain mutation.
        if source.lstrip().lower().startswith('begin read only;'):
            return db.query(path)
        raise

history = [r['version'] for r in query('history', 'begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')]
known = sorted(p.name.split('_')[0] for p in (ROOT / 'supabase/migrations').glob('*.sql'))
assert history == [v for v in known if v <= history[-1]], 'Unexpected migration prefix; no replay'
digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
if action in ('review', 'post'):
    assert (VERSION in history) == (action == 'post'), 'Wrong target migration state'
    sql = (ROOT / 'supabase/tests/FINAL-delivery-rating-policy.sql').read_text(encoding='utf-8')
    if action == 'review':
        candidate = re.sub(r'(?m)^(begin|commit);\s*$', '', MIGRATION.read_text(encoding='utf-8'))
        sql = sql.replace('-- FINAL_RATING_CANDIDATE', candidate)
    results = query('review-operation', sql)[0]['results']
    assert results and all(r['result'] == 'PASS' for r in results)
    evidence = {'project': REF, 'action': action, 'migration_sha256': digest, 'rolled_back': True, 'passed': len(results), 'checks': results, 'actual_auth_admin_ban': False}
    (OUT / (action + '-proof.json')).write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    (ROOT / ('docs/evidence/FINAL-delivery-rating-' + action + '.json')).write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'project': REF, 'mode': action, 'passed': len(results), 'rolled_back': True}))
elif action == 'deploy':
    assert VERSION not in history and history == [v for v in known if v < VERSION], 'Apply reviewed predecessors first; no gaps/replay'
    review = json.loads((OUT / 'review-proof.json').read_text())
    assert review['rolled_back'] and review['migration_sha256'] == digest and review['passed'] >= 20
    source = MIGRATION.read_text(encoding='utf-8')
    assert source.count('\ncommit;') == 1
    source = source.replace('\ncommit;', "\ninsert into supabase_migrations.schema_migrations(version,name)values('202610250007','final_delivery_rating_policy');\ncommit;")
    query('deploy-operation', source)
    versions = [r['version'] for r in query('history-post', 'begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')]
    assert versions == history + [VERSION]
    evidence = {'project': REF, 'version': VERSION, 'migration_sha256': digest, 'versions': len(versions), 'replayed': False, 'production_modified': False}
    (ROOT / 'docs/evidence/FINAL-delivery-rating-deployment.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence))
elif action == 'worker-deploy':
    assert VERSION in history
    # Secret remains in a temporary ignored file, never arguments or stdout.
    secret = query('worker-secret-private', "begin read only;select decrypted_secret as value from vault.decrypted_secrets where name='final_rating_worker';rollback;")[0]['value']
    assert len(secret) >= 32
    path = OUT / 'worker-secret.env'
    try:
        path.write_text('FINAL_RATING_WORKER_KEY=' + secret + '\n', encoding='utf-8')
        for command in [
            [db.CLI, 'secrets', 'set', '--project-ref', REF, '--env-file', str(path)],
            [db.CLI, 'functions', 'deploy', 'final-rating-worker', '--project-ref', REF, '--no-verify-jwt', '--use-api'],
        ]:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding='utf-8', timeout=120)
            (OUT / 'worker-deploy.private.log').write_text(result.stdout + result.stderr, encoding='utf-8')
            assert result.returncode == 0, 'TEST worker provisioning failed; private log retained'
    finally:
        path.unlink(missing_ok=True)
        (OUT / 'worker-secret-private.sql').unlink(missing_ok=True)
    print(json.dumps({'project': REF, 'worker': 'final-rating-worker', 'deployed': True, 'secret_printed': False}))
elif action == 'status':
    rows = query('status-read', """begin read only;select jsonb_build_object(
      'policy_present',to_regclass('final_delivery_private.rating_settings')is not null,
      'schedules',(select jsonb_agg(jsonb_build_object('name',jobname,'schedule',schedule,'active',active))from cron.job where jobname like'final-rating-%'))as status;rollback;""")
    print(json.dumps({'project': REF, 'versions': len(history), 'status': rows[0]['status']}))
elif action == 'reconcile':
    assert VERSION in history
    backend_spec = importlib.util.spec_from_file_location('rating_reconcile_backend', Path(__file__).with_name('FR-04-hosted.py'))
    b = importlib.util.module_from_spec(backend_spec); backend_spec.loader.exec_module(b)
    state = json.loads(b.crypt((OUT / 'accounts.dpapi').read_bytes(), True))
    rider = state['rider']; customer = state['customer']
    rows = query('final-reconcile', """begin read only;select jsonb_build_object(
      'unblocked',not u.is_blocked,'auth_unbanned',not coalesce(a.banned_until>clock_timestamp(),false),
      'cutoff',exists(select 1 from final_delivery_private.rating_cutoffs c where c.user_id=u.id and c.ignore_before is not null),
      'queue_cleared',exists(select 1 from final_delivery_private.rating_queue q where q.user_id=u.id and q.state='CLEARED'),
      'owned_pending_fixtures',(select count(*)from public.orders o where o.user_id=""" + str(customer['profile_id']) + """ and o.delivery_address='Rating hosted SQL synthetic fixture'and o.order_status not in('cancelled','delivered'))
      )as state from public.users u join auth.users a on a.id=u.auth_user_id where u.id=""" + str(rider['profile_id']) + ';rollback;')[0]['state']
    assert rows['unblocked'] and rows['auth_unbanned'] and rows['cutoff'] and rows['queue_cleared'] and rows['owned_pending_fixtures'] == 0
    b.login(rider)
    evidence = {'project': REF, 'state': rows, 'new_password_session': True,
        'cleanup_verified': True, 'production_modified': False,
        'scope': 'Final readback after interrupted overlapping hosted verification; no new review/order fixtures created'}
    (ROOT / 'docs/evidence/FINAL-delivery-rating-reconcile.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'project': REF, 'cleanup_verified': True, 'target_unblocked': True, 'new_password_session': True}))
elif action == 'hosted':
    assert VERSION in history
    import secrets, urllib.request
    backend_spec = importlib.util.spec_from_file_location('rating_hosted_backend', Path(__file__).with_name('FR-04-hosted.py'))
    b = importlib.util.module_from_spec(backend_spec); backend_spec.loader.exec_module(b)
    account_path = OUT / 'accounts.dpapi'
    state = json.loads(b.crypt(account_path.read_bytes(), True)) if account_path.exists() else {}
    def save(): account_path.write_bytes(b.crypt(json.dumps(state).encode()))
    def sql_string(value): return "'" + str(value).replace("'", "''") + "'"
    checks = []
    def check(value, label):
        assert value, label
        checks.append({'check': label, 'result': 'PASS', 'surface': 'actual TEST HTTP and persisted readback'})
        (OUT / 'hosted-attempt-checks.json').write_text(json.dumps(checks, indent=2) + '\n')
        print(json.dumps(checks[-1]), flush=True)
    for label in ('rider', 'customer'):
        a = state.setdefault(label, {'email': 'final-rating-' + label + '-' + uuid.uuid4().hex + '@example.test', 'password': secrets.token_urlsafe(28) + 'aA7!'})
        save()
        if 'auth_id' not in a:
            code, result = b.api('/auth/v1/admin/users', 'POST', {'email': a['email'], 'password': a['password'], 'email_confirm': True, 'user_metadata': {'rating_fixture': True}}, admin=True)
            assert code in (200, 201), 'Synthetic TEST Auth fixture creation'
            a['auth_id'] = result['id']; save()
        query('fixture-profile-' + label, """do $$declare uid bigint;begin
          select id into uid from public.users where auth_user_id=""" + sql_string(a['auth_id']) + """::uuid;
          if uid is null then insert into public.users(email,name,role,verification_status,auth_user_id)values(""" + sql_string(a['email']) + ", 'Rating hosted synthetic', " + sql_string(label) + ",'approved'," + sql_string(a['auth_id']) + """::uuid)returning id into uid;end if;
          """ + ("insert into public.riders(userid)values(uid)on conflict(userid)do nothing;" if label == 'rider' else '') + "end$$;")
        a['profile_id'] = query('fixture-id-' + label, 'begin read only;select id from public.users where auth_user_id=' + sql_string(a['auth_id']) + '::uuid;rollback;')[0]['id']; save()
    rider = state['rider']; customer = state['customer']
    token = b.login(rider)
    # New synthetic review/order fixtures exercise policy and real Auth sync.
    # They deliberately do not claim ten physical deliveries or feedback-UI runs.
    fixture_orders = query('fixture-policy-input', """begin;
      do $$declare oid bigint;begin
       for i in 1..10 loop
        insert into public.orders(user_id,amount,order_status,payment_method,delivery_address)
         values(""" + str(customer['profile_id']) + """,1,'pending','COD','Rating hosted SQL synthetic fixture')returning id into oid;
        insert into public.reviews(id,reviewer_id,reviewee_id,order_id,rating,comment,target_user_id,target_role,verified_at,request_payload)
         values(gen_random_uuid(),""" + sql_string(customer['auth_id']) + '::uuid,' + sql_string(rider['auth_id']) + '::uuid,oid,1,' + sql_string('FINAL RATING synthetic policy fixture') + ',' + str(rider['profile_id']) + """,'rider',clock_timestamp(),'{}');
       end loop;
       insert into final_delivery_private.rating_queue(user_id,state,rating_count,average_rating)values(""" + str(rider['profile_id']) + """,'DEFERRED',10,1)
        on conflict(user_id)do update set state='DEFERRED',operation_id=gen_random_uuid(),rating_count=10,average_rating=1,evaluated_at=clock_timestamp(),updated_at=clock_timestamp();
      end$$;
      select id from public.orders where user_id=""" + str(customer['profile_id']) + " and order_status='pending';commit;")
    order_ids = [row['id'] for row in fixture_orders]
    secret = query('worker-secret-private', "begin read only;select decrypted_secret as value from vault.decrypted_secrets where name='final_rating_worker';rollback;")[0]['value']
    try:
        def invoke(secret_header=None):
            request = urllib.request.Request(b.BASE + '/functions/v1/final-rating-worker', method='POST', headers={'Content-Type': 'application/json', **({'x-final-rating-worker-key': secret_header} if secret_header else {})}, data=b'{"source":"retry"}')
            try:
                with urllib.request.urlopen(request, timeout=60) as response: return response.status, json.load(response)
            except __import__('urllib.error').error.HTTPError as error: return error.code, json.load(error)
        code, _ = invoke(); check(code == 403, 'deployed rating worker rejects unauthenticated invocation')
        code, outcome = invoke(secret); check(code == 200 and outcome['synced'] >= 1 and outcome['pending'] == 0, 'private worker confirms real Auth ban and FR28 synchronization')
        rows = query('block-readback', """begin read only;select jsonb_build_object(
         'blocked',u.is_blocked,'banned',coalesce(a.banned_until>clock_timestamp(),false),
         'sessions',(select count(*)from auth.sessions where user_id=u.auth_user_id),
         'audit',(select count(*)from public.security_audit_log where action='auto_low_rating'and target_id=u.id),
         'operation_synced',(select o.state='SYNCED'from final_delivery_private.rating_queue q join public.fr28_operations o on o.id=q.operation_id where q.user_id=u.id),
         'admin_notified',not exists(select 1 from public.users adm where adm.role='admin'and not exists(select 1 from public.notifications n where n.user_id=adm.id and n.type='auto_low_rating'and n.message like'Account #'||u.id||' %'))
         )as state from public.users u join auth.users a on a.id=u.auth_user_id where u.id=""" + str(rider['profile_id']) + ';rollback;')[0]['state']
        check(rows['blocked'] and rows['banned'] and rows['sessions'] == 0 and rows['operation_synced'], 'actual Auth ban, zero target sessions and SYNCED operation agree with persisted account block')
        check(rows['audit'] >= 1 and rows['admin_notified'], 'automatic reason audit and every-Admin notification persisted')
        code, _ = b.api('/functions/v1/security-gateway', 'POST', {'method': 'POST', 'path': '/rpc/final2_rider_performance', 'query': '', 'headers': {'content-type': 'application/json'}, 'body': '{}'}, token)
        check(code in (401, 403), 'real pre-block Rider access token cannot access a protected operation')
        admin_accounts = json.loads(b.crypt((b.PRIVATE / 'fr28-accounts.bin').read_bytes(), True))['accounts']
        admin_token = b.login(admin_accounts['admin'])
        code, result = b.api('/functions/v1/admin-user-status', 'POST', {'target_id': rider['profile_id'], 'blocked': False, 'request_id': str(uuid.uuid4())}, admin_token)
        check(code == 200 and result['code'] == 'OK', 'existing actual authenticated Admin unblocks the synthetic account through FR28')
        rows = query('unblock-readback', """begin read only;select jsonb_build_object('blocked',u.is_blocked,
         'banned',coalesce(a.banned_until>clock_timestamp(),false),'cutoff',(select ignore_before is not null from final_delivery_private.rating_cutoffs where user_id=u.id))as state
         from public.users u join auth.users a on a.id=u.auth_user_id where u.id=""" + str(rider['profile_id']) + ';rollback;')[0]['state']
        check(not rows['blocked'] and not rows['banned'] and rows['cutoff'], 'confirmed real Admin unblock stores the rating cutoff and removes the Auth ban')
        query('stale-queue-fixture', "update final_delivery_private.rating_queue set state='DEFERRED',operation_id=gen_random_uuid(),updated_at=clock_timestamp()where user_id=" + str(rider['profile_id']) + ';')
        code, outcome = invoke(secret)
        rows = query('cutoff-readback', 'begin read only;select u.is_blocked,q.state from public.users u join final_delivery_private.rating_queue q on q.user_id=u.id where u.id=' + str(rider['profile_id']) + ';rollback;')[0]
        check(code == 200 and not rows['is_blocked'] and rows['state'] == 'CLEARED', 'actual retry clears a staged stale queue; old reviews cannot reblock an Admin-unblocked account')
        b.login(rider); check(True, 'new Rider password session succeeds after actual Admin unblock')
    finally:
        query('retire-owned-orders', 'update public.orders set order_status=\'cancelled\'where user_id=' + str(customer['profile_id']) + ' and id in(' + ','.join(str(i) for i in order_ids) + ") and order_status='pending';")
        (OUT / 'worker-secret-private.sql').unlink(missing_ok=True)
    evidence = {'project': REF, 'passed': len(checks), 'checks': checks, 'actual_auth_admin_ban': True, 'actual_admin_unblock': True, 'input_data': 'new marked synthetic SQL reviews/orders and staged target queue; not physical delivery or feedback-UI proof', 'cleanup': 'only new owned pending orders cancelled; synthetic profiles/reviews/audits retained; target unblocked; no production'}
    (ROOT / 'docs/evidence/FINAL-delivery-rating-hosted.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
