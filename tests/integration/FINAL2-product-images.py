"""Guarded owned history review/deployment and authenticated security verification on TEST only."""
import base64,hashlib,importlib.util,json,re,sys,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('fixture_backend','FR-04-hosted.py');db=module('guarded_db','FINAL-security.py');db.OUT=OUT
b.target();assert b.REF==REF and sys.argv[1]=='product-images'
action=sys.argv[2];assert action in('review','deploy','post','hosted','lifetime','limits')
state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts'];admin=legacy['admin']
vendor=b.login(state['accounts']['live-vendor']);customer=b.login(state['accounts']['review-customer']);admin_token=b.login(admin);other=b.login(legacy['customer']);other_vendor=b.login(legacy['vendor']);rider=b.login(legacy['rider'])
def claims(token):
 p=token.split('.')[1];return json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4)))
version='202610240003';migration=ROOT/'supabase/migrations/202610240003_final2_product_images.sql'
history=OUT/'product-images-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
known=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
expected=[v for v in known if v<=version]
actual=[r['version']for r in db.query(history)]
if action in('review','deploy'):
 assert actual==[v for v in expected if v!=version],'Unexpected history; no replay'
else:
 assert actual==known[:len(actual)] and version in actual,'Target must be applied within an exact known migration prefix'
digest=hashlib.sha256(migration.read_bytes()).hexdigest()
checks=[]
def check(ok,label,level='real authenticated TEST HTTP'):
 assert ok,label
 checks.append({'check':label,'result':'PASS','surface':level});print(json.dumps(checks[-1]),flush=True)
 (OUT/('product-images-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
def gateway(name,token,data):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-product-images.sql').read_text(encoding='utf-8-sig')
 if action=='post':source=source.replace('-- FINAL2_LEGACY_BEGIN','alter table public.products disable trigger final2_product_image_guard;').replace('-- FINAL2_LEGACY_END','alter table public.products enable trigger final2_product_image_guard;')
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 for key,token in [('VENDOR',vendor),('CUSTOMER',customer),('ADMIN',admin_token),('OTHER',other),('OTHER_VENDOR',other_vendor),('RIDER',rider)]:source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
 path=OUT/'product-images-review.private.sql';path.write_text(source,encoding='utf-8')
 for row in db.query(path)[0]['results']:check(row['result']=='PASS',row['check'],row['surface'])
 (OUT/('product-images-'+action+'-proof.json')).write_text(json.dumps({'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True},indent=2)+'\n',encoding='utf-8')
elif action=='deploy':
 review=json.loads((OUT/'product-images-review-proof.json').read_text());assert review['rolled_back']and review['migration_sha256']==digest
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate)\b',source,re.I)
 assert not re.search(r'(?im)^\s*delete from',source),'Ledger migration must preserve history'
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610240003','final2_product_images');commit;")
 path=OUT/'product-images-deploy.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 (OUT/'product-images-deployment.json').write_text(json.dumps({'project':REF,'version':version,'versions':len(expected),'review_passes':review['passed'],'production_modified':False,'replayed':False},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'deployment':'confirmed','project':REF,'versions':len(expected)}))

elif action=='hosted':
 import io
 from PIL import Image
 fixture=state.setdefault('product_image_fixture',{'request_id':str(uuid.uuid4()),'other_request':str(uuid.uuid4()),'product_request':str(uuid.uuid4()),'marker':'FINAL2 IMAGE '+uuid.uuid4().hex[:10]})
 def save(): (OUT/'onboarding-accounts.dpapi').write_bytes(b.crypt(json.dumps(state).encode()))
 save()
 def png(color):
  data=io.BytesIO();Image.new('RGBA',(64,64),color).save(data,format='PNG');return data.getvalue()
 original=png((0,128,0,255));changed=png((200,0,0,255))
 def upload_audits():
  sql=OUT/'product-images-audit.private.sql'
  sql.write_text("begin read only;select count(*)as uploads from public.security_audit_log where actor_id="+str(state['live_vendor_profile_id'])+" and action='product_image_uploaded';rollback;",encoding='utf-8')
  return int(db.query(sql)[0]['uploads'])
 if 'audit_baseline'not in fixture:fixture['audit_baseline']=upload_audits();save()

 def upload_payload(data=original,request=None,mime='image/png'):
  return {'action':'upload','request_id':request or fixture['request_id'],'mime_type':mime,'image_base64':base64.b64encode(data).decode()}
 def image(data,token=None):return b.api('/functions/v1/final2-product-image','POST',data,token)
 code,value=image(upload_payload(),vendor);check(code==200 and value.get('reference')=='tezproduct:'+fixture['request_id'],'own approved Vendor uploads actual decoded PNG through real guarded Edge endpoint')
 fixture['reference']=value['reference'];save()
 code,value=image(upload_payload(),vendor);check(code==200 and value.get('reference')==fixture['reference'],'same actual bytes and request retry return identical completed reference')
 code,_=image(upload_payload(changed),vendor);check(code==409,'changed actual image bytes with same request are rejected')
 code,value=image({'action':'view','image_id':fixture['request_id']},vendor);check(code==200 and base64.b64decode(value['image_base64'])==original,'owner draft preview returns actual byte-identical image without private URL')
 for token,label in [(customer,'Customer'),(other_vendor,'unrelated Vendor'),(rider,'Rider'),(admin_token,'Admin')]:
  code,_=image({'action':'view','image_id':fixture['request_id']},token)
  check(code==403,label+' cannot view unpublished Vendor draft image')
 for token,label in [(customer,'Customer'),(rider,'Rider'),(admin_token,'Admin')]:
  code,_=image(upload_payload(request=str(uuid.uuid4())),token);check(code==403,label+' cannot become a product-image uploader')
 code,_=image(upload_payload(request=str(uuid.uuid4())));check(code in(401,403),'anonymous product upload denied')
 code,_=image({'action':'view','image_id':fixture['request_id']});check(code in(401,403),'anonymous image view denied')
 for content,mime,status,label in [(b'<script>bad</script>','image/png',422,'forged PNG contents'),(original,'text/html',415,'forged MIME'),(original[:30],'image/png',422,'truncated PNG')]:
  code,_=image(upload_payload(content,str(uuid.uuid4()),mime),vendor);check(code==status,'real server decoder rejects '+label)
 if not fixture.get('product_id'):
  code,value=gateway('fr17_save_product',vendor,{'p_request_id':fixture['product_request'],'p_product_id':None,'p_data':{'name':fixture['marker'],'price':12.25,'image_url':fixture['reference'],'category':'FINAL2 TEST only'},'p_stock':2,'p_threshold':0,'p_expected_version':None})
  assert code==200 and value['code']in('UPDATED','ALREADY_UPDATED');fixture['product_id']=value['product_id'];fixture['stock_version']=value['stock_version'];save()
 check(True,'real owning Vendor stock-aware product creation accepts its completed image reference')
 for token,label in [(customer,'Customer'),(other,'unrelated Customer'),(other_vendor,'Vendor'),(rider,'Rider'),(admin_token,'Admin')]:
  code,value=image({'action':'view','image_id':fixture['request_id']},token)
  check(code==200 and base64.b64decode(value['image_base64'])==original,label+' can view approved published commercial product image through real authorization')
 for proposed,label in [('https://example.invalid/unvalidated.png','arbitrary new external URL'),('tezproduct:'+str(uuid.uuid4()),'unfinished or unknown media reference')]:
  code,_=gateway('fr17_save_product',vendor,{'p_request_id':str(uuid.uuid4()),'p_product_id':fixture['product_id'],'p_data':{'name':fixture['marker'],'price':12.25,'image_url':proposed},'p_stock':2,'p_threshold':0,'p_expected_version':fixture['stock_version']})
  check(code in(400,422),'real product write rejects '+label)
 code,_=gateway('fr17_save_product',other_vendor,{'p_request_id':str(uuid.uuid4()),'p_product_id':None,'p_data':{'name':'FINAL2 forbidden adoption','price':1,'image_url':fixture['reference']},'p_stock':0,'p_threshold':0,'p_expected_version':None})
 check(code in(400,422),'unrelated real Vendor cannot attach another owner image')
 code,rows=b.api('/storage/v1/object/list/final2-product-images','POST',{'prefix':'','limit':20},customer)
 check(code in(401,403)or(code==200 and rows==[]),'raw authenticated object listing exposes no private product objects')
 code,_=gateway('final2_product_image_finish',customer,{'p_auth_id':claims(customer)['sub'],'p_request_id':fixture['request_id'],'p_digest':hashlib.sha256(original).hexdigest(),'p_mime':'image/png','p_size':len(original)})
 check(code in(401,403),'real Customer cannot forge trusted image completion')
 count=upload_audits();check(count==fixture['audit_baseline']+1,'real image upload and same-request retry commit exactly one canonical owning Vendor audit')
 fixture['hosted_verified']=True;save()
 (OUT/'product-images-hosted-proof.json').write_text(json.dumps({'project':REF,'passed':len(checks),'actual_image_bytes_uploaded_and_read':True,'private_urls_returned':False,'production_modified':False},indent=2)+'\n',encoding='utf-8')
elif action=='limits':
 import io
 from PIL import Image
 attempts=[]
 for raw,mime,label,status in [(b'\x89PNG\r\n\x1a\n'+b'0'*(5242881-8),'image/png','actual 5 MB plus one decoded byte',413)]:
  request=str(uuid.uuid4());attempts.append(request)
  code,_=b.api('/functions/v1/final2-product-image','POST',{'action':'upload','request_id':request,'mime_type':mime,'image_base64':base64.b64encode(raw).decode()},vendor)
  check(code==status,'real trusted endpoint rejects '+label+' before Storage reservation')
 raw=io.BytesIO();Image.new('RGBA',(2049,1),(0,128,0,255)).save(raw,format='PNG');request=str(uuid.uuid4());attempts.append(request)
 code,_=b.api('/functions/v1/final2-product-image','POST',{'action':'upload','request_id':request,'mime_type':'image/png','image_base64':base64.b64encode(raw.getvalue()).decode()},vendor)
 check(code==422,'real trusted endpoint rejects valid PNG with excessive decoded dimensions')
 query=OUT/'product-images-limits.private.sql';query.write_text("begin read only;select count(*)as reservations from final2_private.product_images where id in("+','.join("'"+v+"'::uuid"for v in attempts)+");rollback;",encoding='utf-8')
 check(int(db.query(query)[0]['reservations'])==0,'invalid real file size/dimensions create no upload reservation or object reference')
 (OUT/'product-images-limits-proof.json').write_text(json.dumps({'project':REF,'passed':len(checks),'actual_low_volume_HTTP_requests':2,'invalid_media_reserved':False,'production_modified':False},indent=2)+'\n',encoding='utf-8')
elif action=='lifetime':
 fixture=state['product_image_fixture'];assert fixture['hosted_verified']
 data={'action':'view','image_id':fixture['request_id']}
 code,value=b.api('/functions/v1/final2-product-image','POST',data,other)
 check(code==200 and isinstance(value.get('expires_in'),int)and 1<=value['expires_in']<=900,'real authorized image view is bounded by the trusted session deadline and maximum 900 seconds')
 check(set(value)=={'image_base64','mime_type','expires_in'}and value['mime_type']=='image/png','real image view returns verified bytes and lifetime, never a reusable private URL')
 code,_=b.api('/auth/v1/logout?scope=local','POST',token=other);assert code in(200,204),'Only the fresh non-phone Customer session may be revoked'
 code,value=b.api('/functions/v1/final2-product-image','POST',data,other)
 check(code==401 and value.get('code')=='FR28_SESSION_REVOKED','actual provider logout revokes otherwise valid Customer JWT access to the product-image endpoint')
 (OUT/'product-images-lifetime-proof.json').write_text(json.dumps({'project':REF,'passed':len(checks),'actual_local_provider_logout':True,'phone_session_modified':False,'private_URL_issued':False,'production_modified':False},indent=2)+'\n',encoding='utf-8')
else:raise SystemExit('Unsupported action; no test executed')
