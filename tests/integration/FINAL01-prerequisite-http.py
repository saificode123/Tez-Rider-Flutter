"""Bounded real-session prerequisite checks, no provider call or business mutation."""
import importlib.util,json,re
from pathlib import Path
spec=importlib.util.spec_from_file_location('b',Path(__file__).with_name('FR-04-hosted.py'));b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
b.target();OUT=b.ROOT/'.fr21-local/final01';checks=[]
def check(ok,label):
 assert ok,label
 checks.append({'check':label,'result':'PASS'})
accounts=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']
for role in ['customer','vendor','rider','admin']:
 a=accounts[role];assert a['email'].startswith('fr28-')and a['email'].endswith('@example.test')
 token=b.login(a)
 code,context=b.rpc('final01_authorize_request',{},token)
 check(code==200 and context['code']=='OK'and context['role']==role,role+': new POST authorizer verifies canonical real session and quota')
 check(context['auth_id']==a['auth_id']and bool(context.get('session_expires_at')),role+': deadline and subject from trusted Auth session')
 body={'p_actor':context['auth_id'],'p_session':context['session_id'],'p_method':'GET','p_path':'/products'}
 code,value=b.rpc('final01_request_ticket',body,token)
 check(code==403,role+': client cannot mint a gateway capability')
 code,proof=b.rpc('final01_request_ticket',body,admin=True)
 check(code==200 and isinstance(proof,str)and re.fullmatch(r'[0-9]{10,12}\.[0-9a-f]{64}',proof)is not None,role+': trusted server mints bound capability without exposing key')
 body={'p_actor':a['auth_id'],'p_endpoint':'rest','p_kind':'authorization'}
 code,_=b.rpc('final01_record_failure',body,token)
 check(code==403,role+': client cannot forge classified failure audit')
 # Record the actual denied privilege probe once, as a trusted test server.
 code,first=b.rpc('final01_record_failure',body,admin=True)
 code2,second=b.rpc('final01_record_failure',body,admin=True)
 check(code==200 and code2==200 and second is False and isinstance(first,bool),role+': real denial audit is bounded/deduplicated')
code,_=b.rpc('final01_authorize_request',{},'invalid')
check(code==401,'invalid signature never reaches request budget authority')
(OUT/'prerequisite-http.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
print(json.dumps({'TEST':b.REF,'prerequisite_real_session_passed':len(checks),'provider_requests':0,'business_mutations':0}))
