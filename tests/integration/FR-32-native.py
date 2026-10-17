"""Observed UI only on the authorized physical TEST package; no simulated taps."""
import importlib.util
import json
import re
from pathlib import Path
import shlex
import sys
import time
import xml.etree.ElementTree as ET

def load(name,file):
 spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
h=load('fr32','FR-32-hosted.py');ui=load('fr10ui','FR-10-native.py')
adb=ui.adb;screen=ui.screen;tap=ui.tap
def emit(value):
 with(h.OUT/'native-evidence.jsonl').open('a')as f:f.write(json.dumps(value)+'\n')
 print(json.dumps(value),flush=True)
def labels():return[n.get('text')or n.get('content-desc')or''for n in screen()]
def main(action):
 if action=='screen':
  print(json.dumps([{'label':'[synthetic account]'if'@'in(n.get('text')or n.get('content-desc')or'')else n.get('text')or n.get('content-desc'),'bounds':n.get('bounds'),'class':n.get('class')}for n in screen()if(n.get('text')or n.get('content-desc'))and n.get('class')!='android.widget.EditText']))
 elif action=='login-customer':
  a=h.state['accounts']['customer'];status,user=h.b.api('/auth/v1/admin/users/'+a['auth_id'],admin=True)
  assert status==200 and user['user_metadata'].get('fr32_fixture')is True,'Own synthetic customer required'
  fields=[n for n in screen()if n.get('class')=='android.widget.EditText'];assert len(fields)==2,'Observed TEST login required'
  tap(fields[0]);adb('shell','input','keyevent','123')
  for _ in range(len(fields[0].get('text',''))):adb('shell','input','keyevent','67')
  adb('shell','input','text',shlex.quote(a['email']));adb('shell','input','keyevent','4')
  fields=[n for n in screen()if n.get('class')=='android.widget.EditText'];tap(fields[1]);adb('shell','input','text',shlex.quote(a['password']));adb('shell','input','keyevent','4')
  nodes=[n for n in screen()if(n.get('text')or n.get('content-desc'))=='Sign in as Customer'];assert len(nodes)==1,'Selected customer role required';tap(nodes[0]);emit({'action':'synthetic_customer_login_submitted','success_pending':True})
 elif action=='search-stocked':
  fields=[n for n in screen()if n.get('class')=='android.widget.EditText'];assert len(fields)==1 and fields[0].get('password')!='true','Observed search field required'
  tap(fields[0]);adb('shell','input','text',shlex.quote('FR32%ssynthetic%svendor2'));adb('shell','input','keyevent','4');emit({'synthetic_stocked_product_search':True})
 elif action.startswith('tap:'):
  label=action[4:];nodes=[n for n in screen()if(n.get('text')or n.get('content-desc'))==label];assert len(nodes)==1,'One observed control required';tap(nodes[0]);emit({'observed_control_tapped':label})
 elif action.startswith('contains:'):
  label=action[9:];nodes=[n for n in screen()if n.get('class')!='android.widget.EditText'and label in(n.get('text')or n.get('content-desc')or'')];assert len(nodes)==1,'One observed matching control required';tap(nodes[0]);emit({'observed_control_containing':label})
 elif action=='assert-invoice':
  values=labels();assert'Invoice'in values,'Actual Order History invoice action required'
  assert any('Order #'+str(h.state['invoice_order_id'])in s for s in values),'Own recorded paid order visible'
  emit({'physical_invoice_action':'PASS','order_id':h.state['invoice_order_id'],'observed':True})
 elif action=='unpaid-invoice':
  nodes=screen();order=[n for n in nodes if(n.get('text')or n.get('content-desc'))=='Order #'+str(h.state['order_id'])]
  buttons=[n for n in nodes if(n.get('text')or n.get('content-desc'))=='Invoice']
  assert len(order)==1 and buttons,'Observed unpaid order and invoice controls required'
  def middle(n):
   xy=list(map(int,re.findall(r'\d+',n.get('bounds',''))));assert len(xy)==4;return(xy[1]+xy[3])/2
  tap(min(buttons,key=lambda n:abs(middle(n)-middle(order[0]))));emit({'unpaid_invoice_requested':True,'success_pending':True})
 elif action=='assert-unpaid':
  assert any('No paid invoice is available yet.'in s for s in labels()),'Actual unready invoice feedback required'
  emit({'physical_unpaid_invoice_suppressed':'PASS'})
 elif action=='viewer':
  activity=adb('shell','dumpsys','activity','activities').split('topResumedActivity=')[-1].splitlines()[0]
  assert 'com.android.chrome'in activity,'Observed external Chrome viewer required'
  adb('shell','uiautomator','dump','/data/local/tmp/fr32-viewer.xml')
  nodes=list(ET.fromstring(adb('exec-out','cat','/data/local/tmp/fr32-viewer.xml')).iter('node'))
  values=[]
  for n in nodes:
   value=n.get('text')or n.get('content-desc')or''
   if value and n.get('class')!='android.widget.EditText':
    if any(s in value for s in['http','token=','supabase.co','@']):value='[private document link redacted]'
    values.append({'label':value,'bounds':n.get('bounds')})
  print(json.dumps(values))
  rendered=' '.join(v['label']for v in values)
  if'PDF view'in rendered:
   assert 'Order #'+str(h.state['invoice_order_id'])in rendered and'Total paid: PKR 440.00'in rendered,'Actual PDF content mismatch'
   assert rendered.count('Shared delivery fee: PKR 200.00')==1,'Shared delivery duplicated in phone PDF'
   emit({'physical_invoice_render':'PASS','actual_browser_PDF':True,'total_PKR':'440.00','shared_delivery_once':True,'signed_link_not_logged':True})
 elif action=='download-check':
  import hashlib
  path='/sdcard/Download/'+h.state['invoice_id']+'.pdf'
  p=__import__('subprocess').run([ui.ADB,'-s',ui.SERIAL,'exec-out','cat',path],capture_output=True,timeout=30)
  assert p.returncode==0 and p.stdout.startswith(b'%PDF-'),'Actual browser-downloaded invoice required'
  expected=(h.OUT/'hosted-invoice.pdf').read_bytes()
  assert hashlib.sha256(p.stdout).digest()==hashlib.sha256(expected).digest(),'Phone PDF differs from verified invoice'
  emit({'physical_private_invoice_download':'PASS','same_verified_pdf':True,'bytes':len(p.stdout),'signed_link_not_logged':True})
 elif action=='verify-checkout':
  uid=int(h.state['accounts']['customer']['profile_id'])
  rows=h.query(f"select o.id,o.order_status,(select count(*)from public.email_outbox e where e.dedupe_key='order:'||o.id)as confirmations,(select count(*)from public.invoices i where i.order_id=o.id)as invoices from public.orders o where o.user_id={uid} and o.checkout_request_id is not null and o.created_at>clock_timestamp()-interval '15 minutes' order by o.id desc limit 1;")
  assert len(rows)==1 and rows[0]['id']not in(h.state['order_id'],h.state['invoice_order_id']),'New actual physical checkout required'
  assert rows[0]['confirmations']==1 and rows[0]['invoices']==0,'One confirmation and no uncollected COD invoice required'
  assert 'Your cart is empty'in labels(),'Actual cart cleared after checkout required'
  h.state['physical_order_id']=rows[0]['id'];h.save();emit({'physical_checkout':'PASS',**rows[0]})
 elif action=='verify-notifications':
  uid=int(h.state['accounts']['customer']['profile_id'])
  ids=h.state.get('physical_read_notification_ids')
  scope=''if not ids else ' and id in('+','.join(str(int(i))for i in ids)+')'
  rows=h.query(f'select count(*)as total,count(*)filter(where not is_read)as unread,json_agg(id)as ids from public.notifications where user_id={uid}'+scope+';')
  assert rows[0]['total']>0 and rows[0]['unread']==0,'Actual persisted mark-all-read required'
  assert 'Notifications'in labels(),'Observed notifications screen required'
  h.state['physical_read_notification_ids']=rows[0].pop('ids');h.save()
  emit({'physical_mark_all_read':'PASS',**rows[0],'persisted_ids_checked':bool(ids)})
 elif action=='prepare-otp':
  assert 'fr32_physical_otp_order'not in h.state,'Reuse the recorded physical OTP fixture; do not duplicate it'
  oid=h.f.order('fr32-device',real=True)
  h.state['fr32_physical_otp_order']=oid;h.save()
  emit({'synthetic_physical_otp_fixture':oid,'actual_email_not_yet_requested':True})
 elif action in('otp-accepted','verify-otp'):
  oid=int(h.state['fr32_physical_otp_order'])
  status,rows=h.b.api(f'/rest/v1/delivery_otps?order_id=eq.{oid}&select=id,state,attempts,provider_id&order=created_at.desc&limit=1',admin=True)
  assert status==200 and len(rows)==1 and rows[0]['provider_id'],'Actual provider-accepted OTP required'
  row=rows[0]
  quota=h.query("select count(*)as n from fr32_private.quota_reservations where kind='otp' and attempt_key='"+str(__import__('uuid').UUID(row['id']))+"'::uuid;")
  assert quota[0]['n']==1,'One shared OTP admission required'
  if action=='otp-accepted':
   assert row['state']=='ACCEPTED','Actual OTP acceptance required'
   assert any('Confirm Delivery'in s for s in labels()),'Actual code-entry screen required'
   emit({'physical_otp_provider_acceptance':'PASS','order_id':oid,'shared_otp_admissions':1,'inbox_receipt':'PENDING USER CODE ENTRY'})
  else:
   status,orders=h.b.api(f'/rest/v1/orders?id=eq.{oid}&select=order_status',admin=True)
   assert status==200 and len(orders)==1 and orders[0]['order_status']=='delivered'and row['state']=='USED','Actual completed delivery with used OTP required'
   h.f.effects(oid)
   emit({'physical_fr33_real_email_otp':'PASS','order_id':oid,'shared_otp_admissions':1,'inbox_receipt':'USER ENTERED CODE ON DEVICE','one_proof_and_audit':True})
 elif action=='logs':
  pid=adb('shell','pidof',ui.PKG).strip();assert pid.isdigit()
  logs=adb('logcat','-d','--pid',pid,'-v','brief');(h.OUT/'native-logcat.log').write_text(logs)
  assert not any(e in logs for e in['FATAL EXCEPTION','Unhandled Exception','EXCEPTION CAUGHT BY','used after being disposed']),'Runtime failure observed'
  assert labels(),'Visible TEST app required';emit({'physical_runtime_log_scan':'PASS'})
 else:raise ValueError('Unknown observed UI action')
if __name__=='__main__':main(sys.argv[1])
