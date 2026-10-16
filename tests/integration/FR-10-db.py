"""Bounded SQL checks/deployment. Fixed TEST target; local load stays loopback."""
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.fr21-local/fr10'
OUT.mkdir(parents=True, exist_ok=True)
REF = 'igeisilhtmglgnqvllrx'
CLI = 'C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
CONTAINER = 'supabase_db_tezrider-fr30-local'
MIGRATION = ROOT / 'supabase/migrations/202610160001_fr10_order_timeout.sql'


def local(sql):
    result = subprocess.run(['docker', 'exec', '-i', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-X', '-v', 'ON_ERROR_STOP=1', '-At'], input=sql, text=True, capture_output=True, timeout=180)
    (OUT / 'local-last.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        print(result.stderr[-2500:])
        raise RuntimeError('Local SQL failed')
    return result.stdout


def hosted(sql):
    assert (ROOT / 'supabase/.temp/project-ref').read_text().strip() == REF
    file = OUT / 'query.sql'
    file.write_text(sql, encoding='utf-8')
    result = subprocess.run([CLI, 'db', 'query', '--linked', '--project-ref', REF, '--file', str(file), '--output', 'json'], capture_output=True, text=True, timeout=180)
    (OUT / 'hosted-last.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError('TEST SQL failed; inspect protected local log')
    return json.loads(result.stdout[result.stdout.index('{'):])['rows']


def main():
    mode = sys.argv[1]
    if mode == 'local-migrate':
        versions = local('select version from supabase_migrations.schema_migrations order by version;').splitlines()
        for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
            version = path.name.split('_')[0]
            if version in versions:
                continue
            assert path.name in ('202610150006_fr30_android_push.sql', MIGRATION.name), 'Unexpected local migration gap'
            local(path.read_text(encoding='utf-8'))
            local("insert into supabase_migrations.schema_migrations(version,name) values('" + version + "','" + path.stem.split('_', 1)[1] + "');")
            print('Local applied once: ' + path.name)
    elif mode in ('local-sql', 'hosted-sql', 'hosted-review'):
        sql = (ROOT / 'supabase/tests/FR-10.sql').read_text(encoding='utf-8')
        if mode == 'hosted-review':
            migration = re.sub(r'^begin;\s*|^commit;\s*', '', MIGRATION.read_text(encoding='utf-8'), flags=re.M)
            sql = sql.replace('begin;', 'begin;\n' + migration, 1)
        result = ([{'results': json.loads(next(line for line in local(sql).splitlines() if line.startswith('[{')))}] if mode == 'local-sql' else hosted(sql))
        (OUT / (mode + '.json')).write_text(json.dumps(result, indent=2), encoding='utf-8')
        print(json.dumps({'mode': mode, 'passed': len(result[0]['results']), 'rolled_back': True}))
    elif mode == 'deploy':
        versions = [r['version'] for r in hosted('select version from supabase_migrations.schema_migrations order by version;')]
        expected = sorted(p.name.split('_')[0] for p in (ROOT / 'supabase/migrations').glob('*.sql'))
        assert versions == [v for v in expected if v != MIGRATION.name.split('_')[0]], 'Never replay migrations'
        for args in (['--dry-run'], []):
            result = subprocess.run([CLI, 'db', 'push', '--linked', *args], capture_output=True, text=True, timeout=180)
            (OUT / ('deployment-plan.log' if args else 'deployment.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
            assert result.returncode == 0, 'TEST deployment failed'
            if args:
                assert sorted(set(re.findall(r'2026\d{8}_[a-z0-9_]+\.sql', result.stdout + result.stderr))) == [MIGRATION.name], 'Unexpected migration plan'
        assert [r['version'] for r in hosted('select version from supabase_migrations.schema_migrations order by version;')] == expected
        print(json.dumps({'project': REF, 'applied': MIGRATION.name, 'production_touched': False}))
    else:
        raise ValueError('Unknown guarded mode')


if __name__ == '__main__':
    main()
