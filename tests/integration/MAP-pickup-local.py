"""Real PostgreSQL tests in a newly created LOCAL empty scratch database only."""
import json
from pathlib import Path
import re
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
CONTAINER = 'supabase_db_tezrider-fr30-local'

def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, encoding='utf-8', timeout=180, **kwargs)

def main():
    endpoint = run(['docker', 'context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'])
    assert endpoint.returncode == 0 and endpoint.stdout.strip().startswith('npipe://'), 'Local Windows Docker required'
    database = 'tezrider_map_ui_validation_' + uuid.uuid4().hex[:12]
    created = run(['docker', 'exec', CONTAINER, 'createdb', '-U', 'postgres', database])
    assert created.returncode == 0, 'New isolated local database creation unconfirmed; no existing database reused'
    migration = (ROOT / 'supabase/migrations/202610300001_fr14_pickup_navigation.sql').read_text(encoding='utf-8')
    assert migration.count('\nbegin;') == 1 and migration.rstrip().endswith('commit;')
    body = migration.replace('\nbegin;', '', 1).rsplit('commit;', 1)[0]
    sql = ('begin;\n' + (ROOT / 'tests/integration/MAP-pickup-bootstrap.sql').read_text(encoding='utf-8') +
        '\n' + body + '\n' + (ROOT / 'tests/integration/MAP-pickup-assertions.sql').read_text(encoding='utf-8') + '\nrollback;\n')
    result = run(['docker', 'exec', '-i', CONTAINER, 'psql', '-X', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1'], input=sql)
    out = ROOT / '.fr21-local/map-pickup-sql.log'
    out.write_text(result.stdout + result.stderr, encoding='utf-8')
    # The transaction is rolled back even on psql failure/disconnect. Verify no
    # application relations exist before dropping ONLY the just-created DB.
    empty = run(['docker', 'exec', CONTAINER, 'psql', '-X', '-U', 'postgres', '-d', database, '-Atc',
        "select count(*)from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','fr14_private')and c.relkind in('r','v','m','S');"])
    removed = False
    if empty.returncode == 0 and empty.stdout.strip() == '0':
        removed = run(['docker', 'exec', CONTAINER, 'dropdb', '-U', 'postgres', database]).returncode == 0
    checks = re.findall(r'NOTICE:\s+PASS: (.+)', result.stderr)
    evidence = {'local_sql_passed': result.returncode == 0, 'assertions': checks,
        'passed': len(checks), 'scratch_database_removed_after_empty_check': removed,
        'hosted_orders_created': 0, 'production_modified': False,
        'scope': 'Actual local PostgreSQL/PostGIS execution of the new migration and rollback-only synthetic fixtures. Auth stand-ins are test-only; deployed functions reuse existing live Auth. No hosted order or provider request.'}
    (ROOT / 'docs/evidence/MAP-pickup-local.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(evidence))
    assert result.returncode == 0 and len(checks) >= 25 and removed, 'Local SQL validation failed; inspect ignored map-pickup-sql.log'

if __name__ == '__main__':
    main()
