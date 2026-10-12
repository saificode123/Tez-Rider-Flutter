"""Connected TEST phone probes. Credentials remain in memory; evidence is sanitized."""
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

import argparse,datetime as dt,re,subprocess,time,xml.etree.ElementTree as ET
ADB='C:/Users/urreh/AppData/Local/Android/sdk/platform-tools/adb.exe'
PKG='com.example.flutter_application_1.fr21test'
SERIAL='AESWNRBAEUPNTGJZ'
EVIDENCE=ROOT/'.fr21-local/device-evidence.jsonl'

def adb(*args):
    p=subprocess.run([ADB,'-s',SERIAL,*args],capture_output=True,text=True,encoding='utf-8',timeout=30)
    if p.returncode:raise RuntimeError('Authorized Android command failed')
    return p.stdout

def emit(data):
    data={'time':dt.datetime.now(dt.timezone.utc).isoformat(),**data}
    EVIDENCE.parent.mkdir(exist_ok=True)
    with EVIDENCE.open('a',encoding='utf-8') as f:f.write(json.dumps(data)+'\n')
    print(json.dumps(data),flush=True)

def screen():
    assert PKG in adb('shell','dumpsys','activity','activities').split('topResumedActivity=')[-1].splitlines()[0], 'TEST app must be foreground'
    adb('shell','uiautomator','dump','/data/local/tmp/fr21-device.xml')
    raw=adb('exec-out','cat','/data/local/tmp/fr21-device.xml')
    adb('shell','rm','/data/local/tmp/fr21-device.xml')
    return list(ET.fromstring(raw).iter('node'))

def observation(include_ui=True):
    prefs=ET.fromstring(adb('exec-out','run-as',PKG,'cat','shared_prefs/FlutterSharedPreferences.xml'))
    saved=next((e.text for e in prefs if e.get('name')=='flutter.sb-'+REF+'-auth-token'),None)
    assert saved,'No saved TEST session'
    jwt=json.loads(saved)['access_token']
    status,user=request('/auth/v1/user',token=jwt)
    valid=status==200
    if not valid:
        # A disconnected phone may retain an expired access token until refresh.
        # Decode only to identify which synthetic fixture to observe; this token
        # is never used to authorize a write or treated as a valid session.
        payload=jwt.split('.')[1];payload+='='*(-len(payload)%4)
        identity=json.loads(base64.urlsafe_b64decode(payload))['sub']
        status,user=request('/auth/v1/admin/users/'+identity,admin=True)
        assert status==200 and user['user_metadata'].get('fr21_fixture') is True
    assert user['id']==state['accounts']['approved-rider']['auth_id'], 'Approved synthetic rider session required'
    emit({'probe':'device_auth','valid_access_token':valid})
    id=state['accounts']['approved-rider']['profile_id']
    status,rows=request(f'/rest/v1/riders?userid=eq.{id}&select=is_online,last_seen,presence_epoch,presence_sequence,is_available,isavailable&limit=1',admin=True)
    assert status==200 and len(rows)==1, 'Rider read HTTP '+str(status)+' code '+str(rows.get('code') if isinstance(rows,dict) else 'row_count')
    row=rows[0];age=(dt.datetime.now(dt.timezone.utc)-dt.datetime.fromisoformat(row['last_seen'])).total_seconds() if row['last_seen'] else None
    status,orders=request(f'/rest/v1/orders?rider_id=eq.{id}&order_status=eq.on_the_way&select=id,order_status&limit=2',token=jwt if valid else None,admin=not valid)
    assert status==200
    emit({'probe':'active_orders','orders':orders})
    if len(orders)==1:
        status,assignments=request(f'/rest/v1/rider_assignments?orderid=eq.{orders[0]["id"]}&select=id&limit=2',token=jwt if valid else None,admin=not valid)
        assert status==200 and len(assignments)==1,'One persisted assignment required'
        emit({'test':'physical_assignment_uniqueness','result':'PASS','order_id':orders[0]['id'],'assignment_count':1})
    labels=[(n.get('text','')+' '+n.get('content-desc','')).strip() for n in screen()] if include_ui else []
    emit({'probe':'status','row':row,'age_seconds':round(age,2) if age is not None else None,'effective_online':row['is_online'] and age is not None and age<=120,'ui_online':any(x=='Online' for x in labels),'ui_offline':any(x=='Offline' for x in labels),'ui_active_delivery':any('Active Delivery' in x and 'No Active Delivery' not in x for x in labels),'ui_connection_error':any('Connection lost' in x or 'not confirmed' in x for x in labels),'ui_retry':any(x=='Retry' for x in labels)})

def tap_toggle(taps=1):
    nodes=screen();switches=[n for n in nodes if n.get('class') in ('android.widget.Switch','android.widget.CheckBox') and n.get('enabled')=='true']
    if not switches:
        # The existing floating app bar may be above the visible scroll area.
        adb('shell','input','swipe','540','650','540','1550','450')
        switches=[n for n in screen() if n.get('class') in ('android.widget.Switch','android.widget.CheckBox') and n.get('enabled')=='true']
    assert len(switches)==1,'One enabled rider availability switch required'
    values=list(map(int,re.findall(r'\d+',switches[0].get('bounds',''))));assert len(values)==4
    adb('shell','input','tap',str((values[0]+values[2])//2),str((values[1]+values[3])//2))
    if taps==2:adb('shell','input','tap',str((values[0]+values[2])//2),str((values[1]+values[3])//2))
    emit({'action':'tap_toggle','taps':taps})

def rejected_write():
    account=state['accounts']['approved-rider'];id=account['profile_id']
    status,user=request('/auth/v1/admin/users/'+account['auth_id'],admin=True)
    assert status==200 and user['user_metadata'].get('fr21_fixture') is True
    query=f'/rest/v1/riders?userid=eq.{id}&select=is_online,last_seen,presence_epoch,presence_sequence&limit=1'
    status,rows=request(query,admin=True);assert status==200 and len(rows)==1
    before=rows[0];assert before['is_online'] is False,'Start the isolated failure test Offline'
    status,profiles=request(f'/rest/v1/users?id=eq.{id}&select=role,verification_status&limit=1',admin=True)
    assert status==200 and profiles==[{'role':'rider','verification_status':'approved'}]
    status,other=request(f'/rest/v1/riders?userid=eq.{state["accounts"]["second-rider"]["profile_id"]}&select=is_online,last_seen,presence_epoch,presence_sequence&limit=1',admin=True)
    assert status==200
    # Change approval only for the explicitly synthetic phone fixture; no Auth
    # sessions, grants, RLS policies, migrations or other accounts are changed.
    try:
        status,changed=request(f'/rest/v1/users?id=eq.{id}','PATCH',{'verification_status':'pending'},admin=True)
        assert status==200 and len(changed)==1
        prefs=ET.fromstring(adb('exec-out','run-as',PKG,'cat','shared_prefs/FlutterSharedPreferences.xml'))
        jwt=json.loads(next(e.text for e in prefs if e.get('name')=='flutter.sb-'+REF+'-auth-token'))['access_token']
        status,error=request('/rest/v1/rpc/fr21_set_presence','POST',{'p_online':True,'p_epoch':before['presence_epoch'],'p_sequence':before['presence_sequence']+1},token=jwt)
        assert status==403 and error['code']=='42501','Controlled server rejection required'
        tap_toggle();time.sleep(3)
        labels=[(n.get('text','')+' '+n.get('content-desc','')).strip() for n in screen()]
        status,after=request(query,admin=True);assert status==200 and after==[before],'Rejected write changed persisted presence'
        assert any('An approved rider account is required.' in x for x in labels),'Expected rejection message missing'
        assert any(x=='Offline' for x in labels) and not any(x=='Online' for x in labels),'UI failed to roll back'
        emit({'test':'failed_write_rollback','result':'PASS','rejection_http':403,'rejection_code':'42501','server_presence_unchanged':True,'ui_offline':True,'appropriate_error_visible':True})
    finally:
        status,changed=request(f'/rest/v1/users?id=eq.{id}','PATCH',{'verification_status':'approved'},admin=True)
        assert status==200 and len(changed)==1,'Restore the synthetic fixture approval'
        emit({'action':'restore_synthetic_approval','restored':True})
    status,other_after=request(f'/rest/v1/riders?userid=eq.{state["accounts"]["second-rider"]["profile_id"]}&select=is_online,last_seen,presence_epoch,presence_sequence&limit=1',admin=True)
    assert status==200 and other_after==other
    emit({'test':'failure_isolation','result':'PASS','other_rider_unchanged':True,'auth_sessions_mutated':False,'global_policies_mutated':False})

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['status','database','toggle','doubletap','start','stop','logs','networkoff','networkon','retry','assign','cancel','reject','crashbegin','crashend']);args=parser.parse_args()
    target()
    if args.mode=='status':observation()
    elif args.mode=='database':observation(False)
    elif args.mode=='toggle':tap_toggle()
    elif args.mode=='doubletap':tap_toggle(2)
    elif args.mode=='reject':rejected_write()
    elif args.mode in ('crashbegin','crashend'):
        id=state['accounts']['approved-rider']['profile_id']
        query=f'/rest/v1/riders?userid=eq.{id}&select=is_online,last_seen,presence_epoch,presence_sequence&limit=1'
        marker=ROOT/'.fr21-local/force-stop-before.json'
        if args.mode=='crashbegin':
            status,before=request(query,admin=True);assert status==200 and len(before)==1 and before[0]['is_online']
            age=(dt.datetime.now(dt.timezone.utc)-dt.datetime.fromisoformat(before[0]['last_seen'])).total_seconds()
            assert age<60,'A fresh device heartbeat is required'
            marker.write_text(json.dumps(before[0]))
            adb('shell','am','force-stop',PKG)
            process=subprocess.run([ADB,'-s',SERIAL,'shell','pidof',PKG],capture_output=True,text=True,timeout=20)
            assert not process.stdout.strip(),'TEST process remained running'
            status,after=request(query,admin=True);assert status==200 and after==before,'Force-stop caused a presence write'
            emit({'test':'force_stop_no_final_offline','result':'PASS','row':after[0],'process_running':False})
        else:
            before=json.loads(marker.read_text());status,after=request(query,admin=True)
            assert status==200 and after==[before],'A heartbeat or final Offline write changed the lease after force-stop'
            age=(dt.datetime.now(dt.timezone.utc)-dt.datetime.fromisoformat(before['last_seen'])).total_seconds()
            assert age>120,'Wait for the actual two-minute cutoff'
            emit({'test':'force_stop_expiry','result':'PASS','row':after[0],'age_seconds':round(age,2),'effective_online':False,'last_seen_unchanged':True,'no_final_offline_write':True})
    elif args.mode=='start':
        adb('shell','input','keyevent','224');adb('shell','am','start','-n',PKG+'/com.example.flutter_application_1.MainActivity');emit({'action':'start_test_app'})
    elif args.mode=='stop':adb('shell','am','force-stop',PKG);emit({'action':'force_stop_test_app'})
    elif args.mode=='networkoff':
        flags={'wifi':adb('shell','settings','get','global','wifi_on').strip()!='0','data':adb('shell','settings','get','global','mobile_data').strip()=='1'}
        (ROOT/'.fr21-local/network-before.json').write_text(json.dumps(flags))
        adb('shell','svc','wifi','disable');adb('shell','svc','data','disable');emit({'action':'network_disabled','previous':flags})
    elif args.mode=='networkon':
        flags=json.loads((ROOT/'.fr21-local/network-before.json').read_text())
        for name,enabled in flags.items():adb('shell','svc',name,'enable' if enabled else 'disable')
        emit({'action':'network_restored','restored':flags})
    elif args.mode=='retry':
        nodes=[n for n in screen() if (n.get('text','')+' '+n.get('content-desc','')).strip()=='Retry' and n.get('enabled')=='true']
        assert nodes,'Visible Retry required'
        values=list(map(int,re.findall(r'\d+',nodes[0].get('bounds',''))))
        adb('shell','input','tap',str((values[0]+values[2])//2),str((values[1]+values[3])//2));emit({'action':'retry_presence'})
    elif args.mode=='assign':
        import importlib.util
        spec=importlib.util.spec_from_file_location('hosted',Path(__file__).with_name('FR-21-hosted.py'))
        hosted=importlib.util.module_from_spec(spec);spec.loader.exec_module(hosted)
        vendor=hosted.fixture('vendor','vendor');customer=hosted.fixture('customer','customer')
        order,vo=hosted.new_order(customer,vendor)
        result=hosted.rpc('fr21_ready_and_assign',{'p_vendor_order_id':vo['id']},vendor['token'])
        emit({'action':'synthetic_assignment','order_id':order['id'],'vendor_order_id':vo['id'],'assigned_to_phone':result.get('rider_id')==state['accounts']['approved-rider']['profile_id'],'has_rider':result.get('rider_id') is not None})
    elif args.mode=='cancel':
        account=state['accounts']['customer']
        status,login=request('/auth/v1/token?grant_type=password','POST',{'email':account['email'],'password':account['password']})
        assert status==200 and login['user']['id']==account['auth_id'] and login['user']['user_metadata'].get('fr21_fixture') is True
        id=state['orders'][-1]
        status,owned=request(f'/rest/v1/orders?id=eq.{id}&user_id=eq.{account["profile_id"]}&select=id,delivery_address&limit=1',token=login['access_token'])
        assert status==200 and len(owned)==1 and owned[0]['delivery_address']=='FR21 synthetic device delivery'
        status,changed=request(f'/rest/v1/orders?id=eq.{id}&user_id=eq.{account["profile_id"]}','PATCH',{'order_status':'cancelled'},token=login['access_token'])
        assert status==200 and len(changed)==1
        emit({'action':'cancel_own_synthetic_order','order_id':id})
    else:
        pid=adb('shell','pidof',PKG).strip();assert pid,'TEST app not running'
        raw=adb('logcat','-d','--pid='+pid,'-v','brief')
        emit({'probe':'logs','fatal_exception':raw.count('FATAL EXCEPTION'),'unhandled_exception':raw.count('Unhandled Exception'),'authentication_error_mentions':len(re.findall(r'AuthException|Invalid login credentials|JWT expired',raw)),'api_error_mentions':len(re.findall(r'PostgrestException|SocketException|HandshakeException',raw))})

