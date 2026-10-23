"""Guarded Stage2 TEST metadata/review helper. Never print private payloads."""
from pathlib import Path
import hashlib,importlib.util,json,sys
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'.fr21-local/final2';OUT.mkdir(exist_ok=True)
REF='igeisilhtmglgnqvllrx'
assert (ROOT/'supabase/.temp/project-ref').read_text().strip()==REF
spec=importlib.util.spec_from_file_location('guarded_sql',Path(__file__).with_name('FINAL-security.py'))
db=importlib.util.module_from_spec(spec);spec.loader.exec_module(db);db.OUT=OUT
if sys.argv[1]in('inspect','current'):
 catalog=db.query(ROOT/'supabase/inspection/FINAL-security.sql')[0]['inspection']
 expected=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
 assert catalog['versions']==expected,'History mismatch; no mutation performed'
 if sys.argv[1]=='current':
  (OUT/'current-catalog.private.json').write_text(json.dumps(catalog,indent=2),encoding='utf-8')
  index_sql=OUT/'indexes.sql';index_sql.write_text("begin read only;select indexname,indexdef from pg_indexes where schemaname='public'and tablename='products';rollback;",encoding='utf-8')
  (OUT/'product-indexes.json').write_text(json.dumps(db.query(index_sql),indent=2),encoding='utf-8')
  print(json.dumps({'project':REF,'migrations':len(expected),'tables':len(catalog['tables']),'functions':len(catalog['functions']),'mutation':False}))
  raise SystemExit(0)
 assert len(expected)==45,'Initial baseline must remain the accepted45-version checkpoint'
 (OUT/'baseline-catalog.private.json').write_text(json.dumps(catalog,indent=2),encoding='utf-8')
 sql=OUT/'schema.sql'
 sql.write_text("""begin read only;
 select table_schema,table_name,column_name,data_type,is_nullable,column_default from information_schema.columns
 where table_schema='public' or table_schema like '%private' order by table_schema,table_name,ordinal_position;
 rollback;""",encoding='utf-8')
 columns=db.query(sql);(OUT/'baseline-columns.private.json').write_text(json.dumps(columns,indent=2),encoding='utf-8')
 manifest=[{'file':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}for p in sorted((ROOT/'supabase/migrations').glob('*.sql'))]
 (OUT/'baseline-migrations.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'project':REF,'migrations':len(expected),'tables':len(catalog['tables']),'functions':len(catalog['functions']),'columns_inspected':len(columns),'mutation':False}))
else:raise SystemExit('Unsupported action; no implicit deployment')
