"""Real concurrent PostgreSQL sessions; named preserved LOCAL database only."""
import concurrent.futures,importlib.util,json,threading,uuid
from pathlib import Path
spec=importlib.util.spec_from_file_location('db',Path(__file__).with_name('FR-32-db.py'))
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
OUT=d.ROOT/'.fr21-local/checklist';results=[]
def scalar(q):return d.local(q).strip().splitlines()[-1]
def check(v,label):
 assert v,label
 results.append({'check':label,'result':'PASS'})
def pair(queries):
 gate=threading.Barrier(2)
 def run(q):gate.wait(timeout=15);return d.local(q)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:return list(pool.map(run,queries))
def fixture():
 key=str(uuid.uuid4());auth=str(uuid.uuid4());session=str(uuid.uuid4())
 row=json.loads(scalar("""do $$declare uid bigint;cid bigint;o bigint;a bigint;begin
 create schema if not exists checklist_test;
 create table if not exists checklist_test.fixtures(key uuid primary key,oid bigint,aid bigint,rid bigint);
 insert into auth.users(id,email,email_confirmed_at,role,aud)values('"""+auth+"""','checklist-concurrent-"""+key+"""@example.test',now(),'authenticated','authenticated');
 insert into public.users(email,name,role,verification_status)values('checklist-concurrent-"""+key+"""@example.test','CHECKLIST LOCAL CONCURRENCY SYNTHETIC','rider','approved')returning id into uid;
 insert into auth.sessions(id,user_id,created_at,updated_at)values('"""+session+"""','"""+auth+"""',now(),now());
 select id into cid from public.users where role='customer'order by id limit 1;
 insert into public.orders(user_id,rider_id,order_status,amount,payment_method,delivery_address)values(cid,uid,'ready',200,'COD','CHECKLIST LOCAL CONCURRENCY SYNTHETIC')returning id into o;
 insert into public.rider_assignments(orderid,riderid,status)values(o,uid,'Accepted')returning id into a;
 insert into checklist_test.fixtures values('"""+key+"""',o,a,uid);end$$;
 select row_to_json(f)from checklist_test.fixtures f where key='"""+key+"';"))
 claims=json.dumps({'sub':auth,'role':'authenticated','session_id':session})
 row['claim']="select set_config('request.jwt.claims','"+claims+"',true);"
 row['submit']="select public.submit_pre_delivery_checklist("+str(row['aid'])+",1,'[{\"id\":\"items_match\",\"confirmed\":true},{\"id\":\"packaging_intact\",\"confirmed\":true},{\"id\":\"details_confirmed\",\"confirmed\":true}]');"
 return row
fixtures=[]
try:
 f=fixture();fixtures.append(f)
 out=pair(['begin;'+f['claim']+f['submit']+'select pg_sleep(0.3);commit;']*2)
 replies=[json.loads(next(l for l in s.splitlines()if l.startswith('{')and'COMPLETED'in l))for s in out]
 check(all(r['code']=='COMPLETED'for r in replies)and sorted(r['replayed']for r in replies)==[False,True],'simultaneous submissions produce one completion and one replay')
 check(scalar('select count(*)from public.pre_delivery_checklists where assignment_id='+str(f['aid']))=='1','unique concurrent evidence record')
 check(replies[0]['completed_at']==replies[1]['completed_at'],'concurrent retry preserves original timestamp')
 out=pair(['begin;'+f['claim']+'select public.start_checklisted_delivery('+str(f['aid'])+');select pg_sleep(0.3);commit;']*2)
 replies=[json.loads(next(l for l in s.splitlines()if l.startswith('{')and'STARTED'in l))for s in out]
 check(all(r['code']=='STARTED'for r in replies)and sorted(r['replayed']for r in replies)==[False,True],'simultaneous start produces one transition and one replay')
 f=fixture();fixtures.append(f)
 pair(['begin;'+f['claim']+f['submit']+'select pg_sleep(0.3);commit;',"begin;update public.orders set order_status='cancelled'where id="+str(f['oid'])+';commit;'])
 check(scalar('select order_status from public.orders where id='+str(f['oid']))=='cancelled','cancellation versus checklist race leaves cancelled parent')
 reply=json.loads(scalar(f['claim']+'select public.start_checklisted_delivery('+str(f['aid'])+');'))
 check(reply['code']!='STARTED','concurrent cancellation cannot be bypassed by later start')
finally:
 for f in fixtures:
  d.local("update public.orders set order_status='cancelled'where id="+str(f['oid'])+" and delivery_address='CHECKLIST LOCAL CONCURRENCY SYNTHETIC'and order_status not in('cancelled','delivered');")
(OUT/'local-concurrency.json').write_text(json.dumps(results,indent=2));print(json.dumps({'passed':len(results),'real_independent_sessions':True,'local_only':True}))
