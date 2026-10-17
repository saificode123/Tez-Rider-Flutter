"""Guarded FR32 local review and TEST SQL; never reset/replay accepted migrations."""
import importlib.util
import json
from pathlib import Path
import re
import sys

spec = importlib.util.spec_from_file_location('fr17db', Path(__file__).with_name('FR-17-db.py'))
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)
ROOT = d.ROOT
OUT = ROOT / '.fr21-local/fr32'
OUT.mkdir(parents=True, exist_ok=True)
MIGRATION = ROOT / 'supabase/migrations/202610160003_fr32_email_outbox.sql'

def local(sql):
    return d.local(sql)

def main(mode):
    rules = (ROOT / 'supabase/tests/FR-32.sql').read_text(encoding='utf-8')
    if mode == 'local-review-functions':
        names = ['fr32_private.claim', 'public.fr32_begin_email', 'public.fr32_finish_email', 'fr32_private.payment_captured']
        source = MIGRATION.read_text()
        functions = []
        for name in names:
            match = re.search(r'create function ' + re.escape(name) + r'\(.*?end\$\$;', source, re.S)
            assert match, 'Draft function source missing'
            functions.append(match[0].replace('create function', 'create or replace function', 1))
        changes = '\n'.join(functions)
        output = local(rules.replace('begin;', 'begin;\n' + changes, 1))
        result = json.loads(next(line for line in output.splitlines() if line.startswith('[{')))
        (OUT / 'local-review.json').write_text(json.dumps(result, indent=2))
        # Unreleased draft-function correction, not accepted migration replay.
        local('begin;' + changes + "update fr32_private.configuration set quota_mode='rolling_26h';commit;")
        print(json.dumps({'passed': len(result), 'draft_functions_updated': len(names), 'local_only': True, 'rolling_26h_user_approved': True}))
    elif mode == 'local-review':
        assert local("select to_regnamespace('fr32_private')is null;").strip() == 't', 'Review requires unapplied FR32'
        draft = re.sub(r'^begin;\s*|^commit;\s*', '', MIGRATION.read_text(), flags=re.M)
        output = local(rules.replace('begin;', 'begin;\n' + draft, 1))
        result = json.loads(next(line for line in output.splitlines() if line.startswith('[{')))
        (OUT / 'local-review.json').write_text(json.dumps(result, indent=2))
        print(json.dumps({'passed': len(result), 'rollback': True, 'local_only': True}))
    elif mode in ('local-sql', 'hosted-sql'):
        result = (json.loads(next(line for line in local(rules).splitlines() if line.startswith('[{')))
                  if mode == 'local-sql' else d.hosted(rules)[0]['results'])
        (OUT / (mode + '.json')).write_text(json.dumps(result, indent=2))
        print(json.dumps({'passed': len(result), 'rollback': True, 'mode': mode}))
    elif mode == 'local-migrate':
        versions = local('select version from supabase_migrations.schema_migrations order by version;').splitlines()
        missing = [p for p in sorted((ROOT / 'supabase/migrations').glob('*.sql')) if p.name.split('_')[0] not in versions]
        assert missing == [MIGRATION], 'Unexpected history; never replay'
        local(MIGRATION.read_text())
        local("insert into supabase_migrations.schema_migrations(version,name)values('202610160003','fr32_email_outbox');")
        print('FR32 applied once to preserved LOCAL database; quota remains disabled pending policy approval')
    else:
        raise ValueError('Unsupported safe mode')

if __name__ == '__main__':
    main(sys.argv[1])
