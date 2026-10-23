"""Bounded physical Stage2 TEST actions with private stdin-only credentials."""
import importlib.util,secrets,sys,uuid
from pathlib import Path
s=importlib.util.spec_from_file_location('native',Path(__file__).with_name('FINAL01-native.py'));n=importlib.util.module_from_spec(s);s.loader.exec_module(n)
n.OUT=n.ROOT/'.fr21-local/final2'
def test_nodes():
 active=n.adb('shell','dumpsys','activity','activities')
 assert n.re.search(r'topResumedActivity=ActivityRecord\{[^}]*'+n.re.escape(n.PKG)+'/',active),'TEST app must be foreground'
 for attempt in range(3):
  n.adb('shell','uiautomator','dump','/data/local/tmp/final2-ui.xml')
  raw=n.adb('exec-out','cat','/data/local/tmp/final2-ui.xml')
  try:
   root=n.ET.fromstring(raw);break
  except n.ET.ParseError:
   if attempt==2:raise
   n.time.sleep(.5)
 allowed=[node for node in root.iter('node')if node.get('package')==n.PKG]
 assert allowed,'TEST controls obscured by a system overlay; no other controls inspected'
 # Persist only flat TEST nodes, never another app/system window's contents.
 safe=n.ET.Element('test-controls')
 for node in allowed:n.ET.SubElement(safe,'node',dict(node.attrib))
 (n.OUT/'ui.private.xml').write_text(n.ET.tostring(safe,encoding='unicode'),encoding='utf-8')
 return allowed
n.nodes=test_nodes
original_picture=n.picture
def picture(name):
 nodes=test_nodes()
 if any(node.get('class')=='android.widget.EditText'and node.get('text')for node in nodes):return
 original_picture(name)
n.picture=picture
state_path=n.OUT/'onboarding-accounts.dpapi'
state=n.json.loads(n.b.crypt(state_path.read_bytes(),True))
def save():state_path.write_bytes(n.b.crypt(n.json.dumps(state).encode()))
def record(check,surface='android'):
 row={'check':check,'result':'PASS','surface':surface,'observed_at':n.datetime.datetime.now(n.datetime.timezone.utc).isoformat(),'device':n.SERIAL,'package':n.PKG}
 with(n.OUT/'native-results.jsonl').open('a',encoding='utf-8')as f:f.write(n.json.dumps(row)+'\n')
 print(n.json.dumps(row),flush=True)
n.record=record
def fill(node,value):
 n.tap(node);n.adb('shell','input','keyevent','123')
 n.adb('shell',input='input keyevent '+' '.join(['67']*160)+'\ninput text '+n.shlex.quote(value)+'\nexit\n')
 n.adb('shell','input','keyevent','4')
 n.time.sleep(.4)
 if 'mInputShown=true'in n.adb('shell','dumpsys','input_method'):
  n.adb('shell','input','keyevent','4');n.time.sleep(.4)
def form(name,value):
 for attempt in range(5):
  nodes=n.nodes();labels=[node for node in nodes if n.label(node)==name]
  if labels:
   bounds=list(map(int,n.re.findall(r'\d+',labels[0].get('bounds',''))))
   choices=[]
   for node in nodes:
    xy=list(map(int,n.re.findall(r'\d+',node.get('bounds',''))))
    if node.get('class')=='android.widget.EditText'and len(xy)==4 and xy[1]>=bounds[3]and xy[1]-bounds[3]<160 and xy[3]<2350:choices.append(node)
   if len(choices)==1:fill(choices[0],value);return
  upper=name in('Full Name','Email','Phone Number')
  n.adb('shell','input','swipe','500','1200'if upper else'2050','500','2100'if upper else'1000','450');n.time.sleep(.5)
 raise AssertionError('Observed signup field required: '+name)
action=sys.argv[2];assert sys.argv[1]=='native'
def gateway(name,token,data):
 return n.b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':n.json.dumps(data)},token)
if action=='scan-changed':
 protected=[n.b.SERVICE]
 for accounts in (state['accounts'],n.accounts,n.b.fr04['accounts']):
  protected.extend(account['password']for account in accounts.values()if isinstance(account,dict)and'password'in account)
 names=set()
 for args in [('diff','--name-only','-z','b19dc24'),('ls-files','--others','--exclude-standard','-z')]:
  names.update(n.subprocess.check_output(['git',*args],cwd=n.ROOT).decode().split('\0'))
 paths=[n.ROOT/name for name in names if name and(n.ROOT/name).is_file()]
 assert all(not any(value.encode()in path.read_bytes()for value in protected if value)for path in paths),'Protected credential detected; values withheld'
 result={'files_checked':len(paths),'protected_credential_matches':0,'scope':'actual TEST service key and protected Stage2/FR28/FR04 fixture passwords; changed/new files since b19dc24'}
 (n.OUT/'protected-scan.json').write_text(n.json.dumps(result,indent=2)+'\n',encoding='utf-8');print(n.json.dumps(result))
elif action=='verify-delete-protocol':
 token=n.b.login(state['accounts']['live-vendor']);owner=state['live_vendor_profile_id']
 if 'delete_fixture'not in state:
  code,existing=n.b.api('/rest/v1/products?vendor_id=eq.'+str(owner)+'&name=like.FINAL2%20delete%20protocol*&select=id,name&order=id.desc&limit=2',admin=True)
  assert code==200 and len(existing)<=1,'Do not infer ambiguous fixture ownership'
  if existing:
   pid=existing[0]['id'];name=existing[0]['name']
   code,moves=n.b.api('/rest/v1/inventory_movements?product_id=eq.'+str(pid)+'&select=request_id,product_name',admin=True)
   assert code==200 and len(moves)==1 and moves[0]['product_name']==name
   request=moves[0]['request_id']
  else:
   request=str(uuid.uuid4());name='FINAL2 delete protocol '+uuid.uuid4().hex[:8]
   code,value=gateway('fr17_save_product',token,{'p_request_id':request,'p_product_id':None,'p_data':{'name':name,'price':1,'category':'Food'},'p_stock':1,'p_threshold':0,'p_expected_version':None})
   assert code==200 and value['code']=='UPDATED';pid=value['product_id']
  state['delete_fixture']={'id':pid,'name':name,'request':request};save()
 fixture=state['delete_fixture'];pid=fixture['id'];request=fixture['request'];name=fixture['name']
 def remove(jwt):
  return n.b.api('/functions/v1/security-gateway','POST',{'method':'DELETE','path':'/products','query':'id=eq.'+str(pid)+'&vendor_id=eq.'+str(owner)+'&select=id','headers':{'prefer':'return=representation','content-type':'application/json'},'body':''},jwt)
 assert not fixture.get('deleted'),'Verified fixture already removed; do not replay this cohort'
 code,value=remove(token);assert code==403
 record('real owning Vendor direct DELETE remains denied; trusted deletion does not relax table grants','real authenticated TEST HTTP')
 code,rows=n.b.api('/rest/v1/products?id=eq.'+str(pid)+'&vendor_id=eq.'+str(owner)+'&select=stock_version',admin=True)
 assert code==200 and len(rows)==1;params={'p_product_id':pid,'p_expected_version':rows[0]['stock_version']}
 other=n.b.login(state['accounts']['review-customer']);code,value=gateway('final2_delete_product',other,params)
 assert code==403
 record('real unrelated customer cannot invoke the owning Vendor deletion API','real authenticated TEST HTTP')
 code,value=gateway('final2_delete_product',token,params);assert code==200 and value=={'code':'DELETED','product_id':pid}
 fixture['deleted']=True;save()
 code,rows=n.b.api('/rest/v1/products?id=eq.'+str(pid)+'&select=id',admin=True);assert code==200 and rows==[]
 record('real owning Vendor guarded deletion returns the confirmed removed ID and actual record is absent','real authenticated TEST HTTP')
 code,value=gateway('final2_delete_product',token,params);assert code==200 and value=={'code':'NOT_FOUND'}
 record('real repeated deletion reports NOT_FOUND, which cannot become fabricated widget success','real authenticated TEST HTTP')
 code,ledger=n.b.api('/rest/v1/inventory_movements?vendor_id=eq.'+str(owner)+'&request_id=eq.'+request+'&select=product_id,product_name',admin=True)
 assert code==200 and len(ledger)==1 and ledger[0]['product_id']==pid and ledger[0]['product_name']==name
 record('synthetic unsold-product deletion preserves the accepted inventory audit history','real TEST persistence read')
 code,audit=n.b.api('/rest/v1/security_audit_log?action=eq.product_deleted&target_type=eq.product&target_id=eq.'+str(pid)+'&select=actor_id',admin=True)
 assert code==200 and audit==[{'actor_id':owner}]
 record('actual owning Vendor deletion records one canonical actor audit and replay adds none','real TEST persistence read')
elif action=='prepare-native-cart':
 customer=n.b.login(state['accounts']['review-customer']);code,cart=gateway('final2_cart_get',customer,{})
 assert code==200 and cart['items']==[],'Empty synthetic account cart required'
 fixture=state.setdefault('native_cart',{'marker':'FINAL2CART'+uuid.uuid4().hex[:6],'products':[]});save()
 for index,label in enumerate(('live-vendor','email-vendor')):
  if len(fixture['products'])>index:continue
  token=n.b.login(state['accounts'][label]);name=fixture['marker']+(' A'if index==0 else' B');price=11.25 if index==0 else 22.5
  code,value=gateway('fr17_save_product',token,{'p_request_id':str(uuid.uuid4()),'p_product_id':None,'p_data':{'name':name,'price':price,'category':'FINAL2 Native Cart'},'p_stock':3,'p_threshold':1,'p_expected_version':None})
  assert code==200 and value['code']=='UPDATED'
  fixture['products'].append({'id':value['product_id'],'owner':label,'name':name,'price':price});save()
 record('two real native-cart fixture products created by distinct approved Vendor sessions','real authenticated TEST HTTP')
elif action=='verify-native-cart':
 token=n.b.login(state['accounts']['review-customer']);code,cart=gateway('final2_cart_get',token,{})
 products=state['native_cart']['products'];assert code==200 and len(cart['items'])==2
 assert {int(row['product_id'])for row in cart['items']}=={p['id']for p in products}
 assert len({row['vendor_id']for row in cart['items']})==2 and all(row['qty']==1 for row in cart['items'])
 assert sum(row['price']for row in cart['items'])==33.75
 record('actual native Add controls persisted a two-Vendor cart with exact canonical prices and quantities','real TEST persistence read')
elif action=='retire-native-cart':
 fixture=state['native_cart'];assert not fixture.get('retired'),'Already retired; never replay stock changes'
 customer=n.b.login(state['accounts']['review-customer']);code,current=gateway('final2_cart_get',customer,{})
 assert code==200 and{int(row['product_id'])for row in current['items']}=={p['id']for p in fixture['products']}
 code,cleared=gateway('final2_cart_replace',customer,{'p_revision':current['revision'],'p_request_id':str(uuid.uuid4()),'p_items':[]})
 assert code==200 and cleared['code']=='OK'and cleared['items']==[]
 for product in fixture['products']:
  if product.get('retired'):continue
  token=n.b.login(state['accounts'][product['owner']])
  code,value=gateway('vendor_adjust_stock',token,{'p_product_id':product['id'],'p_quantity':-3,'p_mode':'delta','p_reason':'FINAL2 native cart fixture retirement','p_request_id':str(uuid.uuid4()),'p_threshold':None,'p_expected_version':None})
  assert code==200 and value['code']=='UPDATED'and value['stock_qty']==0
  product['retired']=True;save()
 fixture['retired']=True;save()
 record('native cart synthetic saved rows cleared and both Vendor fixture stocks retired through authenticated APIs; business history preserved','real authenticated TEST HTTP')
elif action=='search-native-cart':
 fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==1
 fill(fields[0],state['native_cart']['marker']);n.time.sleep(2)
elif action=='network-search-recovery':
 fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==1,'Observed search screen required'
 wifi=n.adb('shell','settings','get','global','wifi_on').strip();mobile=n.adb('shell','settings','get','global','mobile_data').strip()
 assert wifi in('0','1')and mobile in('0','1')and(wifi=='1'or mobile=='1'),'Exact connected original network state required'
 (n.OUT/'connectivity-original.json').write_text(n.json.dumps({'wifi_on':wifi,'mobile_data':mobile}),encoding='utf-8')
 try:
  n.adb('shell','svc','wifi','disable');n.adb('shell','svc','data','disable');n.time.sleep(2)
  fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==1
  fill(fields[0],state['native_cart']['marker'])
  n.main('assert:Search could not be completed.')
  record('physical network interruption: actual authenticated catalogue request renders persistent failure and Retry; no success or mutation fabricated')
 finally:
  n.adb('shell','svc','wifi','enable'if wifi=='1'else'disable');n.adb('shell','svc','data','enable'if mobile=='1'else'disable')
  assert n.adb('shell','settings','get','global','wifi_on').strip()==wifi
  assert n.adb('shell','settings','get','global','mobile_data').strip()==mobile
  record('exact original Android Wi-Fi/mobile-data states restored in finally')
 n.time.sleep(3);n.click('Retry');n.main('assert:2 results')
 record('physical catalogue Retry after restored connectivity returns actual authorized results')
elif action.startswith('submit-login:'):
 role=action.split(':',1)[1];assert role in('customer','vendor','rider','admin')
 n.nodes()
 if 'mInputShown=true'in n.adb('shell','dumpsys','input_method'):
  n.adb('shell','input','keyevent','4');n.time.sleep(.4)
 if not any(n.label(node)=='Sign in as '+role.title()for node in n.nodes()):
  n.adb('shell','input','swipe','500','1900','500','1000','350')
 n.click('Sign in as '+role.title());n.time.sleep(4)
elif action=='probe-customer-fields':
 fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==2
 account=state['accounts']['review-customer']
 print(n.json.dumps({'email_matches_protected_fixture':fields[0].get('text')==account['email'],
  'password_field_has_expected_length':len(fields[1].get('text',''))==len(account['password']),
  'password_field_obscured':fields[1].get('password')=='true','credential_values_emitted':False}))
elif action=='refill-customer-password':
 fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==2
 fill(fields[1],state['accounts']['review-customer']['password'])
elif action=='collapse-system-overlay':
 n.adb('shell','cmd','statusbar','collapse')
elif action=='role-picker':
 choices=[node for node in n.nodes()if node.get('clickable')=='true'and n.label(node).split('\n')[0]in('Customer','Vendor','Rider','Admin')]
 assert len(choices)==1,'Observed login role picker required';n.tap(choices[0])
elif action.startswith('choose-role:'):
 role=action.split(':',1)[1];assert role in('customer','vendor','rider','admin')
 choices=[node for node in n.nodes()if node.get('class')=='android.view.MenuItem'and n.label(node).split('\n')[0].lower()==role]
 assert len(choices)==1,'Observed role menu option required';n.tap(choices[0])
elif action in('scroll:down','scroll:up'):
 n.nodes()
 down=action.endswith('down')
 n.adb('shell','input','swipe','500','1900'if down else'1000','500','1000'if down else'1900','450');n.time.sleep(.5)
elif action.startswith('login:')and action[6:]in('live-vendor','review-customer','email-vendor','other-customer'):
 label=action[6:];account=n.accounts['customer']if label=='other-customer'else state['accounts'][label];role='customer'if label in('review-customer','other-customer')else'vendor'
 assert any(n.label(node)=='Sign in as '+role.title()for node in n.nodes())
 for index,value in enumerate([account['email'],account['password']]):
  fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==2
  fill(fields[index],value)
 n.click('Sign in as '+role.title());n.time.sleep(4)
elif action=='signup-email-fill':
 assert any(n.label(node)=='Shop / Store Name'for node in n.nodes()),'Observed Vendor signup required'
 if 'email-vendor'not in state['accounts']:
  mailbox=n.b.fr04['accounts']['rider-email']['email'];local,domain=mailbox.rsplit('@',1)
  assert domain=='gmail.com'
  state['accounts']['email-vendor']={'email':local.split('+')[0]+'+final2-vendor-'+uuid.uuid4().hex[:10]+'@'+domain,'password':secrets.token_urlsafe(24)+'aA7!'};save()
 account=state['accounts']['email-vendor']
 for name,value in [('Full Name','FINAL2 Email Vendor'),('Email',account['email']),('Phone Number','+923001234567'),('Shop / Store Name','FINAL2 Email Store'),('Store Address','FINAL2 Synthetic Street'),('Password',account['password'])]:form(name,value)
 print(n.json.dumps({'form':'isolated Vendor signup filled','credential_output':False,'submitted':False}))
elif action in('email-created','email-confirmed'):
 account=state['accounts']['email-vendor'];found=[]
 for page in range(1,6):
  code,value=n.b.api('/auth/v1/admin/users?page='+str(page)+'&per_page=100',admin=True);assert code==200
  found=[user for user in value['users']if user['email']==account['email']]
  if found or len(value['users'])<100:break
 assert len(found)==1,'Native Auth signup record required';user=found[0];account['auth_id']=user['id'];save()
 assert user['user_metadata']['role']=='vendor'and user['user_metadata']['store_address']=='FINAL2 Synthetic Street'
 if action=='email-created':
  assert not user.get('email_confirmed_at')and user.get('confirmation_sent_at')
  code,value=n.b.api('/auth/v1/token?grant_type=password','POST',{'email':account['email'],'password':account['password']})
  assert code==400 and value.get('error_code')=='email_not_confirmed'
  record('fresh native Vendor Auth signup has durable store metadata and cannot log in before real email confirmation','real TEST Auth HTTP')
 else:
  assert user.get('email_confirmed_at'),'Actual inbox confirmation still required'
  record('fresh native Vendor real inbox confirmation recorded by Auth','real TEST Auth HTTP')
elif action in('verify-email-vendor','verify-email-vendor-final') or action.startswith('review-email-vendor:'):
 account=state['accounts']['email-vendor'];assert account.get('auth_id')
 code,rows=n.b.api('/rest/v1/users?auth_user_id=eq.'+account['auth_id']+'&select=id,role,verification_status',admin=True)
 assert code==200 and len(rows)==1;profile=rows[0];assert profile['role']=='vendor'
 account['profile_id']=profile['id'];save()
 code,stores=n.b.api('/rest/v1/vendors?user_id=eq.'+str(profile['id'])+'&select=id,store_name,address,is_active',admin=True)
 assert code==200 and len(stores)==1 and stores[0]['store_name']=='FINAL2 Email Store'and stores[0]['address']=='FINAL2 Synthetic Street'
 if action=='verify-email-vendor':
  assert profile['verification_status']=='pending'and stores[0]['is_active']is False
  record('actual first native Vendor login persisted exactly one pending profile and inactive store with real signup name/address','real TEST persistence read')
 elif action=='verify-email-vendor-final':
  assert profile['verification_status']=='approved'and stores[0]['is_active']is True
  code,audits=n.b.api('/rest/v1/security_audit_log?target_type=eq.users&target_id=eq.'+str(profile['id'])+'&action=in.(vendor_approved,vendor_rejected)&select=actor_id,action',admin=True)
  assert code==200 and len(audits)==2 and all(a['actor_id']==n.accounts['admin']['profile_id']for a in audits)
  code,notices=n.b.api('/rest/v1/notifications?user_id=eq.'+str(profile['id'])+'&title=in.(Vendor%20registration%20approved,Vendor%20registration%20rejected)&select=title',admin=True)
  assert code==200 and len(notices)==2
  record('native signup/restart retained one approved active store, exactly two canonical-actor decision audits and two owned notices','real TEST persistence read')
 else:
  status=action.split(':',1)[1];assert status in('rejected','approved')
  token=n.b.login(n.accounts['admin'])
  body={'p_user_id':profile['id'],'p_status':status,'p_reason':'FINAL2 native review test'if status=='rejected'else None}
  code,value=n.b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/final2_review_vendor','query':'','headers':{'content-type':'application/json'},'body':n.json.dumps(body)},token)
  assert code==200 and value['verification_status']==status
  record('authenticated Admin confirmed native fixture Vendor '+status+'; phone rendering checked separately','real authenticated TEST HTTP')
elif action in('install','launch','status','back')or action.startswith(('tap:','bounds:','assert:')):
 n.main(action)
else:raise ValueError('Unsupported bounded TEST action')
