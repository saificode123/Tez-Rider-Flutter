"""Loaded by the guarded Admin runner; only explicitly tagged TEST fixtures."""
import concurrent.futures,datetime,json,math,runpy,uuid
from pathlib import Path
assert b.REF==REF=='igeisilhtmglgnqvllrx';b.target()
state_path=OUT/'onboarding-accounts.dpapi';state=json.loads(b.crypt(state_path.read_bytes(),True))
people=json.loads(b.crypt((b.PRIVATE/'fr20-accounts.bin').read_bytes(),True))['accounts']
for label in ['vendor','customer','rider','rider2','admin']:
 assert people[label]['email']=='fr20-'+label+'@example.test'
fixture=state.setdefault('admin_monitor_fixture',{'marker':'FINAL2 ADMIN MONITOR '+uuid.uuid4().hex[:10],
 'product_request':str(uuid.uuid4()),'orders':{label:{'checkout_request':str(uuid.uuid4())}for label in ['race','native']},
 'assignment_requests':{label:str(uuid.uuid4())for label in ['rider','rider2']}})
if action=='cleanup'and fixture.get('cleaned'):
 print(json.dumps({'project':REF,'cleanup':'retained verified cleanup','new_business_mutations':0,'new_auth_logins':0}));raise SystemExit(0)
def save():state_path.write_bytes(b.crypt(json.dumps(state).encode()))
save()
checks=[]
def check(ok,label,surface='real authenticated TEST HTTP'):
 assert ok,label
 row={'check':label,'result':'PASS','surface':surface,'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
 checks.append(row);(OUT/('admin-monitor-'+action+'-observations.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8');print(json.dumps(row),flush=True)
def gateway(name,token,data=None):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data or{})},token)
def sql(source):
 path=OUT/'admin-monitor-operation.private.sql';path.write_text(source,encoding='utf-8');return db.query(path)
def literal(value):
 if value is None:return'null'
 if isinstance(value,bool):return'true'if value else'false'
 if isinstance(value,(int,float)):
  assert math.isfinite(value);return str(value)
 return"'"+str(value).replace("'","''")+"'"
def guard_rider(label):
 uid=int(people[label]['profile_id'])
 return "if not exists(select 1 from public.users where id="+str(uid)+" and name='FR20 synthetic "+label+"'and auth_user_id="+literal(people[label]['auth_id'])+"::uuid)then raise exception 'Exact dedicated synthetic Rider required';end if;"
def position(label,meters=None):
 uid=int(people[label]['profile_id']);extra=''
 if meters is not None:
  assert meters in(12000,13000)
  extra="p:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(-140,-60),4326)::extensions.geography,"+str(meters)+",0)::extensions.geometry;"
  coordinates='latitude=extensions.st_y(p),longitude=extensions.st_x(p),'
 else:coordinates=''
 sql("begin;do $$declare p extensions.geometry;begin "+guard_rider(label)+extra+
  'update public.riders set '+coordinates+"location_updated_at=clock_timestamp(),last_seen=clock_timestamp(),is_online=true"+
  (",is_available=true,isavailable=true"if meters is not None else'')+' where userid='+str(uid)+';end$$;commit;select true as updated;')
def admin_block(blocked):
 uid=int(people['admin']['profile_id'])
 sql("begin;set local request.jwt.claims='{\"role\":\"service_role\"}';do $$begin if not exists(select 1 from public.users where id="+str(uid)+" and name='FR20 synthetic admin')then raise exception 'Exact synthetic Admin required';end if;update public.users set is_blocked="+literal(blocked)+' where id='+str(uid)+';end$$;commit;select true as updated;')
def receipt_counts(order):
 return sql("begin read only;select (select count(*)from final2_private.manual_assignments where order_id="+str(order)+")as receipts,(select count(*)from public.rider_assignments where orderid="+str(order)+" and status='Pending')as pending,(select count(*)from public.security_audit_log where target_type='orders'and target_id="+str(order)+" and action='RIDER_MANUALLY_ASSIGNED')as audits,(select count(*)from public.notifications where rider_assignment_id in(select assignment_id from final2_private.manual_assignments where order_id="+str(order)+"))as notices;rollback;")[0]
tokens={label:b.login(people[label])for label in ['vendor','customer','rider','rider2','admin']}
fixture.setdefault('hosted_tokens',{}).update({label+'_'+uuid.uuid4().hex+'_token':token for label,token in tokens.items()});save()
vendor=tokens['vendor'];customer=tokens['customer'];admin=tokens['admin']
def detail(order):
 code,value=gateway('final2_order_detail',customer,{'p_order_id':order});assert code==200;return value
def cleanup():
 for label,row in fixture['orders'].items():
  if'order_id'not in row:continue
  value=detail(row['order_id']);assert value['order_id']==row['order_id'] and value['status']!='delivered'
  if value['status']!='cancelled':
   if value['status']=='ready':
    assert fixture.get('hosted_verified')and fixture.get('native_verified'),'Verify prepared fixture actions before retirement'
    oid=int(row['order_id']);customer_id=int(people['customer']['profile_id'])
    rider_ids=','.join(str(int(people[k]['profile_id']))for k in ['rider','rider2'])
    # Business cancellation correctly requires review after fulfillment starts.
    # Retire only these exact unpaid, unaccepted synthetic fixtures. Keep that
    # business guard unchanged and preserve every receipt/audit/history record.
    sql("begin;set local request.jwt.claims='{\"role\":\"service_role\"}';do $$declare oid bigint:="+str(oid)+";begin "+
     "perform 1 from public.orders where id=oid for update;perform 1 from public.vendor_orders where order_id=oid for update;"+
     "if not exists(select 1 from public.orders where id=oid and user_id="+str(customer_id)+" and checkout_request_id="+literal(row['checkout_request'])+"::uuid and delivery_address="+literal(fixture['marker']+' '+label)+
     " and order_status='ready'and rider_id in("+rider_ids+")and delivered_at is null and upper(payment_method)='COD')"+
     " or(select count(*)from public.rider_assignments where orderid=oid and status='Pending'and not coalesce(checklist_completed,false))<>1"+
     " or exists(select 1 from public.rider_assignments where orderid=oid and status='Accepted')"+
     " or exists(select 1 from public.cod_cash_events where order_id=oid)"+
     " or exists(select 1 from public.payments where orderid=oid::text and(paidat is not null or coalesce(upper(status),'UNKNOWN')not in('PENDING','UNPAID','FAILED','CANCELLED','VOIDED')))"+
     "then raise exception 'Only exact unpaid unaccepted synthetic fixtures may be retired';end if;"+
     "perform fr17_private.lock_inventory(array[oid]);update public.orders set order_status='cancelled',cancelled_at=clock_timestamp(),cancellation_reason='FINAL2_SYNTHETIC_FIXTURE_CLEANUP',acceptance_deadline_at=null,requires_manual_assignment=false,timeout_review_reason=null where id=oid;"+
     "update public.vendor_orders set status='cancelled'where order_id=oid and status<>'cancelled';"+
     "insert into public.security_audit_log(actor_id,action,target_type,target_id)values(null,'FINAL2_FIXTURE_CLEANUP','orders',oid);end$$;commit;select true as fixture_retired;")
   else:
    code,result=gateway('fr10_vendor_transition',vendor,{'p_vendor_order_id':row['portion_id'],'p_status':'cancelled'})
    assert code==200 and result['code']in('ORDER_CANCELLED','ALREADY_CANCELLED')
  assert detail(row['order_id'])['status']=='cancelled'
 if fixture.get('product_id')and not fixture.get('stock_retired'):
  code,rows=b.api('/rest/v1/products?id=eq.'+str(fixture['product_id'])+'&select=id,name,stock_version',admin=True)
  assert code==200 and len(rows)==1 and rows[0]['name']==fixture['marker']
  fixture.setdefault('retire_request',str(uuid.uuid4()));save()
  if'retire_params'not in fixture:
   fixture['retire_params']={'p_request_id':fixture['retire_request'],'p_product_id':fixture['product_id'],
    'p_data':{'name':fixture['marker'],'price':1.25,'image_url':None,'category':'FINAL2 TEST only','is_available':False},
    'p_stock':0,'p_threshold':0,'p_expected_version':rows[0]['stock_version']};save()
  code,result=gateway('fr17_save_product',vendor,fixture['retire_params'])
  assert code==200 and result['code']in('UPDATED','ALREADY_UPDATED');fixture['stock_retired']=True;save()
 for label,original in fixture.get('original_riders',{}).items():
  uid=int(people[label]['profile_id']);fields=','.join(name+'='+literal(value)for name,value in original.items()if name!='userid')
  sql('begin;do $$begin '+guard_rider(label)+"if exists(select 1 from public.rider_assignments where riderid="+str(uid)+" and status in('Pending','Accepted'))then raise exception 'Active fixture must be cancelled before presence restoration';end if;update public.riders set "+fields+' where userid='+str(uid)+';end$$;commit;select true as restored;')
  code,current=b.api('/rest/v1/riders?userid=eq.'+str(uid)+'&select='+','.join(original),admin=True);assert code==200 and current==[original]
 fixture['cleaned']=True;save()
 check(True,'only tagged fixture orders cancelled, stock retired and exact original synthetic Rider presence restored; receipts/history retained','real authenticated TEST HTTP + scoped fixture SQL restoration')
 for token in fixture['hosted_tokens'].values():
  code,_=b.api('/auth/v1/logout?scope=local','POST',{},token);assert code in(200,204,401,403)
 fixture['hosted_tokens']={};save()

if action=='hosted':
 assert not fixture.get('hosted_verified')and not fixture.get('cleaned'),'Do not replay an accepted fixture cohort'
 if'original_riders'not in fixture:
  originals={}
  for label in ['rider','rider2']:
   uid=int(people[label]['profile_id'])
   code,rows=b.api('/rest/v1/riders?userid=eq.'+str(uid)+'&select=userid,latitude,longitude,location_updated_at,last_seen,is_online,is_available,isavailable',admin=True)
   assert code==200 and len(rows)==1
   active=sql("begin read only;select (select count(*)from public.orders where rider_id="+str(uid)+" and coalesce(order_status,'')not in('delivered','cancelled'))+(select count(*)from public.rider_assignments where riderid="+str(uid)+" and status in('Pending','Accepted'))as n;rollback;")[0]['n']
   assert active==0,'Do not repurpose an active fixture Rider';originals[label]=rows[0]
  fixture['original_riders']=originals;save()
 if not fixture.get('positions_prepared'):
  position('rider',12000);position('rider2',13000);fixture['positions_prepared']=True;save()
 if'product_id'not in fixture:
  code,value=gateway('fr17_save_product',vendor,{'p_request_id':fixture['product_request'],'p_product_id':None,'p_data':{'name':fixture['marker'],'price':1.25,'category':'FINAL2 TEST only'},'p_stock':2,'p_threshold':0,'p_expected_version':None})
  assert code==200 and value['code']in('UPDATED','ALREADY_UPDATED');fixture['product_id']=value['product_id'];save()
 for label,row in fixture['orders'].items():
  if'order_id'not in row:
   code,value=gateway('fr10_checkout',customer,{'p_request_id':row['checkout_request'],'p_items':[{'product_id':fixture['product_id'],'quantity':1}],
    'p_delivery':{'address':fixture['marker']+' '+label,'lat':-59.99,'lng':-140,'speed':'standard','destination_confirmed':True,'destination_source':'map_pin'}})
   assert code==200 and value['code']in('PLACED','ALREADY_PLACED');row['order_id']=value['order_id'];save()
  value=detail(row['order_id']);row['portion_id']=value['vendor_orders'][0]['id'];save()
  if value['status']=='pending':
   code,r=gateway('fr10_vendor_transition',vendor,{'p_vendor_order_id':row['portion_id'],'p_status':'accepted'});assert code==200 and r['code']in('ACCEPTED','ALREADY_ACCEPTED')
   value=detail(row['order_id'])
  if value['status']=='accepted':
   code,r=gateway('fr10_vendor_transition',vendor,{'p_vendor_order_id':row['portion_id'],'p_status':'preparing'});assert code==200 and r['code']=='UPDATED'
   value=detail(row['order_id'])
  if value['status']=='preparing':
   code,r=gateway('fr21_ready_and_assign',vendor,{'p_vendor_order_id':row['portion_id']});assert code==200 and r['code']=='NO_RIDER_AVAILABLE'
  check(detail(row['order_id'])['status']=='ready',label+' real checkout/accept/prepare/radius search reaches ready escalation without pickup or financial success')
 oid=fixture['orders']['race']['order_id'];native=fixture['orders']['native']['order_id']
 for token,label in [(customer,'Customer'),(vendor,'Vendor'),(tokens['rider'],'Rider')]:
  code,_=gateway('final2_admin_order_monitor',token,{});check(code==403,label+' cannot impersonate the hosted Admin monitor')
  code,_=gateway('final2_admin_assignment_candidates',token,{'p_order_id':oid});check(code==403,label+' cannot inspect Admin candidate selection')
  code,_=gateway('final2_admin_assign_rider',token,{'p_order_id':oid,'p_rider_id':int(people['rider']['profile_id']),'p_request_id':str(uuid.uuid4())});check(code==403,label+' cannot forge manual assignment')
 code,_=gateway('final2_admin_order_monitor',None,{});check(code in(401,403),'anonymous hosted monitoring denied')
 code,value=gateway('final2_admin_order_monitor',admin,{'p_status':'ready','p_export':True});check(code==200 and value['export_complete']and len(value['orders'])==value['summary']['total_orders']and{oid,native}.issubset({r['order_id']for r in value['orders']}),'Admin complete filtered export reconciles with actual server counts and includes both owned fixtures')
 code,value=gateway('final2_admin_assignment_candidates',admin,{'p_order_id':oid});check(code==200 and value['candidates'][0]['rider_id']==int(people['rider']['profile_id'])and value['candidates'][0]['distance_m']>10000,'Admin sees actual nearest eligible dedicated Rider beyond the automatic search radius')
 def assign(label):return gateway('final2_admin_assign_rider',admin,{'p_order_id':oid,'p_rider_id':int(people[label]['profile_id']),'p_request_id':fixture['assignment_requests'][label]})
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:outcomes=list(pool.map(assign,['rider','rider2']))
 winners=[(label,value)for label,(code,value)in zip(['rider','rider2'],outcomes)if code==200 and value.get('code')in('ASSIGNED','ALREADY_APPLIED')]
 check(len(winners)==1 and all(code==200 and r.get('code')in('ASSIGNED','ALREADY_APPLIED','ORDER_CHANGED')for code,r in outcomes),'two concurrent authenticated Admin choices produce exactly one canonical assignment receipt')
 winner,assigned=winners[0];fixture['winner']=winner;fixture['assignment_id']=assigned['assignment_id'];save()
 code,replay=assign(winner);check(code==200 and replay['code']=='ALREADY_APPLIED'and replay['assignment_id']==assigned['assignment_id'],'actual uncertain-result replay returns the same assignment')
 loser='rider2'if winner=='rider'else'rider'
 code,_=gateway('final2_admin_assign_rider',admin,{'p_order_id':oid,'p_rider_id':int(people[loser]['profile_id']),'p_request_id':fixture['assignment_requests'][winner]});check(code==409,'same request UUID with changed Rider is rejected by hosted API')
 code,busy=gateway('final2_admin_assign_rider',admin,{'p_order_id':native,'p_rider_id':int(people[winner]['profile_id']),'p_request_id':str(uuid.uuid4())});check(code==200 and busy['code']=='RIDER_CHANGED','busy winning Rider cannot be assigned to a second real ready order')
 counts=receipt_counts(oid);check(counts=={'receipts':1,'pending':1,'audits':1,'notices':1},'real assignment race/replay persists exactly one private receipt, Pending assignment, critical audit and notice','real TEST persistence read')
 runpy.run_path(str(Path(__file__).with_name('FINAL2-admin-monitor-realtime.py')),init_globals=globals())
 fixture['hosted_verified']=True;save()
elif action=='realtime':
 retained=json.loads((OUT/'admin-monitor-hosted-observations.json').read_text());assert len(retained)==19 and all(r['result']=='PASS'for r in retained)
 check(receipt_counts(fixture['orders']['race']['order_id'])=={'receipts':1,'pending':1,'audits':1,'notices':1},'retained actual HTTP/race cohort remains valid before independent Realtime verification','real TEST persistence read; prior19HTTP cases retained')
 runpy.run_path(str(Path(__file__).with_name('FINAL2-admin-monitor-realtime.py')),init_globals=globals())
 fixture['hosted_verified']=True;save()
elif action=='prepare-native':
 assert fixture.get('hosted_verified')and not fixture.get('cleaned')
 for label in ['rider','rider2']:position(label)
 check(True,'only dedicated synthetic Rider presence refreshed for native Admin map/candidate verification; no physical GPS claim','scoped synthetic TEST fixture SQL')
elif action=='verify-native':
 oid=fixture['orders']['native']['order_id'];counts=receipt_counts(oid)
 check(counts=={'receipts':1,'pending':1,'audits':1,'notices':1},'physical Admin confirmation persists exactly one pending assignment/receipt/audit/notice; no Rider acceptance, cash or delivery fabricated','real TEST persistence read')
 native_admin=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']['admin']
 actor=sql("begin read only;select actor_id from public.security_audit_log where target_type='orders'and target_id="+str(oid)+" and action='RIDER_MANUALLY_ASSIGNED';rollback;")
 check(len(actor)==1 and actor[0]['actor_id']==int(native_admin['profile_id']),'critical audit actor matches the actual native Admin account rather than the hosted fixture Admin','real TEST persistence read')
 fixture['native_verified']=True;save()
elif action=='verify-native-cancel':
 check(receipt_counts(fixture['orders']['native']['order_id'])=={'receipts':0,'pending':0,'audits':0,'notices':0},'physical Admin Cancel leaves the order unassigned with no mutation, receipt, audit or assignment notice','real TEST persistence read')
elif action=='cleanup':cleanup()
