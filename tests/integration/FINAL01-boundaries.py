"""Controlled TEST boundary checks on the new marked synthetic fixture only.

Seeds only the new counter to99 (two requests, never a load test). Ages exactly
one newly created synthetic session to test authorization, not provider expiry.
"""
import base64,concurrent.futures,importlib.util,json,re,urllib.request,urllib.error,uuid,sys
from pathlib import Path
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
b=module('b','FR-04-hosted.py');d=module('d','FINAL-security.py');b.target();OUT=b.ROOT/'.fr21-local/final01';checks=[]
enforced=sys.argv[1:]==['enforced']
if enforced:assert (OUT/'deployment-202610220004.json').exists()
a=json.loads(b.crypt((b.PRIVATE/'final01-workflow.bin').read_bytes(),True));uid=str(uuid.UUID(a['auth_id']))
assert a['email'].startswith('final01-')and a['email'].endswith('@example.test')
def check(ok,label):
 assert ok,label
 checks.append({'check':label,'result':'PASS'})
 (OUT/('boundary-enforced-results.json' if enforced else 'boundary-results.json')).write_text(json.dumps(checks,indent=2),encoding='utf-8')
 print(json.dumps(checks[-1]),flush=True)
def sql(source):
 p=OUT/'boundary-operation.private.sql';p.write_text(source,encoding='utf-8');return d.query(p)
def request(path,body,token):
 req=urllib.request.Request(b.BASE+path,method='POST',headers={'apikey':b.ANON,'Authorization':'Bearer '+token,'Content-Type':'application/json'},data=json.dumps(body).encode())
 try:
  with urllib.request.urlopen(req,timeout=45)as r:return r.status,dict(r.headers),json.load(r)
 except urllib.error.HTTPError as e:return e.code,dict(e.headers),json.load(e)
def envelope():return {'method':'GET','path':'/users','query':'select=id&limit=1','headers':{},'body':''}
token=b.login(a);code,context=b.rpc('final01_authorize_request',{},token);check(code==200 and context['code']=='OK','fresh synthetic session authorized before concurrency probe')
rows=sql("begin;update final1_private.request_limits q set used=99,window_at=clock_timestamp()from auth.users u where q.actor=u.id and u.id='"+uid+"'::uuid and u.raw_user_meta_data->>'final01_fixture'='true' returning q.used;commit;")
check(len(rows)==1 and rows[0]['used']==99,'only marked fixture new counter seeded at99')
with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
 futures=[pool.submit(request,'/functions/v1/security-gateway',envelope(),token),pool.submit(request,'/functions/v1/shopping-assistant',{'prompt':'Question','actor':'forbidden'},token)]
 responses=[f.result()for f in futures]
check(sum(r[0]==429 for r in responses)==1 and sum(r[0]in(200,400)for r in responses)==1,'REST and Edge concurrently share last remaining request without overshoot')
limited=next(r for r in responses if r[0]==429)
check(any(k.lower()=='retry-after'and int(v)>0 for k,v in limited[1].items()),'shared quota denial includes positive Retry-After')
rows=sql("begin read only;select used from final1_private.request_limits where actor='"+uid+"'::uuid;rollback;")
check(rows==[{'used':100}],'atomic persisted request cap is exactly100')
# Verify private media with an existing approved synthetic rider document.
accounts=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts'];admin=b.login(accounts['admin'])
rider=b.fr04['accounts']['rider-a'];assert rider['email'].startswith('fr04-')and rider['email'].endswith('@example.test')
code,value=b.api('/functions/v1/fr04-cnic','POST',{'action':'view','user_id':rider['profile_id']},admin)
check(code==200 and 0<value['expires_in']<=900,'authorized private CNIC URL has capped lifetime')
with urllib.request.urlopen(value['url'],timeout=30)as response:check(response.status==200 and len(response.read())>0,'authorized private CNIC URL retrieves real protected bytes')
for role in('customer','vendor'):
 t=b.login(accounts[role]);code,_=b.api('/functions/v1/fr04-cnic','POST',{'action':'view','user_id':rider['profile_id']},t)
 check(code==403,role+': unrelated private CNIC URL denied')
# Fresh login creates a different session; no existing acceptance/device session aged.
code,session=b.api('/auth/v1/token?grant_type=password','POST',{'email':a['email'],'password':a['password']});assert code==200
fresh=session['access_token'];payload=fresh.split('.')[1];claims=json.loads(base64.urlsafe_b64decode(payload+'='*(-len(payload)%4)));sid=str(uuid.UUID(claims['session_id']))
rows=sql("begin;update auth.sessions s set created_at=clock_timestamp()-interval '168 hours 1 second'from auth.users u where s.user_id=u.id and u.id='"+uid+"'::uuid and u.raw_user_meta_data->>'final01_fixture'='true'and s.id='"+sid+"'::uuid and s.created_at>clock_timestamp()-interval '5 minutes' returning s.id is not null as changed;commit;")
check(rows==[{'changed':True}],'controlled clock test ages exactly one fresh marked session')
code,_,value=request('/functions/v1/security-gateway',envelope(),fresh)
check(code==401 and value['code']=='FR28_SESSION_REVOKED','otherwise unexpired access JWT loses application authorization beyond168hours')
code,refreshed=b.api('/auth/v1/token?grant_type=refresh_token','POST',{'refresh_token':session['refresh_token']})
if code==200:
 code,_,value=request('/functions/v1/security-gateway',envelope(),refreshed['access_token'])
 check(code==401 and value['code']=='FR28_SESSION_REVOKED','provider refresh cannot extend approved application authorization deadline')
else:check(code in(400,401,403),'provider independently rejects old controlled session refresh')
check(True,'controlled timestamp test is not seven-day wall-clock or provider refresh-expiry evidence')
print(json.dumps({'TEST':b.REF,'checks':len(checks),'concurrent_requests':2,'provider_spend':0,'post_activation':enforced}))
