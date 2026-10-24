"""Low-volume authenticated TEST checks; retain photos/audits, restore exact fixture references."""
import base64,io,json,time,uuid
from PIL import Image
legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']
fixture=state.setdefault('private_photo_fixture',{'avatar':str(uuid.uuid4()),'delivery':str(uuid.uuid4())})
def save(): (OUT/'onboarding-accounts.dpapi').write_bytes(b.crypt(json.dumps(state).encode()))
def query(sql):
 p=OUT/'private-photo-fixture.private.sql';p.write_text(sql,encoding='utf-8');return db.query(p)
def lit(value):return 'null'if value is None else "'"+str(value).replace("'","''")+"'"
def gateway(name,token,data):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
checks=[]
def check(ok,label,level='real authenticated TEST HTTP'):
 assert ok,label
 checks.append({'check':label,'result':'PASS','surface':level})
 (OUT/('private-photos-'+('hosted'if action=='hosted-tail'else action)+'-observations.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(checks[-1]),flush=True)
if action=='cleanup':
 assert fixture.get('hosted_verified'),'Finish acceptance before reference restoration'
 if not fixture.get('cleaned'):
  # Only exact protected fixture references are restored; uploaded objects/audits remain.
  rows=query("begin;set local lock_timeout='5s';select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
   +"update public.users set profile_image="+lit(fixture['original_avatar'])+" where id="+str(fixture['rider_id'])+" and profile_image='tezphoto:"+fixture['avatar']+"';"
   +("update public.delivery_proof set photourl="+lit(fixture['original_proof'])+" where id="+str(fixture['proof_id'])+" and orderid="+lit(str(fixture['order_id']))+" and photourl='tezphoto:"+fixture['delivery']+"';" if fixture['proof_id'] is not None else '')
   +"select profile_image from public.users where id="+str(fixture['rider_id'])+";commit;")
  assert rows[0]['profile_image']==fixture['original_avatar']
  fixture['cleaned']=True;save()
 check(True,'exact synthetic profile/proof references restored; immutable uploaded history and audit retained','guarded fixture SQL restoration')
elif action=='identity-denials':
 assert fixture.get('hosted_verified')and not fixture.get('cleaned')
 fr20=json.loads(b.crypt((b.PRIVATE/'fr20-accounts.bin').read_bytes(),True))['accounts']
 for label,account in [('unrelated Customer',fr20['customer']),('Vendor',state['accounts']['live-vendor']),('unrelated Rider',fr20['rider']),('Admin',legacy['admin'])]:
  token=b.login(account)
  try:
   code,_=gateway('final2_customer_delivery_identity',token,{'p_order_id':fixture['order_id']})
   check(code==403,label+' cannot read customer-only assigned identity')
   if label in('Vendor','unrelated Rider'):
    code,_=b.api('/functions/v1/final2-private-photo','POST',{'action':'upload','kind':'delivery','order_id':fixture['order_id'],'request_id':str(uuid.uuid4()),'mime_type':'image/png','image_base64':'invalid'},token)
    check(code==403,label+' cannot upload another assignment photo before byte validation')
  finally:b.api('/auth/v1/logout?scope=local','POST',token=token)
 code,_=b.api('/rest/v1/rpc/final2_customer_delivery_identity','POST',{'p_order_id':fixture['order_id']})
 check(code in(401,403),'anonymous assigned identity denied')
elif action=='hosted-tail':
 checks=json.loads((OUT/'private-photos-hosted-observations.json').read_text())
 assert len(checks)==34 and checks[-1]['check']=='owned delivered proof context returns actual photo without upload rights'and all(x['result']=='PASS'for x in checks)
 rows=query("begin read only;select (select photourl from public.delivery_proof where id="+str(fixture['proof_id']or -1)+")as ref,(select order_status from public.orders where id="+str(fixture['order_id'])+")as status,(select count(*)from public.security_audit_log where actor_id="+str(fixture['rider_id'])+" and action='delivery_photo_uploaded'and target_id="+str(fixture['order_id'])+")as audits;rollback;")
 check(rows[0]['ref']==('tezphoto:'+fixture['delivery']if fixture['proof_id']is not None else None)and rows[0]['status']=='delivered'and int(rows[0]['audits'])==1,'photo persists with one audit; existing OTP linked if present, missing legacy OTP never fabricated; no status mutation','real TEST persistence read')
 a=json.loads(b.crypt((b.PRIVATE/'fr20-accounts.bin').read_bytes(),True))['accounts']['customer'];token=b.login(a)
 code,_=b.api('/auth/v1/logout?scope=local','POST',token=token);assert code in(200,204)
 code,_=b.api('/functions/v1/final2-private-photo','POST',{'action':'view','image_id':fixture['delivery']},token)
 check(code==401,'provider-revoked session cannot reach private photo')
 fixture['hosted_verified']=True;save()
 (OUT/'private-photos-hosted-observations.json').write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
else:
 assert not fixture.get('cleaned'),'Never replay cleaned fixtures'
 if fixture.get('hosted_verified'):
  print(json.dumps({'retained_observations':len(json.loads((OUT/'private-photos-hosted-observations.json').read_text())),'fresh_mutations':0}));raise SystemExit(0)
 oid=int(state['cash_invoice_fixture']['order_id'])
 assert state['cash_invoice_fixture']['cash_recorded'],'Only prior labelled synthetic financial fixture'
 if 'order_id'not in fixture:
  rows=query("begin read only;select o.id,o.rider_id,o.user_id,o.order_status,o.delivery_address,u.profile_image,p.id as proof_id,p.photourl from public.orders o join public.users u on u.id=o.rider_id left join public.delivery_proof p on p.orderid=o.id::text and p.proofid='fr21-otp-'||o.id where o.id="+str(oid)+";rollback;")
  assert len(rows)==1 and rows[0]['order_status']=='delivered'
  row=rows[0];assert row['delivery_address']==state['cash_invoice_fixture']['marker'],'Exact existing synthetic marker required'
  assert row['profile_image']in(None,'')or str(row['profile_image']).startswith('tezphoto:'),'Preserve legacy avatar without incompatible rewrite'
  fixture.update(order_id=oid,rider_id=row['rider_id'],customer_id=row['user_id'],proof_id=row['proof_id'],original_avatar=row['profile_image'],original_proof=row['photourl']);save()
 tokens={}
 fr20=json.loads(b.crypt((b.PRIVATE/'fr20-accounts.bin').read_bytes(),True))['accounts']
 try:
  for label,account in [('rider',legacy['rider']),('admin',legacy['admin']),('customer',state['accounts']['review-customer']),('other',fr20['customer']),('vendor',state['accounts']['live-vendor'])]:tokens[label]=b.login(account)
  code,actor=gateway('fr21_actor',tokens['rider'],{});assert code==200 and actor==fixture['rider_id']
  code,actor=gateway('fr21_actor',tokens['customer'],{});assert code==200 and actor==fixture['customer_id']
  tokens['other_rider']=b.login(fr20['rider'])
  code,other_actor=gateway('fr21_actor',tokens['other'],{});assert code==200
  assert int(query('begin read only;select count(*)as n from public.orders where user_id='+str(other_actor)+' and rider_id='+str(fixture['rider_id'])+';rollback;')[0]['n'])==0,'Unrelated-customer test requires no assigned-Rider relationship'
  raw=io.BytesIO();Image.new('RGBA',(32,32),(0,128,0,255)).save(raw,format='PNG');data=raw.getvalue()
  def photo(body,token):return b.api('/functions/v1/final2-private-photo','POST',body,token)
  def upload(kind,request):return {'action':'upload','kind':kind,'order_id':oid if kind=='delivery'else None,'request_id':request,'mime_type':'image/png','image_base64':base64.b64encode(data).decode()}
  for kind,key in [('avatar','avatar'),('delivery','delivery')]:
   payload=upload(kind,fixture[key]);code,value=photo(payload,tokens['rider'])
   check(code==200 and value.get('reference')=='tezphoto:'+fixture[key],'assigned Rider actual decoded '+kind+' upload is confirmed')
   code,value=photo(payload,tokens['rider']);check(code==200 and value.get('reference')=='tezphoto:'+fixture[key],kind+' unchanged retry returns identical reference')
   for label in ['rider','customer','admin']:
    code,value=photo({'action':'view','image_id':fixture[key]},tokens[label])
    check(code==200 and base64.b64decode(value.get('image_base64',''))==data,label+' reads only permitted '+kind+' exact bytes')
    check(set(value)=={'image_base64','mime_type','expires_in'}and 1<=value['expires_in']<=900,label+' '+kind+' view has bounded lifetime and no URL')
   for label in ['other','vendor','other_rider']:
    code,_=photo({'action':'view','image_id':fixture[key]},tokens[label]);check(code==403,'unrelated '+label+' private '+kind+' read denied')
   code,_=photo({'action':'view','image_id':fixture[key]},None);check(code in(401,403),'anonymous private '+kind+' read denied')
  changed=upload('avatar',fixture['avatar']);raw=io.BytesIO();Image.new('RGBA',(32,32),(128,0,0,255)).save(raw,format='PNG');changed['image_base64']=base64.b64encode(raw.getvalue()).decode()
  code,_=photo(changed,tokens['rider']);check(code==409,'changed-byte UUID retry is rejected')
  invalid=upload('avatar',str(uuid.uuid4()));invalid['image_base64']=base64.b64encode(b'<svg/>').decode()
  code,_=photo(invalid,tokens['rider']);check(code==422,'forged PNG contents rejected server-side')
  code,_=photo(upload('delivery',str(uuid.uuid4())),tokens['customer']);check(code==403,'Customer cannot fabricate Rider proof')
  code,_=b.api('/storage/v1/object/list/final2-private-photos','POST',{'prefix':'','limit':10},tokens['customer']);check(code in(401,403)or code==200 and _==[],'raw private object listing reveals nothing')
  paths=query("begin read only;select path from final2_private.photos where id in('"+fixture['avatar']+"','"+fixture['delivery']+"');rollback;")
  for row in paths:
   code,value=b.api('/storage/v1/object/sign/final2-private-photos/'+row['path'],'POST',{'expiresIn':3600},tokens['customer'])
   check(code in(400,401,403,404)and not(isinstance(value,dict)and value.get('signedURL')),'valid existing private object cannot mint a raw signed URL')
   code,_=b.api('/storage/v1/object/authenticated/final2-private-photos/'+row['path'],token=tokens['customer'])
   check(code in(400,401,403,404),'valid existing private object raw download denied')
  code,value=gateway('final2_customer_delivery_identity',tokens['customer'],{'p_order_id':oid})
  check(code==200 and value['rider']['photo']=='tezphoto:'+fixture['avatar']and value['order_status']=='delivered'and value['rider']['rating_count']>=1,'owning Customer identity has actual assigned photo/rating/status')
  code,value=gateway('final2_delivery_photo',tokens['customer'],{'p_order_id':oid});check(code==200 and value['reference']=='tezphoto:'+fixture['delivery']and not value['can_upload'],'owned delivered proof context returns actual photo without upload rights')
  rows=query("begin read only;select (select photourl from public.delivery_proof where id="+str(fixture['proof_id'] or -1)+")as ref,(select order_status from public.orders where id="+str(oid)+")as status,(select count(*)from public.security_audit_log where actor_id="+str(fixture['rider_id'])+" and action='delivery_photo_uploaded'and target_id="+str(oid)+")as audits;rollback;")
  check(rows[0]['ref']==('tezphoto:'+fixture['delivery']if fixture['proof_id']is not None else None)and rows[0]['status']=='delivered'and int(rows[0]['audits'])==1,'photo persists once with canonical audit; existing OTP proof linked if present, missing legacy OTP never fabricated; no order status mutation','real TEST persistence read')
  code,_=b.api('/auth/v1/logout?scope=local','POST',token=tokens['other']);assert code in(200,204)
  code,_=photo({'action':'view','image_id':fixture['delivery']},tokens['other']);check(code==401,'provider-revoked session cannot reach private photo')
  fixture['hosted_verified']=True;save()
 finally:
  for token in tokens.values():
   try:b.api('/auth/v1/logout?scope=local','POST',token=token)
   except Exception:pass
