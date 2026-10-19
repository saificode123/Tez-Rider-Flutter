"""Observed controls from authorized TEST package; no OTP/password field output."""
import importlib.util,json,re,shlex,subprocess,sys,uuid,xml.etree.ElementTree as ET
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr13',Path(__file__).with_name('FR-13-hosted.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
spec=importlib.util.spec_from_file_location('safe_ui',Path(__file__).with_name('CHECKLIST-native.py'))
n=importlib.util.module_from_spec(spec);spec.loader.exec_module(n)
ui=n.ui
def nodes():
 assert ui.PKG in ui.adb('shell','dumpsys','activity','activities').split('topResumedActivity=')[-1].splitlines()[0],'TEST app must be foreground'
 path='/data/local/tmp/fr13-ui-'+uuid.uuid4().hex+'.xml'
 result=ui.adb('shell','uiautomator','dump',path)
 assert 'dumped to:'in result,'Fresh TEST UI capture unavailable; no stale controls used'
 try:current=[node for node in ET.fromstring(ui.adb('exec-out','cat',path)).iter('node')if node.get('package')==ui.PKG]
 finally:ui.adb('shell','rm',path)
 assert current,'TEST controls unavailable; another screen covers the app'
 return current
def label(node):return n.label(node)
def emit(record):
 record.setdefault('utc',h.dt.datetime.now(h.dt.timezone.utc).isoformat())
 with(h.OUT/'native-evidence.jsonl').open('a')as file:file.write(json.dumps(record)+'\n')
 print(json.dumps(record),flush=True)
def battery():
 text=ui.adb('shell','dumpsys','battery');level=re.search(r'level:\s*(\d+)',text);assert level
 return {'percent':int(level[1]),'usb_powered':'USB powered: true'in text,'ac_powered':'AC powered: true'in text}

def permissions():
 text=ui.adb('shell','dumpsys','package',ui.PKG);result={}
 for name in ('ACCESS_FINE_LOCATION','ACCESS_COARSE_LOCATION'):
  match=re.search(r'android\.permission\.'+name+r': granted=(true|false)',text);assert match,'Runtime permission state unavailable'
  result[name]=match[1]=='true'
 return result
def main(action):
 if action=='screen':
  print(json.dumps([{'label':'[TEST account]'if'@'in label(node)else label(node),'bounds':node.get('bounds'),'enabled':node.get('enabled'),'checked':node.get('checked'),'class':node.get('class')}for node in nodes()if node.get('class')!='android.widget.EditText'and(label(node)or node.get('class')in('android.widget.Switch','android.widget.CheckBox'))and not re.fullmatch(r'\d{6}',label(node))]))
 elif action.startswith(('tap:','contains:')):
  exact=action.startswith('tap:');value=action.split(':',1)[1]
  found=[node for node in nodes()if node.get('class')!='android.widget.EditText'and(label(node)==value if exact else value in label(node))]
  assert len(found)==1 and found[0].get('enabled')!='false','Exactly one observed enabled TEST control required'
  ui.tap(found[0]);emit({'observed_control':value,'outcome_pending':True})
 elif action.startswith('nav:'):
  index=int(action.split(':')[1]);assert 0<=index<4;items=[]
  for node in nodes():
   xy=list(map(int,re.findall(r'\d+',node.get('bounds',''))))
   if node.get('clickable')=='true'and len(xy)==4 and xy[1]>=2100 and 0<xy[2]-xy[0]<450 and 0<xy[3]-xy[1]<=200:items.append((xy[0],node))
  items.sort(key=lambda item:item[0]);assert len(items)==4;ui.tap(items[index][1]);emit({'observed_navigation':index})
 elif action=='login:physical-rider':
  a=h.state['accounts']['physical-rider'];code,user=h.b.api('/auth/v1/admin/users/'+a['auth_id'],admin=True);assert code==200 and user['user_metadata'].get('fr13_fixture')is True
  assert any(label(node)=='Sign in as Rider'for node in nodes())
  for index,value in[(0,a['email']),(1,a['password'])]:
   fields=[node for node in nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==2
   ui.tap(fields[index]);ui.adb('shell','input','keyevent','123')
   for _ in range(len(fields[index].get('text',''))):ui.adb('shell','input','keyevent','67')
   ui.adb('shell','input','text',shlex.quote(value));ui.adb('shell','input','keyevent','4')
  found=[node for node in nodes()if label(node)=='Sign in as Rider'];assert len(found)==1;ui.tap(found[0]);emit({'synthetic_physical_rider_login_submitted':True})
 elif action=='online':
  current=nodes();assert any(label(node)=='Rider Dashboard'for node in current)
  switches=[node for node in current if node.get('class')=='android.widget.Switch'];assert len(switches)==1
  if switches[0].get('checked')=='false':ui.tap(switches[0])
  emit({'observed_online_switch_requested':True})
 elif action=='offline':
  current=nodes();assert any(label(node)=='Rider Dashboard'for node in current)
  switches=[node for node in current if node.get('class')=='android.widget.Switch'];assert len(switches)==1
  if switches[0].get('checked')=='true':ui.tap(switches[0])
  emit({'observed_offline_switch_requested':True})
 elif action=='battery':emit({'physical_battery_observation':battery()})
 elif action in ('battery-session-start','battery-session-finish'):
  services=ui.adb('shell','dumpsys','activity','services',ui.PKG)
  assert 'GeolocatorLocationService'in services and'isForeground=true'in services
  now=h.dt.datetime.now(h.dt.timezone.utc)
  if action=='battery-session-start':
   assert 'battery_session'not in h.state
   h.state['battery_session']={'started_at':now.isoformat(),'before':battery(),'order_id':h.state['physical_order_id']};h.save()
   emit({'physical_ten_minute_battery_started':h.state['battery_session']})
  else:
   baseline=h.state['battery_session'];elapsed=(now-h.dt.datetime.fromisoformat(baseline['started_at'])).total_seconds()
   assert elapsed>=600 and baseline['order_id']==h.state['physical_order_id']
   result={'elapsed_seconds':round(elapsed,1),'before':baseline['before'],'after':battery(),'charging_confounds_battery_drain':True}
   (h.OUT/'battery-diagnostic.json').write_text(json.dumps(result,indent=2))
   emit({'physical_ten_minute_battery_diagnostic':result})
 elif action=='verify-cancelled':
  oid=int(h.state['physical_cancel_order']['oid'])
  rows=h.db.query('select (select order_status from public.orders where id='+str(oid)+')as status,(select count(*)from fr13_private.sessions where order_id='+str(oid)+')as sessions,(select count(*)from public.delivery_latest_locations where order_id='+str(oid)+')as latest;')
  assert rows==[{'status':'cancelled','sessions':0,'latest':0}]
  services=ui.adb('shell','dumpsys','activity','services',ui.PKG)
  assert not('GeolocatorLocationService'in services and'isForeground=true'in services)
  assert not any(label(node)=='Stop sharing location'for node in nodes())
  emit({'physical_synthetic_cancellation_stops_gps':'PASS','server_session_and_latest_removed':True,'gps_foreground_service_stopped':True})
 elif action=='final-integrity':
  records=[json.loads(line)for line in(h.OUT/'native-evidence.jsonl').read_text().splitlines()]
  for key in ('physical_fr13_otp_completion','physical_synthetic_cancellation_stops_gps','physical_location_permission_denied','physical_disabled_gps_handling'):
   assert any(record.get(key)=='PASS'for record in records),'Missing executed device evidence: '+key
  assert permissions()==h.state['permission_test_original']
  assert ui.adb('shell','cmd','location','is-location-enabled').strip()=='true'
  battery_result=json.loads((h.OUT/'battery-diagnostic.json').read_text());assert battery_result['elapsed_seconds']>=600
  assert json.loads((h.OUT/'physical-security.json').read_text())['result']=='PASS'
  observed=json.loads((h.OUT/'physical-observer-corrected-build.json').read_text())
  assert observed['final']and observed['events']>0 and observed['duplicates']==0
  main('installed-integrity');main('logs')
  completed=int(h.state['completed_physical_order']['oid']);cancelled=int(h.state['physical_cancel_order']['oid']);rid=int(h.state['accounts']['physical-rider']['profile_id'])
  rows=h.db.query('select (select order_status from public.orders where id='+str(completed)+')as completed_status,(select order_status from public.orders where id='+str(cancelled)+')as cancelled_status,(select count(*)from fr13_private.sessions where order_id in('+str(completed)+','+str(cancelled)+'))as sessions,(select count(*)from public.delivery_latest_locations where order_id in('+str(completed)+','+str(cancelled)+'))as latest,(select is_online from public.riders where userid='+str(rid)+')as online;')
  assert rows==[{'completed_status':'delivered','cancelled_status':'cancelled','sessions':0,'latest':0,'online':False}]
  services=ui.adb('shell','dumpsys','activity','services',ui.PKG)
  assert not('GeolocatorLocationService'in services and'isForeground=true'in services)
  emit({'physical_fr13_final_integrity':'PASS','completed_order_preserved':completed,'synthetic_cancelled_order':cancelled,'gps_service_and_server_state_stopped':True,'original_permissions_and_gps_restored':True,'test_rider_offline':True})
 elif action=='lock-test':
  assert any(label(node)=='Stop sharing location'for node in nodes()),'Active explicit TEST sharing required'
  ui.adb('shell','input','keyevent','223');emit({'controlled_lock_requested':True,'utc':h.dt.datetime.now(h.dt.timezone.utc).isoformat()})
 elif action=='gps-disable':
  assert any(label(node)=='Stop sharing location'for node in nodes())
  assert ui.adb('shell','cmd','location','is-location-enabled').strip()=='true'
  h.state['gps_test_restore']=True;h.save()
  ui.adb('shell','cmd','location','set-location-enabled','false')
  assert ui.adb('shell','cmd','location','is-location-enabled').strip()=='false'
  emit({'actual_location_service_disabled_for_test':True})
 elif action=='gps-restore':
  if h.state.get('gps_test_restore')is True:
   if ui.adb('shell','cmd','location','is-location-enabled').strip()!='true':
    ui.adb('shell','cmd','location','set-location-enabled','true')
   assert ui.adb('shell','cmd','location','is-location-enabled').strip()=='true'
   del h.state['gps_test_restore'];h.save();emit({'original_location_service_setting_restored':True})
 elif action=='permission-baseline':
  assert ui.adb('shell','cmd','location','is-location-enabled').strip()=='true'
  result=permissions();h.state['permission_test_original']=result;h.save();emit({'original_test_location_permissions':result})
 elif action=='permission-prompt-state':
  text=ui.adb('shell','dumpsys','activity','activities');top=text.split('topResumedActivity=')[-1].splitlines()[0]
  emit({'android_permission_prompt_foreground':'permissioncontroller'in top.lower(),'test_location_permissions':permissions()})
 elif action=='verify-permission-denied':
  assert not any(permissions().values())
  problems=('Allow location permission to refresh delivery matching and share an active delivery.','Location permission is blocked. Enable it in app settings and retry.')
  assert any(label(node)in problems for node in nodes()),'Actionable TEST permission message required'
  text=ui.adb('shell','dumpsys','activity','services',ui.PKG)
  assert not('GeolocatorLocationService'in text and'isForeground=true'in text)
  oid=int(h.state['physical_order_id']);rows=h.db.query('select (select count(*)from fr13_private.sessions where order_id='+str(oid)+')as sessions,(select count(*)from public.delivery_latest_locations where order_id='+str(oid)+')as latest;')
  assert rows==[{'sessions':0,'latest':0}]
  emit({'physical_location_permission_denied':'PASS','actionable_ui':True,'no_location_service_or_server_session':True})
 elif action=='verify-permission-restored':
  assert permissions()==h.state['permission_test_original']
  emit({'original_test_location_permissions_restored':True})
 elif action=='verify-gps-disabled':
  assert ui.adb('shell','cmd','location','is-location-enabled').strip()=='false'
  assert any(label(node)=='Location services are disabled. Enable GPS and retry.'for node in nodes())
  text=ui.adb('shell','dumpsys','activity','services',ui.PKG)
  assert not('GeolocatorLocationService'in text and'isForeground=true'in text)
  oid=int(h.state['physical_order_id'])
  rows=h.db.query('select (select count(*)from fr13_private.sessions where order_id='+str(oid)+')as sessions,(select count(*)from public.delivery_latest_locations where order_id='+str(oid)+')as latest;')
  assert rows==[{'sessions':0,'latest':0}]
  emit({'physical_disabled_gps_handling':'PASS','actionable_ui':True,'location_service_stopped':True,'server_session_and_latest_removed':True})
 elif action=='installed-integrity':
  paths=ui.adb('shell','pm','path',ui.PKG).strip().splitlines();assert len(paths)==1 and paths[0].startswith('package:/data/app/')and paths[0].endswith('/base.apk')
  digest=ui.adb('shell','sha256sum',paths[0][8:]).split()[0]
  expected=json.loads((h.OUT/'artifact.json').read_text())['sha256']
  assert digest==expected,'Installed APK differs from scanned source-matched artifact'
  emit({'installed_fr13_apk_sha256':digest,'installed_integrity':'PASS'})
 elif action=='power':
  text=ui.adb('shell','dumpsys','power');match=re.search(r'mWakefulness=(\w+)',text);assert match
  emit({'physical_screen_power':match[1],'utc':h.dt.datetime.now(h.dt.timezone.utc).isoformat()})
 elif action=='background-state':
  text=ui.adb('shell','dumpsys','activity','activities')
  top=text.split('topResumedActivity=')[-1].splitlines()[0]
  services=ui.adb('shell','dumpsys','activity','services',ui.PKG)
  emit({'test_app_foreground':ui.PKG in top,'location_service_foreground':'GeolocatorLocationService'in services and'isForeground=true'in services,'utc':h.dt.datetime.now(h.dt.timezone.utc).isoformat()})
 elif action=='device-network':
  text=ui.adb('shell','dumpsys','connectivity');active=re.search(r'Active default network:\s*([^\r\n]+)',text)
  value=active[1].strip()if active else None
  emit({'default_network_present':None if value is None else value.lower()not in('none','-1'),'any_validated_network':'VALIDATED'in text,'utc':h.dt.datetime.now(h.dt.timezone.utc).isoformat()})
 elif action=='verify-idle':
  rid=int(h.state['accounts']['physical-rider']['profile_id'])
  rows=h.db.query('select is_online,latitude is not null and longitude is not null as fix_present,location_updated_at>clock_timestamp()-interval\'2 minutes\'as fresh from public.riders where userid='+str(rid)+';')
  assert len(rows)==1 and rows[0]['is_online']and rows[0]['fix_present']and rows[0]['fresh']
  emit({'physical_real_idle_fix':'PASS','rider_coordinates_never_seeded':True,'fresh_for_fr20':True})
 elif action=='server-status':
  oid=int(h.state['physical_order_id']);rid=int(h.state['accounts']['physical-rider']['profile_id'])
  rows=h.db.query('select o.order_status,r.is_online,extract(epoch from(clock_timestamp()-r.last_seen))::integer as presence_age_seconds,extract(epoch from(clock_timestamp()-(select max(received_at)from public.delivery_latest_locations where order_id=o.id)))::integer as latest_age_seconds,(select count(*)from fr13_private.sessions where order_id=o.id)as gps_sessions from public.orders o join public.riders r on r.userid='+str(rid)+' where o.id='+str(oid)+';')
  assert len(rows)==1;emit({'physical_fr13_server_status':rows[0]})
 elif action in ('otp-accepted','verify-completed'):
  oid=int(h.state['physical_order_id'])
  code,rows=h.b.api(f'/rest/v1/delivery_otps?order_id=eq.{oid}&select=state,provider_id&order=created_at.desc&limit=1',admin=True)
  assert code==200 and len(rows)==1 and rows[0]['provider_id']
  if action=='otp-accepted':
   assert rows[0]['state']=='ACCEPTED'and any(label(node)=='Confirm Delivery'for node in nodes())
   emit({'actual_fr13_otp_email_accepted':True,'order_id':oid,'private_code_entry_pending':True})
  else:
   assert rows[0]['state']=='USED';h.db.f.OUT=h.OUT;h.db.f.effects(oid)
   rows=h.db.query('select (select order_status from public.orders where id='+str(oid)+')as status,(select count(*)from fr13_private.sessions where order_id='+str(oid)+')as sessions,(select count(*)from public.delivery_latest_locations where order_id='+str(oid)+')as latest;')
   assert rows[0]['status']=='delivered'and rows[0]['sessions']==0 and rows[0]['latest']==0
   services=ui.adb('shell','dumpsys','activity','services',ui.PKG)
   assert not ('GeolocatorLocationService'in services and'isForeground=true'in services)
   emit({'physical_fr13_otp_completion':'PASS','order_id':oid,'one_proof_and_audit':True,'gps_session_and_latest_removed':True,'gps_foreground_service_stopped':True})
 elif action=='logs':
  pid=ui.adb('shell','pidof',ui.PKG).strip();assert pid.isdigit()
  text=ui.adb('logcat','-d','--pid',pid,'-v','brief');(h.OUT/'native-logcat-private.log').write_text(text,encoding='utf-8')
  assert not any(value in text for value in('FATAL EXCEPTION','Unhandled Exception','EXCEPTION CAUGHT BY','used after being disposed'))
  emit({'physical_runtime_fatal_unhandled_scan':'PASS'})
 elif action=='foreground-service':
  text=ui.adb('shell','dumpsys','activity','services',ui.PKG)
  assert 'GeolocatorLocationService'in text and'isForeground=true'in text and re.search(r'foregroundId=[1-9]\d*',text)
  emit({'physical_location_foreground_service':'PASS','foreground_notification_registered':True,'visible_notification_user_check_pending':True,'battery':battery()})
 else:raise ValueError('Unsupported safe observed TEST action')
if __name__=='__main__':main(sys.argv[1])
