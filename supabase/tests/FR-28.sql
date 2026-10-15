-- FR28 rules/permissions in one rollback transaction; HTTP races are separate.
begin;
create temp table fr28_results(name text,result text);
create function pg_temp.ok(value boolean,label text)returns void language plpgsql security definer as $$begin
 if value is distinct from true then raise exception 'FR28 assertion failed: %',label;end if;
 insert into fr28_results values(label,'PASS');
end$$;
create temp table fr28_people(label text,id bigint,auth_id uuid,session_id uuid,email text);
create temp table fr28_ids(label text,id bigint,operation uuid);
do $$declare label text;aid uuid;uid bigint;sid uuid;rid bigint;cid bigint;vid bigint;oid bigint;begin
 foreach label in array array['admin','admin2','customer','vendor','rider']loop
  aid:=gen_random_uuid();sid:=gen_random_uuid();
  insert into auth.users(id,instance_id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
  values(aid,'00000000-0000-0000-0000-000000000000','fr28-sql-'||label||'-'||aid||'@example.test',now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{"fr28_fixture":true}');
  insert into public.users(email,name,role,verification_status)values('fr28-sql-'||label||'-'||aid||'@example.test','FR28 SQL synthetic',case when label='admin2'then 'admin'else label end,'approved')returning id into uid;
  insert into auth.sessions(id,user_id,created_at,updated_at)values(sid,aid,now(),now());
  insert into fr28_people values(label,uid,aid,sid,'fr28-sql-'||label||'-'||aid||'@example.test');
 end loop;
 select p.id into rid from fr28_people p where p.label='rider';select p.id into cid from fr28_people p where p.label='customer';select p.id into vid from fr28_people p where p.label='vendor';
 insert into public.riders(userid,is_online,last_seen)values(rid,true,now());
 insert into public.orders(user_id,rider_id,vendor_id,order_status,amount,payment_method,delivery_address)values(cid,rid,vid,'on_the_way',25,'COD','FR28 SQL SYNTHETIC')returning id into oid;
 insert into fr28_ids values('active-order',oid,null);
 insert into public.products(vendor_id,name,price,is_available)values(vid,'FR28 SQL SYNTHETIC PRODUCT',25,true)returning id into oid;
 insert into fr28_ids values('product',oid,null);
end$$;
create function pg_temp.claim(label text)returns void language plpgsql security definer as $$declare person fr28_people;begin
 select * into person from fr28_people p where p.label=claim.label;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',person.auth_id,'role','authenticated','session_id',person.session_id,'email',person.email)::text,true);
end$$;
grant select on fr28_people,fr28_ids to authenticated,anon;
grant execute on function pg_temp.ok(boolean,text),pg_temp.claim(text)to authenticated,anon;
select pg_temp.claim('admin');
set local role authenticated;
select pg_temp.ok((select count(*)<=25 from public.fr28_user_list()),'admin paginated user list');
select pg_temp.ok((select count(*)=5 from public.fr28_user_list('FR28 SQL synthetic',null,null,null,null,25)),'name search bound');
select pg_temp.ok((select count(*)=1 from public.fr28_user_list('FR28 SQL synthetic','rider',false,null,null,25)),'role/status filters');
reset role;
select pg_temp.claim('customer');set local role authenticated;
do $$begin
 begin perform public.fr28_user_list();raise exception 'directory unexpectedly readable';exception when insufficient_privilege then perform pg_temp.ok(true,'ordinary directory RPC denied');end;
 begin perform public.admin_set_user_blocked(null,1,true,gen_random_uuid());raise exception 'mutation unexpectedly executable';exception when insufficient_privilege then perform pg_temp.ok(true,'ordinary privileged block RPC denied');end;
 begin update public.users set role='admin'where id=(select id from fr28_people where label='customer');raise exception 'role update unexpectedly allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'role escalation denied');end;
 begin update public.users set is_blocked=true where id=(select id from fr28_people where label='customer');raise exception 'blocked flag update unexpectedly allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'own blocked flag update denied');end;
 begin perform 1 from public.fr28_operations;raise exception 'operation secrets readable';exception when insufficient_privilege then perform pg_temp.ok(true,'ordinary operation table access denied');end;
end$$;
select pg_temp.ok((select count(*)=1 from public.users),'ordinary users cannot enumerate directory');
select pg_temp.ok(not has_table_privilege('authenticated','public.security_audit_log','UPDATE'),'ordinary audit updates denied');
select pg_temp.ok(not has_table_privilege('authenticated','public.security_audit_log','DELETE'),'ordinary audit deletion denied');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.ok(public.admin_set_user_blocked((select auth_id from fr28_people where label='admin'),(select id from fr28_people where label='admin'),true,gen_random_uuid())->>'code'='SELF_FORBIDDEN','self block denied');
select pg_temp.ok(public.admin_set_user_blocked((select auth_id from fr28_people where label='admin'),(select id from fr28_people where label='admin2'),true,gen_random_uuid())->>'code'='ADMIN_PROTECTED','other admin protected');
select pg_temp.ok(public.admin_set_user_blocked((select auth_id from fr28_people where label='admin'),-999,true,gen_random_uuid())->>'code'='NOT_FOUND','unknown target');
do $$begin
 begin perform public.admin_set_user_blocked((select auth_id from fr28_people where label='customer'),(select id from fr28_people where label='rider'),true,gen_random_uuid());raise exception 'non-admin mutation allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'server rejects forged non-admin actor');end;
end$$;
insert into fr28_ids values('rider-block',(select id from fr28_people where label='rider'),gen_random_uuid());
select pg_temp.ok(public.admin_set_user_blocked((select auth_id from fr28_people where label='admin'),(select id from fr28_ids where label='rider-block'),true,(select operation from fr28_ids where label='rider-block'))->>'code'='PENDING','block commits before Auth sync');
select pg_temp.ok((select is_blocked from public.users where id=(select id from fr28_ids where label='rider-block')),'authoritative rider blocked');
select pg_temp.ok((select not is_online from public.riders where userid=(select id from fr28_ids where label='rider-block')),'blocked rider offline');
select pg_temp.ok(not public.fr21_approved_rider((select id from fr28_ids where label='rider-block')),'blocked rider ineligible');
select pg_temp.ok((select order_status='on_the_way'and rider_id=(select id from fr28_ids where label='rider-block')from public.orders where id=(select id from fr28_ids where label='active-order')),'active order state and assignment preserved');
select pg_temp.ok((select count(*)=1 from public.security_audit_log where user_operation_id=(select operation from fr28_ids where label='rider-block')and action='BLOCK_USER'),'block audit once');
select pg_temp.ok(public.admin_set_user_blocked((select auth_id from fr28_people where label='admin2'),(select id from fr28_ids where label='rider-block'),false,gen_random_uuid())->>'code'='BUSY','opposite pending intent denied');
select pg_temp.ok(public.admin_set_user_blocked((select auth_id from fr28_people where label='admin'),(select id from fr28_ids where label='rider-block'),true,(select operation from fr28_ids where label='rider-block'))->>'code'='PENDING','pending duplicate idempotent');
select pg_temp.ok(public.fr28_finish((select operation from fr28_ids where label='rider-block'),'AUTH_UNCONFIRMED')->>'code'='AUTH_SYNC_PENDING','controlled external failure remains partial');
select pg_temp.ok((select is_blocked from public.users where id=(select id from fr28_ids where label='rider-block')),'Auth failure never restores access');
select pg_temp.claim('rider');set local role authenticated;
select pg_temp.ok(not public.is_current_user_allowed(),'existing valid session immediately denied');
select pg_temp.ok(public.fr21_actor()is null,'blocked rider actor denied');
select pg_temp.ok(public.fr28_account_status()->>'code'='FR28_ACCOUNT_BLOCKED','own status usable for exact blocked message');
select set_config('request.path','/orders',true);
do $$begin
 begin perform public.fr28_pre_request();raise exception 'blocked request allowed';exception when sqlstate 'PT403'then perform pg_temp.ok(true,'REST next call explicitly 403');end;
 begin perform public.fr21_set_presence(true,1,1);raise exception 'blocked presence accepted';exception when insufficient_privilege then perform pg_temp.ok(true,'blocked rider presence denied');end;
end$$;
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);
-- Explicit mock Auth state in a rolled-back SQL test; not a real API ban claim.
update auth.users set banned_until=now()+interval '1 day'where id=(select auth_id from fr28_people where label='rider');
select public.fr28_revoke_sessions((select operation from fr28_ids where label='rider-block'));
select pg_temp.ok((select count(*)=0 from auth.sessions where user_id=(select auth_id from fr28_people where label='rider')),'only target sessions revoked');
select pg_temp.ok((select count(*)=4 from auth.sessions where user_id in(select auth_id from fr28_people where label<>'rider')),'other fixture sessions preserved');
select pg_temp.ok(public.fr28_finish((select operation from fr28_ids where label='rider-block'))->>'code'='OK','confirmed mocked ban completes SQL phase');
select pg_temp.ok(public.admin_set_user_blocked((select auth_id from fr28_people where label='admin'),(select id from fr28_ids where label='rider-block'),true,gen_random_uuid())->>'code'='NO_CHANGE','already blocked no-op');
insert into fr28_ids values('rider-unblock',(select id from fr28_people where label='rider'),gen_random_uuid());
select public.admin_set_user_blocked((select auth_id from fr28_people where label='admin'),(select id from fr28_ids where label='rider-unblock'),false,(select operation from fr28_ids where label='rider-unblock'));
select pg_temp.ok((select is_blocked from public.users where id=(select id from fr28_ids where label='rider-unblock')),'pending unblock remains denied');
select pg_temp.ok(public.fr28_finish((select operation from fr28_ids where label='rider-unblock'))->>'code'='AUTH_SYNC_PENDING','unconfirmed unban cannot restore access');
update auth.users set banned_until=null where id=(select auth_id from fr28_people where label='rider');
select public.fr28_revoke_sessions((select operation from fr28_ids where label='rider-unblock'));
select pg_temp.ok(public.fr28_finish((select operation from fr28_ids where label='rider-unblock'))->>'code'='OK','confirmed mocked unban restores SQL authorization');
select pg_temp.ok((select not is_blocked from public.users where id=(select id from fr28_ids where label='rider-unblock')),'unblocked status persisted');
select pg_temp.ok((select not is_online from public.riders where userid=(select id from fr28_ids where label='rider-unblock')),'unblock never sets rider online');
select pg_temp.ok((select count(*)=1 from public.security_audit_log where user_operation_id=(select operation from fr28_ids where label='rider-unblock')and action='UNBLOCK_USER'),'unblock audit once');
select pg_temp.ok(public.admin_set_user_blocked((select auth_id from fr28_people where label='admin'),(select id from fr28_ids where label='rider-unblock'),false,gen_random_uuid())->>'code'='NO_CHANGE','already unblocked no-op');
select pg_temp.claim('rider');set local role authenticated;
select pg_temp.ok(not public.fr28_token_live(),'revoked old JWT cannot return after unblock');
select set_config('request.path','/orders',true);
do $$begin begin perform public.fr28_pre_request();raise exception 'old JWT unexpectedly allowed';exception when sqlstate 'PT401'then perform pg_temp.ok(true,'revoked session returns explicit 401 after unblock');end;end$$;
reset role;
insert into auth.sessions(id,user_id,created_at)select session_id,auth_id,now()from fr28_people where label='rider';
select pg_temp.claim('rider');set local role authenticated;
select pg_temp.ok(public.is_current_user_allowed(),'new session unblocked access restored');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into fr28_ids values('vendor-block',(select id from fr28_people where label='vendor'),gen_random_uuid());
select public.admin_set_user_blocked((select auth_id from fr28_people where label='admin'),(select id from fr28_ids where label='vendor-block'),true,(select operation from fr28_ids where label='vendor-block'));
select pg_temp.claim('customer');set local role authenticated;
select pg_temp.ok((select count(*)=0 from public.products where id=(select id from fr28_ids where label='product')),'blocked vendor products hidden');
reset role;select pg_temp.claim('vendor');set local role authenticated;
select pg_temp.ok(public.fr21_actor()is null,'blocked vendor protected operations denied');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into fr28_ids values('customer-block',(select id from fr28_people where label='customer'),gen_random_uuid());
select public.admin_set_user_blocked((select auth_id from fr28_people where label='admin'),(select id from fr28_ids where label='customer-block'),true,(select operation from fr28_ids where label='customer-block'));
select pg_temp.claim('customer');set local role authenticated;
do $$begin
 begin insert into public.orders(user_id,amount,order_status,delivery_address)values((select id from fr28_people where label='customer'),25,'placed','FR28 DENIED');raise exception 'blocked customer inserted order';exception when insufficient_privilege then perform pg_temp.ok(true,'blocked customer order placement denied');end;
 begin insert into public.security_audit_log(actor_id,action,target_type,target_id)values((select id from fr28_people where label='customer'),'UNBLOCK_USER','users',1);raise exception 'audit forged';exception when insufficient_privilege then perform pg_temp.ok(true,'ordinary audit forgery denied');end;
end$$;
reset role;select set_config('request.jwt.claims','{}',true);set local role anon;
do $$begin
 begin perform public.fr28_user_list();raise exception 'anonymous list allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'anonymous directory denied');end;
 begin perform public.admin_set_user_blocked(null,1,true,gen_random_uuid());raise exception 'anonymous mutation allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'anonymous block denied');end;
end$$;
reset role;
-- A confirmed Auth email can change independently of the legacy profile email.
-- Service routines must still act on the bound UUID, not another profile alias.
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$declare aid uuid:=gen_random_uuid(); uid bigint; victim bigint; old_email text;
 cid bigint; cauth uuid; current_email text; oid bigint; reserved jsonb; begin
 insert into auth.users(id,email,email_confirmed_at,role,aud)
 values(aid,'fr28-canonical-'||aid||'@example.test',now(),'authenticated','authenticated');
 insert into public.users(email,name,role,verification_status)
 values('fr28-canonical-'||aid||'@example.test','FR28 canonical synthetic','rider','approved')returning id into uid;
 select id,email into victim,old_email from fr28_people where label='rider';
 update auth.users set email='fr28-moved-'||id||'@example.test'where id=(select auth_id from fr28_people where label='rider');
 update public.users set is_blocked=true where id=victim;
 update auth.users set email=old_email where id=aid;
 perform public.fr04_begin_upload(aid,gen_random_uuid(),repeat('a',64),'jpg','3200012345671');
 perform pg_temp.ok((select cnic_submission_status='uploading'from public.users where id=uid),'CNIC service actor bound by UUID after Auth email drift');
 perform pg_temp.ok((select cnic_upload_id is null from public.users where id=victim),'blocked email-alias victim not modified');
 update public.users set verification_status='approved'where id=uid;
 select id,auth_id into cid,cauth from fr28_people where label='customer';
 current_email:='fr28-current-recipient-'||cauth||'@example.test';
 update auth.users set email=current_email where id=cauth;
 insert into public.orders(user_id,rider_id,order_status,amount,payment_method,delivery_address)
 values(cid,uid,'on_the_way',25,'COD','FR28 CANONICAL SQL SYNTHETIC')returning id into oid;
 -- SQL-only provider mock: temporary quota headroom is rolled back; no mail.
 update public.delivery_otp_budgets set used=0 where day=(clock_timestamp()at time zone'UTC')::date;
 reserved:=public.issue_delivery_otp(oid,gen_random_uuid(),aid);
 perform pg_temp.ok(reserved->>'code'='SEND','OTP service rider bound by UUID after Auth email drift');
 perform pg_temp.ok(reserved->>'recipient'=current_email,'OTP recipient is current confirmed canonical Auth email');
end$$;
select jsonb_agg(to_jsonb(r))as results from fr28_results r;
rollback;
