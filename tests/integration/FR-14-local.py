"""Real concurrent transactions against the preserved LOCAL database only."""
import concurrent.futures,importlib.util,json,threading,subprocess
from pathlib import Path
spec=importlib.util.spec_from_file_location('db',Path(__file__).with_name('FR-17-db.py'))
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
OUT=d.ROOT/'.fr21-local/fr14';checks=[]
def scalar(sql):return d.local(sql).strip().splitlines()[-1]

assert scalar("select exists(select 1 from supabase_migrations.schema_migrations where version='202610200001');")=='t','Cache contention test requires the follow-up LOCAL migration; this runner never applies migrations'
def check(v,label):
 assert v,label
 checks.append({'check':label,'result':'PASS'})
source=(d.ROOT/'supabase/tests/FR-14.sql').read_text().split('do $$declare f fr14_fixture;who',1)[0]
row=json.loads(next(s for s in d.local(source+'select row_to_json(f)from fr14_fixture f;commit;').splitlines()if s.startswith('{')))
oid,cid,rid=row['oid'],row['cid'],row['rid']
try:
 before=int(scalar('select count(*)from fr14_private.quota_reservations;'))
 gate=threading.Barrier(8)
 def request(_):
  gate.wait(timeout=30)
  return json.loads(scalar(f'select public.fr14_prepare({oid},{cid},true);'))
 with concurrent.futures.ThreadPoolExecutor(max_workers=8)as pool:results=list(pool.map(request,range(8)))
 check(sum(r['code']=='COMPUTE'for r in results)==1,'8 independent concurrent SQL sessions acquire one lease')
 check(sum(r['code']=='BUSY'for r in results)==7,'remaining sessions observe in-flight lease')
 check(int(scalar('select count(*)from fr14_private.quota_reservations;'))==before+1,'concurrent requests reserve provider quota exactly once')
 token=next(r['lease']for r in results if r['code']=='COMPUTE')
 provider=json.dumps({'geometry':{'type':'LineString','coordinates':[[73.05,33.7],[73.06,33.71]]},'distanceMeters':1600,'durationSeconds':240})
 saved=json.loads(scalar(f"select public.fr14_finish({oid},{cid},'{token}','{provider}');"))
 check(saved['code']=='OK','lease holder commits provider result and ETA')
 check(json.loads(scalar(f'select public.fr14_prepare({oid},{cid},true);'))['code']=='CACHE','subsequent SQL transaction uses committed cache')
 check(int(scalar('select count(*)from fr14_private.quota_reservations;'))==before+1,'cache hit consumes no further provider request')
 # Hold the parent row in a separate transaction. An authorized fresh cache
 # read must still complete with a strict lock timeout; recomputes stay locked.
 locker=subprocess.Popen(['docker','exec','-i',d.CONTAINER,'psql','-U','postgres','-d','postgres','-X','-v','ON_ERROR_STOP=1','-At'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 try:
  locker.stdin.write(f"begin;select id from public.orders where id={oid} for update;select 'LOCKED';select pg_sleep(4);rollback;\n");locker.stdin.close()
  assert locker.stdout.readline().strip()=='BEGIN'
  assert locker.stdout.readline().strip()==str(oid)
  assert locker.stdout.readline().strip()=='LOCKED'
  result=json.loads(scalar(f"set lock_timeout='500ms';select public.fr14_prepare({oid},{cid},true);"))
  check(result['code']=='CACHE','fresh cache read succeeds while another transaction holds parent row')
 finally:
  locker.wait(timeout=10)
finally:
 # Only this marked synthetic fixture; no history reset or real data deletion.
 d.local(f"update public.orders set order_status='cancelled'where id={oid} and delivery_address='FR14 SQL SYNTHETIC';update public.rider_assignments set status='Cancelled'where orderid={oid};")
(OUT/'local-concurrency.json').write_text(json.dumps(checks,indent=2));print(json.dumps({'local_concurrency_passed':len(checks),'sessions':8}))
