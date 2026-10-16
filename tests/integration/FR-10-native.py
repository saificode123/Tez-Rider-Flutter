"""Physical TEST probes. No credential values are emitted or saved in evidence."""
import importlib.util
import datetime as dt
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('fr10', Path(__file__).with_name('FR-10-hosted.py'))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
ADB = 'C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
PKG = 'com.example.flutter_application_1.fr21test'
SERIAL = 'AESWNRBAEUPNTGJZ'

def adb(*args):
    p = subprocess.run([ADB, '-s', SERIAL, *args], capture_output=True, timeout=40)
    assert p.returncode == 0, 'Authorized TEST device operation failed'
    return p.stdout.decode('utf-8', errors='replace')

def screen():
    assert PKG in adb('shell','dumpsys','activity','activities').split('topResumedActivity=')[-1].splitlines()[0], 'TEST app must be foreground'
    adb('shell','uiautomator','dump','/data/local/tmp/fr10-ui.xml')
    return list(ET.fromstring(adb('exec-out','cat','/data/local/tmp/fr10-ui.xml')).iter('node'))

def tap(node):
    xy = list(map(int,re.findall(r'\d+',node.get('bounds',''))))
    assert len(xy) == 4 and xy[2] > xy[0] and xy[3] > xy[1], 'Visible observed control required'
    adb('shell','input','tap',str((xy[0]+xy[2])//2),str((xy[1]+xy[3])//2))

def emit(value):
    with (h.OUT/'native-evidence.jsonl').open('a',encoding='utf-8') as f:
        f.write(json.dumps(value)+'\n')
    print(json.dumps(value),flush=True)

def account(label):
    assert label in ('customer','vendor')
    return h.previous.state['accounts']['customer'] if label == 'customer' else h.state['accounts']['vendor']

def main(action,label):
    if action == 'screen':
        print(json.dumps([{'label':n.get('text') or n.get('content-desc'),'bounds':n.get('bounds'),'class':n.get('class')} for n in screen() if (n.get('text') or n.get('content-desc')) and n.get('class') != 'android.widget.EditText']))
    elif action == 'assert-ui':
        labels = [n.get('text') or n.get('content-desc') or '' for n in screen()]
        if label == 'cod-timeline':
            assert 'Order #'+str(h.state['native_orders']['ui-cod']['id']) in labels
            assert 'Order cancelled — vendor unavailable.' in labels
            assert any(s.startswith('cancelled\nOrder cancelled — vendor unavailable.\n') for s in labels)
        elif label == 'refund':
            assert 'Order #'+str(h.state['native_orders']['captured']['id']) in labels
            assert 'Refund pending — money has not yet been returned.' in labels
        elif label == 'notification':
            assert any('Order cancelled — vendor unavailable.' in s for s in labels)
            assert any('Notifications' in s for s in labels)
        elif label == 'accepted':
            assert any('accepted' in s.lower() for s in labels)
        elif label == 'expired':
            assert any('expired and can no longer be accepted' in s or 'This order is cancelled.' in s for s in labels)
        else:
            raise AssertionError('Unknown UI assertion')
        emit({'physical_UI_check':label,'result':'PASS','observed_labels':labels})
    elif action == 'verify-accepted':
        oid = h.state['native_orders']['vendor-before']['id']
        status, rows = h.b.api(f'/rest/v1/vendor_orders?order_id=eq.{oid}&select=id,status',admin=True)
        assert status == 200 and len(rows) == 1 and rows[0]['status'] == 'accepted', 'Actual accepted child required'
        labels = [n.get('text') or n.get('content-desc') or '' for n in screen()]
        assert any(s.startswith('Order #'+str(rows[0]['id'])+'\nACCEPTED\n') for s in labels), 'Matching accepted vendor card required'
        emit({'physical_before_deadline_acceptance':'PASS','order_id':oid,'vendor_order_id':rows[0]['id'],'persisted_status':'accepted'})
    elif action == 'accept-after':
        oid = h.state['native_orders']['vendor-after']['id']
        status, rows = h.b.api(f'/rest/v1/orders?id=eq.{oid}&select=acceptance_deadline_at,order_status',admin=True)
        assert status == 200 and len(rows) == 1 and rows[0]['order_status'] == 'pending', 'Still pending fixture required'
        deadline = dt.datetime.fromisoformat(rows[0]['acceptance_deadline_at'])
        delay = (deadline-dt.datetime.now(dt.timezone.utc)).total_seconds()+1
        assert delay < 65, 'Bounded physical wait required'
        if delay > 0:time.sleep(delay)
        nodes = screen()
        buttons = [n for n in nodes if (n.get('text') or n.get('content-desc')) == 'Accept Order']
        assert len(buttons) == 1, 'Observed pending acceptance control required after deadline'
        tap(buttons[0]);emit({'physical_after_deadline_acceptance_submitted':True,'order_id':oid,'server_deadline':deadline.isoformat(),'result_pending':True})
    elif action == 'logs':
        pid = adb('shell','pidof',PKG).strip()
        assert pid.isdigit(), 'One running TEST process required'
        logs = adb('logcat','-d','--pid',pid,'-v','brief')
        (h.OUT/'native-logcat.log').write_text(logs,encoding='utf-8')
        fatal = len(re.findall(r'FATAL EXCEPTION|Fatal signal|Unhandled Exception',logs))
        emit({'physical_TEST_log_scan':'PASS' if fatal == 0 else 'FAIL','fatal_or_unhandled_count':fatal,'flutter_error_lines':sum('E/flutter' in line for line in logs.splitlines()),'raw_logs_ignored':True})
        assert fatal == 0, 'TEST app fatal/unhandled log found'
    elif action == 'broadcast':
        h.previous.safe_audience('VENDORS')
        request = {'p_request_id':str(uuid.uuid4()),'p_title':'FR10 notification regression','p_message':'Synthetic TEST broadcast remains available.','p_audience':'VENDORS'}
        status,result = h.b.rpc('admin_send_broadcast',request,h.b.login(h.fixture('native-admin','admin')))
        assert status == 200 and result['code'] in ('SENT','ALREADY_SENT'), 'Existing broadcast returned '+str(result.get('code'))
        h.state['native_broadcast'] = {**request,'id':result['id']};h.save()
        emit({'physical_broadcast_preparation':'accepted','delivery_pending':True})
    elif action == 'broadcast-os':
        request = h.state['native_broadcast']
        keys = [k.strip() for k in adb('shell','cmd','notification','list').splitlines() if PKG in k and request['p_request_id'] in k]
        assert len(keys) == 1, 'One actual TEST broadcast OS notice required'
        notice = adb('shell','cmd','notification','get',shlex.quote(keys[0]))
        assert request['p_title'] in notice and request['p_message'] in notice, 'Actual existing broadcast message required'
        emit({'physical_existing_broadcast_OS':'PASS','exact_message':True})
    elif action == 'final-check':
        ids = [h.state['native_orders'][k]['id'] for k in ('ui-cod','captured','vendor-before','vendor-after')]
        rows = h.query('select o.id,o.order_status,o.rider_id,(select count(*)from public.rider_assignments where orderid=o.id)as assignments,(select count(*)from public.notifications where timeout_order_id=o.id)as notices,(select count(*)from public.order_timeline_events where order_id=o.id and status=\'cancelled\')as events,(select count(*)from public.order_refund_actions where order_id=o.id and status=\'PENDING\' and amount=200)as refunds,(select jsonb_agg(status)from public.vendor_orders where order_id=o.id)as children from public.orders o where id in('+','.join(map(str,ids))+')order by id;')
        by_id = {r['id']:r for r in rows}
        for label in ('ui-cod','captured','vendor-after'):
            r = by_id[h.state['native_orders'][label]['id']]
            assert r['order_status'] == 'cancelled' and r['rider_id'] is None and r['assignments'] == 0 and r['notices'] == r['events'] == 1 and r['children'] == ['cancelled'], 'Final cancellation/assignment/dedup integrity required'
            assert r['refunds'] == (1 if label == 'captured' else 0), 'Canonical financial outcome required'
        assert by_id[h.state['native_orders']['vendor-before']['id']]['order_status'] == 'accepted'
        assert 'native_original_timeout' not in h.state, 'TEST timeout restoration required'
        config = h.query('select vendor_acceptance_timeout_seconds as seconds from fr10_private.configuration;')[0]['seconds']
        assert config == 180, 'Approved default required'
        emit({'physical_fixture_final_integrity':'PASS','seconds_restored':config,'orders':rows})
    elif action == 'unread':
        uid = account('customer')['profile_id']
        rows = h.query(f'select count(*)as unread from public.notifications where user_id={uid} and not is_read;')
        emit({'physical_notification_unread_database':rows[0]})
    elif action == 'push':
        assert label in h.state['native_orders']
        oid = h.state['native_orders'][label]['id']
        rows = h.query(f'select order_push_event_id::text as event from public.notifications where timeout_order_id={oid};')
        assert len(rows) == 1, 'Committed owner notice required'
        keys = [k.strip() for k in adb('shell','cmd','notification','list').splitlines() if PKG in k and rows[0]['event'] in k]
        assert len(keys) == 1, 'One actual TEST OS timeout notification required'
        notice = adb('shell','cmd','notification','get',shlex.quote(keys[0]))
        assert 'Order cancelled — vendor unavailable.' in notice, 'Actual timeout message required'
        emit({'physical_OS_timeout':label,'order_id':oid,'result':'PASS','one_notice':True,'exact_message':True})
    elif action == 'fields':
        print(json.dumps([{'class':n.get('class'),'bounds':n.get('bounds'),'text_length':len(n.get('text','')),'description':n.get('content-desc'),'password':n.get('password')} for n in screen() if n.get('class') == 'android.widget.EditText']))
    elif action == 'login':
        a = account(label)
        status, user = h.b.api('/auth/v1/admin/users/'+a['auth_id'],admin=True)
        assert status == 200 and any(k.endswith('fixture') and v is True for k,v in user['user_metadata'].items()), 'Marked synthetic account required'
        fields = [n for n in screen() if n.get('class') == 'android.widget.EditText']
        assert len(fields) == 2, 'Observed TEST sign-in fields required'
        if fields[0].get('text') != a['email']:
            tap(fields[0])
            adb('shell','input','keyevent','123')
            for _ in range(len(fields[0].get('text',''))):
                adb('shell','input','keyevent','67')
            adb('shell','input','text',shlex.quote(a['email']))
            adb('shell','input','keyevent','4')
        fields = [n for n in screen() if n.get('class') == 'android.widget.EditText']
        tap(fields[1]);adb('shell','input','text',shlex.quote(a['password']))
        adb('shell','input','keyevent','4')
        nodes = [n for n in screen() if (n.get('content-desc') or n.get('text')) == 'Sign in as '+label.title()]
        assert len(nodes) == 1, 'Selected role must match synthetic account'
        tap(nodes[0]);emit({'action':'synthetic_login_submitted','role':label,'success_pending':True})
    elif action in ('tap','tap-containing'):
        nodes = [n for n in screen() if ((n.get('text') or n.get('content-desc') or '') == label if action == 'tap' else label in (n.get('text') or n.get('content-desc') or ''))]
        assert len(nodes) == 1, 'One exact observed TEST control required'
        tap(nodes[0]);emit({'action':'observed_control_tapped','label':label})
    elif action == 'contact':
        fields = [n for n in screen() if n.get('class') == 'android.widget.EditText']
        assert len(fields) == 3, 'Three observed checkout contact fields required'
        for index,value in [(1,'03000000000')]:
            fields = [n for n in screen() if n.get('class') == 'android.widget.EditText']
            tap(fields[index]);adb('shell','input','keyevent','123')
            for _ in range(len(fields[index].get('text',''))):
                adb('shell','input','keyevent','67')
            adb('shell','input','text',shlex.quote(value.replace(' ','%s')))
            adb('shell','input','keyevent','4')
        emit({'action':'synthetic_checkout_contact_entered'})
    elif action == 'type':
        assert label in ('FR10','FR10 synthetic TEST address'), 'Synthetic text only'
        fields = [n for n in screen() if n.get('class') == 'android.widget.EditText' and n.get('password') != 'true']
        assert len(fields) == 1, 'One observed input required'
        tap(fields[0]);adb('shell','input','text',shlex.quote(label.replace(' ','%s')))
        adb('shell','input','keyevent','4')
        emit({'action':'synthetic_text_entered','value':label})
    elif action == 'configure':
        assert 'native_original_timeout' not in h.state, 'Restore previous native configuration first'
        original = h.query('select vendor_acceptance_timeout_seconds as seconds from fr10_private.configuration;')[0]['seconds']
        h.state['native_original_timeout'] = original;h.save()
        h.query('update fr10_private.configuration set vendor_acceptance_timeout_seconds=60;')
        emit({'action':'TEST_timeout_configured','seconds':60,'original_saved':True})
    elif action == 'restore':
        original = h.state['native_original_timeout']
        assert isinstance(original,int) and 60 <= original <= 3600
        result = h.query(f'update fr10_private.configuration set vendor_acceptance_timeout_seconds={original} returning vendor_acceptance_timeout_seconds as seconds;')[0]
        assert result['seconds'] == original
        del h.state['native_original_timeout'];h.save()
        emit({'action':'TEST_timeout_restored','seconds':original})
    elif action == 'record-ui-checkout':
        a = account('customer')
        rows = h.query(f"select o.id,o.order_status,o.acceptance_deadline_at,(select acceptance_deadline_at-acceptance_started_at from public.vendor_orders where order_id=o.id limit 1)::text as duration from public.orders o where user_id={a['profile_id']} and checkout_request_id is not null and created_at>clock_timestamp()-interval '10 minutes' order by id desc limit 1;")
        assert len(rows) == 1 and rows[0]['duration'] == '00:01:00', 'Actual recent UI checkout with 60-second snapshot required'
        h.state.setdefault('native_orders',{})['ui-cod'] = {'id':rows[0]['id']};h.save()
        emit({'action':'actual_UI_checkout_database_confirmed',**rows[0]})
    elif action == 'seed':
        assert label in ('cod','captured','vendor-before','vendor-after')
        a = account('customer');vendor = account('vendor')['profile_id']
        status, products = h.b.api(f'/rest/v1/products?vendor_id=eq.{vendor}&is_available=eq.true&select=id&limit=1',admin=True)
        assert status == 200 and len(products) == 1
        request = {'p_request_id':str(uuid.uuid4()),'p_items':[{'product_id':products[0]['id'],'quantity':1}], 'p_delivery':{'address':'FR10 synthetic physical TEST','lat':33.68,'lng':73.04,'speed':'standard'}}
        status,result = h.b.rpc('fr10_checkout',request,h.b.login(a))
        assert status == 200 and result['code'] == 'PLACED'
        oid = result['order_id']
        if label == 'captured':
            # Explicit synthetic captured-provider fixture, no money was collected.
            h.query(f"update public.payments set method='CARD',status='SUCCESS',paidat=clock_timestamp() where orderid='{oid}' and customerid='{a['profile_id']}';update public.orders set payment_method='CARD' where id={oid};")
        h.state.setdefault('native_orders',{})[label] = {'id':oid,'request_id':request['p_request_id']};h.save()
        emit({'action':'synthetic_physical_order_created','scenario':label,'order_id':oid,'actual_money_movement':False})
    elif action == 'verify':
        ids = [v['id'] for v in h.state.get('native_orders',{}).values()]
        assert ids and all(isinstance(i,int) for i in ids)
        rows = h.query('select o.id,o.order_status,o.cancellation_reason,o.timeout_review_reason,(select count(*)from public.notifications where timeout_order_id=o.id)as notices,(select count(*)from public.order_refund_actions where order_id=o.id and status=\'PENDING\')as refunds,(select count(*)from public.order_timeline_events where order_id=o.id and status=\'cancelled\')as cancellation_events from public.orders o where id in('+','.join(map(str,ids))+') order by id;')
        emit({'action':'physical_fixture_database_observation','orders':rows})
    else:
        raise AssertionError('Unknown guarded physical action')

if __name__ == '__main__':
    try:
        main(sys.argv[1],sys.argv[2])
    except Exception as e:
        print(json.dumps({'failed':True,'reason':str(e) if isinstance(e,AssertionError) else 'Guarded operation failed; credentials withheld','type':type(e).__name__}))
        sys.exit(1)
