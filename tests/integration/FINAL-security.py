"""Guarded, non-Docker security inspection. No credentials or raw errors printed."""
import json
import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
REF = 'igeisilhtmglgnqvllrx'
CLI = 'C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
OUT = ROOT / '.fr21-local/final1'


def query(path):
    assert (ROOT / 'supabase/.temp/project-ref').read_text().strip() == REF
    result = subprocess.run([CLI, 'db', 'query', '--linked', '--project-ref', REF,
                             '--file', str(path), '--output', 'json'],
                            capture_output=True, text=True, encoding='utf-8', timeout=90)
    if result.returncode:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / 'query-error.private.log').write_text(result.stdout + result.stderr, encoding='utf-8')
        # Never echo SQL errors containing data or signed URLs.
        raise RuntimeError('Guarded TEST SQL operation failed; no raw response emitted')
    return json.loads(result.stdout[result.stdout.index('{'):])['rows']


def inspect():
    OUT.mkdir(parents=True, exist_ok=True)
    data = query(ROOT / 'supabase/inspection/FINAL-security.sql')[0]['inspection']
    (OUT / 'catalog.json').write_text(json.dumps(data, indent=2), encoding='utf-8')
    print(json.dumps({'TEST': REF, 'tables': len(data['tables']),
                      'functions': len(data['functions']), 'versions': len(data['versions'])}))


def sql_tests(review=False, version='202610220001'):
    OUT.mkdir(parents=True, exist_ok=True)
    sql = (ROOT / 'supabase/tests/FINAL-security.sql').read_text(encoding='utf-8')
    assert sql.rstrip().endswith('rollback;'), 'Tests must roll back'
    if review:
        assert version in ('202610220001', '202610220002')
        migration = next((ROOT / 'supabase/migrations').glob(version + '_*.sql')).read_text(encoding='utf-8')
        source = re.sub(r'^(begin|commit);\s*', '', migration, flags=re.M)
        sql = sql.replace('begin;', 'begin;\n' + source, 1)
    path = OUT / 'test-operation.sql'
    path.write_text("select set_config('final1.test_project_ref','" + REF + "',false);\n" + sql, encoding='utf-8')
    data = query(path)[0]['results']
    assert data and all(r['result'] == 'PASS' for r in data)
    name = 'review' if review else 'sql'
    (OUT / (name + '-results.json')).write_text(json.dumps(data, indent=2), encoding='utf-8')
    if review:
        (OUT / ('review-' + version + '-results.json')).write_text(json.dumps(data, indent=2), encoding='utf-8')
    print(json.dumps({'TEST': REF, 'mode': name, 'passed': len(data), 'rolled_back': True}))


def deploy(version='202610220001'):
    """Apply exactly one reviewed new migration; never replay accepted history."""
    OUT.mkdir(parents=True, exist_ok=True)
    versions_path = OUT / 'versions.sql'
    versions_path.write_text('begin read only; select version from supabase_migrations.schema_migrations order by version; rollback;', encoding='utf-8')
    versions = [r['version'] for r in query(versions_path)]
    expected = sorted(p.name.split('_')[0] for p in (ROOT / 'supabase/migrations').glob('*.sql'))
    assert version in ('202610220001', '202610220002')
    assert versions == [v for v in expected if v != version], 'Unexpected history; never replay/reset'
    review_path = OUT / ('review-' + version + '-results.json')
    if not review_path.exists() and version == '202610220001':
        review_path = OUT / 'review-results.json'
    passed = json.loads(review_path.read_text())
    assert len(passed) >= 79 and all(r['result'] == 'PASS' for r in passed)
    migration = next((ROOT / 'supabase/migrations').glob(version + '_*.sql'))
    source = migration.read_text(encoding='utf-8')
    assert not re.search(r'\b(delete|truncate)\s|disable\s+row', source, re.I)
    # Schema and history commit atomically. No existing migration is rerun.
    name = migration.stem.split('_', 1)[1]
    source = source.replace('commit;', "insert into supabase_migrations.schema_migrations(version,name)values('" + version + "','" + name + "');\ncommit;")
    path = OUT / 'deploy.sql'
    path.write_text(source, encoding='utf-8')
    query(path)
    assert [r['version'] for r in query(versions_path)] == expected
    (OUT / 'deployment.json').write_text(json.dumps({'project': REF, 'migration': migration.name,
        'versions': len(expected), 'production_modified': False, 'replayed': False}, indent=2))
    (OUT / ('deployment-' + version + '.json')).write_text((OUT / 'deployment.json').read_text(), encoding='utf-8')
    print(json.dumps({'TEST': REF, 'new_migration': migration.name, 'versions': len(expected), 'production_modified': False}))


if __name__ == '__main__':
    if sys.argv[1:] == ['inspect']:
        inspect()
    elif sys.argv[1:2] == ['review']:
        sql_tests(review=True, version=sys.argv[2] if len(sys.argv)>2 else '202610220001')
    elif sys.argv[1:] == ['sql']:
        sql_tests()
    elif sys.argv[1:2] == ['deploy']:
        deploy(sys.argv[2] if len(sys.argv)>2 else '202610220001')
    else:
        raise SystemExit('Supported action: inspect')
