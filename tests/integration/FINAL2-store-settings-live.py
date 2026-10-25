"""Actual owner-store reads/writes; restore exact existing fixture fields through the same RPC."""
import json,uuid,sys
b.target();state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
fixture=state.setdefault('store_settings_fixture',{'request':str(uuid.uuid4()),'restore_request':str(uuid.uuid4())})
checks=[];tokens={}
def save():(OUT/'onboarding-accounts.dpapi').write_bytes(b.crypt(json.dumps(state).encode()))
def check(ok,label):
 assert ok,label
 checks.append({'check':label,'result':'PASS','surface':'real authenticated TEST HTTP'})
 (OUT/'store-settings-hosted-observations.json').write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8');print(json.dumps(checks[-1]),flush=True)
def gateway(name,token,data):return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
def payload(store,request,version,name=None):return {'p_request_id':request,'p_expected_version':version,'p_name':store['store_name']if name is None else name,'p_address':store['address'],'p_latitude':store['latitude'],'p_longitude':store['longitude']}
if sys.argv[2]=='hosted-tail':
 assert fixture.get('cleaned')
 checks=json.loads((OUT/'store-settings-hosted-observations.json').read_text());assert len(checks)==15 and checks[-1]['check']=='exact original fixture metadata restored through canonical owner API'
 try:
  tokens['owner']=b.login(state['accounts']['live-vendor']);tokens['other']=b.login(state['accounts']['email-vendor'])
  code,value=gateway('final2_store_settings',tokens['other'],{});check(code==200 and value['store_id']!=fixture['original']['store_id'],'registered unrelated Vendor can resolve only its own store')
  code,_=b.api('/rest/v1/vendors?user_id=eq.'+str(state['live_vendor_profile_id']),'PATCH',{'is_active':False},tokens['owner']);check(code==403,'raw REST cannot bypass validated store writes or activation guard')
  code,_=b.api('/rest/v1/rpc/final2_store_settings','POST',{});check(code in(401,403),'anonymous store-settings read denied')
  sql=OUT/'store-settings-audit.private.sql';sql.write_text('begin read only;select (select count(*)from final2_private.store_settings_receipts where actor_id='+str(state['live_vendor_profile_id'])+" and request_id in('"+fixture['request']+"','"+fixture['restore_request']+"'))as receipts,(select count(*)from public.security_audit_log where actor_id="+str(state['live_vendor_profile_id'])+" and action='store_settings_updated'and target_id="+str(fixture['original']['store_id'])+")as audits;rollback;",encoding='utf-8')
  counts=db.query(sql)[0];check(int(counts['receipts'])==2,'actual update/retry/restore persist exactly two immutable receipts')
  check(int(counts['audits'])==2,'actual change and restoration produce exactly two canonical audits; retry adds none')
 finally:
  for token in tokens.values():
   try:b.api('/auth/v1/logout?scope=local','POST',token=token)
   except Exception:pass
 raise SystemExit(0)
if fixture.get('cleaned'):
 print(json.dumps({'retained_prior_observations':len(json.loads((OUT/'store-settings-hosted-observations.json').read_text())),'new_mutations':0}));raise SystemExit(0)
try:
 legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']
 for label,account in [('vendor',state['accounts']['live-vendor']),('customer',state['accounts']['review-customer']),('rider',legacy['rider']),('admin',legacy['admin']),('other_vendor',state['accounts']['email-vendor'])]:tokens[label]=b.login(account)
 code,original=gateway('final2_store_settings',tokens['vendor'],{});check(code==200 and original['store_name']and original['address'],'approved Vendor reads canonical own store metadata')
 if 'original'not in fixture:fixture['original']=original;fixture['edited_name']=(original['store_name'][:160]+' TEST SETTINGS');save()
 original=fixture['original']
 params=payload(original,fixture['request'],original['version'],fixture['edited_name'])
 code,result=gateway('final2_save_store_settings',tokens['vendor'],params)
 check(code==200 and result['code']in('SAVED','ALREADY_APPLIED')and result['store']['store_name']==fixture['edited_name'],'real owner update confirms persisted store name')
 fixture['changed']=True;save();changed=result['store']
 check(changed['is_active']==original['is_active']and changed['latitude']==original['latitude']and changed['longitude']==original['longitude'],'approval/activation and exact pickup coordinates preserved')
 code,replay=gateway('final2_save_store_settings',tokens['vendor'],params)
 check(code==200 and replay['code']=='ALREADY_APPLIED'and replay['store']==changed,'same UUID retry cannot duplicate or drift metadata/version')
 code,_=gateway('final2_save_store_settings',tokens['vendor'],{**params,'p_name':'Different retry'})
 check(code==409,'changed same-UUID payload conflicts')
 code,_=gateway('final2_save_store_settings',tokens['vendor'],{**params,'p_request_id':str(uuid.uuid4())})
 check(code==409,'stale independent version cannot overwrite current store')
 code,_=gateway('final2_save_store_settings',tokens['vendor'],{**params,'p_request_id':str(uuid.uuid4()),'p_expected_version':changed['version'],'p_latitude':1,'p_longitude':None})
 check(code in(400,422),'server rejects incomplete coordinate pair')
 code,_=gateway('final2_save_store_settings',tokens['vendor'],{**params,'p_request_id':str(uuid.uuid4()),'p_expected_version':changed['version'],'p_name':'x'*201})
 check(code in(400,422),'server rejects oversized store name')
 for role in ['customer','rider','admin']:
  code,_=gateway('final2_store_settings',tokens[role],{});check(code==403,role+' cannot use owner store-read projection')
  code,_=gateway('final2_save_store_settings',tokens[role],params);check(code==403,role+' cannot impersonate Vendor store write')
 code,value=gateway('final2_store_settings',tokens['other_vendor'],{});check(code==200 and value['store_id']!=original['store_id'],'unrelated Vendor can resolve only its own store')
 code,_=b.api('/rest/v1/vendors?user_id=eq.'+str(state['live_vendor_profile_id']),'PATCH',{'is_active':False},tokens['vendor']);check(code==403,'raw REST cannot bypass validated store writes or activation guard')
 code,_=b.api('/rest/v1/rpc/final2_store_settings','POST',{});check(code in(401,403),'anonymous store-settings read denied')
finally:
 if fixture.get('changed')and not fixture.get('cleaned')and 'vendor'in tokens:
  original=fixture['original'];code,current=gateway('final2_store_settings',tokens['vendor'],{});assert code==200 and current['store_name']==fixture['edited_name'],'Do not overwrite unrelated edits'
  fixture.setdefault('restore_params',payload(original,fixture['restore_request'],current['version']));save()
  code,restored=gateway('final2_save_store_settings',tokens['vendor'],fixture['restore_params']);assert code==200 and restored['code']in('SAVED','ALREADY_APPLIED')
  check(all(restored['store'][key]==original[key]for key in ['store_id','store_name','address','latitude','longitude','is_active']),'exact original fixture metadata restored through canonical owner API')
  fixture['cleaned']=True;save()
 for token in tokens.values():
  try:b.api('/auth/v1/logout?scope=local','POST',token=token)
  except Exception:pass
assert fixture.get('cleaned')and len(checks)>=18
sql=OUT/'store-settings-audit.private.sql';sql.write_text('begin read only;select count(*)as receipts from final2_private.store_settings_receipts where actor_id='+str(state['live_vendor_profile_id'])+" and request_id in('"+fixture['request']+"','"+fixture['restore_request']+"');rollback;",encoding='utf-8')
check(int(db.query(sql)[0]['receipts'])==2,'real update/retry/restore persist exactly two immutable request receipts')
