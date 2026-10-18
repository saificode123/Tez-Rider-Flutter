"""Checklist-aware synthetic TEST lifecycle for older regression fixtures.

No production exception is added. Older tests seeded transit/delivered directly;
their fixtures now submit the real checklist and call the real start RPC first.
"""
import json,secrets,subprocess,uuid
from pathlib import Path

def start(b,order_id,rider):
 token=b.login(rider)
 status,data=b.rpc('pre_delivery_checklist',{'p_order_id':order_id},token)
 assert status==200 and data['code']=='OK','Fixture checklist definition unavailable'
 status,result=b.rpc('submit_pre_delivery_checklist',{
  'p_assignment_id':data['assignment_id'],'p_version':data['version'],
  'p_confirmations':[{'id':i['id'],'confirmed':True}for i in data['items']]},token)
 assert status==200 and result['code']=='COMPLETED','Real fixture checklist submission failed'
 status,result=b.rpc('start_checklisted_delivery',{'p_assignment_id':data['assignment_id']},token)
 assert status==200 and result['code']=='STARTED','Real fixture start failed'

def financial_rider(b):
 path=b.PRIVATE/'checklist-regression-fixtures.bin'
 a=json.loads(b.crypt(path.read_bytes(),True))if path.exists()else{
  'email':'checklist-financial-rider@example.test','password':secrets.token_urlsafe(28)+'aA7!'}
 def save():path.write_bytes(b.crypt(json.dumps(a).encode()))
 save()
 if'auth_id'not in a:
  status,user=b.api('/auth/v1/admin/users','POST',{'email':a['email'],'password':a['password'],'email_confirm':True,'user_metadata':{'checklist_fixture':True,'role':'rider'}},admin=True)
  assert status in(200,201),'Own synthetic regression rider creation failed';a['auth_id']=user['id'];save()
 if'profile_id'not in a:
  status,rows=b.api('/rest/v1/users','POST',{'email':a['email'],'name':'CHECKLIST financial regression SYNTHETIC','role':'rider','verification_status':'approved'},admin=True)
  assert status==201;a['profile_id']=rows[0]['id'];save()
 status,user=b.api('/auth/v1/admin/users/'+a['auth_id'],admin=True)
 assert status==200 and user['user_metadata'].get('checklist_fixture')is True,'Only owned synthetic rider permitted'
 return a

def create(b,body,rider=None):
 b.target();assert b.REF=='igeisilhtmglgnqvllrx'
 expected=body['order_status'];assert expected in('on_the_way','delivered')
 assert 'SYNTHETIC'in body.get('delivery_address',''),'Only explicitly synthetic fixtures supported'
 rider=rider or financial_rider(b);rid=int(rider['profile_id'])
 status,user=b.api('/auth/v1/admin/users/'+rider['auth_id'],admin=True)
 assert status==200 and any(k.endswith('fixture')and v is True for k,v in user['user_metadata'].items()),'Marked fixture identity required'
 # The old FR33 verifier suite creates sequential security scenarios for one
 # rider. Retire only its previous synthetic assignment, never another job.
 status,active=b.api(f'/rest/v1/rider_assignments?riderid=eq.{rid}&status=in.(Pending,Accepted)&select=id,orderid',admin=True)
 assert status==200
 for assignment in active:
  status,orders=b.api('/rest/v1/orders?id=eq.'+str(assignment['orderid'])+'&select=delivery_address',admin=True)
  allowed={body['delivery_address']}
  if rider['email']=='checklist-financial-rider@example.test':allowed.update(('FR25 SYNTHETIC TEST ONLY','FR26 SYNTHETIC TEST ONLY'))
  assert status==200 and len(orders)==1 and orders[0]['delivery_address']in allowed,'Unrelated active assignment must be preserved'
  status,_=b.api('/rest/v1/rider_assignments?id=eq.'+str(assignment['id']),'PATCH',{'status':'Cancelled'},admin=True);assert status==200
 status,rows=b.api('/rest/v1/orders','POST',{**body,'rider_id':rid,'order_status':'ready'},admin=True)
 assert status==201 and len(rows)==1;oid=rows[0]['id']
 status,_=b.api('/rest/v1/rider_assignments','POST',{'orderid':oid,'riderid':rid,'status':'Accepted'},admin=True);assert status==201
 start(b,oid,rider)
 if expected=='delivered':
  # Explicit privileged historical fixture, not a claim of real OTP delivery.
  # The real checklist/start gate has already passed. No email/quota is used.
  sql=f"begin;update public.orders set order_status='delivered'where id={int(oid)} and rider_id={rid};update public.rider_assignments set status='Delivered'where orderid={int(oid)} and riderid={rid};commit;"
  path=b.ROOT/'.fr21-local/checklist'/('financial-fixture-'+str(uuid.uuid4())+'.sql')
  path.write_text(sql)
  try:
   p=subprocess.run(['C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe','db','query','--linked','--project-ref',b.REF,'--file',str(path),'--output','json'],capture_output=True,text=True,timeout=120)
   (b.ROOT/'.fr21-local/checklist/financial-fixture-last.log').write_text(p.stdout+p.stderr,encoding='utf-8')
   assert p.returncode==0,'Protected financial fixture state not confirmed'
  finally:path.unlink(missing_ok=True)
 status,rows=b.api('/rest/v1/orders?id=eq.'+str(oid),admin=True)
 assert status==200 and len(rows)==1 and rows[0]['order_status']==expected
 return 201,rows
