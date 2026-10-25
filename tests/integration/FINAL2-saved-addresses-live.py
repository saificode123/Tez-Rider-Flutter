"""Real owner CRUD and private denials; delete only newly tagged synthetic addresses."""
import json,uuid
b.target();state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
fixture=state.setdefault('saved_address_fixture',{'marker':'FINAL2 ADDRESS '+uuid.uuid4().hex[:8],'creates':[str(uuid.uuid4()),str(uuid.uuid4())],'edit':str(uuid.uuid4()),'deletes':[str(uuid.uuid4()),str(uuid.uuid4())],'ids':[]})
checks=[];tokens={}
def save():(OUT/'onboarding-accounts.dpapi').write_bytes(b.crypt(json.dumps(state).encode()))
def check(ok,label):
 assert ok,label
 checks.append({'check':label,'result':'PASS','surface':'real authenticated TEST HTTP/persistence'})
 (OUT/'saved-addresses-hosted-observations.json').write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8');print(json.dumps(checks[-1]),flush=True)
def gateway(name,token,data):return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
def change(token,request,operation,id=None,revision=None,label=None,address=None):return gateway('final2_change_address',token,{'p_request_id':request,'p_operation':operation,'p_id':id,'p_expected_revision':revision,'p_label':label,'p_address':address})
if fixture.get('cleaned'):
 print(json.dumps({'retained_observations':len(json.loads((OUT/'saved-addresses-hosted-observations.json').read_text())),'new_mutations':0}));raise SystemExit(0)
save()
try:
 legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts'];other=json.loads(b.crypt((b.PRIVATE/'fr20-accounts.bin').read_bytes(),True))['accounts']['customer']
 for label,account in [('customer',state['accounts']['review-customer']),('other',other),('vendor',state['accounts']['live-vendor']),('rider',legacy['rider']),('admin',legacy['admin'])]:tokens[label]=b.login(account)
 code,actor=gateway('fr21_actor',tokens['customer'],{});assert code==200 and isinstance(actor,int);fixture['actor']=actor;save()
 for i in range(2):
  code,value=change(tokens['customer'],fixture['creates'][i],'create',label=fixture['marker']+' '+str(i),address=fixture['marker']+' SYNTHETIC STREET')
  if code==200 and isinstance(value.get('address_id'),int)and len(fixture['ids'])<=i:fixture['ids'].append(value['address_id']);save()
  check(code==200 and value['code']in('APPLIED','ALREADY_APPLIED'),'owner creates confirmed synthetic address '+str(i))
 code,value=change(tokens['customer'],fixture['creates'][0],'create',label=fixture['marker']+' 0',address=fixture['marker']+' SYNTHETIC STREET')
 check(code==200 and value['code']=='ALREADY_APPLIED'and value['address_id']==fixture['ids'][0],'unchanged create retry returns same persisted address ID')
 code,_=change(tokens['customer'],fixture['creates'][0],'create',label='Changed retry',address='Changed address');check(code==409,'changed same-request payload conflicts')
 code,page=gateway('final2_saved_addresses',tokens['customer'],{'p_limit':1});check(code==200 and len(page['items'])==1 and page['has_more'],'bounded owner list reports more data rather than truncating silently')
 code,next_page=gateway('final2_saved_addresses',tokens['customer'],{'p_limit':1,'p_before':page['cursor']});check(code==200 and {page['items'][0]['id'],next_page['items'][0]['id']}==set(fixture['ids']),'actual cursor returns both newly owned addresses without duplication')
 code,value=change(tokens['customer'],fixture['edit'],'edit',fixture['ids'][0],0,fixture['marker']+' EDITED',fixture['marker']+' SYNTHETIC STREET')
 check(code==200 and value['code']in('APPLIED','ALREADY_APPLIED'),'owned edit commits with expected revision')
 code,value=change(tokens['customer'],fixture['edit'],'edit',fixture['ids'][0],0,fixture['marker']+' EDITED',fixture['marker']+' SYNTHETIC STREET')
 check(code==200 and value['code']=='ALREADY_APPLIED','owned edit retry does not duplicate effect')
 code,_=change(tokens['customer'],str(uuid.uuid4()),'edit',fixture['ids'][0],0,'Stale','Stale');check(code==409,'stale revision edit cannot overwrite latest address')
 code,_=change(tokens['other'],str(uuid.uuid4()),'edit',fixture['ids'][0],1,'Attack','Attack');check(code==403,'unrelated Customer edit denied')
 code,_=change(tokens['other'],str(uuid.uuid4()),'delete',fixture['ids'][0],1);check(code==403,'unrelated Customer deletion denied')
 code,page=gateway('final2_saved_addresses',tokens['other'],{});check(code==200 and not(set(fixture['ids'])&{x['id']for x in page['items']}),'unrelated Customer list reveals no private fixture addresses')
 for role in ['vendor','rider','admin']:
  code,_=gateway('final2_saved_addresses',tokens[role],{});check(code==403,role+' cannot use Customer-only address list')
  code,_=change(tokens[role],str(uuid.uuid4()),'create',label='Bad',address='Bad');check(code==403,role+' cannot impersonate owner create')
 code,_=change(tokens['customer'],str(uuid.uuid4()),'create',label='x'*101,address='Address');check(code in(400,422),'trusted label bound enforced')
 code,_=b.api('/rest/v1/addresses?id=eq.'+str(fixture['ids'][0]),'DELETE',token=tokens['customer']);check(code==403,'raw REST cannot bypass guarded address deletion')
 code,_=b.api('/rest/v1/rpc/final2_saved_addresses','POST',{});check(code in(401,403),'anonymous private addresses denied')
finally:
 if 'customer'in tokens:
  for i,aid in enumerate(fixture['ids']):
   code,page=gateway('final2_saved_addresses',tokens['customer'],{'p_before':aid+1,'p_limit':1});assert code==200
   current=next((x for x in page['items']if x['id']==aid),None)
   if current is not None:
    assert current['label'].startswith(fixture['marker'])and current['address']==fixture['marker']+' SYNTHETIC STREET','Never delete unrelated or externally changed data'
    fixture.setdefault('delete_revisions',{})[str(aid)]=current['revision'];save()
   revision=fixture.get('delete_revisions',{}).get(str(aid));assert revision is not None
   code,result=change(tokens['customer'],fixture['deletes'][i],'delete',aid,revision);assert code==200 and result['code']in('APPLIED','ALREADY_APPLIED')
   check(True,'only tagged synthetic address '+str(i)+' removed through confirmed owner API')
  if len(fixture['ids'])==2:fixture['cleaned']=True;save()
 for token in tokens.values():
  try:b.api('/auth/v1/logout?scope=local','POST',token=token)
  except Exception:pass
assert fixture.get('cleaned')
sql=OUT/'saved-addresses-audit.private.sql';ids=','.join(map(str,fixture['ids']));sql.write_text('begin read only;select (select count(*)from public.addresses where id in('+ids+'))as remaining,(select count(*)from public.security_audit_log where actor_id='+str(fixture['actor'])+" and target_type='addresses'and target_id in("+ids+"))as audits;rollback;",encoding='utf-8')
counts=db.query(sql)[0];check(counts['remaining']==0 and counts['audits']==5,'real two creates/one edit/two deletes produce exactly five audits; retry adds none; no fixture address remains')
