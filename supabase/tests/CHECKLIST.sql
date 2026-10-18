-- Real rollback SQL. Independent-session concurrency has a separate runner.
begin;
create temp table checklist_results(name text,result text);
create temp table checklist_people(label text,id bigint,auth_id uuid,session_id uuid);
create function pg_temp.ok(v boolean,label text)returns void language plpgsql security definer as $$begin
 if v is distinct from true then raise exception 'CHECKLIST assertion: %',label;end if;
 insert into checklist_results values(label,'PASS');end$$;
do $$declare who text;a uuid;s uuid;uid bigint;mail text;begin
 foreach who in array array['customer','vendor','rider','other','admin']loop
 a:=gen_random_uuid();s:=gen_random_uuid();mail:='checklist-sql-'||a||'@example.test';
 insert into auth.users(id,email,email_confirmed_at,role,aud)values(a,mail,now(),'authenticated','authenticated');
 insert into public.users(email,name,role,verification_status)values(mail,'CHECKLIST SQL SYNTHETIC',case when who='other'then'rider'else who end,'approved')returning id into uid;
 insert into auth.sessions(id,user_id,created_at,updated_at)values(s,a,now(),now());
 insert into checklist_people values(who,uid,a,s);end loop;
end$$;
create function pg_temp.claim(who text)returns void language plpgsql security definer as $$declare p checklist_people;begin
 select *into p from checklist_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id)::text,true);
end$$;
create temp table checklist_fixture(oid bigint,aid bigint,uid bigint);
do $$declare o bigint;a bigint;rid bigint;cid bigint;begin
 select id into rid from checklist_people where label='rider';select id into cid from checklist_people where label='customer';
 insert into public.riders(userid,is_online,is_available,isavailable,last_seen)values(rid,true,false,false,clock_timestamp());
 insert into public.orders(user_id,rider_id,order_status,amount,payment_method,delivery_address)values(cid,rid,'ready',200,'COD','CHECKLIST SYNTHETIC TEST ONLY')returning id into o;
 insert into public.rider_assignments(orderid,riderid,status)values(o,rid,'Accepted')returning id into a;
 insert into checklist_fixture values(o,a,rid);
 -- Explicit privileged mock issuance; no email/provider call or plaintext stored.
 insert into public.delivery_otps(id,order_id,rider_id,review_admin_id,auth_id,nonce,verifier,state,sent_at,expires_at,provider_id,lease_until)
 values(gen_random_uuid(),o,rid,(select id from checklist_people where label='admin'),
 (select auth_id from checklist_people where label='rider'),'CHECKLIST-SQL-MOCK',
 public.fr33_tag(o,'CHECKLIST-SQL-MOCK','123456'),'ACCEPTED',clock_timestamp(),clock_timestamp()+interval'10 minutes','CHECKLIST-SQL-MOCK',clock_timestamp()+interval'10 minutes');
end$$;
create function pg_temp.valid()returns jsonb language sql as $$select '[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]'::jsonb$$;
create function pg_temp.submit(v integer,body jsonb)returns jsonb language sql as $$select public.submit_pre_delivery_checklist((select aid from checklist_fixture),v,body)$$;
create function pg_temp.denied(command text,label text,zero_rows_denied boolean default false)returns void language plpgsql as $$declare affected bigint;begin
 begin execute command;get diagnostics affected=row_count;
 if zero_rows_denied and affected=0 then perform pg_temp.ok(true,label);return;end if;
 exception when insufficient_privilege or check_violation then perform pg_temp.ok(true,label);return;end;
 raise exception 'Unexpected permitted operation: %',label;end$$;
do $$declare who text;r jsonb;f checklist_fixture;t timestamptz;n bigint;begin
 select *into f from checklist_fixture;
 foreach who in array array['customer','vendor','other','admin']loop
 perform pg_temp.claim(who);r:=pg_temp.submit(1,pg_temp.valid());perform pg_temp.ok(r->>'code'='FORBIDDEN',who||' cannot submit as assigned rider');end loop;
 perform set_config('request.jwt.claims','{}',true);perform pg_temp.ok(pg_temp.submit(1,pg_temp.valid())->>'code'='FORBIDDEN','anonymous identity denied');
 perform pg_temp.claim('rider');r:=public.pre_delivery_checklist(f.oid);
 perform pg_temp.ok(r->>'code'='OK'and jsonb_array_length(r->'items')=3 and(r->>'completed')::boolean=false,'authoritative definition and initial incomplete state');
 perform pg_temp.ok(pg_temp.submit(2,pg_temp.valid())->>'code'='INVALID_VERSION','unapproved version rejected');
 perform pg_temp.ok(pg_temp.submit(1,'[]')->>'code'='INVALID_CONFIRMATIONS','missing confirmations rejected');
 perform pg_temp.ok(pg_temp.submit(1,null)->>'code'='INVALID_CONFIRMATIONS','null confirmations rejected');
 perform pg_temp.ok(pg_temp.submit(1,'{}')->>'code'='INVALID_CONFIRMATIONS','object confirmations rejected');
 perform pg_temp.ok(pg_temp.submit(1,jsonb_set(pg_temp.valid(),'{0,confirmed}','false'))->>'code'='INVALID_CONFIRMATIONS','false confirmation rejected');
 perform pg_temp.ok(pg_temp.submit(1,jsonb_set(pg_temp.valid(),'{0,id}','"unknown"'))->>'code'='INVALID_CONFIRMATIONS','unknown item rejected');
 perform pg_temp.ok(pg_temp.submit(1,jsonb_set(pg_temp.valid(),'{0,id}','"packaging_intact"'))->>'code'='INVALID_CONFIRMATIONS','duplicate item rejected');
 perform pg_temp.ok(pg_temp.submit(1,jsonb_set(pg_temp.valid(),'{0,confirmed}','"true"'))->>'code'='INVALID_CONFIRMATIONS','string true rejected');
 perform pg_temp.ok(pg_temp.submit(1,jsonb_set(pg_temp.valid(),'{0,extra}','true'))->>'code'='INVALID_CONFIRMATIONS','unknown confirmation property rejected');
 perform pg_temp.ok(public.start_checklisted_delivery(f.aid)->>'code'='CHECKLIST_REQUIRED','start before checklist rejected');
 select count(*)into n from public.delivery_otp_verifications where order_id=f.oid;
 perform pg_temp.ok(public.verify_delivery_otp(f.oid,'123456',gen_random_uuid())->>'code'='CHECKLIST_REQUIRED','OTP returns actionable checklist gate');
 perform pg_temp.ok((select count(*)=n from public.delivery_otp_verifications where order_id=f.oid),'checklist rejection does not create OTP attempt');
 perform pg_temp.ok(not exists(select 1 from public.delivery_otp_rates where rider_id=f.uid),'checklist rejection does not consume verifier rate');
 perform pg_temp.ok((select state='ACCEPTED'and attempts=0 from public.delivery_otps where order_id=f.oid),'valid OTP remains accepted and unconsumed');
 begin
  update public.orders set order_status='cancelled'where id=f.oid;
  perform pg_temp.ok(pg_temp.submit(1,pg_temp.valid())->>'code'='INACTIVE_ASSIGNMENT','cancelled order cannot submit');
  if pg_temp.submit(1,pg_temp.valid())->>'code'<>'INACTIVE_ASSIGNMENT'then raise exception 'Cancellation bypass';end if;
  raise sqlstate'PT001';
 exception when sqlstate'PT001'then null;end;
 perform pg_temp.ok(true,'cancelled order submission rejected inside rollback fixture');
 perform pg_temp.ok((select order_status='ready'from public.orders where id=f.oid),'cancelled fixture subtransaction restored without business mutation');
 perform pg_temp.denied('update public.orders set order_status=''on_the_way''where id='||f.oid,'trusted direct premature start also rejected');
 update public.rider_assignments set status='Pending'where id=f.aid;
 perform pg_temp.ok(pg_temp.submit(1,pg_temp.valid())->>'code'='PICKUP_REQUIRED','pending assignment not yet accepted for pickup');
 update public.rider_assignments set status='Cancelled'where id=f.aid;
 perform pg_temp.ok(pg_temp.submit(1,pg_temp.valid())->>'code'='INACTIVE_ASSIGNMENT','inactive assignment rejected');
 update public.rider_assignments set status='Accepted'where id=f.aid;
 update public.orders set order_status='preparing'where id=f.oid;
 perform pg_temp.ok(pg_temp.submit(1,pg_temp.valid())->>'code'='PICKUP_REQUIRED','submission outside pickup rejected');
 update public.orders set order_status='ready'where id=f.oid;
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 update public.users set is_blocked=true where id=f.uid;
 perform pg_temp.claim('rider');
 perform pg_temp.ok(pg_temp.submit(1,pg_temp.valid())->>'code'='FORBIDDEN','blocked rider cannot submit');
 perform pg_temp.ok(public.start_checklisted_delivery(f.aid)->>'code'='FORBIDDEN','blocked rider cannot start');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 update public.users set is_blocked=false where id=f.uid;
 perform pg_temp.claim('rider');
 r:=pg_temp.submit(1,pg_temp.valid());perform pg_temp.ok(r->>'code'='COMPLETED'and(r->>'completed')::boolean,'assigned rider submits full checklist');
 select submitted_at into t from public.pre_delivery_checklists where assignment_id=f.aid;
 perform pg_temp.ok(t is not null and t<=clock_timestamp(),'server generated timestamp');
 perform pg_temp.ok((select checklist_completed and checklist_completed_at=t from public.rider_assignments where id=f.aid),'atomic assignment flag and evidence timestamp');
 perform pg_temp.ok((select definition_snapshot=(select items from checklist_private.definitions where version=1)from public.pre_delivery_checklists where assignment_id=f.aid),'exact definition snapshot preserved');
 r:=pg_temp.submit(1,pg_temp.valid());perform pg_temp.ok((r->>'replayed')::boolean,'repeated submission idempotent');
 perform pg_temp.ok((select count(*)=1 and min(submitted_at)=t from public.pre_delivery_checklists where assignment_id=f.aid),'one record and unchanged timestamp');
 perform pg_temp.ok((select order_status='ready'from public.orders where id=f.oid),'checklist completion alone does not start delivery');
 r:=public.start_checklisted_delivery(f.aid);perform pg_temp.ok(r->>'code'='STARTED','completed rider can start');
 perform pg_temp.ok((select order_status='on_the_way'from public.orders where id=f.oid),'actual in-transit transition');
 perform pg_temp.ok((public.start_checklisted_delivery(f.aid)->>'replayed')::boolean,'start retry idempotent');
 perform pg_temp.ok((select state='ACCEPTED'and attempts=0 from public.delivery_otps where order_id=f.oid),'start does not consume existing valid OTP');
end$$;
grant select on checklist_fixture,checklist_people to authenticated;
select pg_temp.claim('rider');set local role authenticated;
select pg_temp.ok((select count(*)=1 from public.pre_delivery_checklists where assignment_id=(select aid from checklist_fixture)),'rider own evidence readable');
select pg_temp.denied('update public.rider_assignments set checklist_completed=false where id='||(select aid from checklist_fixture),'direct checklist field modification denied');
select pg_temp.denied('insert into public.pre_delivery_checklists(assignment_id,rider_id,checklist_version,confirmations,definition_snapshot)values(0,0,1,''[]'',''[]'')','direct response insert denied');
select pg_temp.denied('update public.pre_delivery_checklists set confirmations=''[]''','direct response edit denied');
select pg_temp.denied('update public.orders set order_status=''delivered''where id='||(select oid from checklist_fixture),'direct completion bypass denied',true);
reset role;
select pg_temp.ok((select order_status='on_the_way'from public.orders where id=(select oid from checklist_fixture)),'direct write did not complete delivery');
set local role authenticated;
reset role;select pg_temp.claim('other');set local role authenticated;
select pg_temp.ok((select count(*)=0 from public.pre_delivery_checklists where assignment_id=(select aid from checklist_fixture)),'second rider cannot read evidence');
reset role;select pg_temp.claim('customer');set local role authenticated;
select pg_temp.ok((select count(*)=0 from public.pre_delivery_checklists where assignment_id=(select aid from checklist_fixture)),'customer cannot read rider evidence');
reset role;select pg_temp.claim('admin');set local role authenticated;
select pg_temp.ok((select count(*)=1 from public.pre_delivery_checklists where assignment_id=(select aid from checklist_fixture)),'approved admin evidence read');
reset role;
do $$declare f checklist_fixture;r jsonb;begin
 select *into f from checklist_fixture;perform pg_temp.claim('rider');
 r:=public.verify_delivery_otp(f.oid,'123456',gen_random_uuid());
 perform pg_temp.ok(r->>'code'='OK','original valid OTP succeeds after checklist and start');
 perform pg_temp.ok((select state='USED'from public.delivery_otps where order_id=f.oid),'successful verifier consumes OTP exactly once');
 perform pg_temp.ok((select count(*)=1 from public.delivery_proof where orderid=f.oid::text),'existing one protected delivery proof');
 perform pg_temp.ok(pg_temp.submit(1,pg_temp.valid())->>'code'='INACTIVE_ASSIGNMENT','delivered assignment cannot be resubmitted');
 perform pg_temp.ok(public.verify_delivery_otp(f.oid,'123456',gen_random_uuid())->>'code'='ALREADY_DELIVERED','completed delivery retry remains idempotent');
end$$;
select pg_temp.ok(not has_function_privilege('anon','public.submit_pre_delivery_checklist(bigint,integer,jsonb)','execute'),'anonymous RPC grant denied');
select pg_temp.ok(not has_table_privilege('authenticated','public.pre_delivery_checklists','insert'),'response insert grant absent');
select pg_temp.ok(not has_schema_privilege('authenticated','checklist_private','usage'),'private definition and exemption schema hidden');
do $$declare x record;n bigint;begin
 if to_regclass('pg_temp.checklist_before_migration')is not null then
  execute 'select *from checklist_before_migration'into x;
  perform pg_temp.ok(checklist_private.legacy(x.oid,x.rid),'actual pre-migration in-transit assignment captured');
  perform pg_temp.ok(not exists(select 1 from checklist_private.legacy_transit where order_id=x.pickup_oid),'pre-migration pickup order not exempt');
  perform pg_temp.ok((select not checklist_completed and checklist_completed_at is null from public.rider_assignments where id=x.aid),'legacy exemption does not fabricate completed checklist');
  perform pg_temp.ok(not exists(select 1 from public.pre_delivery_checklists where assignment_id=x.aid),'legacy has no invented checklist response');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',x.auth_id,'role','authenticated','session_id',x.session_id)::text,true);
  perform pg_temp.ok(public.verify_delivery_otp(x.oid,'123456',gen_random_uuid())->>'code'='NO_OTP','legacy in-transit reaches original verifier without checklist gate');
  update public.rider_assignments set status='Cancelled'where id=x.aid;
  insert into public.rider_assignments(orderid,riderid,status)values(x.oid,x.rid,'Accepted')returning id into n;
  perform pg_temp.ok(not checklist_private.allowed(x.oid,x.rid),'new assignment cannot inherit old legacy exemption');
  perform pg_temp.ok(public.verify_delivery_otp(x.oid,'123456',gen_random_uuid())->>'code'='CHECKLIST_REQUIRED','replacement assignment OTP cannot bypass checklist');
 end if;
end$$;
select jsonb_agg(to_jsonb(x))from checklist_results x;
rollback;
