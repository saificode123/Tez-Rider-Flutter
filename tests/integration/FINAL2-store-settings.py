"""Exact-history, hash-reviewed TEST Admin monitoring acceptance; no Docker."""
import hashlib,importlib.util,json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
db=module('guarded_db','FINAL-security.py');db.OUT=OUT
assert(ROOT/'supabase/.temp/project-ref').read_text().strip()==REF and sys.argv[1]=='store-settings'
action=sys.argv[2];assert action in('review','deploy','post','hosted','hosted-tail')
version='202610250004';migration=ROOT/'supabase/migrations/202610250004_final2_store_settings.sql'
digest=hashlib.sha256(migration.read_bytes()).hexdigest()
history=OUT/'store-settings-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
known=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
expected=[v for v in known if v<=version];actual=[r['version']for r in db.query(history)]
assert(actual in([v for v in expected if v!=version],expected)if action=='fixture-status'else actual==([v for v in expected if v!=version]if action in('review','deploy')else expected)),'Unexpected TEST history; never replay'
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-store-settings.sql').read_text(encoding='utf-8-sig')
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 assert source.rstrip().endswith('rollback;')
 path=OUT/'store-settings-check.private.sql';path.write_text(source,encoding='utf-8')
 checks=db.query(path)[0]['results'];assert checks and all(r['result']=='PASS'for r in checks)
 (OUT/('store-settings-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
 proof={'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True}
 (OUT/('store-settings-'+action+'-proof.json')).write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(proof))
elif action=='deploy':
 proof=json.loads((OUT/'store-settings-review-proof.json').read_text());assert proof['passed']>=15 and proof['rolled_back'] and proof['migration_sha256']==digest
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate)\b',source,re.I)and not re.search(r'(?im)^\s*delete from',source)
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610250004','final2_store_settings');commit;")
 path=OUT/'store-settings-deploy.private.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 proof={'project':REF,'version':version,'versions':len(expected),'migration_sha256':digest,'review_passes':proof['passed'],'replayed':False,'production_modified':False}
 (OUT/'store-settings-deployment.json').write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8');print(json.dumps(proof))

elif action in('hosted','hosted-tail'):
 import runpy
 runpy.run_path(str(Path(__file__).with_name('FINAL2-store-settings-live.py')),init_globals={'b':module('fixture_backend','FR-04-hosted.py'),'db':db,'OUT':OUT,'ROOT':ROOT,'REF':REF})
