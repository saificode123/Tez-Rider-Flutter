"""Preserved LOCAL stack / isolated TEST only; never reset or replay history."""
import importlib.util,json,re,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr32db',Path(__file__).with_name('FR-32-db.py'))
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
ROOT=d.ROOT;OUT=ROOT/'.fr21-local/checklist';OUT.mkdir(parents=True,exist_ok=True)
MIGRATION=ROOT/'supabase/migrations/202610170001_pre_delivery_checklist.sql'
mode=sys.argv[1];rules=(ROOT/'supabase/tests/CHECKLIST.sql').read_text(encoding='utf-8')
if mode=='local-review':
 assert d.local("select to_regnamespace('checklist_private')is null;").strip()=='t','Review requires unapplied new migration'
 migration=re.sub(r'^begin;\s*|^commit;\s*','',MIGRATION.read_text(),flags=re.M)
 before=(ROOT/'supabase/tests/CHECKLIST-before-migration.sql').read_text()
 output=d.local(rules.replace('begin;','begin;\n'+before+'\n'+migration,1))
 result=json.loads(next(line for line in output.splitlines()if line.startswith('[{')))
elif mode=='local-sql':
 output=d.local(rules);result=json.loads(next(line for line in output.splitlines()if line.startswith('[{')))
elif mode=='local-apply':
 versions=d.local('select version from supabase_migrations.schema_migrations order by version;').splitlines()
 missing=[p for p in sorted((ROOT/'supabase/migrations').glob('*.sql'))if p.name.split('_')[0]not in versions]
 assert missing==[MIGRATION],'Unexpected history: never reset/replay accepted migrations'
 d.local(MIGRATION.read_text())
 d.local("insert into supabase_migrations.schema_migrations(version,name)values('202610170001','pre_delivery_checklist');")
 print('Checklist applied once to preserved LOCAL database only');sys.exit(0)
else:raise ValueError('Unsupported read-only/rollback review mode')
(OUT/(mode+'.json')).write_text(json.dumps(result,indent=2));print(json.dumps({'mode':mode,'passed':len(result),'rollback':True}))
