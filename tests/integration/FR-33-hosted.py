"""Guarded FR-33 TEST inspection and verification; no hosted load traffic."""
import importlib.util,json,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr33_shared',Path(__file__).with_name('FR-26-hosted.py'));g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
b=g.b;ROOT=g.ROOT;OUT=ROOT/'.fr21-local/fr33';OUT.mkdir(exist_ok=True,parents=True)
def inspect():
 sql=OUT/'inspect.sql';sql.write_text("""select jsonb_build_object(
 'migrations',(select jsonb_agg(version order by version) from supabase_migrations.schema_migrations),
 'columns',(select jsonb_agg(jsonb_build_object('table',table_name,'column',column_name,'type',data_type)) from information_schema.columns where table_schema='public' and table_name in ('orders','delivery_otps','delivery_proof','security_audit_log','notifications')),
 'otp_functions',(select jsonb_agg(jsonb_build_object('name',proname,'definition',pg_get_functiondef(p.oid))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (proname like '%delivery%otp%' or proname in ('fr21_accept_order','fr21_ready_and_assign','fr21_complete_delivery'))),
 'extensions',(select jsonb_agg(jsonb_build_object('name',extname,'schema',n.nspname)) from pg_extension e join pg_namespace n on n.oid=e.extnamespace),
 'policies',(select jsonb_agg(jsonb_build_object('table',tablename,'name',policyname,'command',cmd,'using',qual,'check',with_check)) from pg_policies where schemaname='public' and tablename in ('orders','delivery_proof','delivery_otps')),
 'legacy_plaintext_counts',(select jsonb_build_object('orders',count(*) filter(where delivery_otp is not null)) from public.orders),
 'proof_plaintext_count',(select count(*) from public.delivery_proof where otp is not null)
 ) as inspection;""")
 row=g.g.query(sql)['rows'][0]['inspection'];(OUT/'schema-inspection.json').write_text(json.dumps(row,indent=2));print(json.dumps({'migrations':len(row['migrations']),'otp_table_exists':any(c['table']=='delivery_otps' for c in row['columns']),'legacy_plaintext_counts':row['legacy_plaintext_counts'],'proof_plaintext_count':row['proof_plaintext_count'],'extensions':row['extensions']}))
def email_config():
 import re
 values={}
 for line in (ROOT/'supabase/functions/.env.test.local').read_text().splitlines():
  if not line.strip() or line.lstrip().startswith('#'):continue
  key,sep,value=line.partition('=');key=key.strip();value=value.strip()
  if value[:1] in ('"',"'") and value[-1:]==value[:1]:value=value[1:-1]
  if sep and key in ('BREVO_API_KEY','BREVO_SENDER_EMAIL','BREVO_TEST_RECIPIENT'):values[key]=value
 assert all(values.get(k) for k in ('BREVO_API_KEY','BREVO_SENDER_EMAIL','BREVO_TEST_RECIPIENT')),'Private Brevo configuration incomplete'
 assert all(re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+',values[k]) for k in ('BREVO_SENDER_EMAIL','BREVO_TEST_RECIPIENT')),'Private email configuration invalid'
 return values
def preflight():
 import urllib.request,urllib.parse
 config=email_config();data={}
 for endpoint in ('senders','account'):
  request=urllib.request.Request('https://api.brevo.com/v3/'+endpoint,headers={'api-key':config['BREVO_API_KEY'],'Accept':'application/json','User-Agent':'TezRider-TEST-FR33'})
  try:
   with urllib.request.urlopen(request,timeout=20) as response:data[endpoint]=json.load(response)
  except Exception as error:
   import urllib.error
   if isinstance(error,urllib.error.HTTPError):
    try:body=json.load(error)
    except Exception:body={}
    known={'unauthorized','permission_denied','invalid_parameter','document_not_found','not_enough_credits'}
    message=str(body.get('message','')).lower()
    category='IP_AUTHORIZATION_REQUIRED' if 'ip' in message and any(t in message for t in ['unrecogn','unauthor','allow','authoriz']) else 'ACCOUNT_ACTIVATION_REQUIRED' if 'activat' in message else 'PROVIDER_ACCESS_DENIED'
    result={'endpoint':endpoint,'http_status':error.code,'provider_code':body.get('code') if isinstance(body.get('code'),str) and __import__('re').fullmatch('[a-zA-Z_]{1,40}',body['code']) else 'REDACTED','category':category,'json_response':'json' in (error.headers.get('Content-Type') or ''),'no_email_sent':True}
    (OUT/'brevo-preflight.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));return
   raise
 sender=next((s for s in data['senders'].get('senders',[]) if s.get('email','').lower()==config['BREVO_SENDER_EMAIL'].lower()),{})
 code,profiles=b.api('/rest/v1/users?email=eq.'+urllib.parse.quote(config['BREVO_TEST_RECIPIENT'].lower())+'&select=role&limit=2',admin=True)
 assert code==200,'TEST recipient profile lookup failed'
 result={'sender_found':bool(sender),'sender_active':sender.get('active') is True,'recipient_existing_roles':[p['role'] for p in profiles],'plans':[{k:p[k] for k in ('type','credits','creditsType','startDate','endDate') if k in p} for p in data['account'].get('plan',[])],'no_email_sent':True}
 (OUT/'brevo-preflight.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
def query(file):
 import subprocess,re
 b.target()
 completed=subprocess.run(['C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe','db','query','--linked','--project-ref',b.REF,'--file',str(file),'--output','json'],capture_output=True,text=True,timeout=90)
 if completed.returncode:
  match=re.search(r'ERROR:\s*(?:[A-Z0-9]{5}:\s*)?([^\r\n]+)',completed.stderr)
  message=match.group(1).split('\\n')[0].split('DETAIL:')[0] if match else 'SQL check failed'
  message=re.sub(r'[^\s]+@[^\s]+|[0-9a-f]{20,}|\b\d{6,}\b','[redacted]',message)
  raise AssertionError(message[:160])
 return json.loads(completed.stdout[completed.stdout.index('{'):])
def review():
 migration=(ROOT/'supabase/migrations/202610140001_fr33_email_delivery_otp.sql').read_text()
 import re
 migration=re.sub(r'^begin;\s*','',migration,flags=re.M);migration=re.sub(r'^commit;\s*','',migration,flags=re.M)
 rules=(ROOT/'supabase/tests/FR-33.sql').read_text();rules=re.sub(r'^begin;\s*','',rules,flags=re.M);rules=re.sub(r'^rollback;\s*','',rules,flags=re.M)
 file=OUT/'review.sql';file.write_text('begin;\n'+migration+'\n'+rules+'\nrollback;')
 result=query(file);print(json.dumps({'passed':len(result['rows'][0]['results']),'rolled_back':True}));(OUT/'migration-review.json').write_text(json.dumps(result,indent=2))
def deploy():
 import subprocess,re
 exe='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
 expected='202610140001_fr33_email_delivery_otp.sql'
 file=OUT/'history.sql';file.write_text('select version from supabase_migrations.schema_migrations order by version;')
 versions=[row['version'] for row in query(file)['rows']]
 assert versions==sorted(p.name.split('_')[0] for p in (ROOT/'supabase/migrations').glob('*.sql') if p.name!=expected),'Existing accepted migrations differ'
 assert (ROOT/'supabase/.temp/pooler-url').exists() and b.REF in (ROOT/'supabase/.temp/pooler-url').read_text(),'TEST pooler reference required'
 def command(args):
  b.target();completed=subprocess.run([exe,*args],cwd=ROOT,capture_output=True,text=True,timeout=180)
  assert completed.returncode==0,'Guarded TEST deployment command failed'
  return completed.stdout+completed.stderr
 preview=command(['db','push','--linked','--dry-run','--output','json'])
 metadata={'migrations':sorted(set(re.findall(r'2026\d{8}_[a-z0-9_]+\.sql',preview))),'dry_run':True};assert metadata['migrations']==[expected],'Unexpected migration plan'
 (OUT/'migration-preview.json').write_text(json.dumps(metadata,indent=2))
 # Three approved TEST-only values; the ignored original file is never printed.
 email_config()
 secret_names=[]
 for line in (ROOT/'supabase/functions/.env.test.local').read_text().splitlines():
  if line.strip() and not line.lstrip().startswith('#'):secret_names.append(line.partition('=')[0].strip())
 assert sorted(secret_names)==['BREVO_API_KEY','BREVO_SENDER_EMAIL','BREVO_TEST_RECIPIENT'],'Unexpected private secret file fields'
 command(['secrets','set','--project-ref',b.REF,'--env-file','supabase/functions/.env.test.local'])
 applied=command(['db','push','--linked','--output','json']);assert sorted(set(re.findall(r'2026\d{8}_[a-z0-9_]+\.sql',applied)))==[expected],'Migration application mismatch'
 assert [row['version'] for row in query(file)['rows']]==sorted(p.name.split('_')[0] for p in (ROOT/'supabase/migrations').glob('*.sql')),'Post-application history mismatch'
 command(['functions','deploy','send-delivery-otp','--project-ref',b.REF,'--no-verify-jwt'])
 result={'project_ref':b.REF,'applied':[expected],'edge_function':'send-delivery-otp','private_secrets_configured':True,'jwt_authentication':'Explicit Auth /user validation plus assigned-rider RPC authorization','hmac_secret':'Vault-generated FR33-only key; no prior keys modified','production_access':False}
 (OUT/'deployment.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
STATE=b.PRIVATE/'fr33-accounts.bin'
state=json.loads(b.crypt(STATE.read_bytes(),True)) if STATE.exists() else {'accounts':{},'orders':{}}
checks=[]
ACTOR="rider"
def save():STATE.write_bytes(b.crypt(json.dumps(state).encode()))
def check(ok,label):
 assert ok,label
 record={'time':__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(),'result':'PASS','check':label};checks.append(record);print(json.dumps(record),flush=True)
 with (OUT/'checks.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
def fixture(label,role):
 import secrets
 config=email_config();account=state['accounts'].setdefault(label,{'email':config['BREVO_TEST_RECIPIENT'] if label=='customer' else 'fr33-'+label+'@example.test','password':secrets.token_urlsafe(28)+'aA7!'});save()
 if label=='customer' and 'auth_id' not in account:account['email']=config['BREVO_TEST_RECIPIENT'].lower();save()
 if 'auth_id' not in account:
  code,user=b.api('/auth/v1/admin/users','POST',{'email':account['email'],'password':account['password'],'email_confirm':True,'user_metadata':{'name':'FR33 synthetic '+label,'role':role,'fr33_fixture':True}},admin=True)
  if code not in (200,201):
   message=str(user.get('msg',user.get('message',user.get('error_description','')))).lower() if isinstance(user,dict) else ''
   category='ACCOUNT_EXISTS' if any(x in message for x in ['already','registered','exists']) else 'INVALID_EMAIL' if 'email' in message and any(x in message for x in ['invalid','validat']) else 'AUTH_PROVIDER_REJECTED'
   raise AssertionError('Synthetic TEST account creation denied: status '+str(code)+', '+category+'; no existing account changed')
  account['auth_id']=user['id'];save()
 if 'profile_id' not in account:
  code,rows=b.api('/rest/v1/users','POST',{'email':account['email'],'name':'FR33 synthetic '+label,'role':role,'verification_status':'approved' if role in ('rider','admin') else 'pending'},admin=True);assert code==201
  account['profile_id']=rows[0]['id'];save()
  if role=='rider':
   code,_=b.api('/rest/v1/riders','POST',{'userid':account['profile_id'],'is_online':False},admin=True);assert code==201
 return account,b.login(account)
def fixtures():
 for label,role in [('customer','customer'),('rider','rider'),('other-rider','rider'),('vendor','vendor'),('admin','admin')]:fixture(label,role)
 check(True,'protected synthetic TEST accounts ready; only authorized recipient configured')
def security_fixtures():
 for label,role in [('security-customer','customer'),('rider','rider'),('other-rider','rider'),('vendor','vendor'),('admin','admin')]:fixture(label,role)
 check(True,'synthetic security fixtures ready; no SMTP request')
def order(label,real=False):
 rider=state['accounts'][ACTOR];customer=state['accounts']['customer' if real else 'security-customer']
 code,rows=b.api('/rest/v1/orders','POST',{'user_id':customer['profile_id'],'rider_id':rider['profile_id'],'order_status':'on_the_way','amount':25,'payment_method':'COD','delivery_address':'FR33 SYNTHETIC TEST ONLY'},admin=True);assert code==201
 state['orders'][label]=rows[0]['id'];save();return rows[0]['id']
def simulated_issue(order_id):
 import uuid
 rider=state['accounts'][ACTOR];id=str(uuid.uuid4());code,data=b.rpc('issue_delivery_otp',{'p_order_id':order_id,'p_request_id':id,'p_actor':rider['auth_id']},admin=True);assert code==200 and data.get('code')=='SEND','Protected mock-provider fixture issuance failed'
 code,start=b.rpc('fr33_start_send',{'p_id':id},admin=True);assert code==200 and start is True
 code,result=b.rpc('fr33_finish_send',{'p_id':id,'p_result':'ACCEPTED','p_provider_id':'FR33-SECURITY-TEST-MOCK-PROVIDER'},admin=True);assert code==200 and result['code']=='EMAIL_ACCEPTED'
 return id,data['otp']
def verify_call(token,order_id,value,request):return b.rpc('verify_delivery_otp',{'p_order_id':order_id,'p_otp':value,'p_request_id':request},token)
def effects(order_id):
 code,proof=b.api('/rest/v1/delivery_proof?orderid=eq.'+str(order_id)+'&select=id,otpconfirmed,otp&limit=2',admin=True);check(code==200 and len(proof)==1 and proof[0]['otpconfirmed'] is True and proof[0]['otp'] is None,'one protected delivery proof for '+str(order_id))
 code,audit=b.api('/rest/v1/security_audit_log?target_type=eq.order&target_id=eq.'+str(order_id)+'&action=eq.delivery_completed&select=id&limit=2',admin=True);check(code==200 and len(audit)==1,'one completion audit for '+str(order_id))
def tests():
 global ACTOR
 ACTOR='security-rider'
 fixture(ACTOR,'rider')
 import uuid,concurrent.futures,threading
 tokens={label:b.login(account) for label,account in state['accounts'].items() if 'auth_id' in account};rider=state['accounts'][ACTOR];tokens['rider']=tokens[ACTOR];d=order('security');issuance,value=simulated_issue(d)
 for label in ('security-customer','other-rider','vendor','admin'):
  code,result=verify_call(tokens[label],d,value,str(uuid.uuid4()));check(code==200 and result['code']=='FORBIDDEN',label+' cannot verify another assigned delivery')
  code,_=b.api('/rest/v1/delivery_otps?select=id&limit=1',token=tokens[label]);check(code in (401,403),'no direct OTP SELECT for '+label)
  code,_=b.rpc('issue_delivery_otp',{'p_order_id':d,'p_request_id':str(uuid.uuid4()),'p_actor':rider['auth_id']},tokens[label]);check(code in (401,403),label+' cannot invoke privileged issuance')
  code,data=b.api('/functions/v1/send-delivery-otp','POST',{'order_id':d,'request_id':str(uuid.uuid4())},tokens[label]);check(code==403 and data.get('code')=='FORBIDDEN',label+' cannot send delivery email')
 code,_=verify_call(None,d,value,str(uuid.uuid4()));check(code in (401,403),'anonymous verify denied')
 code,_=b.api('/functions/v1/send-delivery-otp','POST',{'order_id':d,'request_id':str(uuid.uuid4())});check(code==401,'anonymous email request denied')
 code,safe=b.rpc('delivery_otp_status',{'p_order_id':d},tokens['rider']);check(code==200 and safe['code']=='EMAIL_ACCEPTED' and not any(k in safe for k in ('otp','recipient','nonce','verifier')),'authorized public status has no code/verifier/full recipient')
 wrong='111111' if value=='000000' else '000000';request=str(uuid.uuid4());code,invalid=verify_call(tokens['rider'],d,wrong,request);check(code==200 and invalid['remaining']==2,'wrong code consumes exactly one attempt')
 code,retry=verify_call(tokens['rider'],d,wrong,request);check(code==200 and retry['replayed'] and retry['remaining']==2,'network retry preserves remaining attempts')
 for remaining in (1,0):
  code,result=verify_call(tokens['rider'],d,wrong,str(uuid.uuid4()));check(code==200 and result['remaining']==remaining,'persisted remaining '+str(remaining))
 code,rows=b.api('/rest/v1/orders?id=eq.'+str(d)+'&select=otp_admin_review,order_status,delivery_otp&limit=1',admin=True);check(code==200 and rows[0]['otp_admin_review'] and rows[0]['order_status']=='on_the_way' and rows[0]['delivery_otp'] is None,'lockout preserves active order and flags admin review')
 code,notices=b.api('/rest/v1/notifications?delivery_otp_id=eq.'+issuance+'&type=eq.otp_review&select=id&limit=2',admin=True);check(code==200 and len(notices)==1,'one hosted admin lockout notice')
 for label,modes in [('correct-correct',['correct','correct']),('correct-wrong',['correct','wrong']),('wrong-wrong',['wrong','wrong'])]:
  target=order(label);_,secret=simulated_issue(target);bad='111111' if secret=='000000' else '000000';barrier=threading.Barrier(2)
  def compete(mode):barrier.wait(timeout=10);return verify_call(tokens['rider'],target,secret if mode=='correct' else bad,str(uuid.uuid4()))
  with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:outcomes=list(pool.map(compete,modes))
  check(all(status==200 for status,_ in outcomes),label+' genuine separate-request race returns structured outcomes')
  codes=[row['code'] for _,row in outcomes]
  if label=='correct-correct':check(sorted(codes)==['ALREADY_DELIVERED','OK'],'one correct race winner');effects(target)
  elif label=='correct-wrong':check(codes[0]=='OK' and codes[1] in ('INVALID','ALREADY_DELIVERED'),'correct/wrong race safe outcome');effects(target)
  else:check(sorted(row['remaining'] for _,row in outcomes)==[1,2],'two concurrent wrong entries both persist')
 target=order('issuance-race');barrier=threading.Barrier(2)
 def reserve(_):barrier.wait(timeout=10);return b.rpc('issue_delivery_otp',{'p_order_id':target,'p_request_id':str(uuid.uuid4()),'p_actor':rider['auth_id']},admin=True)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:outcomes=list(pool.map(reserve,range(2)))
 check(sorted(row['code'] for _,row in outcomes)==['EMAIL_PENDING','SEND'],'concurrent issuance reserves once')
 reserved=next(row for _,row in outcomes if row['code']=='SEND');b.rpc('fr33_start_send',{'p_id':reserved['issuance_id']},admin=True);b.rpc('fr33_finish_send',{'p_id':reserved['issuance_id'],'p_result':'FAILED'},admin=True)
 target=order('issue-verify-race');old_issue,secret=simulated_issue(target)
 import datetime as dt
 code,_=b.api('/rest/v1/delivery_otps?id=eq.'+old_issue,'PATCH',{'created_at':(dt.datetime.now(dt.timezone.utc)-dt.timedelta(seconds=61)).isoformat()},admin=True);assert code==200
 barrier=threading.Barrier(2)
 def racing(kind):
  barrier.wait(timeout=10)
  if kind=='verify':return verify_call(tokens['rider'],target,secret,str(uuid.uuid4()))
  return b.rpc('issue_delivery_otp',{'p_order_id':target,'p_request_id':str(uuid.uuid4()),'p_actor':rider['auth_id']},admin=True)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:outcomes=list(pool.map(racing,['verify','issue']))
 check(outcomes[0][0]==200 and outcomes[0][1]['code']=='OK' and outcomes[1][1]['code'] in ('ALREADY_DELIVERED','SEND'),'issuance versus verification retains one completion');effects(target)
 (OUT/'hosted-tests.json').write_text(json.dumps({'project_ref':b.REF,'passed':len(checks),'failed':0,'real_emails_sent':0,'provider_acceptance':'Explicit privileged mock fixtures for backend security tests only','checks':checks},indent=2))
 print(json.dumps({'passed':len(checks),'real_emails_sent':0}))
def sql():
 result=query(ROOT/'supabase/tests/FR-33.sql');rows=result['rows'][0]['results'];assert all(r['result']=='PASS' for r in rows)
 (OUT/'sql-results.json').write_text(json.dumps(rows,indent=2));print(json.dumps({'passed':len(rows),'rolled_back':True}))
def verify():
 file=OUT/'verify.sql';file.write_text("""select jsonb_build_object(
 'versions',(select jsonb_agg(version order by version) from supabase_migrations.schema_migrations),
 'functions',(select jsonb_agg(jsonb_build_object('name',proname,'path',proconfig,'anon',has_function_privilege('anon',p.oid,'execute'),'authenticated',has_function_privilege('authenticated',p.oid,'execute'),'service',has_function_privilege('service_role',p.oid,'execute'))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname in ('issue_delivery_otp','verify_delivery_otp','fr33_tag','fr33_equal','fr33_start_send','fr33_finish_send','delivery_otp_status')),
 'tables',(select jsonb_agg(jsonb_build_object('name',c.relname,'rls',c.relrowsecurity,'client_read',has_table_privilege('authenticated',c.oid,'SELECT'),'client_insert',has_table_privilege('authenticated',c.oid,'INSERT'))) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('delivery_otps','delivery_otp_verifications','delivery_otp_rates','delivery_otp_budgets','orders','delivery_proof','notifications','security_audit_log')),
 'plain_order_count',(select count(*) from public.orders where delivery_otp is not null),
 'plain_proof_count',(select count(*) from public.delivery_proof where otp is not null),
 'published_secret_tables',(select count(*) from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename in ('delivery_otps','delivery_otp_verifications')),
 'vault_client_read',has_table_privilege('authenticated','vault.decrypted_secrets','SELECT')
 ) as verified;""")
 result=query(file)['rows'][0]['verified'];check(result['versions']==sorted(p.name.split('_')[0] for p in (ROOT/'supabase/migrations').glob('*.sql')),'all repository migration versions match; accepted features intact')
 check(all('search_path=""' in (f['path'] or []) and not f['anon'] for f in result['functions']),'fixed search paths and anonymous RPC execution denied')
 check(all(f['authenticated']==(f['name'] in ('verify_delivery_otp','delivery_otp_status')) for f in result['functions']),'only safe status and verification executable by clients')
 check(all(t['rls'] for t in result['tables']),'RLS enabled on all touched application tables')
 check(all(not t['client_read'] and not t['client_insert'] for t in result['tables'] if t['name'].startswith('delivery_otp')),'no client access to protected OTP tables')
 check(result['plain_order_count']==0 and result['plain_proof_count']==0,'no persisted plaintext legacy OTPs')
 check(result['published_secret_tables']==0 and not result['vault_client_read'],'OTP secrets absent from Realtime and Vault denied to clients')
 (OUT/'schema-verification.json').write_text(json.dumps(result,indent=2))
def recovery_review():
 import re
 migration=(ROOT/'supabase/migrations/202610140002_fr33_dispatch_recovery.sql').read_text();migration=re.sub(r'^begin;\s*','',migration,flags=re.M);migration=re.sub(r'^commit;\s*','',migration,flags=re.M)
 rules=(ROOT/'supabase/tests/FR-33.sql').read_text();rules=re.sub(r'^begin;\s*','',rules,flags=re.M);rules=re.sub(r'^rollback;\s*','',rules,flags=re.M)
 file=OUT/'recovery-review.sql';file.write_text('begin;\n'+migration+'\n'+rules+'\nrollback;')
 result=query(file);(OUT/'recovery-review.json').write_text(json.dumps(result,indent=2));print(json.dumps({'passed':len(result['rows'][0]['results']),'rolled_back':True}))
def recovery_apply():
 import subprocess,re
 expected='202610140002_fr33_dispatch_recovery.sql';file=OUT/'history.sql';file.write_text('select version from supabase_migrations.schema_migrations order by version;')
 assert [row['version'] for row in query(file)['rows']]==sorted(p.name.split('_')[0] for p in (ROOT/'supabase/migrations').glob('*.sql') if p.name!=expected),'Existing history mismatch'
 def run(dry):
  b.target();args=['C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe','db','push','--linked']+(['--dry-run'] if dry else [])
  result=__import__('subprocess').run(args,capture_output=True,text=True,timeout=120);assert result.returncode==0,'TEST recovery migration command failed'
  assert sorted(set(re.findall(r'2026\d{8}_[a-z0-9_]+\.sql',result.stdout+result.stderr)))==[expected],'Unexpected migration sequence'
 run(True);run(False)
 check([row['version'] for row in query(file)['rows']]==sorted(p.name.split('_')[0] for p in (ROOT/'supabase/migrations').glob('*.sql')),'dispatch recovery applied once; all accepted migrations preserved')
def refresh_config():
 import subprocess
 config=email_config();temporary=b.PRIVATE/'fr33-recipient.tmp'
 try:
  temporary.write_text('BREVO_TEST_RECIPIENT='+json.dumps(config['BREVO_TEST_RECIPIENT'])+'\n')
  b.target();result=subprocess.run(['C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe','secrets','set','--project-ref',b.REF,'--env-file',str(temporary)],capture_output=True,text=True,timeout=90);assert result.returncode==0,'TEST recipient configuration failed'
  b.target();result=subprocess.run(['C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe','functions','deploy','send-delivery-otp','--project-ref',b.REF,'--no-verify-jwt'],capture_output=True,text=True,timeout=120);assert result.returncode==0,'Updated TEST function deployment failed'
  check(True,'authorized recipient updated and latest authenticated TEST Edge Function deployed; no email sent')
 finally:temporary.unlink(missing_ok=True)
def git_safety():
 import subprocess
 config=email_config();private=list(config.values())+[b.SERVICE]
 for source in (state['accounts'],b.state.get('accounts',{}),g.state.get('accounts',{})):
  for account in source.values():
   for key in ('password','email'):
    if account.get(key):private.append(account[key])
 names=subprocess.run(['git','diff','--name-only'],capture_output=True,text=True,check=True).stdout.splitlines()+subprocess.run(['git','ls-files','--others','--exclude-standard'],capture_output=True,text=True,check=True).stdout.splitlines()
 for name in set(names):
  file=ROOT/name
  assert file.is_file() and file.stat().st_size<=5*1024*1024,'Unexpected large/nonfile Git candidate'
  assert not any(x in name.lower() for x in ('.env','.apk','.dpapi','build/','.bin')),'Private/build Git candidate'
  data=file.read_bytes();assert all(value.encode() not in data for value in private),'Private account/configuration value found in Git candidate'
 result={'checked_files':len(set(names)),'private_values_absent':True,'maximum_candidate_bytes':max((ROOT/n).stat().st_size for n in set(names)),'branch':subprocess.run(['git','branch','--show-current'],capture_output=True,text=True,check=True).stdout.strip(),'env_ignored':subprocess.run(['git','check-ignore','supabase/functions/.env.test.local'],capture_output=True).returncode==0}
 assert result['branch']=='feature/FR-33-email-delivery-otp' and result['env_ignored'];(OUT/'git-safety.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))

def artifact():
 import hashlib,zipfile,subprocess
 mirror=Path('C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-auth-debug/android-build-20261012-125502')
 sources=list((ROOT/'lib').rglob('*.dart'))
 assert all((mirror/p.relative_to(ROOT)).read_bytes()==p.read_bytes() for p in sources),'APK build mirror differs from current Dart source'
 apk=OUT/'TezRider-FR33-Test-debug.apk';assert apk.exists()
 private=list(email_config().values())+[b.SERVICE]
 for account in state['accounts'].values():private.append(account['password'])
 with zipfile.ZipFile(apk) as archive:
  payload=b''.join(archive.read(n) for n in archive.namelist() if not n.endswith('/'))
 assert b.BASE.encode() in payload,'Compiled APK lacks TEST target'
 assert b'https://arrqsvejrfdbacfwtpcc.supabase.co' not in payload,'Forbidden production target in compiled APK'
 assert all(value.encode() not in payload for value in private),'Private fixture/configuration leaked into APK'
 manifest=subprocess.run(['C:/Users/urreh/AppData/Local/Android/Sdk/build-tools/36.0.0/aapt.exe','dump','badging',str(apk)],capture_output=True,text=True,timeout=30)
 assert manifest.returncode==0 and "package: name='com.example.flutter_application_1.fr21test'" in manifest.stdout,'Separate TEST package required'
 result={'package':'com.example.flutter_application_1.fr21test','project_ref':b.REF,'source_files_matched':len(sources),'apk_sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'apk_bytes':apk.stat().st_size,'private_credentials_absent':True,'production_url_absent':True}
 (OUT/'artifact-verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))

if __name__=='__main__':
 try:{'device':lambda:exec(compile((ROOT/'tests/integration/FR-33-device.py').read_text(),str(ROOT/'tests/integration/FR-33-device.py'),'exec'),{'backend':sys.modules[__name__]}),'git-safety':git_safety,'artifact':artifact,'inspect':inspect,'preflight':preflight,'review':review,'deploy':deploy,'fixtures':fixtures,'security-fixtures':security_fixtures,'tests':tests,'sql':sql,'verify':verify,'recovery-review':recovery_review,'recovery-apply':recovery_apply,'refresh-config':refresh_config}[sys.argv[1]]()
 except Exception as e:print(json.dumps({'failed':1,'error_type':type(e).__name__,'reason':str(e) if isinstance(e,AssertionError) else 'Guarded TEST check failed'}));sys.exit(1)
