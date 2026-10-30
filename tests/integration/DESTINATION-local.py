"""Execute the real destination migration in a new rollback-only local database."""
import importlib.util
import json
from pathlib import Path
import re
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('local_map_runner', Path(__file__).with_name('MAP-pickup-local.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
assert runner.run(['docker','context','inspect','--format','{{.Endpoints.docker.Host}}']).stdout.strip().startswith('npipe://')
database = 'tezrider_destination_validation_' + uuid.uuid4().hex[:12]
assert runner.run(['docker','exec',runner.CONTAINER,'createdb','-U','postgres',database]).returncode == 0
original = (ROOT/'supabase/migrations/202610190001_fr14_route_eta.sql').read_text()
guard = 'create function fr14_private.guard_destination()' + original.split('create function fr14_private.guard_destination()',1)[1].split('create table fr14_private.configuration',1)[0]
migration = (ROOT/'supabase/migrations/202610300002_delivery_destination_amendment.sql').read_text()
assert migration.count('\nbegin;') == 1 and migration.rstrip().endswith('commit;')
body = migration.replace('\nbegin;','',1).rsplit('commit;',1)[0]
route_migration = (ROOT/'supabase/migrations/202610300003_destination_route_revalidation.sql').read_text()
route_body = route_migration.replace('\nbegin;','',1).rsplit('commit;',1)[0]
route_rollback = (ROOT/'supabase/rollback/202610300003_destination_route_revalidation.sql').read_text()
route_rollback_body = route_rollback.replace('\nbegin;','',1).rsplit('commit;',1)[0]
rollback = (ROOT/'supabase/rollback/202610300002_delivery_destination_amendment.sql').read_text()
rollback_body = rollback.replace('\nbegin;','',1).rsplit('commit;',1)[0]
rollback_checks = """
do $$begin update public.orders set delivery_lat=34 where id=3180;raise exception 'Rollback left destination unlocked';
 exception when insufficient_privilege then raise notice 'PASS: rollback restores the original destination lock';end$$;
select pg_temp.check_it(to_regprocedure('public.final_delivery_destination_context(bigint)')is null,'rollback removes new public entry points');
select pg_temp.check_it((select count(*)=1 from final_delivery_private.destination_amendments),'rollback retains private amendment history');
select pg_temp.check_it((select delivery_lat=33.71 and amount=470 and fare=120 and order_status='on_the_way'from public.orders where id=3180),'rollback never resets selected destination charges or lifecycle');
"""
route_checks = """
select pg_temp.check_it(public.fr14_route_context(3180)->'destination'='[73.11,33.71]'::jsonb,'final route authorization returns current destination tuple');
select pg_temp.check_it(public.fr14_route_context(3180)->>'destination_revision'=(select to_jsonb(destination_confirmed_at)#>>'{}'from public.orders where id=3180),'route context revision matches confirmed order');
select set_config('test.actor','160',true);
select pg_temp.check_it(public.fr14_route_context(3180)='{"code":"FORBIDDEN"}'::jsonb,'unauthorized final context never exposes destination');
select set_config('test.actor','159',true);
select pg_temp.check_it(not has_function_privilege('anon','public.fr14_route_context(bigint)','execute'),'anonymous route context remains denied');
"""
route_rollback_check = "select pg_temp.check_it(not(public.fr14_route_context(3180)?'destination'),'rollback restores previous route metadata contract');"
sql = 'begin;\n' + (ROOT/'tests/integration/DESTINATION-bootstrap.sql').read_text() + '\n' + guard + '\n' + body + '\n' + route_body + '\n' + (ROOT/'tests/integration/DESTINATION-assertions.sql').read_text() + '\n' + route_checks + '\n' + route_rollback_body + '\n' + route_rollback_check + '\n' + rollback_body + '\n' + rollback_checks + '\nrollback;'
result = runner.run(['docker','exec','-i',runner.CONTAINER,'psql','-X','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'],input=sql)
(ROOT/'.fr21-local/destination-sql.log').write_text(result.stdout+result.stderr)
empty = runner.run(['docker','exec',runner.CONTAINER,'psql','-X','-U','postgres','-d',database,'-Atc',"select count(*)from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','fr14_private','final_delivery_private')and c.relkind in('r','v','m','S');"])
removed = empty.returncode == 0 and empty.stdout.strip() == '0' and runner.run(['docker','exec',runner.CONTAINER,'dropdb','-U','postgres',database]).returncode == 0
checks = re.findall(r'NOTICE:\s+PASS: (.+)',result.stderr)
proof = {'passed':len(checks),'assertions':checks,'local_sql_passed':result.returncode==0,
 'new_empty_scratch_database_removed':removed,'hosted_orders_created':0,'production_modified':False,
 'scope':'Real PostgreSQL execution of original guard and new migration with synthetic local Auth stand-ins; all writes rolled back. No hosted order or destination changed.'}
(ROOT/'docs/evidence/COMPLETE-destination-local.json').write_text(json.dumps(proof,indent=2)+'\n')
print(json.dumps(proof))
assert result.returncode == 0 and len(checks)>=25 and removed,'Local destination verification failed; inspect ignored log.'
