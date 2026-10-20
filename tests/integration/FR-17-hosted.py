"""Actual bounded TEST HTTP checks. No live payment, email or hosted load."""
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import secrets
import sys
import uuid

spec=importlib.util.spec_from_file_location('fr10',Path(__file__).with_name('FR-10-hosted.py'))
old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
b=old.b;ROOT=old.ROOT;OUT=ROOT/'.fr21-local/fr17';FILE=b.PRIVATE/'fr17-accounts.bin'
state=json.loads(b.crypt(FILE.read_bytes(),True))if FILE.exists()else{'accounts':{},'products':{},'orders':{}}
checks=[]
def save():FILE.write_bytes(b.crypt(json.dumps(state).encode()))
def check(value,label):
    assert value,label
    checks.append({'check':label,'result':'PASS'})
def query(sql):
    path=OUT/'hosted-query.sql';path.write_text(sql,encoding='utf-8')
    return old.previous.query(path)['rows']
def fixture(label,role):
    a=state['accounts'].setdefault(label,{'email':'fr17-'+label+'@example.test','password':secrets.token_urlsafe(28)+'aA7!'})
    save()
    if'auth_id'not in a:
        status,row=b.api('/auth/v1/admin/users','POST',{'email':a['email'],'password':a['password'],'email_confirm':True,'user_metadata':{'fr17_fixture':True,'role':role}},admin=True)
        assert status in(200,201),'Synthetic confirmed fixture creation'
        a['auth_id']=row['id'];save()
    if'profile_id'not in a:
        status,rows=b.api('/rest/v1/users','POST',{'email':a['email'],'name':'FR17 synthetic '+label,'role':role,'verification_status':'approved'},admin=True)
        assert status==201,'Synthetic profile creation'
        a['profile_id']=rows[0]['id'];save()
    return a
def product(label,qty=20,threshold=5,owner='vendor'):
    a=state['accounts'][owner]
    status,r=b.rpc('fr17_save_product',{'p_request_id':str(uuid.uuid4()),'p_product_id':None,'p_data':{'name':'FR17 synthetic '+label,'price':80,'is_available':True},'p_stock':qty,'p_threshold':threshold,'p_expected_version':None},b.login(a))
    assert status==200 and r['code']=='UPDATED','Real product/stock RPC required'
    state['products'][label]={'id':r['product_id'],'owner':owner};save()
    return r['product_id']
def read_product(pid,token):
    status,rows=b.api(f'/rest/v1/products?id=eq.{pid}&select=id,stock_qty,stock_version,stock_confirmed,is_available,low_stock_threshold',token=token)
    assert status==200 and len(rows)==1,'Scoped current stock read required'
    return rows[0]
def checkout(items,token,request=None):
    return b.rpc('fr10_checkout',{'p_request_id':request or str(uuid.uuid4()),'p_items':items,'p_delivery':{'address':'FR17 synthetic TEST','lat':33.68,'lng':73.04,'speed':'standard','destination_confirmed':True,'destination_source':'map_pin'}},token)
def adjust(pid,qty,token,req=None,threshold=None):
    row=read_product(pid,token)
    return b.rpc('vendor_adjust_stock',{'p_product_id':pid,'p_quantity':qty,'p_mode':'set','p_reason':'FR17 synthetic verified count','p_request_id':req or str(uuid.uuid4()),'p_threshold':threshold,'p_expected_version':row['stock_version']},token)
def expire(oid):
    assert oid in [o['id']for o in state['orders'].values()],'Only recorded FR17 orders may be clock-controlled'
    # This helper is used only by the synthetic captured shared-order case.
    # Establish its financial fixture before publishing an expired deadline;
    # otherwise the real cron can correctly cancel COD before capture is seeded.
    query(f"begin;update public.orders set payment_method='CARD'where id={oid};update public.payments set method='CARD',status='SUCCESS',paidat=clock_timestamp()where orderid='{oid}';create temp table original as select checkout_finalized_at as stamp from public.orders where id={oid};update public.orders set checkout_finalized_at=null where id={oid};update public.vendor_orders set acceptance_started_at=clock_timestamp()-interval '1 hour',acceptance_deadline_at=clock_timestamp()-interval '1 second'where order_id={oid};update public.orders set checkout_finalized_at=(select stamp from original),acceptance_deadline_at=clock_timestamp()-interval '1 second'where id={oid};commit;")

def hosted():
    for label,role in[('vendor','vendor'),('vendor2','vendor'),('customer','customer'),('other','customer'),('rider','rider'),('admin','admin')]:fixture(label,role)
    tokens={k:b.login(v)for k,v in state['accounts'].items()}
    v=tokens['vendor'];c=tokens['customer']
    p=product('atomic',20);q=product('shared-other',20,5,'vendor2')
    req=str(uuid.uuid4());items=[{'product_id':p,'quantity':2}]
    status,r=checkout(items,c,req);check(status==200 and r['code']=='PLACED','HTTP atomic checkout committed')
    state['orders']['atomic']={'id':r['order_id']};save()
    check(read_product(p,v)['stock_qty']==18,'HTTP exact decrement')
    status,again=checkout(items,c,req);check(status==200 and again['code']=='ALREADY_PLACED'and read_product(p,v)['stock_qty']==18,'HTTP retry no double decrement')
    status,ledger=b.api(f'/rest/v1/inventory_movements?order_id=eq.{r["order_id"]}&select=movement_type,quantity_delta',token=v)
    check(status==200 and ledger==[{'movement_type':'ORDER_DECREMENT','quantity_delta':-2}],'HTTP owner ledger actual movement')
    last=product('last-unit',1,0)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
        results=list(pool.map(lambda token:checkout([{'product_id':last,'quantity':1}],token),[c,tokens['other']]))
    check(all(s==200 for s,r in results)and sorted(r['code']for s,r in results)==['INSUFFICIENT_STOCK','PLACED'],'two real concurrent HTTP buyers no oversell')
    check(read_product(last,v)['stock_qty']==0,'concurrent HTTP final stock zero')
    before=query(f'select count(*)as n from public.orders where user_id={state["accounts"]["customer"]["profile_id"]};')[0]['n']
    status,r=checkout([{'product_id':p,'quantity':1},{'product_id':last,'quantity':1}],c)
    check(status==200 and r['code']=='INSUFFICIENT_STOCK'and r['shortages'][0]['product_id']==last,'HTTP structured multi-item shortage')
    after=query(f'select count(*)as n from public.orders where user_id={state["accounts"]["customer"]["profile_id"]};')[0]['n']
    check(before==after and read_product(p,v)['stock_qty']==18,'HTTP shortage no partial order or stock')
    status,r=checkout([{'product_id':p,'quantity':1},{'product_id':p,'quantity':2}],c)
    check(status==200 and r['code']=='PLACED'and read_product(p,v)['stock_qty']==15,'HTTP duplicate product aggregation')
    # Shared order, one accepted sibling, verified synthetic captured payment.
    status,r=checkout([{'product_id':p,'quantity':2},{'product_id':q,'quantity':3}],c)
    check(status==200 and r['code']=='PLACED','HTTP shared checkout')
    oid=r['order_id'];state['orders']['shared']={'id':oid};save()
    status,children=b.api(f'/rest/v1/vendor_orders?order_id=eq.{oid}&select=id',token=v)
    assert status==200 and len(children)==1
    status,accepted=b.rpc('fr10_vendor_transition',{'p_vendor_order_id':children[0]['id'],'p_status':'accepted'},v)
    check(status==200 and accepted['code']=='ACCEPTED','shared sibling accepted before timeout')
    expire(oid)
    query('select public.cancel_timed_out_orders();')
    check(read_product(p,v)['stock_qty']==15 and read_product(q,tokens['vendor2'])['stock_qty']==20,'timeout restores every shared item')
    row=query(f"select(select count(*)from public.inventory_movements where order_id={oid} and movement_type='ORDER_RESTORE')as restores,(select count(*)from public.order_refund_actions where order_id={oid} and amount=600 and status='PENDING')as refunds,(select count(*)from public.notifications where timeout_order_id={oid})as notices;")[0]
    check(row=={'restores':2,'refunds':1,'notices':1},'shared full pending refund/notice preserved with two restores')
    query('select public.cancel_timed_out_orders();')
    check(query(f"select count(*)as n from public.inventory_movements where order_id={oid} and movement_type='ORDER_RESTORE';")[0]['n']==2,'repeated worker no duplicate restore')
    # Vendor rejection invokes the same stock hook.
    status,r=checkout([{'product_id':p,'quantity':2}],c);assert status==200 and r['code']=='PLACED';oid=r['order_id'];state['orders']['rejected']={'id':oid};save()
    status,rows=b.api(f'/rest/v1/vendor_orders?order_id=eq.{oid}&select=id',token=v);assert status==200 and len(rows)==1
    status,r=b.rpc('fr10_vendor_transition',{'p_vendor_order_id':rows[0]['id'],'p_status':'cancelled'},v)
    check(status==200 and r['code']=='ORDER_CANCELLED'and read_product(p,v)['stock_qty']==15,'HTTP vendor rejection restores')
    # Real crossing/re-arm owner notification rows.
    low=product('low-crossing',7,5)
    checkout([{'product_id':low,'quantity':2}],c);checkout([{'product_id':low,'quantity':1}],c)
    status,notices=b.api(f'/rest/v1/notifications?stock_product_id=eq.{low}&select=message',token=v)
    check(status==200 and notices==[{'message':'Low stock alert: FR17 synthetic low-crossing.'}],'one exact low-stock notice while below threshold')
    status,r=adjust(low,10,v);assert status==200 and r['code']=='UPDATED';checkout([{'product_id':low,'quantity':5}],c)
    status,notices=b.api(f'/rest/v1/notifications?stock_product_id=eq.{low}&select=id',token=v)
    check(status==200 and len(notices)==2,'restock re-arms low-stock HTTP notifications')
    for role in['customer','rider','vendor2']:
        status,result=b.rpc('vendor_adjust_stock',{'p_product_id':p,'p_quantity':1,'p_mode':'delta','p_reason':'Forged synthetic','p_request_id':str(uuid.uuid4())},tokens[role])
        check(status in(401,403)or(status==200 and result['code']=='FORBIDDEN'),role+' stock adjustment denied')
    for column,value in[('stock_qty',999),('low_stock_threshold',999),('stock_version',999),('stock_confirmed',True)]:
        status,_=b.api(f'/rest/v1/products?id=eq.{p}','PATCH',{column:value},token=v)
        check(status in(401,403),'direct '+column+' HTTP update denied')
    status,_=b.api('/rest/v1/inventory_movements','POST',{'product_id':p,'quantity_delta':100},token=v)
    check(status in(401,403),'direct ledger HTTP write denied')
    status,rows=b.api('/rest/v1/inventory_movements?select=id&limit=1',token=c)
    check(status==200 and rows==[],'customer ledger read isolated')
    vendor=state['accounts']['vendor'];status,auth=b.api('/auth/v1/admin/users/'+vendor['auth_id'],admin=True)
    assert status==200 and auth['user_metadata'].get('fr17_fixture')is True
    try:
        status,rows=b.api('/rest/v1/users?id=eq.'+str(vendor['profile_id']),'PATCH',{'is_blocked':True},admin=True)
        assert status==200 and len(rows)==1
        status,_=b.rpc('vendor_adjust_stock',{'p_product_id':p,'p_quantity':1,'p_mode':'delta','p_reason':'Blocked synthetic','p_request_id':str(uuid.uuid4())},v)
        check(status==403,'blocked owning vendor HTTP denied')
    finally:
        status,rows=b.api('/rest/v1/users?id=eq.'+str(vendor['profile_id']),'PATCH',{'is_blocked':False},admin=True)
        assert status==200 and len(rows)==1,'Synthetic vendor unblock restoration'
    (OUT/'hosted-tests.json').write_text(json.dumps({'passed':len(checks),'checks':checks,'project':b.REF,'actual_money_movement':False},indent=2),encoding='utf-8')
    print(json.dumps({'passed':len(checks),'synthetic_only':True,'TEST':b.REF}))

def verify():
    result=query("""select jsonb_build_object('versions',(select jsonb_agg(version order by version)from supabase_migrations.schema_migrations),
    'unconfirmed_products',(select count(*)from public.products where not stock_confirmed),
    'invalid_stock',(select count(*)from public.products where stock_qty<0 or low_stock_threshold<0),
    'authenticated_stock_write',has_column_privilege('authenticated','public.products','stock_qty','UPDATE'),
    'authenticated_threshold_write',has_column_privilege('authenticated','public.products','low_stock_threshold','UPDATE'),
    'authenticated_product_insert',has_table_privilege('authenticated','public.products','INSERT'),
    'ledger_write',has_table_privilege('authenticated','public.inventory_movements','INSERT'),
    'restore_execute',has_function_privilege('authenticated','fr17_private.restore_cancelled()','EXECUTE'),
    'ledger_rls',(select relrowsecurity from pg_class where oid='public.inventory_movements'::regclass),
    'indexes',(select jsonb_agg(indexname)from pg_indexes where indexname like 'fr17_%'),
    'cron',(select jsonb_agg(jsonb_build_object('id',jobid,'name',jobname,'active',active,'schedule',schedule))from cron.job where jobname in('fr10-order-timeout','fr30-android-push')),
    'timeout',(select vendor_acceptance_timeout_seconds from fr10_private.configuration))as verification;""")[0]['verification']
    check(result['invalid_stock']==0 and result['ledger_rls'],'stock constraints and ledger RLS')
    check(not any(result[k]for k in['authenticated_stock_write','authenticated_threshold_write','authenticated_product_insert','ledger_write','restore_execute']),'ordinary protected writes/internal restoration denied')
    check(len(result['versions'])==32 and result['versions'][-1]=='202610160002','exact migration history no replay')
    check(result['timeout']==180 and len(result['cron'])==2 and all(j['active']for j in result['cron']),'accepted scheduler/default preserved')
    (OUT/'hosted-verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({'verified':checks,'unconfirmed_existing_products':result['unconfirmed_products']}))

if __name__=='__main__':
    try:
        if sys.argv[1]=='hosted':hosted()
        elif sys.argv[1]=='verify':verify()
        else:raise ValueError('Unknown guarded hosted phase')
    except Exception as e:
        print(json.dumps({'failed':True,'reason':str(e)if isinstance(e,AssertionError)else'Guarded TEST operation failed; credentials withheld','type':type(e).__name__}))
        sys.exit(1)
