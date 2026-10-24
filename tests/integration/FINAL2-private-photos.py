"""Exact-history, hash-reviewed TEST private photo acceptance; no Docker."""
import hashlib,importlib.util,json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
db=module('guarded_db','FINAL-security.py');db.OUT=OUT
assert(ROOT/'supabase/.temp/project-ref').read_text().strip()==REF and sys.argv[1]=='private-photos'
action=sys.argv[2];assert action in('review','deploy','post','fixture-status','hosted','hosted-tail','identity-denials','cleanup','deadline-review','deadline-deploy','deadline-post')
deadline=action.startswith('deadline-')
if deadline:action=action.removeprefix('deadline-')
version='202610250002'if deadline else'202610250001';migration=ROOT/('supabase/migrations/202610250002_final2_photo_session_deadline.sql'if deadline else'supabase/migrations/202610250001_final2_private_photos.sql')
record_prefix='private-photos-deadline'if deadline else'private-photos'
digest=hashlib.sha256(migration.read_bytes()).hexdigest()
history=OUT/'private-photos-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
known=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
expected=[v for v in known if v<=version];actual=[r['version']for r in db.query(history)]
assert actual==([v for v in expected if v!=version]if action in('review','deploy')else known[:len(actual)])and(action in('review','deploy')or version in actual),'Unexpected TEST history; never replay'
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-private-photos.sql').read_text(encoding='utf-8-sig')
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 source=source.replace('-- FINAL2_DEADLINE',"update auth.sessions set created_at=clock_timestamp()-interval '169 hours'where id=(select session_id from photo_people where label='rider');\ndo $$begin begin perform public.final2_photo_begin((select auth_id from photo_people where label='rider'),(select session_id from photo_people where label='rider'),gen_random_uuid(),'avatar',null,repeat('a',64),'image/png',68);raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.photo_ok(true,'trusted finish rechecks accepted 168-hour application deadline');end;end$$;\nupdate auth.sessions set created_at=clock_timestamp()where id=(select session_id from photo_people where label='rider');"if deadline else'')
 assert source.rstrip().endswith('rollback;')
 path=OUT/'private-photos-check.private.sql';path.write_text(source,encoding='utf-8')
 checks=db.query(path)[0]['results'];assert checks and all(r['result']=='PASS'for r in checks)
 (OUT/(record_prefix+'-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
 proof={'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True}
 (OUT/(record_prefix+'-'+action+'-proof.json')).write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(proof))
elif action=='deploy':
 proof=json.loads((OUT/(record_prefix+'-review-proof.json')).read_text());assert proof['passed']>=20 and proof['rolled_back'] and proof['migration_sha256']==digest
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate)\b',source,re.I)and not re.search(r'(?im)^\s*delete from',source)
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('"+version+"','final2_private_photos');commit;")
 path=OUT/'private-photos-deploy.private.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 proof={'project':REF,'version':version,'versions':len(expected),'migration_sha256':digest,'review_passes':proof['passed'],'replayed':False,'production_modified':False}
 (OUT/(record_prefix+'-deployment.json')).write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8');print(json.dumps(proof))

elif action in('fixture-status','hosted','hosted-tail','identity-denials','cleanup'):
 b=module('fixture_backend','FR-04-hosted.py');b.target()
 state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
 if action=='fixture-status':
  print(json.dumps({k:list(v.keys())if isinstance(v,dict)else type(v).__name__ for k,v in state.items()if 'fixture'in k or 'feedback'in k}))
 else:
  import runpy
  runpy.run_path(str(Path(__file__).with_name('FINAL2-private-photos-live.py')),init_globals={'b':b,'db':db,'state':state,'OUT':OUT,'ROOT':ROOT,'REF':REF,'action':action})
