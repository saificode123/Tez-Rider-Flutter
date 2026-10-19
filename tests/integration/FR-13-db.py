"""Preserved LOCAL database only. Never reset/replay accepted migrations."""
import importlib.util,json,re,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('db',Path(__file__).with_name('FR-17-db.py'))
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
ROOT=d.ROOT;OUT=ROOT/'.fr21-local/fr13';OUT.mkdir(parents=True,exist_ok=True)
MIGRATION=ROOT/'supabase/migrations/202610180001_fr13_live_gps.sql'
mode=sys.argv[1];rules=(ROOT/'supabase/tests/FR-13.sql').read_text()
if mode=='review':
 assert d.local("select to_regnamespace('fr13_private')is null;").strip()=='t','Review requires unapplied migration'
 draft=re.sub(r'^begin;\s*|^commit;\s*','',MIGRATION.read_text(),flags=re.M)
 result=d.local(rules.replace('begin;','begin;\n'+draft,1))
elif mode=='sql':result=d.local(rules)
elif mode=='draft-cleanup-review':
 source=MIGRATION.read_text();match=re.search(r'create function fr13_private.cleanup\(\).*?end\$\$;',source,re.S);assert match
 function=match[0].replace('create function','create or replace function',1)
 result=d.local(rules.replace('begin;','begin;\n'+function,1))
 # Only this unreleased draft function is corrected; never replay the migration.
 d.local(function)
elif mode=='apply':
 versions=d.local('select version from supabase_migrations.schema_migrations order by version;').splitlines()
 missing=[p for p in sorted((ROOT/'supabase/migrations').glob('*.sql'))if p.name.split('_')[0]not in versions]
 assert missing==[MIGRATION],'Unexpected local history; never replay/reset'
 d.local(MIGRATION.read_text());d.local("insert into supabase_migrations.schema_migrations(version,name)values('202610180001','fr13_live_gps');")
 print('FR13 applied once only to preserved LOCAL database');sys.exit(0)
else:raise ValueError('Unsupported safe mode')
rows=json.loads(next(line for line in result.splitlines()if line.startswith('[{')))
(OUT/('local-'+mode+'.json')).write_text(json.dumps(rows,indent=2));print(json.dumps({'mode':mode,'passed':len(rows),'rollback':True}))
