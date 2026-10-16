"""FR17 isolated TEST/local SQL runner; no reset or accepted migration replay."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'.fr21-local/fr17'
OUT.mkdir(parents=True,exist_ok=True)
REF='igeisilhtmglgnqvllrx'
CLI='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
CONTAINER='supabase_db_tezrider-fr30-local'
MIGRATION=ROOT/'supabase/migrations/202610160002_fr17_inventory.sql'

def hosted(sql):
    assert (ROOT/'supabase/.temp/project-ref').read_text().strip()==REF
    path=OUT/'query.sql';path.write_text(sql,encoding='utf-8')
    p=subprocess.run([CLI,'db','query','--linked','--project-ref',REF,'--file',str(path),'--output','json'],capture_output=True,text=True,timeout=180)
    (OUT/'hosted-last.log').write_text(p.stdout+p.stderr,encoding='utf-8')
    assert p.returncode==0,'TEST SQL failed; protected local log retained'
    return json.loads(p.stdout[p.stdout.index('{'):])['rows']

def local(sql):
    p=subprocess.run(['docker','exec','-i',CONTAINER,'psql','-U','postgres','-d','postgres','-X','-v','ON_ERROR_STOP=1','-At'],input=sql,capture_output=True,text=True,timeout=180)
    (OUT/'local-last.log').write_text(p.stdout+p.stderr,encoding='utf-8')
    if p.returncode:print(p.stderr[-2200:])
    assert p.returncode==0,'Local SQL failed'
    return p.stdout

def main(mode):
    if mode=='inspect':
        result=hosted((ROOT/'supabase/inspection/FR-17-preflight.sql').read_text())[0]['inspection']
        assert result['versions']==sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
        (OUT/'preflight.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        print(json.dumps({'target':REF,'read_only':True,'versions':len(result['versions']),'products':result['product_counts'],'product_indexes':result['product_indexes']}))
    elif mode=='local-migrate':
        versions=local('select version from supabase_migrations.schema_migrations order by version;').splitlines()
        missing=[p for p in sorted((ROOT/'supabase/migrations').glob('*.sql'))if p.name.split('_')[0]not in versions]
        assert missing==[MIGRATION],'Unexpected history gap; never replay'
        local(MIGRATION.read_text())
        local("insert into supabase_migrations.schema_migrations(version,name)values('202610160002','fr17_inventory');")
        print('Local FR17 applied once')
    elif mode in('local-sql','hosted-sql','hosted-review'):
        sql=(ROOT/'supabase/tests/FR-17.sql').read_text(encoding='utf-8')
        if mode=='hosted-review':sql=sql.replace('begin;','begin;\n'+re.sub(r'^begin;\s*|^commit;\s*','',MIGRATION.read_text(),flags=re.M),1)
        result=([{'results':json.loads(next(line for line in local(sql).splitlines()if line.startswith('[{')))}]if mode=='local-sql'else hosted(sql))
        (OUT/(mode+'.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
        print(json.dumps({'mode':mode,'passed':len(result[0]['results']),'rollback':True}))
    elif mode=='deploy':
        versions=[r['version']for r in hosted('select version from supabase_migrations.schema_migrations order by version;')]
        expected=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
        assert versions==[v for v in expected if v!='202610160002'],'Never replay migrations'
        for extra in(['--dry-run'],[]):
            p=subprocess.run([CLI,'db','push','--linked',*extra],capture_output=True,text=True,timeout=180)
            (OUT/('deployment-plan.log'if extra else'deployment.log')).write_text(p.stdout+p.stderr,encoding='utf-8')
            assert p.returncode==0,'TEST deployment failed'
            if extra:assert sorted(set(re.findall(r'2026\d{8}_[a-z0-9_]+\.sql',p.stdout+p.stderr)))==[MIGRATION.name]
        assert [r['version']for r in hosted('select version from supabase_migrations.schema_migrations order by version;')]==expected
        print(json.dumps({'TEST_migration':MIGRATION.name,'production_touched':False}))
    else:raise ValueError('Unknown guarded mode')

if __name__=='__main__':main(sys.argv[1])
