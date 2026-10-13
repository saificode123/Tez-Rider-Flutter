"""Real TEST Auth/Storage/FR-04 checks. No private values are printed."""
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

import datetime as dt,io,subprocess,sys,time,uuid,hashlib,runpy,zipfile
from PIL import Image,ImageDraw
OUT=ROOT/'.fr21-local/fr04';OUT.mkdir(parents=True,exist_ok=True)
CHECKS=[]
FR04_FILE=PRIVATE/'fr04-accounts.bin'
fr04=json.loads(crypt(FR04_FILE.read_bytes(),True)) if FR04_FILE.exists() else {'accounts':{}}
def save():FR04_FILE.write_bytes(crypt(json.dumps(fr04).encode()))
def check(ok,label):
    if not ok:raise AssertionError(label)
    CHECKS.append(label)
    record={'check':label,'result':'PASS','time':dt.datetime.now(dt.timezone.utc).isoformat()}
    with (OUT/'checks.jsonl').open('a') as log:log.write(json.dumps(record)+'\n')
    print(json.dumps(record),flush=True)
def api(path,method='GET',body=None,token=None,admin=False,mime='application/json'):
    target();key=SERVICE if admin else ANON
    data=body if isinstance(body,bytes) else json.dumps(body).encode() if body is not None else None
    headers={'apikey':key,'Authorization':'Bearer '+(token or key),'Content-Type':mime,'Prefer':'return=representation'}
    if path.startswith('/storage/v1/object/') and method=='POST':headers['x-upsert']='true'
    req=urllib.request.Request(BASE+path,headers=headers,method=method,data=data)
    try:
        with urllib.request.urlopen(req,timeout=60) as response:
            raw=response.read();status=response.status
    except urllib.error.HTTPError as error:status=error.code;raw=error.read()
    try:return status,json.loads(raw) if raw else None
    except (ValueError,UnicodeDecodeError):return status,raw
def rpc(name,body,token=None,admin=False):return api('/rest/v1/rpc/'+name,'POST',body,token,admin)
def login(account):
    status,result=api('/auth/v1/token?grant_type=password','POST',{'email':account['email'],'password':account['password']})
    assert status==200 and result['user']['id']==account['auth_id'],'Synthetic login failed'
    return result['access_token']
def fixture(label):
    a=fr04['accounts'].setdefault(label,{'email':'fr04-'+label+'@example.test','password':secrets.token_urlsafe(24)+'aA7!'})
    save()
    if 'auth_id' not in a:
        status,user=api('/auth/v1/admin/users','POST',{'email':a['email'],'password':a['password'],'email_confirm':True,
          'user_metadata':{'name':'FR04 synthetic '+label,'role':'rider','fr04_fixture':True}},admin=True)
        assert status in (200,201),'Synthetic Auth creation failed'
        a['auth_id']=user['id'];save()
    if 'profile_id' not in a:
        status,rows=api('/rest/v1/users','POST',{'name':'FR04 synthetic '+label,'email':a['email'],'role':'rider','verification_status':'pending'},admin=True)
        assert status==201,'Synthetic profile creation failed'
        a['profile_id']=rows[0]['id'];save()
    return a,login(a)
def image(format):
    picture=Image.new('RGB',(320,180),'white');ImageDraw.Draw(picture).text((20,65),'FR04 SYNTHETIC TEST\nNOT AN IDENTITY DOCUMENT',fill='black')
    buffer=io.BytesIO();picture.save(buffer,format=format);return buffer.getvalue()
def upload(token,raw,mime,request_id=None,number=None):
    body={'action':'upload','image_base64':base64.b64encode(raw).decode(),'mime_type':mime,
      'request_id':request_id or str(uuid.uuid4()),'cnic':number or ('32000'+'1234567'+'1')}
    return api('/functions/v1/fr04-cnic','POST',body,token)
def storage():
    status,b=api('/storage/v1/bucket/rider-cnic',admin=True)
    if status==404 or (isinstance(b,dict) and str(b.get('statusCode'))=='404'):
        raise RuntimeError('Existing private CNIC bucket missing; no recreation authorized')
    status,b=api('/storage/v1/bucket/rider-cnic',admin=True)
    check(status==200 and b['public'] is False and b['file_size_limit']==5242880 and set(b['allowed_mime_types'])=={'image/jpeg','image/png'},'private bucket MIME/5MB restrictions')
def backup():
    file=OUT/'key-backup-read.sql'
    file.write_text("select decrypted_secret as k from vault.decrypted_secrets where name='tezrider_cnic_key_v1';")
    target()
    cli='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
    result=subprocess.run([cli,'db','query','--linked','--project-ref',REF,'--file',str(file),'--output','json'],capture_output=True,text=True,timeout=60)
    assert result.returncode==0,'Protected key backup read failed'
    data=json.loads(result.stdout[result.stdout.index('{'):]);key=data['rows'][0]['k']
    assert len(key)==64
    protected=crypt(json.dumps({'version':'v1','secret_name':'tezrider_cnic_key_v1','key':key}).encode())
    (PRIVATE/'fr04-key-backup.dpapi').write_bytes(protected)
    check(json.loads(crypt(protected,True))['key']==key,'protected key backup round trip')
    file.unlink()
def ttl():
    record=json.loads(crypt((PRIVATE/'fr04-signed-url.bin').read_bytes(),True))
    if time.time()<=record['exp']+2:raise RuntimeError('Actual 900-second expiry wait is not finished')
    target()
    try:
        with urllib.request.urlopen(record['url'],timeout=30) as r:status=r.status
    except urllib.error.HTTPError as e:status=e.code
    check(status in (400,401,403,404),'signed URL is rejected after actual expiry')
    admin=login(state['accounts']['admin'])
    status,fresh=api('/functions/v1/fr04-cnic','POST',{'action':'view','user_id':fr04['accounts']['rider-a']['profile_id']},admin)
    check(status==200 and fresh['url']!=record['url'],'fresh authorized URL issued after expiry')
    target()
    with urllib.request.urlopen(fresh['url'],timeout=30) as response:
        check(response.status==200 and len(response.read())>0,'fresh private URL usable after expiry')

def load():
    # No signup/upload load against Free TEST. Two VUs, 8 or 40 read-only iterations.
    token=login(state['accounts']['admin']);target()
    fixture_file=PRIVATE/'fr04-load-session.json'
    fixture_file.write_text(json.dumps({'anon_key':ANON,'admin_token':token,'rider_id':fr04['accounts']['rider-a']['profile_id']}))
    env=dict(os.environ);env.pop('FR21_TEST_KEYS_JSON',None)
    env.update(FR04_URL=BASE,FR04_HOSTED_SMOKE='true',FR04_FIXTURE_FILE=str(fixture_file))
    executable=next((OUT/'k6').rglob('k6.exe'))
    try:
        result=subprocess.run([str(executable),'run','--summary-export',str(OUT/'load-summary.json'),str(ROOT/'tests/load/FR-04.js')],env=env,capture_output=True,text=True,timeout=120)
        (OUT/'load-output.log').write_text(result.stdout+result.stderr)
        print(json.dumps({'load_exit':result.returncode,'vus':2,'iterations':int(env.get('FR04_SMOKE_ITERATIONS','8'))}))
        check(result.returncode==0,'two-user read-only hosted smoke thresholds')
    finally:fixture_file.unlink(missing_ok=True)

def device():
    runpy.run_path(str(ROOT/'tests/integration/FR-04-device.py'),init_globals={'backend':sys.modules[__name__]})

def acceptance_read():
    customer=login(state['accounts']['customer'])
    order=json.loads((OUT/'device-order.json').read_text())
    status,identity=rpc('fr04_order_rider_identity',{'p_order_id':order['order_id']},customer)
    check(status==200 and identity['cnic_masked']=='3***0-*******-*' and 'cnic' not in identity,'owned physical customer order exposes masked identity only')
    status,rows=api(f'/rest/v1/riders?userid=eq.{fr04["accounts"]["rider-pending"]["profile_id"]}&select=is_online,last_seen&limit=1',admin=True)
    check(status==200 and len(rows)==1 and rows[0]['is_online'] is False,'physical rider logout persisted Offline in TEST')

def artifact():
    mirror=Path('C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-auth-debug/android-build-20261012-125502')
    apk=mirror/'build/app/outputs/flutter-apk/app-fr21test-debug.apk'
    for source in (ROOT/'lib').rglob('*.dart'):
        check(source.read_bytes()==(mirror/source.relative_to(ROOT)).read_bytes(),'APK source match: '+str(source.relative_to(ROOT)))
    backup=json.loads(crypt((PRIVATE/'fr04-key-backup.dpapi').read_bytes(),True))
    forbidden=[SERVICE.encode(),backup['key'].encode()]
    for account in list(state['accounts'].values())+list(fr04['accounts'].values()):
        forbidden.append(account['password'].encode())
    changed=subprocess.check_output(['git','diff','--name-only','-z'],cwd=ROOT)
    staged=subprocess.check_output(['git','diff','--cached','--name-only','-z'],cwd=ROOT)
    new=subprocess.check_output(['git','ls-files','--others','--exclude-standard','-z'],cwd=ROOT)
    for name in set((changed+staged+new).decode().split('\0'))- {''}:
        file=ROOT/name
        if not file.is_file():continue
        assert file.stat().st_size<=5*1024*1024,'Generated large file in working changes'
        assert file.suffix.lower() not in ('.apk','.png','.jpg','.jpeg','.jks','.keystore'), 'Private/generated artifact in working changes'
        assert not file.name.startswith('.env'),'Environment configuration in working changes'
        assert not any(secret in file.read_bytes() for secret in forbidden),'Protected credential in working changes'
    check(True,'changed/new Git files exclude protected credentials, images and large build artifacts')
    with zipfile.ZipFile(apk) as archive:
        found=False;public=False
        for item in archive.infolist():
            if item.is_dir():continue
            raw=archive.read(item)
            assert not any(secret in raw for secret in forbidden),'Private value embedded in APK'
            if item.filename.endswith('libflutter.so'):continue
            assert b'arrqsvejrfdbacfwtpcc.supabase.co' not in raw,'Production URL embedded in APK'
            found|=BASE.encode() in raw;public|=ANON.encode() in raw
        check(found and public,'compiled APK contains TEST URL and public key')
    check(True,'APK contains no fixture passwords, service-role key or Vault encryption key')
    (OUT/'apk-manifest.json').write_text(json.dumps({'project_ref':REF,'path':str(apk),'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'size':apk.stat().st_size,'source_verified':True},indent=2))
def tests():
    a,ta=fixture('rider-a');b,tb=fixture('rider-b');missing,tp=fixture('rider-missing')
    admin=login(state['accounts']['admin']);customer=login(state['accounts']['customer']);vendor=login(state['accounts']['vendor'])
    for token,label in [(ta,'pending rider'),(tb,'other rider'),(customer,'customer'),(vendor,'vendor'),(None,'anonymous')]:
        status,_=rpc('fr04_admin_riders',{},token)
        check(status in (401,403),'admin queue forbidden: '+label)
    status,_=rpc('fr04_review_rider',{'p_user_id':a['profile_id'],'p_status':'approved'},admin)
    current=rpc('fr04_application_status',{},ta)[1]
    if current['document_valid'] is not True:
        check(status==403,'admin cannot approve missing CNIC document')
    for bad,label in [('123','short'),('320001234567X','characters'),('3200-01234567-1','dash format')]:
        status,_=upload(ta,image('PNG'),'image/png',number=bad)
        check(status==422,'invalid CNIC rejected: '+label)
    status,_=upload(ta,b'x'*(5242880+1),'image/png')
    check(status==413,'oversized Edge image rejected')
    status,_=upload(ta,image('PNG'),'application/pdf')
    check(status==415,'invalid MIME rejected')
    status,_=upload(ta,b'\x89PNG\r\n\x1a\n'+b'x'*100,'image/png')
    check(status==422,'spoofed image rejected by actual decoding')
    rid=str(uuid.uuid4());status,j=upload(ta,image('JPEG'),'image/jpeg',rid)
    check(status==200 and j['path'].startswith(a['auth_id']+'/') and j['path'].endswith('/cnic.jpg'),'valid real JPEG upload and UUID ownership')
    status,again=upload(ta,image('JPEG'),'image/jpeg',rid)
    check(status==200 and again['path']==j['path'],'duplicate submission is idempotent')
    jpeg_path=j['path'];fr04['jpeg_path']=jpeg_path;save()
    status,row=api(f'/rest/v1/users?id=eq.{a["profile_id"]}&select=cnic,cnic_image_url,verification_status,cnic_submission_status&limit=1',token=ta)
    check(status==200 and row[0]['cnic'].startswith('pgp:v1:') and row[0]['cnic']!=('32000'+'1234567'+'1'),'CNIC number persisted encrypted')
    check(row[0]['cnic_image_url']==jpeg_path and row[0]['verification_status']=='pending' and row[0]['cnic_submission_status']=='submitted','verified completion retains pending approval and object path only')
    for token,label in [(tb,'other rider'),(customer,'customer'),(vendor,'vendor'),(None,'anonymous')]:
        status,_=api('/functions/v1/fr04-cnic','POST',{'action':'view','user_id':a['profile_id']},token)
        check(status in (401,403),'document viewing forbidden: '+label)
    for token,label in [(ta,'own rider'),(tb,'other rider'),(customer,'customer'),(vendor,'vendor'),(None,'anonymous')]:
        status,_=api('/storage/v1/object/sign/rider-cnic/'+jpeg_path,'POST',{'expiresIn':3600},token)
        check(status>=400,'direct signed URL bypass denied: '+label)
        status,_=api('/storage/v1/object/authenticated/rider-cnic/'+jpeg_path,token=token)
        check(status>=400,'direct object read bypass denied: '+label)
    status,_=api('/storage/v1/object/public/rider-cnic/'+jpeg_path)
    check(status>=400,'public object URL denied')
    status,_=api('/storage/v1/object/rider-cnic/'+b['auth_id']+'/cnic.jpg','POST',image('JPEG'),ta,mime='image/jpeg')
    check(status>=400,'cross-rider upload denied')
    status,_=api('/storage/v1/object/rider-cnic/'+a['auth_id']+'/invalid.pdf','POST',b'PDF',admin=True,mime='application/pdf')
    check(status>=400,'bucket rejects unsupported MIME even for privileged upload')
    status,_=api('/storage/v1/object/rider-cnic/'+a['auth_id']+'/oversized.png','POST',b'x'*(5242880+1),admin=True,mime='image/png')
    check(status>=400,'bucket rejects oversized file even for privileged upload')
    status,signed=api('/functions/v1/fr04-cnic','POST',{'action':'view','user_id':a['profile_id']},admin)
    check(status==200 and signed['expires_in']==900,'authorized admin URL issuance')
    url=signed['url'];token=urllib.parse.parse_qs(urllib.parse.urlparse(url).query)['token'][0]
    payload=token.split('.')[1];payload+='='*(-len(payload)%4);claims=json.loads(base64.urlsafe_b64decode(payload))
    check(claims['exp']-claims['iat']==900,'signed JWT TTL exactly 900 seconds')
    target()
    with urllib.request.urlopen(url,timeout=30) as r:raw=r.read();status=r.status
    check(status==200 and raw==image('JPEG'),'signed URL serves the actual private JPEG')
    (PRIVATE/'fr04-signed-url.bin').write_bytes(crypt(json.dumps({'url':url,'exp':claims['exp']}).encode()))
    status,png=upload(ta,image('PNG'),'image/png')
    check(status==200 and png['path']!=jpeg_path and png['path'].endswith('/cnic.png'),'valid PNG replacement uses an immutable owned version')
    status,_=rpc('fr04_review_rider',{'p_user_id':a['profile_id'],'p_status':'approved'},admin)
    check(status==200,'admin approval succeeds only after valid submission')
    status,result=rpc('fr04_review_rider',{'p_user_id':a['profile_id'],'p_status':'approved'},admin)
    check(status==200,'admin approval retry is idempotent')
    status,_=rpc('fr04_begin_upload',{'p_auth_uid':b['auth_id'],'p_request_id':str(uuid.uuid4()),'p_digest':'a'*64,'p_extension':'png','p_cnic':'32000'+'1234567'+'1'},ta)
    check(status in (401,403),'client cannot call backend-only upload lease')
    status,_=api(f'/rest/v1/users?id=eq.{b["profile_id"]}','PATCH',{'cnic_image_url':png['path']},tb)
    check(status==403,'rider cannot forge document path')
    status,_=rpc('fr04_review_rider',{'p_user_id':missing['profile_id'],'p_status':'approved'},admin)
    check(status==403,'admin cannot approve another incomplete rider')
    status,pending=rpc('fr04_application_status',{},tp)
    check(status==200 and pending['submission_status']=='missing','interrupted signup stays recoverable and incomplete')
    status,_=rpc('fr04_admin_riders',{'p_limit':51},admin)
    check(status==400,'admin queue pagination bounded server-side')
    status,queue=rpc('fr04_admin_riders',{'p_limit':30},admin)
    check(status==200 and len(queue)<=30 and all('cnic' not in row for row in queue),'admin queue returns bounded masked projection only')
    # Stop between lease and Storage write, then resume the exact immutable request.
    rid=str(uuid.uuid4());raw=image('PNG')
    status,lease=rpc('fr04_begin_upload',{'p_auth_uid':b['auth_id'],'p_request_id':rid,'p_digest':hashlib.sha256(raw).hexdigest(),'p_extension':'png','p_cnic':'3200012345671'},admin=True)
    check(status==200 and not lease['complete'],'interrupted upload lease remains incomplete')
    status,_=rpc('fr04_review_rider',{'p_user_id':b['profile_id'],'p_status':'approved'},admin)
    check(status==403,'unfinished Storage write cannot be approved')
    status,_=upload(tb,raw,'image/png')
    check(status==409,'concurrent different upload blocked by active lease')
    status,resumed=upload(tb,raw,'image/png',rid)
    check(status==200 and resumed['path']==lease['path'],'interrupted exact upload resumes without duplicate object')
    # Persist fixtures for physical gallery testing; no private values in report.
    (OUT/'synthetic-doc.png').write_bytes(image('PNG'))
    fr04['ttl_exp']=claims['exp'];save()

if __name__=='__main__':
    try:
        mode=sys.argv[1];{'storage':storage,'tests':tests,'ttl':ttl,'backup':backup,'load':load,'device':device,'artifact':artifact,'acceptance-read':acceptance_read}[mode]()
        report={'project_ref':REF,'mode':mode,'passed':len(CHECKS),'failed':0,'checks':CHECKS}
        (OUT/(mode+'-results.json')).write_text(json.dumps(report,indent=2))
        print(json.dumps({'mode':mode,'passed':len(CHECKS),'failed':0}))
    except Exception as error:
        print(json.dumps({'passed':len(CHECKS),'failed':1,'reason':str(error) if isinstance(error,(AssertionError,RuntimeError)) else type(error).__name__}))
        sys.exit(1)
