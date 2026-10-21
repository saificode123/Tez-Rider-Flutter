-- Non-destructive TEST-only role checks. Every fixture/action rolls back.
-- No existing record changes, external provider requests, trigger disabling or deletes.
do $$begin
 if current_setting('final1.test_project_ref',true) is distinct from 'igeisilhtmglgnqvllrx' then
   raise exception 'Dedicated TEST marker required';
 end if;
end$$;
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create temp table final1_results(name text,result text);
create temp table final1_people(label text,id bigint,auth_id uuid,session_id uuid,email text);
create temp table final1_orders(label text,id bigint,vo bigint,assignment bigint);
create function pg_temp.ok(v boolean,label text)returns void language plpgsql security definer set search_path=pg_temp,pg_catalog as $$begin
 if v is distinct from true then raise exception 'FINAL security assertion: %',label;end if;
 insert into final1_results values(label,'PASS');end$$;
create function pg_temp.denied(statement text,expected text,label text)returns void
language plpgsql security invoker set search_path=pg_temp,pg_catalog as $$declare actual text;begin
 begin execute statement;exception when others then get stacked diagnostics actual=returned_sqlstate;end;
 perform pg_temp.ok(actual=expected,label);end$$;

do $$declare who text;u bigint;a uuid;s uuid;mail text;r text;begin
 foreach who in array array['customer','other-customer','vendor','other-vendor','rider','other-rider','admin','pending-admin','blocked'] loop
 a:=gen_random_uuid();s:=gen_random_uuid();mail:='final1-sql-'||a||'@example.test';
 r:=case when who in('other-customer','blocked')then'customer' when who='other-vendor'then'vendor' when who='other-rider'then'rider' when who='pending-admin'then'admin'else who end;
 insert into auth.users(id,email,email_confirmed_at,role,aud)values(a,mail,now(),'authenticated','authenticated');
 insert into public.users(name,email,role,verification_status,is_blocked)
 values('FINAL1 SQL SYNTHETIC',mail,r,case when who='pending-admin'then'pending'else'approved'end,who='blocked') returning id into u;
 insert into auth.sessions(id,user_id,created_at,updated_at)values(s,a,now(),now());
 insert into final1_people values(who,u,a,s,mail);
 end loop;
end$$;
create function pg_temp.claim(who text)returns void language plpgsql security definer set search_path=pg_temp,pg_catalog as $$declare p final1_people;begin
 select * into strict p from final1_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id,'email',p.email)::text,true);
end$$;

do $$declare i integer;o bigint;v bigint;a bigint;r bigint;begin
 for i in 1..2 loop
 select id into r from final1_people where label=case when i=1 then'rider'else'other-rider'end;
 insert into public.riders(userid,is_online,is_available,isavailable,last_seen)values(r,true,false,false,clock_timestamp());
 insert into public.orders(user_id,rider_id,order_status,amount,payment_method,delivery_address)
 values((select id from final1_people where label=case when i=1 then'customer'else'other-customer'end),r,'ready',1,'COD','FINAL1 SQL SYNTHETIC')returning id into o;
 insert into public.vendor_orders(order_id,vendor_id,status,sub_total)
 values(o,(select id from final1_people where label=case when i=1 then'vendor'else'other-vendor'end),'ready',1)returning id into v;
 insert into public.rider_assignments(orderid,riderid,status)values(o,r,'Accepted')returning id into a;
 insert into final1_orders values(i::text,o,v,a);
 end loop;
end$$;
grant select on final1_people,final1_orders to authenticated,anon;
select pg_temp.ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where c.relkind in('r','p') and(n.nspname='public' or n.nspname like '%private')and not c.relrowsecurity),'all application tables have RLS');
select pg_temp.ok(not exists(select 1 from pg_namespace n where n.nspname like '%private'
 and(has_schema_privilege('authenticated',n.oid,'USAGE')or has_schema_privilege('anon',n.oid,'USAGE'))),'private schemas deny client USAGE');
select pg_temp.ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where p.prosecdef and(n.nspname='public' or n.nspname like '%private')and(p.proconfig is null or not exists(select 1 from unnest(p.proconfig)s where s in('search_path=""','search_path=pg_catalog')))),'every definer pins trusted search_path');
select pg_temp.ok(not exists(select 1 from storage.buckets where name in('rider-cnic','dispute-evidence','invoices')and public),'sensitive buckets private');

set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select pg_temp.denied('select public.final1_review_vendor(1,''approved'')','42501','anonymous vendor review denied');
select pg_temp.denied('select public.final1_claim_assistant()','42501','anonymous provider claim denied');
select pg_temp.denied('select * from public.security_audit_log','42501','anonymous audit denied');
select pg_temp.denied('select public.final1_search_products(''food'')','42501','anonymous search denied');
select pg_temp.ok(not exists(select 1 from storage.objects where bucket_id in('rider-cnic','dispute-evidence','invoices')),'anonymous private Storage invisible');
reset role;

set local role authenticated;
do $$declare who text;target bigint;v bigint;n integer;begin
 foreach who in array array['customer','vendor','rider','pending-admin','blocked']loop
 perform pg_temp.claim(who);
 perform pg_temp.denied('select public.final1_review_vendor(1,''approved'')','42501',who||': privileged review denied');
 perform pg_temp.denied('insert into public.security_audit_log(actor_id,action,target_type,target_id)values(null,''forged'',''users'',1)','42501',who||': audit forgery denied');
 perform pg_temp.denied('update public.security_audit_log set action=''forged''where target_id in(select id from final1_people)','42501',who||': audit update denied');
 perform pg_temp.denied('delete from public.security_audit_log where target_id in(select id from final1_people)','42501',who||': audit delete denied');
 perform pg_temp.denied('select * from vault.decrypted_secrets','42501',who||': Vault denied');
 end loop;
 perform pg_temp.claim('customer');
 select id into target from final1_people where label='other-customer';
 perform pg_temp.ok(not exists(select 1 from public.users where id=target),'cross-customer profile invisible');
 perform pg_temp.ok(not exists(select 1 from public.orders where id=(select id from final1_orders where label='2')),'cross-customer orders invisible');
 perform pg_temp.ok(exists(select 1 from public.orders where id=(select id from final1_orders where label='1')),'owned customer order visible');
 perform pg_temp.denied('update public.users set role=''admin'' where id=public.fr21_actor()','42501','role escalation denied');
 perform pg_temp.denied('update public.users set auth_user_id=gen_random_uuid()where id=public.fr21_actor()','42501','identity reassignment denied');
 perform pg_temp.denied('update public.users set name=repeat(''x'',121)where id=public.fr21_actor()','22023','oversized profile name rejected');
 perform pg_temp.denied('update public.users set name=''''where id=public.fr21_actor()','22023','empty profile name rejected');
 perform pg_temp.denied('update public.users set phone=''abc<script>''where id=public.fr21_actor()','22023','malformed phone rejected');
 update public.users set name='Valid TEST profile',phone='+92 300 1234567'where id=public.fr21_actor();
 perform pg_temp.ok((select name='Valid TEST profile'from public.users where id=public.fr21_actor()),'valid profile update confirmed');
 perform pg_temp.denied('select public.final1_search_products(repeat(''x'',121))','22023','oversized search rejected');
 perform pg_temp.denied('select public.final1_search_products(null)','22023','null search rejected');
 perform pg_temp.denied('select public.final1_search_products('''')','22023','empty search rejected');
 perform pg_temp.ok((select count(*)from public.final1_search_products('x%,name.eq.secret'))<=40,'filter punctuation treated as literal search');
 for n in 1..10 loop perform pg_temp.ok(public.final1_claim_assistant(),'assistant bounded claim '||n);end loop;
 perform pg_temp.ok(not public.final1_claim_assistant(),'assistant eleventh request denied without provider');
 perform pg_temp.claim('vendor');
 perform pg_temp.ok(not exists(select 1 from public.vendor_orders where id=(select vo from final1_orders where label='2')),'cross-vendor portion invisible');
 perform pg_temp.ok(exists(select 1 from public.vendor_orders where id=(select vo from final1_orders where label='1')),'owned vendor portion visible');
 perform pg_temp.denied('update public.products set price=0 where vendor_id=public.fr21_actor()','42501','direct price manipulation denied');
 perform pg_temp.claim('rider');
 perform pg_temp.ok(not exists(select 1 from public.rider_assignments where id=(select assignment from final1_orders where label='2')),'cross-rider assignment invisible');
 perform pg_temp.ok(exists(select 1 from public.rider_assignments where id=(select assignment from final1_orders where label='1')),'own rider assignment visible');
 perform pg_temp.ok(public.fr13_tracking_context((select id from final1_orders where label='2'),true)->>'code'='FORBIDDEN','unrelated rider tracking denied');
 perform pg_temp.ok(public.fr14_route_context((select id from final1_orders where label='2'))->>'code'='FORBIDDEN','unrelated rider route denied');
 begin
   update public.orders set order_status='delivered'where id=(select id from final1_orders where label='1');
 exception when insufficient_privilege or check_violation then null;
 end;
 perform pg_temp.ok((select order_status='ready'from public.orders where id=(select id from final1_orders where label='1')),'direct delivery transition leaves ready state unchanged');
 perform pg_temp.claim('blocked');
 perform pg_temp.ok(public.fr21_actor()is null,'blocked actor unavailable');
 perform pg_temp.ok(not exists(select 1 from public.orders),'blocked order reads denied');
 perform pg_temp.denied('select public.final1_claim_assistant()','42501','blocked provider claim denied');
 perform pg_temp.denied('select public.final1_search_products(''food'')','42501','blocked search denied');
 perform pg_temp.claim('admin');
 select id into target from final1_people where label='vendor';
 perform pg_temp.denied('select public.final1_review_vendor(0,''approved'')','22023','malformed vendor ID rejected');
 perform pg_temp.denied('select public.final1_review_vendor(1,''suspended'')','22023','unsupported review status rejected');
 perform pg_temp.denied('select public.final1_review_vendor(1,null)','22023','null review status rejected');
 perform pg_temp.ok(public.final1_review_vendor(target,'rejected')->>'verification_status'='rejected','admin vendor decision confirmed');
 perform pg_temp.ok(public.final1_review_vendor(target,'rejected')->>'verification_status'='rejected','same decision idempotently reconciles');
 perform pg_temp.denied('select * from public.security_audit_log','42501','admin cannot directly read unrestricted audit table');
end$$;
reset role;
-- Owner verifies only fixtures and side effects; authorization assertions above ran as client roles.
select set_config('request.jwt.claims','{}',true);
select pg_temp.ok((select count(*)=1 from public.security_audit_log where target_id=(select id from final1_people where label='vendor')and action='vendor_rejected'),'vendor decision exactly one transactional audit');
select pg_temp.ok((select count(*)=0 from public.security_audit_log where action='forged'),'no forged events');
select pg_temp.ok((select count(*)=1 from fr32_private.account_events where user_id=(select id from final1_people where label='vendor')and kind='vendor_rejected'),'existing account-email event preserved without sending');
select jsonb_agg(jsonb_build_object('check',name,'result',result))as results from final1_results;
rollback;
