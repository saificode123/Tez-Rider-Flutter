"""One persistent, explicitly marked synthetic COD workflow through the TEST gateway.

No deletion, paid capture/refund, rider assignment, routing, or provider sending.
Secrets/fixture identifiers are DPAPI-protected, and only checks are printed.
"""
import importlib.util,json,secrets,uuid,urllib.parse
from pathlib import Path
spec=importlib.util.spec_from_file_location('b',Path(__file__).with_name('FR-04-hosted.py'));b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
b.target();OUT=b.ROOT/'.fr21-local/final01';F=b.PRIVATE/'final01-workflow.bin';checks=[]
state=json.loads(b.crypt(F.read_bytes(),True))if F.exists()else {'email':'final01-'+uuid.uuid4().hex+'@example.test','password':secrets.token_urlsafe(24)+'aA7!','product_request':str(uuid.uuid4()),'checkout_request':str(uuid.uuid4())}
def save():F.write_bytes(b.crypt(json.dumps(state).encode()))
def check(ok,label):
 assert ok,label
 checks.append({'check':label,'result':'PASS'})
 (OUT/'workflow-results.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
 print(json.dumps(checks[-1]),flush=True)
def api(path,method='GET',body=None,token=None):
 parsed=urllib.parse.urlsplit(path)
 return b.api('/functions/v1/security-gateway','POST',{'method':method,'path':parsed.path,'query':parsed.query,'headers':{'content-type':'application/json','prefer':'return=representation'},'body':json.dumps(body)if body is not None else ''},token)
def rpc(name,body,token):return api('/rpc/'+name,'POST',body,token)
save()
if 'auth_id'not in state:
 code,user=b.api('/auth/v1/admin/users','POST',{'email':state['email'],'password':state['password'],'email_confirm':True,'user_metadata':{'name':'FINAL01 SYNTHETIC SECURITY TEST','role':'customer','final01_fixture':True}},admin=True)
 check(code in(200,201),'isolated marked Auth fixture created without SMTP')
 state['auth_id']=user['id'];save()
if 'profile_id'not in state:
 code,rows=b.api('/rest/v1/users?auth_user_id=eq.'+state['auth_id']+'&select=id',admin=True)
 assert code==200
 if not rows:
  code,rows=b.api('/rest/v1/users','POST',{'auth_user_id':state['auth_id'],'name':'FINAL01 SYNTHETIC SECURITY TEST','email':state['email'],'role':'customer','verification_status':'approved'},admin=True)
  check(code==201,'isolated canonical customer profile created')
 state['profile_id']=rows[0]['id'];save()
accounts=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']
tokens={role:b.login(accounts[role])for role in('customer','vendor','rider')};customer=b.login(state);vendor=tokens['vendor']
code,rows=api('/users?id=eq.'+str(state['profile_id'])+'&select=id,name','PATCH',{'name':'FINAL01 SYNTHETIC SECURITY TEST UPDATED'},customer)
check(code==200 and len(rows)==1 and rows[0]['name'].endswith('UPDATED'),'own profile write confirmed by actual returned row')
code,_=api('/users?id=eq.'+str(state['profile_id']),'PATCH',{'role':'admin'},customer)
check(code==403,'customer cannot promote canonical role')
product_body={'p_request_id':state['product_request'],'p_product_id':None,'p_data':{'name':'FINAL01 SECURITY SYNTHETIC TEST ONLY','price':25,'is_available':True},'p_stock':4,'p_threshold':0,'p_expected_version':None}
code,result=rpc('fr17_save_product',product_body,vendor)
check(code==200 and result['code']in('UPDATED','ALREADY_UPDATED'),'vendor product and inventory save through gateway')
state['product_id']=result['product_id'];save();pid=str(state['product_id'])
code,denied=rpc('fr17_save_product',dict(product_body,p_request_id=str(uuid.uuid4())),customer)
check(code==200 and denied['code']=='FORBIDDEN','customer cannot create vendor inventory')
checkout={'p_request_id':state['checkout_request'],'p_items':[{'product_id':state['product_id'],'quantity':1}],'p_delivery':{'address':'FINAL01 SECURITY SYNTHETIC TEST ONLY','lat':33.68,'lng':73.04,'speed':'standard','destination_confirmed':True,'destination_source':'map_pin'}}
code,result=rpc('fr10_checkout',checkout,customer)
check(code==200 and result['code']in('PLACED','ALREADY_PLACED'),'customer atomic COD checkout confirmed')
state['order_id']=result['order_id'];save();oid=str(state['order_id'])
code,replay=rpc('fr10_checkout',checkout,customer)
check(code==200 and replay['code']=='ALREADY_PLACED'and replay['order_id']==state['order_id'],'checkout retry preserves exact order identity')
code,rows=api('/orders?id=eq.'+oid+'&select=id,user_id,payment_method',token=customer)
check(code==200 and len(rows)==1 and rows[0]['user_id']==state['profile_id']and rows[0]['payment_method']=='COD','owner reads real COD order')
code,rows=api('/orders?id=eq.'+oid+'&select=id',token=tokens['customer'])
check(code==200 and rows==[],'unrelated customer cannot read isolated order')
code,rows=api('/vendor_orders?order_id=eq.'+oid+'&select=id',token=vendor)
check(code==200 and len(rows)==1,'owning vendor reads its order child')
vo=rows[0]['id']
code,value=rpc('fr10_vendor_transition',{'p_vendor_order_id':vo,'p_status':'accepted'},customer)
check(code==200 and value['code']=='FORBIDDEN','customer cannot perform vendor transition')
if not state.get('cancelled'):
 code,value=rpc('fr10_vendor_transition',{'p_vendor_order_id':vo,'p_status':'accepted'},vendor)
 check(code==200 and value['code']in('ACCEPTED','ALREADY_ACCEPTED'),'vendor accepts own synthetic child')
 code,value=rpc('fr10_vendor_transition',{'p_vendor_order_id':vo,'p_status':'cancelled'},vendor)
 check(code==200 and value['code']=='ORDER_CANCELLED','vendor cancels real unpaid COD order through intended workflow')
 state['cancelled']=True;save()
code,value=rpc('fr10_vendor_transition',{'p_vendor_order_id':vo,'p_status':'cancelled'},vendor)
check(code==200 and value['code']=='ORDER_CANCELLED','cancellation retry is idempotent')
code,rows=api('/products?id=eq.'+pid+'&select=stock_qty',token=vendor)
check(code==200 and len(rows)==1 and rows[0]['stock_qty']==4,'stock restored exactly once after cancellation')
code,rows=api('/orders?id=eq.'+oid+'&select=order_status',token=customer)
check(code==200 and rows[0]['order_status']=='cancelled','owner confirms persisted terminal cancellation')
# Privileged read verifies accounting only; never counted as user-RLS evidence.
code,rows=b.api('/rest/v1/payments?orderid=eq.'+oid+'&select=method,status',admin=True)
check(code==200 and len(rows)==1 and rows[0]['method']=='COD'and rows[0]['status']not in('captured','paid','refunded'),'accounting evidence: no fabricated capture or refund')
print(json.dumps({'TEST':b.REF,'checks':len(checks),'synthetic_workflow':True,'fixtures_preserved':True,'provider_calls':0,'physical_device_test':False}))
