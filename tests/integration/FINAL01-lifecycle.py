"""Real block/unblock/revocation checks on the new cancelled-order fixture only."""
import importlib.util,json,uuid,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('b',Path(__file__).with_name('FR-04-hosted.py'));b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
b.target();OUT=b.ROOT/'.fr21-local/final01';a=json.loads(b.crypt((b.PRIVATE/'final01-workflow.bin').read_bytes(),True));assert a.get('cancelled')and a['email'].startswith('final01-')and a['email'].endswith('@example.test');checks=[]
enforced=sys.argv[1:]in(['enforced'],['enforced-physical'])
physical=sys.argv[1:]==['enforced-physical']
if enforced:assert (OUT/'deployment-202610220004.json').exists()
if physical:
 spec=importlib.util.spec_from_file_location('native',Path(__file__).with_name('FINAL01-native.py'));native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native)
 native.main('assert:Search food, stores, cuisines...')
accounts=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts'];admin=b.login(accounts['admin']);customer=b.login(a)
def check(ok,label):
 assert ok,label
 checks.append({'check':label,'result':'PASS'})
 (OUT/('lifecycle-enforced-results.json'if enforced else'lifecycle-results.json')).write_text(json.dumps(checks,indent=2),encoding='utf-8')
 print(json.dumps(checks[-1]),flush=True)
def gateway(token):return b.api('/functions/v1/security-gateway','POST',{'method':'GET','path':'/users','query':'select=id&limit=1','headers':{},'body':''},token)
def block(value):
 operation=str(uuid.uuid4())
 body={'target_id':a['profile_id'],'blocked':value,'request_id':operation}
 code,result=b.api('/functions/v1/admin-user-status','POST',body,admin)
 check(code==200 and result.get('is_blocked')is value and result.get('code')!='AUTH_SYNC_PENDING','Admin '+('block'if value else 'unblock')+' confirmed by synchronized server response')
 return operation,body
# Always attempt the authorized unblock even if the block response is lost.
# No fixture deletion or pre-existing account target.
code,profile=b.api('/rest/v1/users?id=eq.'+str(a['profile_id'])+'&select=is_blocked',admin=True)
assert code==200 and profile==[{'is_blocked':False}],'Marked fixture must start confirmed active'
blocked=False
try:
 blocked=True;operation,body=block(True)
 if physical:
  native.main('launch');native.main('assert:Sign in as Customer')
  native.record('post-enforcement marked-customer block routed physical app to sign-in')
  check(True,'physical marked-customer session denied after confirmed server block')
 code,result=gateway(customer)
 check(code in(401,403),'blocked/revoked pre-block JWT loses gateway access')
 code,_=b.api('/auth/v1/token?grant_type=password','POST',{'email':a['email'],'password':a['password']})
 check(code in(400,401,403),'provider refuses password login while synthetic customer blocked')
 code,replay=b.api('/functions/v1/admin-user-status','POST',body,admin)
 check(code==200 and replay.get('is_blocked')is True,'block request replay remains idempotent')
 code,rows=b.api('/rest/v1/security_audit_log?user_operation_id=eq.'+operation+'&select=id,action',admin=True)
 check(code==200 and len(rows)==1,'trusted accounting read confirms exactly one committed Admin block audit')
finally:
 if blocked:block(False)
fresh=b.login(a)
code,result=b.rpc('final01_authorize_request',{},fresh)
check(code==200 and result['code']=='OK','fresh password login after unblock receives live application authorization')
code,_=b.api('/auth/v1/logout?scope=local','POST',token=fresh)
check(code in(200,204),'normal provider logout confirms fresh synthetic session revoked')
code,result=gateway(fresh)
check(code==401 and result['code']=='FR28_SESSION_REVOKED','otherwise valid access JWT denied after server session revocation')
if physical:
 native.main('login:final01');native.main('assert:Search food, stores, cuisines...')
 native.main('bounds:[66,170][192,296]');native.main('tap:Sign Out');native.main('assert:Sign in as Customer')
 check(True,'physical password login after unblock restores catalogue and normal logout returns to sign-in')
code,profile=b.api('/rest/v1/users?id=eq.'+str(a['profile_id'])+'&select=is_blocked',admin=True)
assert code==200 and profile==[{'is_blocked':False}],'Final marked fixture unblock must be confirmed'
print(json.dumps({'TEST':b.REF,'checks':len(checks),'only_new_marked_fixture':True,'physical_device_test':physical,'post_activation':enforced,'fixture_confirmed_active':True,'provider_spend':0}))
