"""Observed physical TEST UI and synthetic inventory fixture probes only."""
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess
import sys
import time
import uuid

def load(name,file):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
h=load('fr17','FR-17-hosted.py');ui=load('fr10ui','FR-10-native.py')
adb=ui.adb;screen=ui.screen;tap=ui.tap
def emit(value):
    with(h.OUT/'native-evidence.jsonl').open('a',encoding='utf-8')as file:file.write(json.dumps(value)+'\n')
    print(json.dumps(value),flush=True)
def labels():return[n.get('text')or n.get('content-desc')or''for n in screen()]
def account(label):
    assert label in('vendor','vendor2','customer')
    return h.state['accounts'][label]
def fields():return[n for n in screen()if n.get('class')=='android.widget.EditText']
def foreground():
    assert ui.PKG in adb('shell','dumpsys','activity','activities').split('topResumedActivity=')[-1].splitlines()[0],'TEST app must remain foreground before input'

def fill(node,value):
    assert node.get('password')!='true','Passwords use protected login only'
    foreground();tap(node);foreground();adb('shell','input','keyevent','123')
    for _ in range(len(node.get('text',''))):adb('shell','input','keyevent','67')
    foreground();adb('shell','input','text',shlex.quote(value.replace(' ','%s')));adb('shell','input','keyevent','4')
def native_product(label):return h.state['native_products'][label]['id']
def observe_orders():
    uid=account('customer')['profile_id']
    return h.query(f"select o.id,o.order_status,o.amount,o.cancellation_reason,(select jsonb_agg(jsonb_build_object('product_id',i.product_id,'qty',i.quantity,'child',v.id,'status',v.status))from public.vendor_orders v join public.order_items i on i.vendor_order_id=v.id where v.order_id=o.id)as items,(select count(*)from public.inventory_movements where order_id=o.id and movement_type='ORDER_RESTORE')as restores,(select count(*)from public.inventory_movements where order_id=o.id and movement_type='ORDER_DECREMENT')as decrements from public.orders o where o.user_id={uid} and o.checkout_request_id is not null order by o.id desc limit 10;")
def main(action,label,value):
    if action=='screen':
        print(json.dumps([{'label':n.get('text')or n.get('content-desc'),'bounds':n.get('bounds'),'class':n.get('class'),'enabled':n.get('enabled')}for n in screen()if(n.get('text')or n.get('content-desc'))and n.get('class')!='android.widget.EditText']))
    elif action=='fields':
        print(json.dumps([{'index':i,'text':n.get('text')if n.get('password')!='true'else'[protected]','bounds':n.get('bounds'),'hint':n.get('hint')}for i,n in enumerate(fields())]))
    elif action=='fill':
        assert label.isdigit()and int(label)<len(fields())and(value.isdecimal()or value.startswith('FR17')or value=='Physical stock count'),'Synthetic input only'
        fill(fields()[int(label)],value);emit({'action':'synthetic_UI_field_filled','index':int(label)})
    elif action in('tap','tap-containing'):
        nodes=[n for n in screen()if ((n.get('text')or n.get('content-desc')or'')==label if action=='tap'else label in(n.get('text')or n.get('content-desc')or''))]
        assert len(nodes)==1,'One observed TEST control required';tap(nodes[0]);emit({'action':'observed_control_tapped','label':label})
    elif action=='login':
        a=account(label);status,user=h.b.api('/auth/v1/admin/users/'+a['auth_id'],admin=True)
        assert status==200 and user['user_metadata'].get('fr17_fixture')is True,'Own marked synthetic account required'
        inputs=fields();assert len(inputs)==2,'Observed TEST login required'
        fill(inputs[0],a['email']);inputs=fields();tap(inputs[1]);foreground();adb('shell','input','text',shlex.quote(a['password']));adb('shell','input','keyevent','4')
        nodes=[n for n in screen()if(n.get('text')or n.get('content-desc'))=='Sign in as '+label.title()]
        assert len(nodes)==1,'Selected synthetic role required';tap(nodes[0]);emit({'action':'synthetic_login_submitted','role':label,'result_pending':True})
    elif action=='record-product':
        uid=account('vendor')['profile_id']
        status,rows=h.b.api(f'/rest/v1/products?vendor_id=eq.{uid}&name=eq.FR17%20physical%20stock&select=id,stock_qty,stock_version,low_stock_threshold,stock_confirmed,is_available&order=id.desc&limit=1',token=h.b.login(account('vendor')))
        assert status==200 and len(rows)==1 and rows[0]['stock_confirmed'],'Actual confirmed physical product required'
        h.state.setdefault('native_products',{})['physical']=rows[0];h.save();emit({'actual_UI_product_database_confirmed':True,**rows[0]})
    elif action=='seed':
        assert label in('zero','valid','shared','shared2','low')
        qty={'zero':0,'valid':20,'shared':20,'shared2':20,'low':7}[label]
        owner='vendor2'if label=='shared2'else'vendor'
        pid=h.product('physical '+label,qty,5,owner)
        h.state.setdefault('native_products',{})[label]={'id':pid,'owner':owner};h.save();emit({'synthetic_physical_fixture_seeded':label,'product_id':pid,'stock':qty})
    elif action=='stock':
        pid=native_product(label);owner=h.state['native_products'][label].get('owner','vendor')
        row=h.read_product(pid,h.b.login(account(owner)))
        if value:assert row['stock_qty']==int(value),'Actual stock mismatch'
        emit({'physical_fixture_stock_observed':label,**row})
    elif action=='adjust':
        pid=native_product(label);owner=h.state['native_products'][label].get('owner','vendor')
        status,result=h.adjust(pid,int(value),h.b.login(account(owner)))
        assert status==200 and result['code']=='UPDATED';emit({'synthetic_server_stock_changed':label,'stock':result['stock_qty']})
    elif action=='purchase':
        pid=native_product(label);status,result=h.checkout([{'product_id':pid,'quantity':int(value)}],h.b.login(account('customer')))
        assert status==200 and result['code']=='PLACED'
        h.state.setdefault('native_orders',{})[label]={'id':result['order_id']};h.save();emit({'actual_synthetic_checkout_committed':label,'order_id':result['order_id']})
    elif action=='orders':emit({'physical_fixture_orders':observe_orders()})
    elif action=='order-clock':
        ids=','.join(str(int(o['id']))for o in h.state['native_orders'].values())
        emit({'recorded_physical_order_clocks':h.query(f"select o.id,o.order_status,o.cancellation_reason,o.checkout_finalized_at,o.acceptance_deadline_at,clock_timestamp()as observed_at,(select jsonb_agg(jsonb_build_object('id',v.id,'status',v.status,'started',v.acceptance_started_at,'deadline',v.acceptance_deadline_at))from public.vendor_orders v where v.order_id=o.id)as portions from public.orders o where o.id in({ids})order by o.id;")})
    elif action in('shortage-before','shortage-after'):
        uid=account('customer')['profile_id']
        status,rows=h.b.api(f'/rest/v1/orders?user_id=eq.{uid}&select=id',token=h.b.login(account('customer')))
        assert status==200
        if action=='shortage-before':
            h.state['native_shortage_order_count']=len(rows);h.save();emit({'physical_shortage_baseline_orders':len(rows)})
        else:
            assert len(rows)==h.state['native_shortage_order_count'],'Shortage created an order'
            assert h.read_product(native_product('valid'),h.b.login(account('vendor')))['stock_qty']==20,'Valid item was partially decremented'
            emit({'physical_shortage_no_partial_order_or_stock':'PASS','order_count_unchanged':True,'valid_stock':20})
    elif action=='integrity':
        ids=[int(p['id'])for p in h.state.get('native_products',{}).values()]
        assert ids,'Recorded physical fixtures required'
        products=','.join(map(str,ids))
        row=h.query(f"select(select count(*)from public.products p where p.id in({products})and(p.stock_qty<0 or p.stock_qty<>(select coalesce(sum(m.quantity_delta),0)from public.inventory_movements m where m.product_id=p.id)))as unreconciled,(select count(*)from(select order_item_id,movement_type from public.inventory_movements where product_id in({products})and order_item_id is not null group by order_item_id,movement_type having count(*)>1)x)as duplicate_movements,(select count(*)from public.inventory_movements m join public.orders o on o.id=m.order_id where m.product_id in({products})and m.movement_type='ORDER_DECREMENT'and o.order_status='cancelled'and not exists(select 1 from public.inventory_movements r where r.order_item_id=m.order_item_id and r.movement_type='ORDER_RESTORE'))as missing_restores;")[0]
        assert all(v==0 for v in row.values()),'Physical fixture inventory integrity failed'
        assert'native_original_timeout'not in h.state,'Restore temporary TEST configuration first'
        emit({'physical_fixture_final_integrity':'PASS','products':len(ids),**row})
    elif action=='ledger-size':
        row=h.query("select count(*)as rows,pg_table_size('public.inventory_movements')as table_bytes,pg_indexes_size('public.inventory_movements')as index_bytes,round(avg(pg_column_size(m)))as mean_tuple_bytes from public.inventory_movements m;")[0]
        (h.OUT/'ledger-size.json').write_text(json.dumps(row,indent=2),encoding='utf-8');emit({'observed_TEST_ledger_size':row})
    elif action=='record-order':
        rows=observe_orders();assert rows and rows[0]['decrements']>0,'Actual UI checkout with inventory decrement required'
        if label=='ui-shared':
            assert rows[0]['decrements']==2 and {i['product_id']for i in rows[0]['items']}=={native_product('valid'),native_product('shared2')},'Confirmed new two-vendor UI order required; old order is not evidence'
        elif label=='ui-reject':
            assert rows[0]['decrements']==1 and rows[0]['items'][0]['product_id']==native_product('physical'),'Matching UI-created product order required'
        h.state.setdefault('native_orders',{})[label]={'id':rows[0]['id']};h.save();emit({'physical_UI_checkout_database_confirmed':label,**rows[0]})
    elif action=='verify-cancel':
        assert label in('ui-reject','ui-shared')
        oid=int(h.state['native_orders'][label]['id']);expected='vendor_rejected'if label=='ui-reject'else'vendor_timeout'
        row=h.query(f"select o.order_status,o.cancellation_reason,(select count(*)from public.vendor_orders v where v.order_id=o.id)as children,(select count(*)from public.vendor_orders v where v.order_id=o.id and v.status<>'cancelled')as live_children,(select count(*)from public.inventory_movements where order_id=o.id and movement_type='ORDER_DECREMENT')as decrements,(select count(*)from public.inventory_movements where order_id=o.id and movement_type='ORDER_RESTORE')as restores,(select count(*)from public.notifications where timeout_order_id=o.id)as notices,(select count(*)from public.order_refund_actions where order_id=o.id)as refunds from public.orders o where o.id={oid};")[0]
        expected_notices=1 if label=='ui-shared'else 0
        assert row['order_status']=='cancelled'and row['cancellation_reason']==expected and row['live_children']==0 and row['decrements']==row['restores']and row['notices']==expected_notices and row['refunds']==0,'Cancellation/restoration invariant failed'
        if label=='ui-shared':
            assert row['children']==2 and row['restores']==2
            for product_label in('valid','shared2'):
                owner=h.state['native_products'][product_label].get('owner','vendor')
                assert h.read_product(native_product(product_label),h.b.login(account(owner)))['stock_qty']==20
        else:assert h.read_product(native_product('physical'),h.b.login(account('vendor')))['stock_qty']==16
        emit({'physical_cancellation_database_check':label,'result':'PASS',**row})
    elif action=='repeat-cancel':
        oid=int(h.state['native_orders']['ui-shared']['id'])
        row=h.query(f"do $$begin if(select count(*)from public.inventory_movements where order_id={oid} and movement_type='ORDER_RESTORE')<>2 then raise exception 'Observe shared cancellation before retry';end if;perform public.cancel_timed_out_orders();if(select count(*)from public.inventory_movements where order_id={oid} and movement_type='ORDER_RESTORE')<>2 then raise exception 'Repeated worker restored twice';end if;end$$;select count(*)as restores from public.inventory_movements where order_id={oid} and movement_type='ORDER_RESTORE';")[0]
        emit({'physical_shared_repeated_worker_restores_once':'PASS',**row})
    elif action=='assert-ui':
        seen=labels()
        assert label in('inventory','zero','shortage','cancelled','notification')
        expected={'inventory':'units','zero':'This product is currently out of stock.','shortage':'Stock changed','cancelled':'Order cancelled — vendor unavailable.','notification':'Low stock alert:'}[label]
        assert any(expected in s for s in seen),'Required actual UI state not observed'
        if label=='zero':assert any(n.get('class')=='android.widget.Button'and n.get('enabled')=='false'for n in screen()),'Disabled purchase control required'
        if label=='cancelled':
            target='Order #'+str(h.state['native_orders']['ui-shared']['id']);start=seen.index(target)
            end=next((i for i in range(start+1,len(seen))if seen[i].startswith('Order #')),len(seen))
            assert expected in seen[start:end],'Cancellation must belong to the actual new shared UI order'
        emit({'physical_UI_check':label,'result':'PASS','observed_labels':[s for s in seen if s]})
    elif action=='push':
        pid=native_product(label);a=account(h.state['native_products'][label].get('owner','vendor'))
        status,rows=h.b.api(f'/rest/v1/notifications?stock_product_id=eq.{pid}&select=order_push_event_id,message&order=id',token=h.b.login(a))
        assert status==200 and len(rows)==int(value),'Exact crossing count required'
        keys=[k.strip()for k in adb('shell','cmd','notification','list').splitlines()if ui.PKG in k]
        event=rows[-1]['order_push_event_id'];matches=[k for k in keys if event in k]
        assert len(matches)==1,'Actual latest inventory OS notification required'
        notice=adb('shell','cmd','notification','get',shlex.quote(matches[0]));assert rows[-1]['message']in notice
        emit({'physical_OS_inventory_notification':'PASS','product_id':pid,'crossing_notice_count':len(rows),'exact_message':True})
    elif action=='notification-read':
        status,rows=h.b.api('/rest/v1/notifications?is_read=eq.false&select=id&limit=1',token=h.b.login(account('vendor')))
        assert status==200 and rows==[],'Actual owning vendor unread count must be zero'
        emit({'physical_notification_mark_all_read':'PASS','own_unread_count':0})
    elif action=='configure':
        assert'native_original_timeout'not in h.state
        seconds=int(value)if value else 60
        assert 60<=seconds<=3600,'TEST acceptance timeout range required'
        h.state['native_original_timeout']=h.query('select vendor_acceptance_timeout_seconds as seconds from fr10_private.configuration;')[0]['seconds'];h.save()
        h.query(f'update fr10_private.configuration set vendor_acceptance_timeout_seconds={seconds};');emit({'TEST_timeout_seconds':seconds,'original_saved':True})
    elif action=='restore':
        original=h.state['native_original_timeout'];assert isinstance(original,int)and 60<=original<=3600
        row=h.query(f'update fr10_private.configuration set vendor_acceptance_timeout_seconds={original} returning vendor_acceptance_timeout_seconds as seconds;')[0]
        assert row['seconds']==original;del h.state['native_original_timeout'];h.save();emit({'TEST_timeout_restored':original})
    elif action=='logs':
        pid=adb('shell','pidof',ui.PKG).strip();assert pid.isdigit()
        logs=adb('logcat','-d','--pid',pid,'-v','brief');(h.OUT/'native-logcat.log').write_text(logs,encoding='utf-8')
        fatal=sum(s in logs for s in['FATAL EXCEPTION','Fatal signal','Unhandled Exception','EXCEPTION CAUGHT BY','Failed assertion','used after being disposed']);assert fatal==0,'TEST runtime/assertion log observed'
        assert any(labels()),'Visible TEST UI required; empty/error screen is not a passing log check'
        emit({'physical_TEST_log_scan':'PASS','fatal_or_unhandled':fatal,'flutter_error_lines':sum('E/flutter'in line for line in logs.splitlines())})
    else:raise AssertionError('Unknown guarded physical action')
if __name__=='__main__':
    try:main(sys.argv[1],sys.argv[2],sys.argv[3]if len(sys.argv)>3 else'')
    except Exception as e:
        print(json.dumps({'failed':True,'reason':str(e)if isinstance(e,AssertionError)else'Guarded physical operation failed; credentials withheld','type':type(e).__name__}));sys.exit(1)
