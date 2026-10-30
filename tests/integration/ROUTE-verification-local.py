"""Rollback-only local verification of the bounded physical routing cap."""
import importlib.util
import json
from pathlib import Path
import re
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('runner', Path(__file__).with_name('MAP-pickup-local.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
assert runner.run(['docker','context','inspect','--format','{{.Endpoints.docker.Host}}']).stdout.strip().startswith('npipe://')
database = 'tezrider_destination_validation_' + uuid.uuid4().hex[:12]
assert runner.run(['docker','exec',runner.CONTAINER,'createdb','-U','postgres',database]).returncode == 0
migration = (ROOT/'supabase/migrations/202610300004_bounded_route_verification.sql').read_text()
body = migration.replace('\nbegin;','',1).rsplit('commit;',1)[0]
checks = """
create function pg_temp.check_it(ok boolean,label text)returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'FAIL: %',label;end if;raise notice 'PASS: %',label;end$$;
select pg_temp.check_it(not has_function_privilege('anon','public.fr14_verification_claim(bigint,bigint,boolean)','execute'),'anonymous cannot claim');
select pg_temp.check_it(not has_function_privilege('authenticated','public.fr14_verification_claim(bigint,bigint,boolean)','execute'),'client cannot forge actor claims');
select pg_temp.check_it(not has_table_privilege('service_role','fr14_private.verification_requests','delete'),'service role cannot reset audit directly');
select pg_temp.check_it(public.fr14_verification_claim(3181,159,false)=0,'other order blocked');
select pg_temp.check_it(public.fr14_verification_claim(3180,160,false)=0,'other actor blocked');
select pg_temp.check_it(public.fr14_verification_claim(3180,159,true)=0,'vendor pickup coordinates excluded');
select pg_temp.check_it(public.fr14_verification_claim(3180,159,null)=0,'missing scope denied');
select pg_temp.check_it(public.fr14_verification_claim(3180,159,false)=1,'first scoped request claimed');
select public.fr14_verification_record(1,'FAILED',null,null);
select pg_temp.check_it(public.fr14_verification_claim(3180,999,false)=2,'failure remains consumed');
select public.fr14_verification_record(2,'HTTP_200',250,80);
select public.fr14_verification_record(2,'FAILED',null,null);
select pg_temp.check_it((select status='HTTP_200'and distance_meters=250 from fr14_private.verification_requests where request_count=2),'terminal record cannot be overwritten');
select pg_temp.check_it(public.fr14_verification_claim(3180,159,false)=3,'third and last claim');
select pg_temp.check_it(public.fr14_verification_claim(3180,999,false)=0,'fourth denied');
select pg_temp.check_it(public.fr14_verification_claim(3180,159,false)=0,'repeated denial never resets count');
select pg_temp.check_it((select count(*)=3 from fr14_private.verification_requests),'exactly three retained entries');
update public.orders set order_status='delivered'where id=3180;
select pg_temp.check_it(public.fr14_verification_claim(3180,159,false)=0,'completed delivery cannot consume provider');
"""
accounting = (ROOT/'supabase/migrations/202610300005_account_pre_cap_route_attempts.sql').read_text().replace('\nbegin;','',1).rsplit('commit;',1)[0]
accounting_checks = """
update public.orders set order_status='on_the_way'where id=3180;
truncate fr14_private.verification_requests;
""" + accounting + """
select pg_temp.check_it(public.fr14_verification_claim(3180,999,false)=3,'pre-cap reservations leave one slot only');
select pg_temp.check_it(public.fr14_verification_claim(3180,999,false)=0,'pre-cap accounting cannot grant extra calls');
"""
sql = 'begin;\n'+(ROOT/'tests/integration/DESTINATION-bootstrap.sql').read_text()+'\n'+body+'\n'+checks+'\n'+accounting_checks+'\nrollback;'
result = runner.run(['docker','exec','-i',runner.CONTAINER,'psql','-X','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'],input=sql)
(ROOT/'.fr21-local/route-verification-sql.log').write_text(result.stdout+result.stderr)
empty = runner.run(['docker','exec',runner.CONTAINER,'psql','-X','-U','postgres','-d',database,'-Atc',"select count(*)from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','fr14_private','fr13_private','final_delivery_private','final2_private')and c.relkind in('r','v','m','S');"])
removed = empty.returncode == 0 and empty.stdout.strip() == '0' and runner.run(['docker','exec',runner.CONTAINER,'dropdb','-U','postgres',database]).returncode == 0
passed = re.findall(r'NOTICE:\s+PASS: (.+)',result.stderr)
proof = {'passed':len(passed),'assertions':passed,'local_sql_passed':result.returncode==0,'fresh_empty_scratch_removed':removed,'external_provider_requests':0,'hosted_orders_created':0}
(ROOT/'docs/evidence/COMPLETE-route-cap-local.json').write_text(json.dumps(proof,indent=2)+'\n')
print(json.dumps(proof))
assert result.returncode == 0 and len(passed)==17 and removed,'Inspect ignored local SQL log'
