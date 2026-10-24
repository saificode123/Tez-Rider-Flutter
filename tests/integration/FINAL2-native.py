"""Bounded physical Stage2 TEST actions with private stdin-only credentials."""
import importlib.util,secrets,sys,uuid
from pathlib import Path
s=importlib.util.spec_from_file_location('native',Path(__file__).with_name('FINAL01-native.py'));n=importlib.util.module_from_spec(s);s.loader.exec_module(n)
n.OUT=n.ROOT/'.fr21-local/final2'
original_adb=n.adb
def guarded_adb(*args,input=None):
 # Retry only reads after transient USB failures. Never replay an input, install,
 # network change, logout or business mutation whose outcome may be uncertain.
 read_only=args[:2]in(('shell','dumpsys'),('shell','uiautomator'),('exec-out','cat'))
 for attempt in range(3 if read_only else 1):
  try:return original_adb(*args,input=input)
  except AssertionError:
   if not read_only or attempt==2:raise
   n.time.sleep(1)
n.adb=guarded_adb
def test_nodes():
 active=n.adb('shell','dumpsys','activity','activities')
 assert n.re.search(r'topResumedActivity=ActivityRecord\{[^}]*'+n.re.escape(n.PKG)+'/',active),'TEST app must be foreground'
 for attempt in range(3):
  try:
   n.adb('shell','uiautomator','dump','/data/local/tmp/final2-ui.xml')
   raw=n.adb('exec-out','cat','/data/local/tmp/final2-ui.xml')
   root=n.ET.fromstring(raw);break
  except (n.ET.ParseError,AssertionError):
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
original_safe=n.safe
def safe_label(value):
 value=original_safe(value)
 value=n.re.sub(r'\b\d{5}-?\d{7}-?\d\b','[CNIC]',value)
 return n.re.sub(r'(?<!\d)\+?\d{10,15}(?!\d)','[phone]',value)
n.safe=safe_label
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
if action=='verify-cohort14-urdu-startup':
 labels=[n.label(node)for node in n.nodes()]
 assert 'دکان کا ڈیش بورڈ'in labels and 'ڈیش بورڈ'in labels and 'Store Dashboard'not in labels
 n.picture('cohort14-urdu-vendor-startup')
 record('latest TEST build restores saved Urdu and existing Vendor session; actual dashboard title and selected navigation translate after restart')
elif action=='verify-cohort14-profile-save':
 current=n.nodes()
 assert 'My Profile'in[n.label(node)for node in current]and len([node for node in current if node.get('class')=='android.widget.EditText'])==2
 n.click('Save')
 labels=[n.label(node)for node in n.nodes()]
 assert 'Profile updated successfully.'in labels
 record('actual Vendor Account Settings opens the shared canonical profile editor and unchanged Save receives confirmed server success; no screenshot of personal fields')
elif action=='verify-cohort14-rider-performance':
 labels='\n'.join(n.label(node)for node in n.nodes())
 assert 'Delivery performance'in labels and 'Completed:'in labels and 'accepted assignments'in labels
 assert 'Performance could not be loaded'not in labels
 record('latest TEST Rider earnings page renders actual stored completion metrics and explicit missing-history information; compensation remains unknown')
elif action=='scan-stage2-changed':
 import subprocess
 protected={n.b.SERVICE,n.b.ANON}
 def collect(value):
  if isinstance(value,dict):
   for key,item in value.items():
    if isinstance(item,str) and any(part in key.lower() for part in ('password','secret','token','api_key')) and len(item)>=8:protected.add(item)
    else:collect(item)
  elif isinstance(value,list):
   for item in value:collect(item)
 collect(state);collect(n.accounts);collect(n.b.fr04)
 for name in ('accounts.bin','final01-workflow.bin'):
  collect(n.json.loads(n.b.crypt((n.b.PRIVATE/name).read_bytes(),True)))
 dotenv=n.ROOT/'supabase/functions/.env.test.local'
 for line in dotenv.read_text(encoding='utf-8-sig').splitlines():
  if '='in line and not line.lstrip().startswith('#'):
   key,value=line.split('=',1)
   if any(part in key.lower()for part in('key','password','secret','token')) and len(value.strip())>=8:protected.add(value.strip().strip('\"\''))
 names=set()
 for args in [('diff','--name-only','-z','HEAD'),('ls-files','--others','--exclude-standard','-z')]:
  names.update(subprocess.check_output(['git',*args],cwd=n.ROOT).decode().split('\0'))
 paths=[n.ROOT/name for name in names if name and(n.ROOT/name).is_file()]
 assert all(not any(value.encode()in path.read_bytes()for value in protected if value)for path in paths),'Protected value found; content withheld'
 result={'project':'igeisilhtmglgnqvllrx','files_checked':len(paths),'protected_values_compared':len(protected),'matches':0,'unreadable_protected_files':0,'network_used':False}
 (n.OUT/'stage2-protected-scan.json').write_text(n.json.dumps(result,indent=2)+'\n',encoding='utf-8');print(n.json.dumps(result))
elif action=='prepare-image-gallery':
 fixture=state['product_image_fixture'];fixture.setdefault('native_marker','FINAL2 NATIVE IMAGE '+uuid.uuid4().hex[:10]);fixture.setdefault('native_file','TezRider-TEST-'+uuid.uuid4().hex[:8]+'.png');save()
 assert any(n.label(node)=='Add Product'for node in n.nodes());assert len([node for node in n.nodes()if node.get('class')=='android.widget.EditText'])==5
 for index,value in [(0,fixture['native_marker']),(2,'13.75'),(3,'2'),(4,'0')]:
  fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==5;fill(fields[index],value)
 from PIL import Image,ImageDraw
 path=n.OUT/fixture['native_file'];image=Image.new('RGB',(256,256),(0,128,0));draw=ImageDraw.Draw(image);draw.rectangle((16,16,239,239),outline='white',width=6);draw.text((88,118),'TEST',fill='white');image.save(path,format='PNG')
 remote='/sdcard/Download/'+fixture['native_file'];fixture['native_device_path']=remote;save()
 existing=n.adb('shell','sh','-c',n.shlex.quote('if test -e '+remote+'; then echo EXISTS; else echo MISSING; fi')).strip()
 if existing=='MISSING':n.adb('push',str(path),remote)
 else:assert existing=='EXISTS'
 actual=n.adb('shell','sha256sum',remote).split()[0];assert actual==n.hashlib.sha256(path.read_bytes()).hexdigest(),'Do not overwrite an existing device file'
 fixture['native_file_pushed']=True;save()
 n.adb('shell','am','broadcast','-a','android.intent.action.MEDIA_SCANNER_SCAN_FILE','-d','file://'+remote)
 n.click('Choose Product Image')
 print(n.json.dumps({'physical_action_required':'Select the synthetic green TEST image in the Android system photo picker','file':fixture['native_file'],'folder':'Downloads','package':n.PKG,'personal_images_inspected':False}),flush=True)
elif action in('submit-image-gallery','verify-image-gallery'):
 fixture=state['product_image_fixture']
 if action=='submit-image-gallery':
  assert any('Selected image:'in n.label(node)for node in n.nodes()),'Physical gallery selection required before submission'
  assert not fixture.get('native_saved')and not fixture.get('native_product_id'),'Do not replay a committed native create'
  n.click('Save');n.main('assert:My Products')
 token=n.b.login(state['accounts']['live-vendor'])
 query='name=eq.'+n.b.urllib.parse.quote(fixture['native_marker'],safe='')+'&select=id,name,price,image_url,stock_qty,stock_version,vendor_id'
 code,rows=n.b.api('/functions/v1/security-gateway','POST',{'method':'GET','path':'/products','query':query,'headers':{},'body':''},token)
 assert code==200 and len(rows)==1 and rows[0]['vendor_id']==state['live_vendor_profile_id']and rows[0]['price']==13.75 and rows[0]['stock_qty']==2
 product=rows[0];fixture['native_product_id']=product['id'];save();assert product['image_url'].startswith('tezproduct:')and product['image_url']!=fixture['reference']
 code,value=n.b.api('/functions/v1/final2-product-image','POST',{'action':'view','image_id':product['image_url'][11:]},token)
 assert code==200
 import base64,io
 from PIL import Image
 image=Image.open(io.BytesIO(base64.b64decode(value['image_base64']))).convert('RGB')
 from PIL import ImageChops,ImageStat
 expected=Image.open(n.OUT/fixture['native_file']).convert('RGB');assert image.size==expected.size==(256,256)
 delta=ImageStat.Stat(ImageChops.difference(image,expected)).mean
 assert max(delta)<12 and all(abs(a-b)<=5 for a,b in zip(image.getpixel((128,80)),(0,128,0))),'Actual synthetic image must survive Android JPEG compression; never compare lossy bytes as identical'
 print(n.json.dumps({'observed_test_image_size':image.size,'mime':value['mime_type'],'mean_absolute_RGB_difference_after_native_compression':delta}),flush=True)

 fixture.update({'native_saved':True,'native_product_id':product['id'],'native_image_reference':product['image_url'],'native_stock_version':product['stock_version']});save()
 n.picture('cohort12-gallery-created');record('actual Android system-gallery selection and physical Vendor Save persist one owned product with original 13.75 price/two stock and a distinct server-decoded green TEST photo','android + real authenticated TEST HTTP + actual image bytes')
elif action.startswith('native-image-control:'):
 fixture=state['product_image_fixture'];which=action.split(':')[1];assert which in('edit','delete')and fixture['native_saved']and not fixture.get('native_deleted')
 nodes=n.nodes();assert any(n.label(node)=='My Products'for node in nodes)
 cards=[node for node in nodes if fixture['native_marker']in n.label(node)];assert len(cards)==1
 box=list(map(int,n.re.findall(r'\d+',cards[0].get('bounds',''))));buttons=[]
 for node in nodes:
  xy=list(map(int,n.re.findall(r'\d+',node.get('bounds',''))))
  if node.get('class')=='android.widget.Button'and not n.label(node)and node.get('clickable')=='true'and len(xy)==4 and box[1]<xy[1]<xy[3]<=box[3]and xy[0]>600:buttons.append(node)
 assert len(buttons)==2,'Only the exact owned fixture card edit/delete pair may be selected'
 buttons.sort(key=lambda node:int(n.re.findall(r'\d+',node.get('bounds',''))[0]));n.tap(buttons[0 if which=='edit'else 1]);n.main('assert:' +('Edit Product'if which=='edit'else'Delete?'))
elif action=='submit-native-image-edit':
 fixture=state['product_image_fixture'];assert fixture['native_saved']and not fixture.get('native_edited');assert any(n.label(node)=='Edit Product'for node in n.nodes())
 for index,value in [(0,fixture['native_marker']+' edited'),(2,'14.25')]:
  fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==5;fill(fields[index],value)
 n.click('Save');n.main('assert:My Products')
 token=n.b.login(state['accounts']['live-vendor']);code,rows=n.b.api('/functions/v1/security-gateway','POST',{'method':'GET','path':'/products','query':'id=eq.'+str(fixture['native_product_id'])+'&select=id,name,price,image_url,stock_qty,stock_version','headers':{},'body':''},token)
 assert code==200 and len(rows)==1 and rows[0]['name']==fixture['native_marker']+' edited'and rows[0]['price']==14.25 and rows[0]['image_url']==fixture['native_image_reference']and rows[0]['stock_qty']==2
 fixture['native_edited']=True;fixture['native_stock_version']=rows[0]['stock_version'];save()
 n.picture('cohort12-gallery-edited');record('physical Vendor Edit and Save update actual owned product name/price to 14.25, preserving confirmed image reference and two stock','android + real authenticated TEST HTTP')
elif action.startswith('native-image-delete:'):
 fixture=state['product_image_fixture'];confirm=action.split(':')[1];assert confirm in('cancel','confirm')and fixture['native_edited']and not fixture.get('native_deleted')
 assert any(n.label(node)=='Delete?'for node in n.nodes());assert any(fixture['native_marker']+' edited'in n.label(node)for node in n.nodes())
 n.click('Delete'if confirm=='confirm'else'Cancel');n.time.sleep(2)
 token=n.b.login(state['accounts']['live-vendor']);query='id=eq.'+str(fixture['native_product_id'])+'&select=id,image_url'
 code,rows=n.b.api('/functions/v1/security-gateway','POST',{'method':'GET','path':'/products','query':query,'headers':{},'body':''},token)
 assert code==200 and (rows==[]if confirm=='confirm'else len(rows)==1)
 if confirm=='cancel':
  record('physical Vendor delete Cancel leaves the exact owned image product persisted','android + real authenticated TEST HTTP')
 else:
  fixture['native_deleted']=True;save()
  customer=n.b.login(state['accounts']['review-customer']);code,_=n.b.api('/functions/v1/final2-product-image','POST',{'action':'view','image_id':fixture['native_image_reference'][11:]},customer);assert code==403
  n.picture('cohort12-gallery-deleted');record('physical Vendor delete Confirm removes only the synthetic product; other Customer image authority is revoked while uploaded object/history is retained','android + real authenticated TEST HTTP')
elif action=='cleanup-image-fixtures':
 fixture=state['product_image_fixture'];assert fixture['native_deleted']and fixture['hosted_verified']
 if not fixture.get('retired'):
  token=n.b.login(state['accounts']['live-vendor'])
  if 'retire_params'not in fixture:
   code,rows=n.b.api('/functions/v1/security-gateway','POST',{'method':'GET','path':'/products','query':'id=eq.'+str(fixture['product_id'])+'&select=id,stock_version','headers':{},'body':''},token);assert code==200 and len(rows)==1
   fixture['retire_params']={'p_request_id':str(uuid.uuid4()),'p_product_id':fixture['product_id'],'p_data':{'name':fixture['marker']+' retired','price':12.25,'image_url':fixture['reference'],'category':'FINAL2 TEST only','is_available':False},'p_stock':0,'p_threshold':0,'p_expected_version':rows[0]['stock_version']};save()
  code,value=gateway('fr17_save_product',token,fixture['retire_params']);assert code==200 and value['code']in('UPDATED','ALREADY_UPDATED')and value['stock_qty']==0
  fixture['retired']=True;save()
 if not fixture.get('native_file_removed'):
  remote=fixture['native_device_path'];assert remote=='/sdcard/Download/'+fixture['native_file']and n.re.fullmatch(r'TezRider-TEST-[a-f0-9]{8}\.png',fixture['native_file'])
  actual=n.adb('shell','sha256sum',remote).split()[0];assert actual==n.hashlib.sha256((n.OUT/fixture['native_file']).read_bytes()).hexdigest(),'Only the unchanged uniquely created TEST file may be removed'
  n.adb('shell','rm',remote)
  assert n.adb('shell','sh','-c',n.shlex.quote('if test -e '+remote+'; then echo EXISTS; else echo MISSING; fi')).strip()=='MISSING'
  fixture['native_file_removed']=True;save()
 record('remaining synthetic product stock retired through actual owner API; only the hash-verified newly created Downloads test file removed; uploaded history and personal files untouched','real authenticated TEST HTTP + scoped Android fixture cleanup')
elif action=='open-image-customer':
 fixture=state['product_image_fixture'];fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==1
 fill(fields[0],fixture['marker']);n.main('assert:'+fixture['marker'])
 choices=[node for node in n.nodes()if fixture['marker']in n.label(node)and node.get('clickable')=='true'and node.get('class')!='android.widget.EditText']
 assert len(choices)==1,'Exact observed commercial product card required';n.tap(choices[0]);n.main('assert:'+fixture['marker']);n.time.sleep(3)
 n.picture('cohort12-customer-image');record('physical Customer Search opens real published image fixture through the actual product-detail handler; screenshot retained for visual image verification')
elif action=='capture-image-customer':
 fixture=state['product_image_fixture'];assert any(fixture['marker']in n.label(node)for node in n.nodes());assert not any(node.get('class')=='android.widget.EditText'for node in n.nodes())
 n.picture('cohort12-customer-image');record('physical Customer product-detail image capture refreshed after transient system banner disappeared; actual green uploaded fixture visually verified')
elif action in('capture-image-vendor','capture-image-vendor-final'):
 fixture=state['product_image_fixture'];assert any(fixture['marker']in n.label(node)for node in n.nodes());assert any('My Products'in n.label(node)for node in n.nodes())
 n.time.sleep(2)
 if action.endswith('-final'):
  token=n.b.login(state['accounts']['live-vendor']);code,value=n.b.api('/functions/v1/final2-product-image','POST',{'action':'view','image_id':fixture['request_id']},token);assert code==200 and 1<=value['expires_in']<=900
  assert not any('Retry product image'in n.label(node)for node in n.nodes())
  n.picture('cohort12-final-vendor-image');record('final source-hash-verified TEST build restores Vendor role and renders the actual product image through the bounded-lifetime client/server path','android + real authenticated TEST HTTP')
 else:n.picture('cohort12-vendor-image');record('physical owning Vendor My Products lists actual image fixture and product controls; screenshot retained for visual image verification')
elif action.startswith('open-history-detail:'):
 kind=action.split(':')[1];assert kind in('fixture','legacy','receipt')
 oid=state['history_fixture']['order_id']if kind=='fixture'else state['cod_fixture']['order_id']if kind=='legacy'else state['cash_invoice_fixture']['order_id']
 for attempt in range(15):
  nodes=n.nodes();orders=[node for node in nodes if 'Order #'+str(oid) in n.label(node).splitlines()]
  if orders:
   top=int(n.re.findall(r'\d+',orders[0].get('bounds',''))[1]);tops=[int(n.re.findall(r'\d+',node.get('bounds',''))[1])for node in nodes if any(n.re.fullmatch(r'Order #[0-9]+',line)for line in n.label(node).splitlines())and 'Order #'+str(oid)not in n.label(node).splitlines()]
   bottom=min([y for y in tops if y>top]+[2200])
   choices=[node for node in nodes if n.label(node)=='Order details'and top<int(n.re.findall(r'\d+',node.get('bounds',''))[1])<bottom]
   if len(choices)==1:n.tap(choices[0]);n.main('assert:Order #'+str(oid)+' details');record('physical Customer opens exact owned '+kind+' order through actual history details handler');break
  more=[node for node in nodes if n.label(node)=='Load more orders'and node.get('clickable')=='true']
  if more:n.tap(more[0])
  else:n.adb('shell','input','swipe','500','1900','500','1100','450');n.time.sleep(.4)
 else:raise AssertionError('Exact owned order and observed details action required')
elif action=='verify-history-items':
 token=n.b.login(state['accounts']['review-customer']);oid=state['history_fixture']['order_id']
 code,value=gateway('final2_order_detail',token,{'p_order_id':oid});assert code==200 and value['item_source']=='CHECKOUT_SNAPSHOT'and value['totals']['total_cents']=='22975'
 required=['Order total: PKR 229.75','Item subtotal: PKR 29.75','Delivery fee: PKR 200.00','2 × PKR 11.25','1 × PKR 7.25']
 for attempt in range(6):
  labels=[n.label(node)for node in n.nodes()]
  if all(any(text in label for label in labels)for text in required):break
  n.adb('shell','input','swipe','500','1900','500','1100','450');n.time.sleep(.4)
 else:raise AssertionError('Exact shared items/quantity/totals must render on the TEST detail page')
 assert all(any(item['product']in label for label in labels)for item in value['items'])
 n.picture('cohort11-shared-history');record('physical shared detail shows original per-Vendor items, fractional unit/line amounts and exact subtotal/delivery/total cents')
elif action=='history-live-cancel':
 oid=state['history_fixture']['order_id'];assert any('Order #'+str(oid)+' details'in n.label(node)for node in n.nodes())
 token=n.b.login(state['accounts']['live-vendor'])
 code,value=gateway('fr10_vendor_transition',token,{'p_vendor_order_id':state['history_fixture']['portion_A'],'p_status':'cancelled'})
 assert code==200 and value['code']=='ORDER_CANCELLED','Do not replay a consumed live-cancellation fixture'
 state['history_fixture']['cancelled']=True;save()
 n.main('assert:Cancelled:')
 token=n.b.login(state['accounts']['review-customer']);code,value=gateway('final2_order_detail',token,{'p_order_id':oid})
 assert code==200 and value['status']=='cancelled'and value['delivered_at']is None and value['payment']['state']=='UNPAID'
 assert len(value['events'])==3 and all(v['status']=='cancelled'and len(v['events'])==3 for v in value['vendor_orders'])
 state['history_fixture']['native_live_cancel_verified']=True;save()
 n.picture('cohort11-live-cancel');record('already-open physical Customer detail receives real Vendor rejection live without Refresh, retains exact items and displays cancellation rather than delivery or cash success','android + real authenticated TEST HTTP + live Realtime')
elif action=='verify-history-legacy':
 required=['Itemized records are unavailable for this older order.','Earlier status history is unavailable. Only recorded events and dates are shown.']
 seen=set()
 for attempt in range(8):
  labels=[n.label(node)for node in n.nodes()]
  seen.update(text for text in required if any(text in label for label in labels))
  if len(seen)==len(required):break
  n.adb('shell','input','swipe','500','1900','500','1100','450');n.time.sleep(.4)
 assert len(seen)==len(required),'Missing legacy history must be labelled explicitly'
 n.picture('cohort11-legacy-limits');record('physical legacy detail explicitly labels absent item/milestone history instead of fabricating earlier steps or products')
elif action=='open-native-feedback':
 oid=state['native_cash_fixture']['order_id']
 for attempt in range(8):
  nodes=n.nodes();orders=[node for node in nodes if 'Order #'+str(oid) in n.label(node).splitlines()]
  if orders:
   top=int(n.re.findall(r'\d+',orders[0].get('bounds',''))[1]);other_tops=[int(n.re.findall(r'\d+',node.get('bounds',''))[1])for node in nodes if any(n.re.fullmatch(r'Order #[0-9]+',line)for line in n.label(node).splitlines())and 'Order #'+str(oid)not in n.label(node).splitlines()]
   bottom=min([y for y in other_tops if y>top]+[2200])
   choices=[node for node in nodes if n.label(node)=='Rate'and top<int(n.re.findall(r'\d+',node.get('bounds',''))[1])<bottom]
   if len(choices)==1:n.tap(choices[0]);n.main('assert:Delivery feedback');record('physical Customer opens delivered-order canonical dual-feedback page from actual Rate handler');break
  n.adb('shell','input','swipe','500','1900','500','1000','450');n.time.sleep(.5)
 else:raise AssertionError('Exact owned native fixture order and visible Rate action required')
elif action.startswith('submit-native-feedback:'):
 role=action.split(':')[1];assert role in('vendor','rider')
 token=n.b.login(state['accounts']['review-customer']);oid=state['native_cash_fixture']['order_id']
 code,context=gateway('final2_feedback_context',token,{'p_order_id':oid});assert code==200
 target=next(t for t in context['targets']if t['role']==role);assert target['review']is None,'No repeated physical submission of an already rated target'
 stars=5 if role=='vendor'else 3
 # Native accessibility omits these plain headings although the inspected TEST
 # screenshot visibly shows Rider then Vendor. Match star rows to the same
 # canonical ordered unreviewed target array, and verify the saved target by RPC.
 pending=[t for t in context['targets']if t['review']is None]
 assert [t['role']for t in context['targets']]==['rider','vendor']
 nodes=n.nodes();choices=[node for node in nodes if n.label(node)==str(stars)+' stars'and node.get('clickable')=='true']
 choices.sort(key=lambda node:int(n.re.findall(r'\d+',node.get('bounds',''))[1]))
 assert len(choices)==len(pending),'All canonical unreviewed star rows must be visible'
 index=next(i for i,t in enumerate(pending)if t['target_id']==target['target_id'])
 n.tap(choices[index])
 nodes=n.nodes();buttons=[node for node in nodes if n.label(node)=='Submit feedback'and node.get('enabled')!='false'and node.get('clickable')=='true']
 assert len(buttons)==1,'Only explicitly selected target can submit';n.tap(buttons[0]);n.main('assert:Saved rating: '+str(stars)+'/5')
 code,context=gateway('final2_feedback_context',token,{'p_order_id':oid});assert code==200
 saved=next(t for t in context['targets']if t['target_id']==target['target_id'])['review'];assert saved['rating']==stars
 n.picture('cohort10-'+role+'-feedback')
 record('physical Customer selects '+role+' stars and actual Submit handler persists canonical saved feedback','android + real authenticated TEST HTTP')
elif action.startswith('live-feedback-signal:'):
 role=action.split(':')[1];assert role in('vendor','rider')
 assert any('Ratings & reviews'in n.label(node)for node in n.nodes()),'Actual profile summary must already be open before external event'
 customer=n.b.login(state['accounts']['review-customer']);oid=state['cod_fixture']['order_id']
 code,context=gateway('final2_feedback_context',customer,{'p_order_id':oid});assert code==200,'Existing explicitly synthetic delivered financial fixture required'
 target=next(t for t in context['targets']if t['role']==role);assert target['review']is None,'Do not replay a consumed live-event fixture'
 fixture=state.setdefault('feedback_live_signal',{});request=fixture.setdefault(role+'_request',str(uuid.uuid4()));save()
 stars=3 if role=='vendor'else 4
 code,value=gateway('final2_submit_feedback',customer,{'p_order_id':oid,'p_target_id':target['target_id'],'p_rating':stars,'p_comment':'FINAL2 SYNTHETIC LIVE PROFILE SIGNAL','p_request_id':request})
 assert code==200 and value['code']=='SUBMITTED';fixture[role+'_submitted']=True;save()
 expected=('4.0'if role=='vendor'else'3.0')+' / 5 · 3 verified ratings'
 n.main('assert:'+expected)
 n.picture('cohort10-'+role+'-live-summary')
 fixture[role+'_native_live_verified']=True;save()
 record('already-open physical '+role+' profile updates exact average/count from separate authenticated Customer API feedback event without tapping Refresh; synthetic financial fixture only','android + real authenticated TEST HTTP + live Realtime')
elif action.startswith('verify-own-rating:'):
 role=action.split(':')[1];assert role in('vendor','rider')
 token=n.b.login(state['accounts']['live-vendor']if role=='vendor'else n.accounts['rider'])
 customer=n.b.login(state['accounts']['review-customer']);code,context=gateway('final2_feedback_context',customer,{'p_order_id':state['native_cash_fixture']['order_id']});assert code==200
 target=next(t for t in context['targets']if t['role']==role)
 code,value=gateway('final2_rating_summary',token,{'p_target_id':target['target_id']});assert code==200
 labels=[n.label(node)for node in n.nodes()];expected=str(float(value['average']))+' / 5 · '+str(value['count'])+' verified ratings'
 assert any(expected in label for label in labels)and value['count']in(2,3)and value['average']==((4.5 if role=='vendor'else 2.5)if value['count']==2 else(4 if role=='vendor'else 3))
 n.picture('cohort10-'+role+'-summary');record('physical '+role+' profile Ratings handler shows exact server-computed own average/count and actual saved feedback')
elif action=='verify-feedback-restored':
 labels=[n.label(node)for node in n.nodes()]
 assert any('Saved rating: 5/5'in label for label in labels)and any('Saved rating: 3/5'in label for label in labels)
 assert 'Submit feedback'not in labels
 record('physical Customer reopened feedback restores separate saved Vendor/Rider ratings and removes duplicate submission controls')
elif action=='verify-customer-cash':
 labels=[n.label(node)for node in n.nodes()]
 oid=state['cash_invoice_fixture']['order_id']
 assert 'Order #'+str(oid)+' payment'in labels
 assert 'COD · Cash collection recorded'in labels and 'Order amount: PKR 130.00'in labels
 assert 'Cash receipt · recorded by rider'in labels
 assert 'Cash acknowledgements are manual records. The app does not transfer money.'in labels
 assert not any(label.startswith('Record cash')or label=='Record unsuccessful refund attempt'for label in labels)
 n.picture('cohort08-customer-cash')
 record('physical owning Customer sees the actual committed COD amount/Rider acknowledgement and manual-record disclaimer; cash/refund write controls are absent')
elif action=='verify-customer-refund':
 labels=[n.label(node)for node in n.nodes()]
 oid=state['cod_fixture']['cancelled_order_id']
 assert 'Order #'+str(oid)+' payment'in labels
 assert 'Confirmed manual return: PKR 31.50'in labels and 'Manual refund confirmed'in labels
 assert 'Cash return receipt · recorded by admin'in labels
 assert not any('return is not confirmed'in label or label.startswith('Record cash')for label in labels)
 n.picture('cohort08-customer-refund')
 record('physical owning Customer sees actual confirmed manual refund amount/Admin receipt; no pending-return or customer cash-write claim')
elif action in('verify-vendor-report','verify-vendor-profile-report'):
 token=n.b.login(state['accounts']['live-vendor'])
 code,value=gateway('final2_vendor_report',token,{'p_after':None,'p_limit':20})
 assert code==200 and value['vendor_id']==state['live_vendor_profile_id']
 labels=[n.label(node)for node in n.nodes()]
 assert 'Analytics'in labels and 'Delivered sales'in labels
 assert 'PKR '+format(value['summary']['delivered_sales'],'.2f')in labels
 assert 'Gross delivered item sales, not net profit or a cash payout. Shared refunds have no recorded vendor allocation.'in labels
 n.picture('cohort08-vendor-report')
 record('physical Vendor profile Payment & Earnings opens the actual authorized report with exact server totals'if action=='verify-vendor-profile-report'else'physical owning Vendor report displays exact server delivered-sales cents and gross/no-payout/no-invented-refund-allocation explanation')
elif action=='verify-vendor-dashboard-sales':
 token=n.b.login(state['accounts']['live-vendor']);code,value=gateway('final2_vendor_report',token,{'p_after':None,'p_limit':1})
 assert code==200
 labels=[n.label(node)for node in n.nodes()]
 expected='PKR '+format(value['summary']['delivered_sales'],'.2f')
 assert 'Store Dashboard'in labels and any(expected in label and'Delivered sales'in label for label in labels)
 n.picture('cohort09-vendor-dashboard')
 record('refreshed physical Vendor dashboard uses exact canonical delivered-sales cents instead of rounded older earnings totals')
elif action=='verify-vendor-breakdown':
 labels=[n.label(node)for node in n.nodes()]
 assert 'Payment: UNPAID'in labels
 assert state['native_cash_fixture']['marker']+' × 2 at PKR 5.00'in labels
 assert any('Order #'+str(state['native_cash_fixture']['order_id'])in label and'Expanded'in label for label in labels)
 n.picture('cohort08-vendor-breakdown')
 record('physical Vendor expands the actual delivered portion, sees two items at canonical unit price and UNPAID before any cash acknowledgement')
elif action=='verify-rider-unpaid':
 labels=[n.label(node)for node in n.nodes()]
 assert 'Order #'+str(state['native_cash_fixture']['order_id'])+' payment'in labels
 assert 'COD · No cash collection is recorded'in labels
 assert 'Record cash already received'in labels and 'Record cash already returned'not in labels
 record('physical assigned Rider sees unpaid COD and own collection action, without Admin refund controls')
elif action=='fill-native-cash-reference':
 current=n.nodes();labels=[n.label(node)for node in current]
 assert 'Record a manual cash acknowledgement'in labels
 button=[node for node in current if n.label(node)=='Record acknowledgement'];assert len(button)==1 and button[0].get('clickable')!='true'
 token=n.b.login(n.accounts['rider']);code,value=gateway('final2_order_payment',token,{'p_order_id':state['native_cash_fixture']['order_id']})
 assert code==200 and value['state']=='UNPAID'and value['events']==[]
 record('Cancel left the actual synthetic order unpaid with no cash event; unchecked/empty acknowledgement cannot submit','real authenticated TEST HTTP plus physical controls')
 fields=[node for node in n.nodes()if node.get('class')=='android.widget.EditText'];assert len(fields)==1
 fill(fields[0],'FINAL2-SYNTHETIC-NATIVE-ACK')
 n.click('I confirm that the exact order cash was already received.')
 button=[node for node in n.nodes()if n.label(node)=='Record acknowledgement'];assert len(button)==1 and button[0].get('clickable')=='true'
 record('physical acknowledgement requires a reference and explicit checkbox before the real submit control becomes available; synthetic TEST record only')
elif action=='cash-network-retry':
 assert any(n.label(node)=='Record a manual cash acknowledgement'for node in n.nodes())
 wifi=n.adb('shell','settings','get','global','wifi_on').strip();mobile=n.adb('shell','settings','get','global','mobile_data').strip()
 assert wifi in('0','1')and mobile in('0','1')and(wifi=='1'or mobile=='1')
 (n.OUT/'cash-connectivity-original.json').write_text(n.json.dumps({'wifi_on':wifi,'mobile_data':mobile}),encoding='utf-8')
 try:
  n.adb('shell','svc','wifi','disable');n.adb('shell','svc','data','disable');n.time.sleep(2)
  n.click('Record acknowledgement');n.main('assert:Retry unchanged record')
  labels=[n.label(node)for node in n.nodes()]
  assert 'Record a manual cash acknowledgement'in labels
  record('physical cash request network failure retains an unchanged-record retry and no fabricated successful acknowledgement')
 finally:
  n.adb('shell','svc','wifi','enable'if wifi=='1'else'disable')
  n.adb('shell','svc','data','enable'if mobile=='1'else'disable')
  assert n.adb('shell','settings','get','global','wifi_on').strip()==wifi
  assert n.adb('shell','settings','get','global','mobile_data').strip()==mobile
  record('exact original Wi-Fi/mobile-data settings restored after physical cash fault injection')
 n.time.sleep(3);n.click('Retry unchanged record');n.main('assert:Cash collection recorded')
 record('physical Rider unchanged-record retry after connectivity recovery displays committed synthetic cash acknowledgement; no real cash transfer asserted')
elif action=='verify-native-cash-persistence':
 token=n.b.login(n.accounts['rider']);oid=state['native_cash_fixture']['order_id']
 code,value=gateway('final2_order_payment',token,{'p_order_id':oid})
 assert code==200 and value['state']=='CASH_RECORDED'and len(value['events'])==1
 event=value['events'][0];assert event['event_kind']=='COLLECTED'and event['actor_role']=='rider'and event['reference']=='FINAL2-SYNTHETIC-NATIVE-ACK'
 code,rows=n.b.api('/rest/v1/security_audit_log?target_type=eq.cod_cash_event&target_id=eq.'+str(event['id'])+'&select=actor_id,action',admin=True)
 assert code==200 and len(rows)==1 and rows[0]['actor_id']==n.accounts['rider']['profile_id']
 state['native_cash_fixture']['physically_recorded_synthetic_ack']=True;save()
 record('real persisted result after physical offline/retry is exactly one synthetic cash event and one canonical Rider audit','real authenticated TEST HTTP/persistence')
elif action=='verify-admin-cash':
 labels=[n.label(node)for node in n.nodes()]
 assert 'Order #'+str(state['native_cash_fixture']['order_id'])+' payment'in labels
 assert 'COD · Cash collection recorded'in labels
 assert 'Reference: FINAL2-SYNTHETIC-NATIVE-ACK'in labels and 'Cash receipt · recorded by rider'in labels
 assert 'Record cash already received'not in labels
 n.picture('cohort08-admin-cash')
 record('physical Admin order-list navigation reads the Rider committed acknowledgement/reference and offers no duplicate collection action')
elif action=='verify-rider-fee-pending':
 labels=[n.label(node)for node in n.nodes()]
 cards=[label for label in labels if'Earned delivery fees'in label]
 assert cards and all('PKR'not in label for label in cards)
 assert any('Fee policy pending approval. Order totals are not Rider earnings.'in label for label in labels)
 n.picture('cohort09-rider-fee-pending')
 record('refreshed physical Rider summary labels earned fees as unknown/policy-pending and does not present delivered order totals as wages; FR22 acceptance remains pending')
elif action=='scan-changed':
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
 deadline=n.time.monotonic()+25
 while True:
  choices=[node for node in n.nodes()if node.get('clickable')=='true'and n.label(node).split('\n')[0]in('Customer','Vendor','Rider','Admin')]
  if len(choices)==1:break
  assert n.time.monotonic()<deadline,'Observed login role picker required after completed logout'
  n.time.sleep(.5)
 assert len(choices)==1,'Observed login role picker required';n.tap(choices[0])
elif action.startswith('choose-role:'):
 role=action.split(':',1)[1];assert role in('customer','vendor','rider','admin')
 choices=[node for node in n.nodes()if node.get('class')=='android.view.MenuItem'and n.label(node).split('\n')[0].lower()==role]
 assert len(choices)==1,'Observed role menu option required';n.tap(choices[0])
elif action in('scroll:down','scroll:up'):
 n.nodes()
 down=action.endswith('down')
 n.adb('shell','input','swipe','500','1900'if down else'1000','500','1000'if down else'1900','450');n.time.sleep(.5)
elif action.startswith('login:')and action[6:]in('live-vendor','review-customer','email-vendor','other-customer','rider','admin'):
 label=action[6:]
 account=n.accounts[label]if label in('rider','admin')else n.accounts['customer']if label=='other-customer'else state['accounts'][label]
 role=label if label in('rider','admin')else'customer'if label in('review-customer','other-customer')else'vendor'
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
