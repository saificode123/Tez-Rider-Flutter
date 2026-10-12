"""Real TEST-only profile recovery/RLS regression; private fixture, no email sent."""
import base64,ctypes,json,os,secrets,urllib.request,urllib.error,urllib.parse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];REF='igeisilhtmglgnqvllrx';BASE='https://'+REF+'.supabase.co';PRIVATE=Path(os.environ['FR21_PRIVATE_DIRECTORY'])
class Blob(ctypes.Structure):
    _fields_=[('size',ctypes.c_ulong),('data',ctypes.POINTER(ctypes.c_ubyte))]
def crypt(data,decrypt=False):
    buf=ctypes.create_string_buffer(data);src=Blob(len(data),ctypes.cast(buf,ctypes.POINTER(ctypes.c_ubyte)));out=Blob()
    fn=ctypes.windll.crypt32.CryptUnprotectData if decrypt else ctypes.windll.crypt32.CryptProtectData
    if not fn(ctypes.byref(src),None,None,None,None,1,ctypes.byref(out)):raise RuntimeError('Private storage unavailable')
    try:return ctypes.string_at(out.data,out.size)
    finally:ctypes.windll.kernel32.LocalFree(out.data)
keys=json.loads(os.environ['FR21_TEST_KEYS_JSON'])
ANON=next(k['api_key'] for k in keys if k['name']=='anon');SERVICE=next(k['api_key'] for k in keys if k['name']=='service_role')
state=json.loads(crypt((PRIVATE/'accounts.bin').read_bytes(),True))
def target():assert (ROOT/'supabase/.temp/project-ref').read_text().strip()==REF,'Wrong target'
def request(path,method='GET',body=None,token=None,admin=False,prefer='return=representation'):
    target();key=SERVICE if admin else ANON
    req=urllib.request.Request(BASE+path,headers={'apikey':key,'Authorization':'Bearer '+(token or key),'Content-Type':'application/json','Prefer':prefer},method=method,data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req,timeout=30) as r:
            raw=r.read();return r.status,json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:return e.code,json.load(e)

file=PRIVATE/'auth-recovery-fixture.dpapi'
if file.exists():a=json.loads(crypt(file.read_bytes(),True))
else:
    a={'email':'fr21-recovery-'+secrets.token_hex(7)+'@example.test','password':secrets.token_urlsafe(24)+'aA7!'}
    file.write_bytes(crypt(json.dumps(a).encode()))
if 'id' not in a:
    status,u=request('/auth/v1/admin/users','POST',{'email':a['email'],'password':a['password'],'email_confirm':True,'user_metadata':{'role':'rider','name':'FR21 synthetic recovery','fr21_fixture':True}},admin=True)
    assert status==200 or status==201,'Synthetic Auth creation failed'
    a['id']=u['id'];file.write_bytes(crypt(json.dumps(a).encode()))
status,login=request('/auth/v1/token?grant_type=password','POST',{'email':a['email'],'password':a['password']});assert status==200
jwt=login['access_token'];body={'email':a['email'],'role':'rider','name':'FR21 synthetic recovery','verification_status':'pending'}
status,old=request('/rest/v1/users?on_conflict=email','POST',body,jwt,prefer='resolution=merge-duplicates,return=representation')
assert status==403 and old['code']=='42501','Protected email/role updates must stay denied'
status,rows=request('/rest/v1/users?email=eq.'+urllib.parse.quote(a['email'],safe='')+'&select=id,role,verification_status',token=jwt);assert status==200
if not rows:
    status,unused=request('/rest/v1/users','POST',body,jwt,prefer='return=minimal');assert status==201,'Own pending insert failed'
    status,rows=request('/rest/v1/users?email=eq.'+urllib.parse.quote(a['email'],safe='')+'&select=id,role,verification_status',token=jwt);assert status==200
assert rows[0]['role']=='rider' and rows[0]['verification_status']=='pending'
id=rows[0]['id']
status,r=request('/rest/v1/riders?userid=eq.'+str(id)+'&select=id',admin=True);assert status==200
if not r:
    status,r=request('/rest/v1/riders','POST',{'id':id,'userid':id,'presence_epoch':1,'is_online':False},admin=True);assert status==201
status,denied=request('/rest/v1/rpc/fr21_set_presence','POST',{'p_online':True,'p_epoch':1,'p_sequence':1},jwt)
assert status==403 and denied['code']=='42501','Pending rider must not go online'
print(json.dumps({'protected_upsert_denied':True,'own_pending_profile_insert_passed':True,'pending_online_denied':True}))
