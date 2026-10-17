"""Bounded synthetic FR32 TEST actions. No production or hosted load tests."""
import datetime as dt
import importlib.util
import json
import re
import secrets
import contextlib
import io
import runpy
import subprocess
import sys
import time
import uuid
from pathlib import Path
import urllib.request
import urllib.error

spec=importlib.util.spec_from_file_location('fr33',Path(__file__).with_name('FR-33-hosted.py'))
f=importlib.util.module_from_spec(spec);spec.loader.exec_module(f)
b=f.b;ROOT=f.ROOT;REF='igeisilhtmglgnqvllrx';OUT=ROOT/'.fr21-local/fr32';OUT.mkdir(parents=True,exist_ok=True)
CLI='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
MIGRATION='202610160003_fr32_email_outbox.sql'
KEY_FILE=b.PRIVATE/'fr32-worker.bin'
STATE=b.PRIVATE/'fr32-accounts.bin'
state=json.loads(b.crypt(STATE.read_bytes(),True))if STATE.exists()else {'accounts':{}}

def save():STATE.write_bytes(b.crypt(json.dumps(state).encode()))
def query(sql):
 b.target();path=OUT/('query-'+str(uuid.uuid4())+'.sql');path.write_text(sql,encoding='utf-8')
 try:return f.query(path)['rows']
 finally:path.unlink(missing_ok=True)
def command(args):
 b.target();p=subprocess.run([CLI,*args],cwd=ROOT,capture_output=True,text=True,timeout=240)
 assert p.returncode==0,'Guarded TEST command failed (private output suppressed)'
 return p.stdout+p.stderr
def check(ok,label):
 assert ok,label
 record={'time':dt.datetime.now(dt.timezone.utc).isoformat(),'check':label,'result':'PASS'}
 with(OUT/'checks.jsonl').open('a')as out:out.write(json.dumps(record)+'\n')
 print(json.dumps(record),flush=True)
def worker_key():return b.crypt(KEY_FILE.read_bytes(),True).decode()
def worker(key=None):
 request=urllib.request.Request('https://'+REF+'.supabase.co/functions/v1/fr32-email-worker',data=b'{}',headers={'Content-Type':'application/json','x-fr32-worker-key':worker_key()if key is None else key},method='POST')
 try:
  with urllib.request.urlopen(request,timeout=100)as r:return r.status,json.load(r)
 except urllib.error.HTTPError as e:
  try:body=json.load(e)
  except Exception:body={}
  return e.code,body
def preflight():
 f.preflight()
 code,settings=b.api('/auth/v1/settings')
 assert code==200,'Auth public settings unavailable'
 # Public settings disclose confirmation flags, not SMTP host/credentials/rates.
 result={'mail_autoconfirm':settings.get('mailer_autoconfirm'),'email_provider_enabled':settings.get('external',{}).get('email'),'smtp_transport':'NOT EXPOSED by public settings; no Management config permission assumed','auth_smtp_changed':False}
 (OUT/'auth-settings.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
def deploy():
 assert subprocess.run(['git','branch','--show-current'],capture_output=True,text=True).stdout.strip()=='feature/FR-32-email-notifications'
 expected=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
 before=query('select version from supabase_migrations.schema_migrations order by version;')
 versions=[r['version']for r in before]
 assert versions==[v for v in expected if v!='202610160003'],'History differs; never replay or reset'
 jobs=query("select jobid,jobname,schedule,active,md5(command)as command_hash from cron.job order by jobid;")
 assert any(j['jobid']==4 and j['jobname']=='fr10-order-timeout'and j['active']for j in jobs)
 assert any(j['jobid']==1 and j['jobname']=='fr30-android-push'and j['active']for j in jobs)
 preview=command(['db','push','--linked','--dry-run'])
 assert sorted(set(re.findall(r'2026\d{8}_[a-z0-9_]+\.sql',preview)))==[MIGRATION],'Unexpected migration plan'
 (OUT/'migration-preview.json').write_text(json.dumps({'unapplied':[MIGRATION],'target':REF},indent=2))
 config=f.email_config()
 if not KEY_FILE.exists():KEY_FILE.write_bytes(b.crypt(secrets.token_hex(32).encode()))
 key=worker_key();assert re.fullmatch('[a-f0-9]{64}',key)
 private=OUT/'worker-secrets.env'
 try:
  private.write_text('\n'.join(k+'='+v for k,v in {**config,'FR32_EMAIL_WORKER_KEY':key}.items())+'\n')
  command(['secrets','set','--project-ref',REF,'--env-file',str(private)])
 finally:private.unlink(missing_ok=True)
 # Deploy inactive workers first. Unauthorized calls cannot reach missing RPCs.
 for name in('fr32-email-worker','fr32-invoice-url'):command(['functions','deploy',name,'--project-ref',REF,'--no-verify-jwt','--use-api'])
 check(worker('unauthorized')[0]==401,'hosted worker rejects wrong secret before privileged action')
 command(['db','push','--linked'])
 assert [r['version']for r in query('select version from supabase_migrations.schema_migrations order by version;')]==expected
 # Key is generated256-bit data, never arbitrary SQL; file is ignored and removed.
 query("begin;do $$begin if exists(select 1 from vault.secrets where name='fr32_email_worker_key')then raise exception 'Unexpected existing FR32 worker secret';end if;perform vault.create_secret('"+key+"','fr32_email_worker_key','FR32 TEST scheduler authentication');end$$;select cron.schedule('fr32-email-worker','*/2 * * * *','select fr32_private.dispatch();')where not exists(select 1 from cron.job where jobname='fr32-email-worker');update fr32_private.configuration set dispatch_enabled=true where singleton and quota_mode='rolling_26h';commit;")
 after=query("select jobid,jobname,schedule,active,md5(command)as command_hash from cron.job order by jobid;")
 assert [j for j in after if j['jobid']in(1,4)]==[j for j in jobs if j['jobid']in(1,4)],'Accepted jobs changed'
 result={'target':REF,'migration':MIGRATION,'functions':['fr32-email-worker','fr32-invoice-url'],'quota_mode':'rolling_26h','daily_budget':300,'otp_reserve':90,'worker_batch':2,'schedule':'*/2 * * * *','jobs':after,'accepted_jobs_unchanged':True,'production_touched':False}
 (OUT/'deployment.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
def verify():
 check(worker('unauthorized')[0]==401,'current hosted worker rejects wrong secret before privileged action')
 result=query("select jsonb_build_object('quota',(select to_jsonb(c)from fr32_private.configuration c),'outbox_rls',(select relrowsecurity from pg_class where oid='public.email_outbox'::regclass),'bucket_private',(select not public from storage.buckets where id='invoices'),'outbox_anon_select',has_table_privilege('anon','public.email_outbox','select'),'worker_anon_execute',has_function_privilege('anon','public.fr32_claim_email(integer)','execute'),'job_count',(select count(*)from cron.job where jobname='fr32-email-worker'),'fr10_active',(select active from cron.job where jobid=4),'fr30_active',(select active from cron.job where jobid=1))as verification;")[0]['verification']
 check(result['quota']['quota_mode']=='rolling_26h'and result['quota']['dispatch_enabled'],'approved shared quota activated')
 check(result['outbox_rls']and result['bucket_private']and not result['outbox_anon_select']and not result['worker_anon_execute'],'hosted outbox, worker RPC and invoice storage protected')
 check(result['job_count']==1 and result['fr10_active']and result['fr30_active'],'one FR32 cron; accepted FR10 and FR30 cron remain active')
 (OUT/'verification.json').write_text(json.dumps(result,indent=2))
def fixture(label,role):
 account=state['accounts'].setdefault(label,{'email':'fr32-'+label+'@example.test','password':secrets.token_urlsafe(28)+'aA7!'})
 save()
 if 'auth_id'not in account:
  status,user=b.api('/auth/v1/admin/users','POST',{'email':account['email'],'password':account['password'],'email_confirm':True,'user_metadata':{'role':role,'fr32_fixture':True}},admin=True)
  assert status in(200,201),'Synthetic TEST identity creation unconfirmed'
  account['auth_id']=user['id'];save()
 if 'profile_id'not in account:
  status,rows=b.api('/rest/v1/users','POST',{'email':account['email'],'name':'FR32 synthetic '+label,'role':role,'verification_status':'approved'},admin=True)
  assert status==201,'Synthetic TEST profile creation unconfirmed'
  account['profile_id']=rows[0]['id'];save()
 return account,b.login(account)
def fixtures():
 for label,role in [('customer','customer'),('other','customer'),('vendor','vendor'),('vendor2','vendor'),('rider','rider'),('admin','admin')]:fixture(label,role)
 check(True,'FR32 synthetic identities ready; delivery redirects only approved inbox')
 if 'order_id'not in state:
  products=[]
  for label in('vendor','vendor2'):
   status,result=b.rpc('fr17_save_product',{'p_request_id':str(uuid.uuid4()),'p_product_id':None,'p_data':{'name':'FR32 synthetic '+label,'price':80,'is_available':True},'p_stock':30,'p_threshold':5,'p_expected_version':None},b.login(state['accounts'][label]))
   assert status==200 and result['code']=='UPDATED','Canonical stocked product creation required'
   products.append(result['product_id'])
  request=str(uuid.uuid4());state['checkout_request']=request;state['product_ids']=products;save()
  status,result=b.rpc('fr10_checkout',{'p_request_id':request,'p_items':[{'product_id':products[0],'quantity':2},{'product_id':products[1],'quantity':1}],'p_delivery':{'address':'FR32 synthetic TEST only','lat':33.68,'lng':73.04,'speed':'standard'}},b.login(state['accounts']['customer']))
  check(status==200 and result['code']=='PLACED','FR32 shared checkout committed through stock-aware RPC')
  state['order_id']=result['order_id'];save()
 oid=state['order_id']
 rows=query(f"select id,status,attempts from public.email_outbox where dedupe_key='order:{oid}';")
 check(len(rows)==1,'one confirmation intent for shared checkout')
 state['confirmation_job']=rows[0]['id'];save()
 check(not query(f'select id from public.invoices where order_id={oid};'),'uncollected COD suppresses paid invoice')
def send_job(job_id):
 status,result=b.rpc('fr32_test_allow_email',{'p_ids':[job_id]},admin=True)
 assert status==200,'Explicit bounded TEST delivery approval failed'
 for _ in range(15):
  http_status,rows=b.api('/rest/v1/email_outbox?id=eq.'+job_id+'&select=status,attempts,provider_message_id,last_error',admin=True)
  assert http_status==200 and len(rows)==1,'Known TEST outbox status required'
  row=rows[0]
  if row['status']=='sent':
   check(bool(row['provider_message_id']),'provider accepted approved TEST job (inbox receipt still requires user confirmation)');return
  assert row['status']not in('failed','delivery_unknown'),'Delivery requires safe manual review: '+str(row['last_error'])
  status,result=worker();assert status in(200,503),'Protected worker request failed'
  time.sleep(2)
 raise AssertionError('Approved email still deferred; no blind resend or receipt claim')
def send_confirmation():
 assert 'confirmation_job'in state,'Prepare FR32 fixtures first'
 send_job(state['confirmation_job'])
def prepare_invoice():
 owner=b.login(state['accounts']['customer'])
 oid=state.get('invoice_order_id',state['order_id'])
 status,orders=b.api('/rest/v1/orders?id=eq.'+str(oid)+'&select=order_status',admin=True)
 assert status==200 and len(orders)==1,'Known synthetic order required'
 if 'invoice_order_id'not in state and orders[0]['order_status']=='cancelled':
  # Never manufacture a COD collection after an unpaid order was cancelled.
  p=state['product_ids']
  status,result=b.rpc('fr10_checkout',{'p_request_id':str(uuid.uuid4()),'p_items':[{'product_id':p[0],'quantity':2},{'product_id':p[1],'quantity':1}],'p_delivery':{'address':'FR32 synthetic invoice TEST','lat':33.68,'lng':73.04,'speed':'standard'}},owner)
  assert status==200 and result['code']=='PLACED','Fresh eligible synthetic checkout required'
  oid=result['order_id']
 state['invoice_order_id']=oid;save()
 # Synthetic trusted-server capture only; never presented as a real bank payment.
 status,rows=b.api('/rest/v1/payments?orderid=eq.'+str(oid)+'&select=id,status',admin=True)
 assert status==200 and len(rows)==1,'Single parent payment required'
 pid=rows[0]['id'];state['payment_id']=pid;save()
 if rows[0]['status'].upper()not in('SUCCESS','PAID','COMPLETED','SUCCEEDED'):
  assert orders[0]['order_status']!='cancelled' or oid!=state['order_id'],'Cancelled unpaid COD cannot be collected by this fixture'
  status,_=b.api('/rest/v1/payments?id=eq.'+str(pid),'PATCH',{'status':'PAID','paidat':dt.datetime.now(dt.timezone.utc).isoformat(),'paymentid':'FR32-SYNTHETIC-COLLECTION-'+str(pid)},admin=True)
  assert status==200,'Synthetic trusted collection not confirmed'
 status,rows=b.api('/rest/v1/invoices?payment_id=eq.'+str(pid)+'&select=id,invoice_number,status,failure_code',admin=True)
 assert status==200 and len(rows)==1,'One invoice required'
 status,jobs=b.api('/rest/v1/email_outbox?dedupe_key=eq.invoice:'+str(pid)+'&select=id',admin=True)
 check(status==200 and len(jobs)==1,'one invoice and intent for verified synthetic full COD collection')
 state['invoice_id']=rows[0]['id'];state['invoice_job']=jobs[0]['id'];save()
 status,_=b.api('/rest/v1/payments?id=eq.'+str(pid),'PATCH',{'status':'PAID'},admin=True);assert status==200
 status,rows=b.api('/rest/v1/invoices?payment_id=eq.'+str(pid)+'&select=id,status,failure_code',admin=True)
 check(status==200 and len(rows)==1,'duplicate success callback reuses invoice number')
 for _ in range(12):
  status,rows=b.api('/rest/v1/invoices?id=eq.'+state['invoice_id']+'&select=status,failure_code',admin=True)
  assert status==200 and len(rows)==1
  if rows[0]['status']=='ready':check(True,'hosted private PDF prepared with TEST email still suppressed');return
  assert rows[0]['status']!='failed','Invoice source needs review: '+str(rows[0]['failure_code'])
  worker();time.sleep(2)
 raise AssertionError('PDF preparation incomplete; inspect bounded safe job status, no invoice email sent')
def send_invoice():
 assert 'invoice_job'in state,'Prepare and verify the private invoice first'
 send_job(state['invoice_job'])
def invoice_access():
 oid=state['invoice_order_id'];owner=b.login(state['accounts']['customer']);other=b.login(state['accounts']['other']);admin=b.login(state['accounts']['admin'])
 for label,token,allowed in [('owner',owner,True),('admin',admin,True),('other customer',other,False)]:
  status,r=b.api('/functions/v1/fr32-invoice-url','POST',{'order_id':oid},token)
  check((status==200 and r.get('expires_in')==900)if allowed else status in(401,403),label+' private signing authorization')
  if label=='owner':
   request=urllib.request.Request(r['url'])
   with urllib.request.urlopen(request,timeout=30)as response:pdf=response.read()
   check(pdf.startswith(b'%PDF-'),'actual hosted private PDF downloaded through owner signed URL')
   (OUT/'hosted-invoice.pdf').write_bytes(pdf)
 status,_=b.api('/storage/v1/object/public/invoices/invalid.pdf')
 check(status in(400,401,403,404),'private invoice cannot be fetched as public object')
 for label in('customer','vendor','rider'):
  status,_=b.api('/rest/v1/email_outbox?select=id&limit=1',token=b.login(state['accounts'][label]))
  check(status in(401,403),label+' outbox HTTP read forbidden')
def send_account(action):
 assert action in('vendor-approved','vendor-rejected','rider-rejected','rider-verified','blocked','unblocked'),'Select a single supported account action'
 label='rider'if action.startswith('rider-')else'other'if action in('blocked','unblocked')else'vendor'
 account=state['accounts'][label];uid=account['profile_id'];token=b.login(state['accounts']['admin'])
 http_status,before=b.api('/rest/v1/email_outbox?recipient_user_id=eq.'+str(uid)+'&select=id',admin=True)
 assert http_status==200,'Known TEST action history required';seen={r['id']for r in before}
 if action in('blocked','unblocked'):
  status,result=b.api('/functions/v1/admin-user-status','POST',{'target_id':uid,'blocked':action=='blocked','request_id':str(uuid.uuid4())},token)
  assert status==200 and result.get('code')in('OK','NO_CHANGE'),'FR28 real Auth sync not confirmed'
 else:
  if action=='rider-verified':
   raw=b.image('PNG');status,result=b.upload(b.login(account),raw,'image/png')
   assert status==200,'Real synthetic CNIC storage upload required'
   status,result=b.rpc('fr04_review_rider',{'p_user_id':uid,'p_status':'approved'},token)
   assert status==200,'CNIC approval unconfirmed'
  else:
   decision='rejected'if action.endswith('rejected')else'approved'
   status,_=b.api(f'/rest/v1/users?id=eq.{uid}','PATCH',{'verification_status':decision},token)
   assert status==200,'Admin account transition unconfirmed'
 http_status,rows=b.api('/rest/v1/email_outbox?recipient_user_id=eq.'+str(uid)+'&select=id,email_type&order=created_at',admin=True)
 assert http_status==200,'Known TEST event history required'
 new=[r for r in rows if r['id']not in seen]
 assert len(new)==1,'Expected exactly one real new account-action intent'
 send_job(new[0]['id']);state['last_account_action']=action;save()
def regressions(profile='all'):
 # Reuse the exact accepted hosted suites. Older standalone SQL fixtures for
 # FR25/26/33 lack the FR28 session claims; do not weaken those production guards.
 commands=[('FR21','FR-30-run.ps1','regression21'),('FR04','FR-04-run.ps1','tests'),
  ('FR25','FR-25-run.ps1','tests'),('FR26','FR-26-run.ps1','tests'),('FR33','FR-33-run.ps1','tests'),
  ('FR28','FR-28-run.ps1','tests'),('FR20','FR-20-run.ps1','tests'),('FR30-sql','FR-30-run.ps1','sql'),
  ('FR30-http','FR-30-run.ps1','tests'),('FR30-realtime','FR-30-run.ps1','realtime'),
  ('FR10-sql','FR-10.sql',None),('FR10-http','FR-10-run.ps1','hosted'),('FR17-sql','FR-17.sql',None),('FR17-http','FR-17-run.ps1','hosted')]
 if profile=='http':commands=[c for c in commands if c[0]in('FR21','FR04','FR30-http','FR30-realtime')]
 if profile=='outstanding':commands=[c for c in commands if c[0]in('FR21','FR25','FR26','FR33')]
 results=[]
 for label,script,kind in commands:
  try:
   if kind:
    path=ROOT/'tests/integration'/script.replace('-run.ps1','-hosted.py')
    output=io.StringIO();old_args=sys.argv;exit_code=0
    try:
     sys.argv=[str(path),kind]
     with contextlib.redirect_stdout(output),contextlib.redirect_stderr(output):
      try:runpy.run_path(str(path),run_name='__main__')
      except SystemExit as e:exit_code=e.code or 0
    finally:sys.argv=old_args
    (OUT/('regression-'+label+'.log')).write_text(output.getvalue())
    assert exit_code==0,'Existing regression runner failed'
    summaries=[json.loads(line)for line in output.getvalue().splitlines()if line.startswith('{')]
    count=next((r['passed']for r in reversed(summaries)if 'passed'in r),len(summaries))
   else:
    name='FR-04.sql'if label=='FR04'else script
    source=(ROOT/'supabase/tests'/name).read_text()
    if label=='FR04':source="select set_config('fr04.test_project_ref','"+REF+"',false);\n"+source
    rows=query(source)
    counts=[len(r['results'])if isinstance(r.get('results'),list)else r.get('fr04_sql',{}).get('passed')for r in rows]
    count=next(c for c in reversed(counts)if c is not None)
   results.append({'FR':label,'result':'PASS','passed':count});print(json.dumps(results[-1]),flush=True)
  except Exception as e:
   results.append({'FR':label,'result':'FAIL','error':str(e)if isinstance(e,AssertionError)else type(e).__name__});print(json.dumps(results[-1]),flush=True)
  (OUT/('regressions-'+profile+'.json'if profile!='all'else'regressions.json')).write_text(json.dumps(results,indent=2))
 assert all(r['result']=='PASS'for r in results),'One or more existing regressions failed; inspect safe local evidence'
def main(mode,action=''):
 if mode=='preflight':preflight()
 elif mode=='inspect-otp':
  row=query("select pg_get_functiondef('public.issue_delivery_otp(bigint,uuid,uuid)'::regprocedure)as source;")[0]['source']
  (OUT/'hosted-otp-definition.sql').write_text(row)
  lines=row.splitlines();matches=[(i,line)for i,line in enumerate(lines)if 'random_bytes:='in line or 'loop'in line]
  print(json.dumps({'matches':matches,'CRLF':'\r\n'in row,'FR32_already_present':'fr32_private'in row}))
 elif mode=='review':
  assert query("select to_regnamespace('fr32_private')is null as unapplied;")[0]['unapplied'],'Review requires unapplied FR32; never replay'
  migration=re.sub(r'^begin;\s*|^commit;\s*','',(ROOT/'supabase/migrations'/MIGRATION).read_text(),flags=re.M)
  tests=(ROOT/'supabase/tests/FR-32.sql').read_text()
  result=query(tests.replace('begin;','begin;\n'+migration,1))[0]['results']
  (OUT/'hosted-review.json').write_text(json.dumps(result,indent=2));print(json.dumps({'passed':len(result),'rollback':True,'target':REF}))
 elif mode=='deploy':deploy()
 elif mode=='verify':verify()
 elif mode=='fixtures':fixtures()
 elif mode=='send-confirmation':send_confirmation()
 elif mode=='prepare-invoice':prepare_invoice()
 elif mode=='send-invoice':send_invoice()
 elif mode=='invoice-access':invoice_access()
 elif mode=='send-account':send_account(action)
 elif mode=='regressions':regressions(action or'all')
 else:raise ValueError('Action not implemented; no unchecked privileged action')
if __name__=='__main__':main(sys.argv[1],sys.argv[2]if len(sys.argv)>2 else'')
