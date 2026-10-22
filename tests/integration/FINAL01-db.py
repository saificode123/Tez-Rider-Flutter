"""Phased TEST-only migration review/deploy. No destructive hosted fixtures."""
import importlib.util,json,re,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('base',Path(__file__).with_name('FINAL-security.py'))
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
ROOT=d.ROOT;OUT=ROOT/'.fr21-local/final01';REF=d.REF
VERSIONS=('202610220003','202610220004')
def versions():
 p=OUT/'history.sql';p.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
 return[r['version']for r in d.query(p)]
def tests(version,review=False):
 assert version in VERSIONS
 source=(ROOT/'supabase/tests/FINAL01-security.sql').read_text(encoding='utf-8-sig')
 assert source.rstrip().endswith('rollback;')and not re.search(r'\b(insert|update|delete|truncate)\s+\w',source,re.I),'Metadata/pure checks only'
 prefix="select set_config('final01.test_project_ref','"+REF+"',false);select set_config('final01.activation','"+str(version==VERSIONS[1]).lower()+"',false);\n"
 if review:
  migration=next((ROOT/'supabase/migrations').glob(version+'_*.sql')).read_text(encoding='utf-8-sig')
  assert migration.count('begin;')==1 and migration.rstrip().endswith('commit;')
  migration=re.sub(r'^begin;\s*|^commit;\s*','',migration,flags=re.M)
  source=source.replace('begin;','begin;\n'+migration,1)
 p=OUT/'review.sql';p.write_text(prefix+source,encoding='utf-8')
 rows=d.query(p)[0]['results'];assert len(rows)==25 and all(r['result']=='PASS'for r in rows), 'SQL review failed; no acceptance claim'
 name=('review-'if review else'post-')+version
 (OUT/(name+'.json')).write_text(json.dumps(rows,indent=2),encoding='utf-8')
 print(json.dumps({'TEST':REF,'mode':name,'checks':len(rows),'metadata_and_pure_only':True,'rolled_back':True}))
def deploy(version):
 assert version in VERSIONS
 expected=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
 required=[v for v in expected if v<version]
 assert versions()==required,'History differs; never replay/reset'
 review=json.loads((OUT/('review-'+version+'.json')).read_text());assert len(review)==25 and all(r['result']=='PASS'for r in review)
 if version==VERSIONS[1]:
  gate=json.loads((OUT/'activation-readiness.json').read_text())
  assert gate.get('hosted_compatible')is True and gate.get('client_ready')is True and gate.get('direct_surfaces_reviewed')is True,'Do not activate before compatible callers and bypass review'
 migration=next((ROOT/'supabase/migrations').glob(version+'_*.sql'));source=migration.read_text(encoding='utf-8-sig')
 assert not re.search(r'\b(?:truncate|drop\s+table|disable\s+row)\b',source,re.I)
 name=migration.stem.split('_',1)[1]
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('"+version+"','"+name+"');\ncommit;")
 p=OUT/'deploy.sql';p.write_text(source,encoding='utf-8');d.query(p)
 assert versions()==required+[version]
 (OUT/('deployment-'+version+'.json')).write_text(json.dumps({'project':REF,'version':version,'versions':len(required)+1,'production_modified':False,'replayed':False},indent=2),encoding='utf-8')
 print(json.dumps({'TEST':REF,'new_migration':version,'versions':len(required)+1,'production_modified':False}))
if __name__=='__main__':
 mode,version=sys.argv[1:3]
 if mode=='review':tests(version,True)
 elif mode=='post':tests(version)
 elif mode=='deploy':deploy(version)
 else:raise ValueError('Unsupported guarded action')
