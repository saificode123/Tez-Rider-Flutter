"""Run accepted SQL suites with explicit synthetic destination selection fixtures."""
import importlib.util,json,re,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('db',Path(__file__).with_name('FR-17-db.py'))
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
hosted=sys.argv[1]=='hosted';run=d.hosted if hosted else d.local
out=d.ROOT/'.fr21-local/fr14';results=[]
suites=sys.argv[2].split(',')if len(sys.argv)>2 else ['FR-21','FR-04','FR-25','FR-26','FR-33','FR-28','FR-20','FR-30','FR-10','FR-17','FR-32','CHECKLIST','FR-13','FR-14']
for name in suites:
 path=d.ROOT/'supabase/tests'/(name+'.sql')
 if not path.exists():
  results.append({'suite':name,'result':'NOT EXECUTED','reason':'No standalone SQL suite at this path'});continue
 source=path.read_text(encoding='utf8')
 # This updates only synthetic delivery INPUT fixtures for the new approved
 # checkout contract. Security assertions and application SQL are unchanged.
 for speed in ['standard','express']:
  source=source.replace('"speed":"'+speed+'"','"speed":"'+speed+'","destination_confirmed":true,"destination_source":"map_pin"')if name!='FR-14'else source
  source=source.replace("'speed','"+speed+"'","'speed','"+speed+"','destination_confirmed',true,'destination_source','map_pin'")if name!='FR-14'else source
 try:
  rows=run(source)
  if hosted:
   raw=rows[0];assert len(raw)==1;data=next(iter(raw.values()))
  else:data=json.loads(next(s for s in rows.splitlines()if s.startswith('[{')))
  assert isinstance(data,list)and data
  failed=[r for r in data if r.get('result')not in('PASS',None)]
  assert not failed,'Assertion result failed'
  result={'suite':name,'result':'PASS','assertions':len(data),'destination_fixtures':'explicit confirmation for new checkouts'}
 except Exception as error:
  result={'suite':name,'result':'FAIL','reason':str(error)if isinstance(error,AssertionError)else type(error).__name__}
 results.append(result);print(json.dumps(result),flush=True)
 (out/('regressions-'+sys.argv[1]+'.json')).write_text(json.dumps(results,indent=2))
if any(r['result']=='FAIL'for r in results):sys.exit(1)
