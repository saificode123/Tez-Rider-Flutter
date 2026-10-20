"""FR14 local review/apply and isolated TEST deployment; no reset/replay."""
import importlib.util,json,re,subprocess,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr17db',Path(__file__).with_name('FR-17-db.py'))
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
ROOT=d.ROOT;OUT=ROOT/'.fr21-local/fr14';OUT.mkdir(parents=True,exist_ok=True)
VERSION=sys.argv[2]if len(sys.argv)>2 else'202610190001'
assert VERSION in('202610190001','202610190002','202610200001')
MIGRATION=next((ROOT/'supabase/migrations').glob(VERSION+'_*.sql'))
def main(mode):
 local=mode.startswith('local');run=d.local if local else d.hosted
 if not local:assert(ROOT/'supabase/.temp/project-ref').read_text().strip()==d.REF
 if mode.endswith('inspect'):
  rows=run("select version from supabase_migrations.schema_migrations order by version;")
  (OUT/(mode+'.json')).write_text(json.dumps(rows));print(json.dumps({'mode':mode,'history_saved':True}));return
 if mode.endswith('review')or mode.endswith('sql'):
  rules=(ROOT/'supabase/tests/FR-14.sql').read_text()
  assert rules.rstrip().endswith('rollback;'),'Security/quota simulations must roll back'
  if mode.endswith('review'):
   source=re.sub(r'^begin;\s*|^commit;\s*','',MIGRATION.read_text(),flags=re.M)
   rules=rules.replace('begin;','begin;\n'+source,1)
  result=run(rules)
  rows=json.loads(next(s for s in result.splitlines()if s.startswith('[{')))if local else result[0]['results']
  (OUT/(mode+'.json')).write_text(json.dumps(rows,indent=2));assert all(r['result']=='PASS'for r in rows)
  print(json.dumps({'mode':mode,'passed':len(rows),'rollback':True}));return
 if mode in('local-apply','hosted-deploy'):
  rows=run('select version from supabase_migrations.schema_migrations order by version;')
  versions=rows.splitlines()if local else [r['version']for r in rows]
  expected=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
  assert versions==[v for v in expected if v!=VERSION],'Unexpected history: never reset or replay'
  # New migration + its history record commit together. No existing version is run.
  source=MIGRATION.read_text().replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('"+VERSION+"','"+MIGRATION.stem.split('_',1)[1]+"');\ncommit;")
  run(source);print(json.dumps({'mode':mode,'migration':VERSION,'target':'local'if local else d.REF}));return
 raise ValueError('Unsupported safe mode')
if __name__=='__main__':main(sys.argv[1])
