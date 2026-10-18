"""Observed controls on the authorized TEST Android device only."""
import importlib.util,json,re,shlex,subprocess,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('checklist',Path(__file__).with_name('CHECKLIST-hosted.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
spec=importlib.util.spec_from_file_location('ui',Path(__file__).with_name('FR-10-native.py'))
ui=importlib.util.module_from_spec(spec);spec.loader.exec_module(ui)
def emit(data):
 with(h.OUT/'native-evidence.jsonl').open('a')as f:f.write(json.dumps(data)+'\n')
 print(json.dumps(data),flush=True)
def nodes():
 current=[n for n in ui.screen()if n.get('package')==ui.PKG]
 assert current,'TEST app controls must be visible; another app or system overlay is open'
 return current
def label(n):return n.get('text')or n.get('content-desc')or''
def screenshot(name):
 p=subprocess.run([ui.ADB,'-s',ui.SERIAL,'exec-out','screencap','-p'],capture_output=True,timeout=30);assert p.returncode==0
 (h.OUT/(name+'.png')).write_bytes(p.stdout)
def main(action):
 if action=='screen':print(json.dumps([{'label':'[TEST account]'if'@'in label(n)else label(n),'bounds':n.get('bounds'),'enabled':n.get('enabled'),'checked':n.get('checked'),'class':n.get('class')}for n in nodes()if(label(n)or n.get('class')in('android.widget.Switch','android.widget.CheckBox'))and n.get('class')!='android.widget.EditText']))
 elif action=='online':
  current=nodes();assert any(label(n)=='Rider Dashboard'for n in current)
  switches=[n for n in current if n.get('class')=='android.widget.Switch'];assert len(switches)==1
  if switches[0].get('checked')=='false':ui.tap(switches[0])
  emit({'observed_online_switch_requested':True})
 elif action.startswith('nav:'):
  index=int(action.split(':')[1]);assert 0<=index<4
  items=[]
  for n in nodes():
   xy=list(map(int,re.findall(r'\d+',n.get('bounds',''))))
   if n.get('clickable')=='true'and len(xy)==4 and xy[1]>=2100 and 0<xy[2]-xy[0]<450 and 0<xy[3]-xy[1]<=200:items.append((xy[0],n))
  items.sort(key=lambda item:item[0]);assert len(items)==4
  ui.tap(items[index][1]);emit({'observed_bottom_navigation':index})
 elif action.startswith(('tap:','contains:')):
  exact=action.startswith('tap:');value=action.split(':',1)[1]
  found=[n for n in nodes()if n.get('class')!='android.widget.EditText'and(label(n)==value if exact else value in label(n))]
  assert len(found)==1 and found[0].get('enabled')!='false','One enabled observed control required';ui.tap(found[0]);emit({'observed_control':value,'result_pending':True})
 elif action.startswith('login:'):
  who=action.split(':')[1];assert who in('rider','other-rider');a=h.state['accounts'][who]
  status,user=h.b.api('/auth/v1/admin/users/'+a['auth_id'],admin=True);assert status==200 and user['user_metadata'].get('checklist_fixture')is True
  fields=[n for n in nodes()if n.get('class')=='android.widget.EditText'];assert len(fields)==2
  for index,value in [(0,a['email']),(1,a['password'])]:
   fields=[n for n in nodes()if n.get('class')=='android.widget.EditText'];ui.tap(fields[index]);ui.adb('shell','input','keyevent','123')
   for _ in range(len(fields[index].get('text',''))):ui.adb('shell','input','keyevent','67')
   ui.adb('shell','input','text',shlex.quote(value));ui.adb('shell','input','keyevent','4')
  button=[n for n in nodes()if label(n)=='Sign in as Rider'];assert len(button)==1;ui.tap(button[0]);emit({'synthetic_rider_login_submitted':who})
 elif action=='assert-incomplete':
  current=nodes();values=[label(n)for n in current]
  for required in('Items match the order.','Packaging is sealed and undamaged.','Delivery address and customer details are confirmed.'):
   assert any(required in value for value in values),'Actual server checklist item missing'
  for required in('Submit checklist','Start Delivery'):
   controls=[n for n in current if label(n)==required];assert len(controls)==1 and controls[0].get('enabled')=='false','Incomplete action must be disabled'
  screenshot('checklist-incomplete');emit({'physical_incomplete_checklist':'PASS','server_items_visible':3,'submit_and_start_disabled':True})
 elif action=='assert-ready-to-submit':
  current=nodes();checkboxes=[n for n in current if n.get('class')=='android.widget.CheckBox']
  assert len(checkboxes)==3 and all(n.get('checked')=='true'for n in checkboxes)
  submit=[n for n in current if label(n)=='Submit checklist'];start=[n for n in current if label(n)=='Start Delivery']
  assert len(submit)==len(start)==1 and submit[0].get('enabled')=='true'and start[0].get('enabled')=='false'
  screenshot('checklist-all-confirmed');emit({'physical_all_items_confirmed':'PASS','submit_enabled_start_disabled':True})
 elif action in('assert-completed','assert-restored'):
  current=nodes();assert any('Checklist completed'in label(n)for n in current)
  controls=[n for n in current if label(n)=='Start Delivery'];assert len(controls)==1 and controls[0].get('enabled')=='true'
  aid=int(h.state['physical_assignment_id']);oid=int(h.state['physical_order_id'])
  status,assignments=h.b.api(f'/rest/v1/rider_assignments?id=eq.{aid}&select=checklist_completed,checklist_completed_at',admin=True)
  assert status==200 and len(assignments)==1 and assignments[0]['checklist_completed']
  status,responses=h.b.api(f'/rest/v1/pre_delivery_checklists?assignment_id=eq.{aid}&select=submitted_at',admin=True)
  assert status==200 and len(responses)==1 and assignments[0]['checklist_completed_at']==responses[0]['submitted_at']
  status,orders=h.b.api(f'/rest/v1/orders?id=eq.{oid}&select=order_status',admin=True)
  assert status==200 and orders==[{'order_status':'ready'}]
  screenshot(action);emit({'physical_checklist_state':action,'result':'PASS','one_response':True,'server_confirmed':True,'trip_not_started':True})
 elif action=='verify-duplicate':
  aid=int(h.state['physical_assignment_id']);token=h.b.login(h.state['accounts']['rider'])
  status,before=h.b.api(f'/rest/v1/pre_delivery_checklists?assignment_id=eq.{aid}&select=submitted_at,confirmations',token=token);assert status==200 and len(before)==1
  status,result=h.b.rpc('submit_pre_delivery_checklist',{'p_assignment_id':aid,'p_version':1,'p_confirmations':before[0]['confirmations']},token)
  assert status==200 and result['code']=='COMPLETED'and result['replayed']is True
  status,after=h.b.api(f'/rest/v1/pre_delivery_checklists?assignment_id=eq.{aid}&select=submitted_at,confirmations',token=token);assert status==200 and after==before
  status,other=h.b.api(f'/rest/v1/pre_delivery_checklists?assignment_id=eq.{aid}&select=assignment_id',token=h.b.login(h.state['accounts']['other-rider']));assert status==200 and other==[]
  status,admin=h.b.api(f'/rest/v1/pre_delivery_checklists?assignment_id=eq.{aid}&select=assignment_id',token=h.b.login(h.h.state['accounts']['admin']));assert status==200 and len(admin)==1
  emit({'physical_fixture_duplicate_submission':'PASS','same_timestamp_and_evidence':True,'other_rider_read_denied':True,'admin_read_allowed':True})
 elif action=='verify-started':
  oid=int(h.state['physical_order_id']);status,rows=h.b.api(f'/rest/v1/orders?id=eq.{oid}&select=order_status',admin=True)
  assert status==200 and rows==[{'order_status':'on_the_way'}]
  assert any(label(n)=='Arrived'and n.get('enabled')=='true'for n in nodes());emit({'physical_start_delivery':'PASS','order_id':oid})
 elif action=='otp-state':
  oid=int(h.state['physical_order_id'])
  status,rows=h.b.api(f'/rest/v1/delivery_otps?order_id=eq.{oid}&select=state,expires_at,attempts&order=created_at.desc&limit=1',admin=True);assert status==200
  status,orders=h.b.api(f'/rest/v1/orders?id=eq.{oid}&select=order_status',admin=True);assert status==200
  print(json.dumps({'order':orders,'issuance':rows}))
 elif action=='otp-attempt-history':
  oid=int(h.state['physical_order_id'])
  status,rows=h.b.api(f'/rest/v1/delivery_otp_verifications?order_id=eq.{oid}&select=result&limit=50',admin=True);assert status==200
  safe=[{key:row['result'][key]for key in('code','remaining')if key in row['result']}for row in rows]
  emit({'order_id':oid,'verification_results':safe,'scope':'server outcomes only; no OTP values'})
 elif action in('otp-accepted','verify-otp'):
  oid=int(h.state['physical_order_id']);status,rows=h.b.api(f'/rest/v1/delivery_otps?order_id=eq.{oid}&select=id,state,provider_id&order=created_at.desc&limit=1',admin=True)
  assert status==200 and len(rows)==1 and rows[0]['provider_id'],'Actual OTP provider acceptance required'
  if action=='otp-accepted':
   assert rows[0]['state']=='ACCEPTED';assert any(label(n)=='Confirm Delivery'for n in nodes());emit({'physical_otp_email_accepted':'PASS','order_id':oid,'inbox_receipt_pending':True})
  else:
   assert rows[0]['state']=='USED';status,orders=h.b.api(f'/rest/v1/orders?id=eq.{oid}&select=order_status',admin=True);assert status==200 and orders==[{'order_status':'delivered'}]
   h.h.f.effects(oid);emit({'physical_checklist_delivery_otp':'PASS','order_id':oid,'backend_used_otp':True,'one_proof_and_audit':True})
 elif action=='verify-other-rider':
  current=nodes();assert any(label(n)=='Rider Dashboard'for n in current)
  assert not any('Active Delivery'in label(n)for n in current),'Other rider must not see target delivery'
  token=h.b.login(h.state['accounts']['other-rider']);aid=int(h.state['physical_assignment_id'])
  status,rows=h.b.api(f'/rest/v1/pre_delivery_checklists?assignment_id=eq.{aid}&select=assignment_id',token=token);assert status==200 and rows==[]
  status,result=h.b.rpc('submit_pre_delivery_checklist',{'p_assignment_id':aid,'p_version':1,'p_confirmations':[{'id':item,'confirmed':True}for item in('items_match','packaging_intact','details_confirmed')]},token)
  assert status==200 and result['code']=='FORBIDDEN'
  emit({'physical_other_rider_view_and_submission':'PASS','target_job_absent':True,'evidence_read_denied':True,'submission_forbidden':True})
 elif action=='final-integrity':
  aid=int(h.state['physical_assignment_id']);oid=int(h.state['physical_order_id'])
  status,assignments=h.b.api(f'/rest/v1/rider_assignments?id=eq.{aid}&select=status,checklist_completed,checklist_completed_at',admin=True)
  assert status==200 and len(assignments)==1 and assignments[0]['status']=='Delivered'and assignments[0]['checklist_completed']
  status,responses=h.b.api(f'/rest/v1/pre_delivery_checklists?assignment_id=eq.{aid}&select=submitted_at,checklist_version,confirmations,definition_snapshot',admin=True)
  assert status==200 and len(responses)==1 and responses[0]['submitted_at']==assignments[0]['checklist_completed_at']and responses[0]['checklist_version']==1
  assert len(responses[0]['confirmations'])==len(responses[0]['definition_snapshot'])==3
  main('verify-otp');main('logs')
  emit({'physical_checklist_final_integrity':'PASS','one_immutable_response':True,'server_timestamp_matches':True,'assignment_delivered':True})
 elif action=='logs':
  pid=ui.adb('shell','pidof',ui.PKG).strip();assert pid.isdigit();logs=ui.adb('logcat','-d','--pid',pid,'-v','brief');(h.OUT/'native-logcat.log').write_text(logs,encoding='utf-8')
  assert not any(s in logs for s in('FATAL EXCEPTION','Unhandled Exception','EXCEPTION CAUGHT BY','used after being disposed'))
  emit({'physical_runtime_fatal_unhandled_scan':'PASS'})
 else:raise ValueError('Unknown observed TEST action')
if __name__=='__main__':main(sys.argv[1])
