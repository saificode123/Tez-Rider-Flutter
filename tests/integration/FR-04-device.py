"""Scoped physical TEST automation; private credentials never enter output."""
import datetime,json,os,re,shlex,subprocess,time,xml.etree.ElementTree as ET,importlib.util
ADB='C:/Users/urreh/AppData/Local/Android/sdk/platform-tools/adb.exe'
PKG='com.example.flutter_application_1.fr21test';SERIAL='AESWNRBAEUPNTGJZ'
def adb(*args,input=None):
    p=subprocess.run([ADB,'-s',SERIAL,*args],input=input,capture_output=True,text=True,encoding='utf-8',timeout=45)
    if p.returncode:raise RuntimeError('Authorized Android command failed')
    return p.stdout
def screen():
    active=adb('shell','dumpsys','activity','activities')
    assert re.search(r'topResumedActivity=ActivityRecord\{[^}]*'+re.escape(PKG)+'/',active),'TEST app must be foreground'
    path='/data/local/tmp/fr04-ui-'+str(os.getpid())+'.xml'
    for attempt in range(3):
        adb('shell','uiautomator','dump',path)
        raw=adb('exec-out','cat',path)
        adb('shell','rm','-f',path)
        try:return list(ET.fromstring(raw).iter('node'))
        except ET.ParseError:
            if attempt==2:raise
            time.sleep(1)
def label(n):return (n.get('text') or n.get('content-desc') or '').strip()
def tap(n):
    xy=list(map(int,re.findall(r'\d+',n.get('bounds',''))));assert len(xy)==4
    assert xy[2]>xy[0] and xy[3]>xy[1] and 0<(xy[1]+xy[3])//2<2350,'Requested control must be visible on device'
    adb('shell','input','tap',str((xy[0]+xy[2])//2),str((xy[1]+xy[3])//2))
def text(value,index=0):
    fields=[n for n in screen() if n.get('class')=='android.widget.EditText'];tap(fields[index])
    adb('shell','input','keyevent','123')
    adb('shell',input='input keyevent '+' '.join(['67']*110)+'\ninput text '+shlex.quote(value)+'\nexit\n')
    adb('shell','input','keyevent','4')
def form_text(name,value):
    for attempt in range(4):
        nodes=screen();headers=[n for n in nodes if label(n)==name]
        if headers:
            header=list(map(int,re.findall(r'\d+',headers[0].get('bounds',''))))
            choices=[]
            for n in nodes:
                xy=list(map(int,re.findall(r'\d+',n.get('bounds',''))))
                if n.get('class')=='android.widget.EditText' and len(xy)==4 and xy[1]>=header[3] and xy[1]-header[3]<160 and xy[3]<2350:choices.append(n)
            if len(choices)==1:
                tap(choices[0]);adb('shell','input','keyevent','123')
                line='input keyevent '+' '.join(['67']*110)+'\n'
                if value:line+='input text '+shlex.quote(value)+'\n'
                adb('shell',input=line+'exit\n');adb('shell','input','keyevent','4');return
        adb('shell','input','swipe','500','1200' if name in ('Full Name','Email') else '2050','500','2100' if name in ('Full Name','Email') else '1000','450');time.sleep(1)
    raise RuntimeError('Named visible signup field required')
def click(value):
    nodes=screen();found=[n for n in nodes if value.lower() in label(n).lower() and n.get('clickable')=='true']
    assert found,'Requested TEST control not visible';tap(found[0])
def emit(value):
    record={'time':datetime.datetime.now(datetime.timezone.utc).isoformat(),**value}
    with (backend.OUT/'device-evidence.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
    print(json.dumps(record),flush=True)

action=os.environ.get('FR04_DEVICE_ACTION','status');backend.target()
if action.startswith('login:'):
    name=action.split(':',1)[1]
    account=backend.fr04['accounts'][name] if name.startswith('rider-') else backend.state['accounts'][name]
    nodes=screen();assert len([n for n in nodes if n.get('class')=='android.widget.EditText'])==2,'Login screen required'
    text(account['email']);text(account['password'],1)
    backend.target();click('Sign in as');time.sleep(4)
elif action.startswith('tap:'):click(action.split(':',1)[1]);time.sleep(1)
elif action=='logout-cnic':
    nodes=screen();assert any(label(n)=='Rider CNIC verification' for n in nodes),'CNIC screen required'
    controls=[]
    for n in nodes:
        xy=list(map(int,re.findall(r'\d+',n.get('bounds',''))))
        if len(xy)==4 and n.get('clickable')=='true' and not label(n) and xy[0]>850 and xy[3]<330:
            controls.append(n)
    assert len(controls)==1,'Unique TEST toolbar logout required';tap(controls[0]);time.sleep(3)
elif action=='rider-profile':
    nodes=screen()
    controls=[]
    for n in nodes:
        xy=list(map(int,re.findall(r'\d+',n.get('bounds',''))))
        if len(xy)==4 and n.get('clickable')=='true' and not label(n) and xy[0]>800 and xy[1]>2100:
            controls.append(n)
    assert len(controls)==1,'Unique observed rider Profile tab required'
    tap(controls[0]);time.sleep(1)
elif action=='customer-track':
    nodes=screen();assert any('Featured' in label(n) for n in nodes),'Observed customer Home screen required'
    adb('shell','input','tap','658','2195');time.sleep(1)
elif action=='signup-fill':
    nodes=screen();assert any(label(n)=='CNIC Number' for n in nodes),'Rider signup required'
    for name,value in [('Phone Number','+923001234567'),('Full Name','FR04validation'),('Email','fr04-device-validation@example.test'),('CNIC Number',''),('Password',backend.fr04['accounts']['rider-pending']['password'])]:form_text(name,value)
elif action=='signup-email-fill':
    nodes=screen();assert any(label(n)=='CNIC Number' for n in nodes),'Rider signup required'
    account=backend.fr04['accounts'].get('rider-email')
    if account is None:
        mailbox=os.environ.get('FR04_CONFIRMATION_MAILBOX','')
        assert re.fullmatch(r'[A-Za-z0-9._-]+@gmail\.com',mailbox),'Approved controlled confirmation mailbox required'
        local,domain=mailbox.rsplit('@',1)
        account={'email':local+'+fr04-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d%H%M%S')+'@'+domain,
          'password':backend.secrets.token_urlsafe(24)+'aA7!'}
        backend.fr04['accounts']['rider-email']=account;backend.save()
    for name,value in [('Phone Number','+923001234567'),('Full Name','FR04 synthetic email rider'),('Email',account['email']),('CNIC Number','3200012345671'),('Password',account['password'])]:form_text(name,value)
elif action in ('email-created','email-confirmed','email-inspect'):
    account=backend.fr04['accounts']['rider-email']
    found=[]
    for page in range(1,6):
        status,result=backend.api('/auth/v1/admin/users?page='+str(page)+'&per_page=100',admin=True)
        assert status==200,'Bounded TEST Auth inspection failed'
        found=[u for u in result['users'] if u['email']==account['email']]
        if found or len(result['users'])<100:break
    assert len(found)==1,'Fresh native synthetic signup must exist'
    user=found[0];account['auth_id']=user['id'];backend.save()
    backend.check(user['user_metadata'].get('role')=='rider' and 'cnic' not in user['user_metadata'],
      'fresh native rider signup contains no raw CNIC in Auth metadata')
    if action=='email-inspect':
        emit({'probe':'fresh_auth_confirmation','confirmed':bool(user.get('email_confirmed_at')),
          'created_at':user.get('created_at'),'confirmed_at':user.get('email_confirmed_at'),
          'confirmation_sent_field_present':'confirmation_sent_at' in user,
          'confirmation_sent':bool(user.get('confirmation_sent_at'))})
    elif action=='email-created':
        backend.check(not user.get('email_confirmed_at') and bool(user.get('confirmation_sent_at')),
          'fresh native signup is unconfirmed and confirmation delivery requested')
        status,error=backend.api('/auth/v1/token?grant_type=password','POST',{'email':account['email'],'password':account['password']})
        backend.check(status==400 and error.get('error_code')=='email_not_confirmed',
          'fresh rider password login blocked before email confirmation')
    else:
        backend.check(bool(user.get('email_confirmed_at')),'fresh rider confirmed through actual email flow')
        token=backend.login(account)
        backend.check(bool(token),'fresh confirmed rider password login succeeds')
elif action=='email-application':
    nodes=screen();account=backend.fr04['accounts']['rider-email']
    prefs=ET.fromstring(adb('exec-out','run-as',PKG,'cat','shared_prefs/FlutterSharedPreferences.xml'))
    saved=next(e.text for e in prefs if e.get('name')=='flutter.sb-'+backend.REF+'-auth-token')
    token=json.loads(saved)['access_token'];status,user=backend.api('/auth/v1/user',token=token)
    backend.check(status==200 and user['id']==account['auth_id'],'physical confirmed fresh rider session matches signup account')
    status,state=backend.rpc('fr04_application_status',{},token)
    backend.check(status==200 and state['verification_status']=='pending' and state['submission_status']=='missing',
      'fresh confirmed rider remains incomplete and pending before upload')
    account['profile_id']=state['id'];backend.save()
    fields=[n for n in nodes if n.get('class')=='android.widget.EditText']
    backend.check(len(fields)==1 and fields[0].get('text')=='3200012345671',
      'fresh signup CNIC draft restored after actual email confirmation and login')
elif action=='email-accepted':
    nodes=screen();account=backend.fr04['accounts']['rider-email']
    backend.check(any(label(n)=='Rider Dashboard' for n in nodes),
      'fresh email-confirmed uploaded approved rider reaches Dashboard on subsequent login')
    token=backend.login(account);status,state=backend.rpc('fr04_application_status',{},token)
    backend.check(status==200 and state['id']==account['profile_id'] and state['verification_status']=='approved'
      and state['submission_status']=='submitted' and state['document_valid'],
      'fresh email flow approval and private document persist in TEST')
    status,rows=backend.api('/rest/v1/users?id=eq.'+str(account['profile_id'])+'&select=cnic&limit=1',token=token)
    backend.check(status==200 and len(rows)==1 and rows[0]['cnic'].startswith('pgp:v1:'),
      'fresh email rider CNIC remains encrypted at rest')
elif action=='signup-number':
    form_text('CNIC Number','3200012345671')
elif action=='signup-inspect':
    fields=[n for n in screen() if n.get('class')=='android.widget.EditText']
    emit({'probe':'signup_field_geometry','fields':[{'index':i,'password':n.get('password'),'bounds':n.get('bounds'),'length':len(n.get('text',''))} for i,n in enumerate(fields)]})
elif action=='logout-via-app':
    screen()
    prefs=ET.fromstring(adb('exec-out','run-as',PKG,'cat','shared_prefs/FlutterSharedPreferences.xml'))
    saved=next(e.text for e in prefs if e.get('name')=='flutter.sb-'+backend.REF+'-auth-token')
    status,user=backend.api('/auth/v1/user',token=json.loads(saved)['access_token'])
    allowed=[a['auth_id'] for a in backend.state['accounts'].values()]+[a['auth_id'] for a in backend.fr04['accounts'].values()]
    assert status==200 and user['id'] in allowed,'Synthetic TEST session required'
    pid=adb('shell','pidof',PKG).strip();assert re.fullmatch(r'\d+',pid)
    log=adb('logcat','-d','--pid='+pid)
    urls=re.findall(r'Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+)',log)
    cache=backend.PRIVATE/'fr04-debug-service.bin'
    if not urls and cache.exists():
        cached=json.loads(backend.crypt(cache.read_bytes(),True))
        if cached['pid']==pid:urls=[cached['url']]
    assert urls,'Existing TEST debug service required'
    cache.write_bytes(backend.crypt(json.dumps({'pid':pid,'url':urls[-1]}).encode()))
    parsed=backend.urllib.parse.urlparse(urls[-1])
    port=adb('forward','tcp:0','tcp:'+str(parsed.port)).strip();assert port.isdigit()
    base='http://127.0.0.1:'+port+parsed.path
    def vm(method,params=None):
        url=base+method+('?' + backend.urllib.parse.urlencode(params) if params else '')
        with backend.urllib.request.urlopen(url,timeout=20) as response:result=json.load(response)
        if 'error' in result:
            diagnostic=str(result['error'].get('data',{}))
            for private in [backend.SERVICE,backend.ANON,urls[-1]]+[a['password'] for a in backend.state['accounts'].values()]+[a['password'] for a in backend.fr04['accounts'].values()]:
                diagnostic=diagnostic.replace(private,'[protected]')
            diagnostic=re.sub(r'https?://\S+','[protected address]',diagnostic)
            emit({'probe':'app_debug_operation','method':method,'error_code':result['error'].get('code'),
              'message':result['error'].get('message'),
              'compiler_diagnostic':diagnostic[:1500]})
            raise RuntimeError('App debug operation failed')
        return result.get('result',result)
    try:
        isolate=next(i for i in vm('getVM')['isolates'] if i.get('name')=='main')
        details=vm('getIsolate',{'isolateId':isolate['id']})
        library=next(l for l in details['libraries'] if l.get('uri')=='package:flutter_application_1/controllers/auth_controller.dart')
        definition=vm('getObject',{'isolateId':isolate['id'],'objectId':library['id']})
        controller=next(c for c in definition['classes'] if c.get('name')=='AuthController')
        instances=vm('getInstances',{'isolateId':isolate['id'],'objectId':controller['id'],'limit':'2'})
        assert len(instances['instances'])==1,'Unique existing AuthController required'
        result=vm('invoke',{'isolateId':isolate['id'],'targetId':instances['instances'][0]['id'],
          'selector':'logout','argumentIds':'[]','disableBreakpoints':'true'})
        assert result.get('type')!='ErrorRef','Existing app logout invocation failed'
        time.sleep(3)
        emit({'probe':'existing_app_logout','session_file_manually_modified':False})
    finally:adb('forward','--remove','tcp:'+port)
elif action=='scroll':
    screen();adb('shell','input','swipe','500','1800','500','700','450');time.sleep(1)
elif action=='scroll-up':
    screen();adb('shell','input','swipe','500','700','500','1800','450');time.sleep(1)
elif action=='toggle':
    switches=[n for n in screen() if n.get('class')=='android.widget.Switch' and n.get('enabled')=='true']
    assert len(switches)==1,'Unique enabled rider availability switch required'
    backend.target();tap(switches[0]);time.sleep(2)
elif action=='presence':
    nodes=screen();prefs=ET.fromstring(adb('exec-out','run-as',PKG,'cat','shared_prefs/FlutterSharedPreferences.xml'))
    saved=next(e.text for e in prefs if e.get('name')=='flutter.sb-'+backend.REF+'-auth-token')
    token=json.loads(saved)['access_token'];status,user=backend.api('/auth/v1/user',token=token)
    account=backend.fr04['accounts']['rider-pending']
    backend.check(status==200 and user['id']==account['auth_id'],'approved FR04 physical rider session confirmed')
    status,rows=backend.api(f'/rest/v1/riders?userid=eq.{account["profile_id"]}&select=is_online,last_seen,presence_epoch,presence_sequence&limit=1',token=token)
    backend.check(status==200 and len(rows)==1,'FR04 approved rider presence row restored')
    switches=[n for n in nodes if n.get('class')=='android.widget.Switch']
    backend.check(len(switches)==1 and (switches[0].get('checked')=='true')==rows[0]['is_online'],'physical availability switch matches hosted TEST')
    record={'time':datetime.datetime.now(datetime.timezone.utc).isoformat(),**rows[0]}
    with (backend.OUT/'presence-series.jsonl').open('a') as log:log.write(json.dumps(record)+'\n')
    emit({'probe':'presence',**record})
elif action=='assign':
    cutoff=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=2)).isoformat()
    path='/rest/v1/riders?is_online=eq.true&last_seen=gte.'+backend.urllib.parse.quote(cutoff,safe='')+'&select=userid&limit=10'
    status,fresh=backend.api(path,admin=True);account=backend.fr04['accounts']['rider-pending']
    assert status==200 and len(fresh)==1 and fresh[0]['userid']==account['profile_id'],'Only physical synthetic rider should be fresh for this isolated assignment'
    spec=importlib.util.spec_from_file_location('fr21_order_fixture',backend.ROOT/'tests/integration/FR-21-hosted.py')
    fixture=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)
    vendor=fixture.fixture('vendor','vendor');customer=fixture.fixture('customer','customer')
    order,vo=fixture.new_order(customer,vendor)
    assigned=fixture.rpc('fr21_ready_and_assign',{'p_vendor_order_id':vo['id']},vendor['token'])
    backend.check(assigned.get('rider_id')==account['profile_id'],'newly approved physical FR04 rider eligible for actual assignment')
    repeated=fixture.rpc('fr21_ready_and_assign',{'p_vendor_order_id':vo['id']},vendor['token'])
    backend.check(repeated.get('rider_id')==account['profile_id'],'physical rider assignment retry does not duplicate assignment')
    (backend.OUT/'device-order.json').write_text(json.dumps({'order_id':order['id'],'vendor_order_id':vo['id'],'rider_id':account['profile_id']}))
    time.sleep(2)
elif action=='cancel-order':
    order=json.loads((backend.OUT/'device-order.json').read_text())
    token=backend.login(backend.state['accounts']['customer'])
    status,rows=backend.api(f'/rest/v1/orders?id=eq.{order["order_id"]}&user_id=eq.{backend.state["accounts"]["customer"]["profile_id"]}&select=id,delivery_address&limit=1',token=token)
    assert status==200 and len(rows)==1 and rows[0]['delivery_address']=='FR21 synthetic device delivery'
    status,rows=backend.api(f'/rest/v1/orders?id=eq.{order["order_id"]}','PATCH',{'order_status':'cancelled'},token)
    backend.check(status==200 and len(rows)==1,'own synthetic order cancellation confirmed')
elif action in ('verify-assignment','accept-synthetic-order'):
    order=json.loads((backend.OUT/'device-order.json').read_text());nodes=screen()
    backend.check(any('Order #'+str(order['order_id']) in label(n) for n in nodes),'physical Android received new assignment via Realtime')
    if action=='accept-synthetic-order':
        headings=[label(n) for n in nodes if re.match(r'Order #\d+',label(n))]
        assert headings and headings[0].startswith('Order #'+str(order['order_id'])),'Exact newest synthetic order required'
        backend.target();click('Accept Order');time.sleep(2)
elif action=='admin-count':
    nodes=screen();token=backend.login(backend.state['accounts']['admin'])
    backend.target()
    request=backend.urllib.request.Request(backend.BASE+'/rest/v1/users?role=eq.rider&verification_status=eq.approved&select=id',
      headers={'apikey':backend.ANON,'Authorization':'Bearer '+token,'Prefer':'count=exact'},method='HEAD')
    with backend.urllib.request.urlopen(request,timeout=30) as response:
        count=int(response.headers['Content-Range'].split('/')[-1])
    backend.check(any(label(n)==str(count)+'\nActive Riders' for n in nodes),
      'physical admin approved rider count matches server count')
elif action=='admin-controls':
    nodes=screen();assert any('Admin Panel' in label(n) or 'Awaiting Approval' in label(n) for n in nodes),'Admin screen required'
    emit({'probe':'admin_controls','controls':[{'label':label(n),'enabled':n.get('enabled'),'clickable':n.get('clickable'),'bounds':n.get('bounds')} for n in nodes if label(n) in ('Approve','View CNIC','Reject')]})
elif action.startswith(('admin-view:','admin-approve:','admin-missing:')):
    command,name=action.split(':',1);account=backend.fr04['accounts'][name]
    nodes=screen();parents={child:parent for parent in nodes for child in parent}
    current=next(n for n in nodes if account['email'] in label(n))
    while current is not None:
        descendants=list(current.iter('node'))
        views=[n for n in descendants if label(n)=='View CNIC']
        approvals=[n for n in descendants if label(n)=='Approve']
        if len(views)==1 and len(approvals)==1:break
        current=parents.get(current)
    if current is None:
        # Flutter may merge the entire Column into one label. Verify every rider
        # and control against the bounded, ordered server queue before indexing.
        admin=backend.login(backend.state['accounts']['admin'])
        status,queue=backend.rpc('fr04_admin_riders',{'p_limit':30,'p_status':'pending'},admin)
        views=[n for n in nodes if label(n)=='View CNIC'];approvals=[n for n in nodes if label(n)=='Approve']
        assert status==200 and len(queue)>=len(views)==len(approvals)>0,'Bounded rider queue controls required'
        assert all(any(row['email'] in label(n) for n in nodes) for row in queue),'UI queue differs from server'
        index=next(i for i,row in enumerate(queue) if str(row['id'])==str(account['profile_id']))
        assert index<len(views),'Target synthetic rider must be visible'
        views=[views[index]];approvals=[approvals[index]]
    if command=='admin-missing':
        backend.check(views[0].get('enabled')=='false' and approvals[0].get('enabled')=='false','physical admin cannot view or approve missing document')
    else:
        button=views[0] if command=='admin-view' else approvals[0]
        assert button.get('enabled')=='true' and button.get('clickable')=='true','Submitted synthetic document control must be enabled'
        backend.target();tap(button);time.sleep(2)
elif action in ('verify-size','verify-invalid-image'):
    nodes=screen()
    expected='The image must be no larger than 5 MB.' if action=='verify-size' else 'This file is not a valid JPEG or PNG image.'
    backend.check(any(label(n)==expected for n in nodes),'physical '+action+' displays actual image rejection')
    token=backend.login(backend.fr04['accounts']['rider-missing'])
    status,state=backend.rpc('fr04_application_status',{},token)
    backend.check(status==200 and state['submission_status']=='missing' and not state['document_valid'],
      'physical invalid image selection leaves hosted registration incomplete')
elif action=='number':text('3200012345671')
elif action=='invalid':text('123X')
elif action=='networkoff':
    flags={'wifi':adb('shell','settings','get','global','wifi_on').strip(),
      'data':adb('shell','settings','get','global','mobile_data').strip()}
    (backend.OUT/'device-network-flags.json').write_text(json.dumps(flags))
    adb('shell','svc','wifi','disable');adb('shell','svc','data','disable')
    emit({'probe':'controlled_device_network','online':False})
elif action=='networkon':
    flags=json.loads((backend.OUT/'device-network-flags.json').read_text())
    adb('shell','svc','wifi','enable' if flags['wifi']=='1' else 'disable')
    adb('shell','svc','data','enable' if flags['data']=='1' else 'disable')
    emit({'probe':'controlled_device_network','restored_original_flags':True})
elif action=='back':adb('shell','input','keyevent','4')
elif action=='viewer-expiry':
    nodes=screen()
    records=[json.loads(line) for line in (backend.OUT/'device-evidence.jsonl').read_text().splitlines()]
    opened=next(r for r in reversed(records) if r.get('action')=='tap:View submitted document')
    elapsed=(datetime.datetime.now(datetime.timezone.utc)-datetime.datetime.fromisoformat(opened['time'])).total_seconds()
    backend.check(elapsed>=900,'native viewer tested after actual fifteen-minute wait')
    backend.check(any(label(n)=='The private viewing link expired. Tap Retry.' for n in nodes),
      'native private viewer shows expiry instead of reusing expired image')
    path='/data/local/tmp/fr04-viewer-expired.png'
    adb('shell','screencap','-p',path)
    adb('pull',path,str(backend.OUT/'viewer-after-expiry.png'));adb('shell','rm',path)
    picture=backend.Image.open(backend.OUT/'viewer-after-expiry.png').convert('RGB')
    # Original green synthetic document occupied this observed central region.
    crop=picture.crop((210,1020,870,1460))
    green=sum(1 for r,g,b in crop.getdata() if g>r*1.2+20 and g>b*1.2+20)/(crop.width*crop.height)
    backend.check(green<0.005,'native expired green document removed from rendered image area')
    emit({'probe':'native_expiry','elapsed_seconds':round(elapsed,1),'old_image_green_fraction':green})
elif action=='verify-viewer-retry':
    nodes=screen()
    backend.check(any(label(n)=='Private CNIC document' for n in nodes) and not any('expired' in label(n) for n in nodes),
      'native Retry clears the expired-link error')
    picture=backend.Image.open(backend.OUT/'viewer-after-retry.png').convert('RGB').crop((210,1020,870,1460))
    pixels=list(picture.getdata())
    green=sum(1 for r,g,b in pixels if g>r*1.2+20 and g>b*1.2+20)
    dark=sum(1 for r,g,b in pixels if max(r,g,b)<130)
    backend.check(green==0 and dark>100,'native Retry displays current synthetic text document instead of cached green version')
    token=backend.login(backend.fr04['accounts']['rider-b'])
    status,link=backend.api('/functions/v1/fr04-cnic','POST',{'action':'view'},token)
    backend.check(status==200,'current native viewer document still requires authorized private access')
    backend.target()
    with backend.urllib.request.urlopen(link['url'],timeout=30) as response:
        backend.check(response.read()==backend.image('PNG'),'current private document matches native Retry synthetic image')
elif action=='logs':
    pid=adb('shell','pidof',PKG).strip();assert re.fullmatch(r'\d+',pid),'TEST PID missing'
    log=adb('logcat','-d','--pid='+pid)
    emit({'probe':'runtime_logs','fatal_count':len(re.findall('FATAL EXCEPTION',log)),
      'unhandled_count':len(re.findall('Unhandled Exception',log)),
      'auth_error_count':len(re.findall('AuthApiException',log))})
elif action=='auth':
    prefs=ET.fromstring(adb('exec-out','run-as',PKG,'cat','shared_prefs/FlutterSharedPreferences.xml'))
    saved=next((e.text for e in prefs if e.get('name')=='flutter.sb-'+backend.REF+'-auth-token'),None)
    assert saved,'No TEST session saved'
    token=json.loads(saved)['access_token'];status,user=backend.api('/auth/v1/user',token=token)
    assert status==200,'Current TEST session invalid'
    match=next((name for name,a in backend.fr04['accounts'].items() if a['auth_id']==user['id']),None)
    emit({'probe':'session','synthetic_fr04_account':match,'valid':True})
elif action=='verify-upload' or action.startswith('verify-upload:'):
    prefs=ET.fromstring(adb('exec-out','run-as',PKG,'cat','shared_prefs/FlutterSharedPreferences.xml'))
    saved=next(e.text for e in prefs if e.get('name')=='flutter.sb-'+backend.REF+'-auth-token')
    token=json.loads(saved)['access_token'];status,user=backend.api('/auth/v1/user',token=token)
    account=backend.fr04['accounts'][action.split(':',1)[1] if ':' in action else 'rider-pending']
    backend.check(status==200 and user['id']==account['auth_id'],'physical synthetic rider Auth confirmed')
    status,state=backend.rpc('fr04_application_status',{},token)
    backend.check(status==200 and state['document_valid'] and state['verification_status']=='pending' and state['cnic_masked']=='3***0-*******-*','physical upload confirmed pending and masked in TEST')
    status,link=backend.api('/functions/v1/fr04-cnic','POST',{'action':'view'},token)
    backend.check(status==200,'physical rider owns signed document access')
    backend.target()
    with backend.urllib.request.urlopen(link['url'],timeout=30) as r:raw=r.read()
    actual=backend.Image.open(backend.io.BytesIO(raw)).convert('RGB')
    expected=backend.Image.open(backend.OUT/'phone-synthetic.png').convert('RGB')
    a=actual.tobytes();b=expected.tobytes()
    deviation=sum(abs(x-y) for x,y in zip(a,b))/max(len(a),1) if actual.size==expected.size else None
    emit({'probe':'synthetic_pixel_comparison','actual_dimensions':actual.size,'expected_dimensions':expected.size,'dimensions_match':actual.size==expected.size,'mean_absolute_difference':deviation})
    # Native image_picker compresses JPEG; compare decoded pixels with a bounded tolerance.
    backend.check(deviation is not None and deviation<3,'physical Gallery upload contains actual compressed synthetic image pixels')
elif action in ('verify-recovery','verify-camera'):
    prefs=ET.fromstring(adb('exec-out','run-as',PKG,'cat','shared_prefs/FlutterSharedPreferences.xml'))
    saved=next(e.text for e in prefs if e.get('name')=='flutter.sb-'+backend.REF+'-auth-token')
    token=json.loads(saved)['access_token'];status,user=backend.api('/auth/v1/user',token=token)
    account=backend.fr04['accounts']['rider-pending']
    backend.check(status==200 and user['id']==account['auth_id'],'physical recovery uses synthetic rider session')
    status,state=backend.rpc('fr04_application_status',{},token)
    backend.check(status==200 and state['document_valid'] and state['verification_status']=='pending','persisted original document remains intact while retrying')
    if action=='verify-recovery':
        fields=[n for n in screen() if n.get('class')=='android.widget.EditText']
        backend.check(len(fields)==1 and fields[0].get('text')=='3200012345671','encrypted interrupted Camera draft restored after restart')
        (backend.OUT/'recovery-before.json').write_text(json.dumps({'path':state['document_path']}))
    else:
        before=json.loads((backend.OUT/'recovery-before.json').read_text())
        backend.check(state['document_path']!=before['path'] and state['document_path'].endswith('/cnic.jpg'),'physical Camera retry creates confirmed immutable JPEG version')
        status,link=backend.api('/functions/v1/fr04-cnic','POST',{'action':'view'},token)
        assert status==200
        backend.target()
        with backend.urllib.request.urlopen(link['url'],timeout=30) as r:raw=r.read()
        picture=backend.Image.open(backend.io.BytesIO(raw)).convert('RGB')
        greens=sum(1 for r,g,b in picture.getdata() if g>r*1.2+20 and g>b*1.2+20)/(picture.width*picture.height)
        backend.check(max(picture.size)<=1600 and greens>0.05,'physical Camera JPEG contains photographed green synthetic target')
elif action!='status':raise RuntimeError('Unknown scoped device action')
if action in ('tap:Gallery','tap:Camera'):
    emit({'probe':'native_picker_requested','source':action.split(':',1)[1]})
    raise SystemExit(0)
nodes=screen()
labels=[label(n) for n in nodes if label(n) and n.get('class')!='android.widget.EditText']
# Redact potential numbers/addresses. No screenshots of credentials/documents.
safe=[re.sub(r'\b\d{5}-?\d{7}-?\d\b','[protected identity]',s) for s in labels if '@' not in s]
emit({'probe':'ui','action':action,'labels':safe})
