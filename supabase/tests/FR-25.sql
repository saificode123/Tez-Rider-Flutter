-- Database rule tests only. Real file validation/access/expiry is verified by
-- tests/integration/FR-25-hosted.py against the Storage API, not these metadata fixtures.
begin;
set local statement_timeout='60s';
create temporary table fr25_results(test text,result text);
create function pg_temp.assert(p_ok boolean,p_label text) returns void language plpgsql as $$ begin
 if p_ok is not true then raise exception 'FR25 assertion failed: %',p_label; end if;
 insert into fr25_results values(p_label,'PASS');
end $$;
create function pg_temp.denied(p_sql text,p_label text) returns void language plpgsql as $$ begin
 begin execute p_sql; exception when insufficient_privilege or invalid_parameter_value or unique_violation or sqlstate 'PT422' or sqlstate 'PT409' then
  insert into fr25_results values(p_label,'PASS');return;end;
 raise exception 'FR25 forbidden operation succeeded: %',p_label;
end $$;
-- Transaction-scoped synthetic identities, never existing personal accounts.
do $$ declare a uuid; other uuid; admin uuid; rider uuid; vendor uuid; actor bigint; o bigint; late_order bigint; early_order bigint; boundary bigint; missing_time bigint; rid uuid:=gen_random_uuid();p text; begin
 a:=gen_random_uuid();other:=gen_random_uuid();admin:=gen_random_uuid();rider:=gen_random_uuid();vendor:=gen_random_uuid();
 insert into auth.users(id,email,email_confirmed_at,role,aud) values
 (a,'fr25-sql-'||a||'@example.test',now(),'authenticated','authenticated'),
 (other,'fr25-sql-'||other||'@example.test',now(),'authenticated','authenticated'),
 (admin,'fr25-sql-'||admin||'@example.test',now(),'authenticated','authenticated'),
 (rider,'fr25-sql-'||rider||'@example.test',now(),'authenticated','authenticated'),
 (vendor,'fr25-sql-'||vendor||'@example.test',now(),'authenticated','authenticated');
 insert into public.users(email,name,role,verification_status) values
 ('fr25-sql-'||a||'@example.test','FR25 SQL synthetic','customer','pending'),
 ('fr25-sql-'||other||'@example.test','FR25 SQL synthetic','customer','pending'),
 ('fr25-sql-'||admin||'@example.test','FR25 SQL synthetic','admin','approved'),
 ('fr25-sql-'||rider||'@example.test','FR25 SQL synthetic','rider','pending'),
 ('fr25-sql-'||vendor||'@example.test','FR25 SQL synthetic','vendor','pending');
 select id into actor from public.users where email='fr25-sql-'||a||'@example.test';
 insert into public.orders(user_id,amount,order_status) values(actor,1,'delivered') returning id into o;
 insert into public.orders(user_id,amount,order_status) values(actor,1,'delivered') returning id into late_order;
 insert into public.orders(user_id,amount,order_status) values(actor,1,'placed') returning id into early_order;
 insert into public.orders(user_id,amount,order_status) values(actor,1,'delivered') returning id into boundary;
 insert into public.orders(user_id,amount,order_status) values(actor,1,'delivered') returning id into missing_time;
 -- Preserve the exact deployed trigger definition. A transaction-local body
 -- permits only this owner's fixture timestamp updates; it is restored before
 -- any authorization test and the entire transaction is rolled back. Other
 -- sessions cannot observe the uncommitted replacement.
 create temporary table fr25_original_trigger(def text);
 insert into fr25_original_trigger select pg_get_functiondef('public.fr25_delivery_timestamp()'::regprocedure);
 execute 'create or replace function public.fr25_delivery_timestamp() returns trigger language plpgsql set search_path='''' as $body$ begin return new; end $body$';
 update public.orders set delivered_at=clock_timestamp()-interval '24 hours 1 second' where id=late_order;
 update public.orders set delivered_at=clock_timestamp()-interval '24 hours'+interval '5 seconds' where id=boundary;
 update public.orders set delivered_at=null where id=missing_time;
 execute (select def from fr25_original_trigger);
 perform set_config('fr25.test_auth',a::text,true);perform set_config('fr25.test_other',other::text,true);
 perform set_config('fr25.test_admin',admin::text,true);perform set_config('fr25.test_rider',rider::text,true);perform set_config('fr25.test_vendor',vendor::text,true);
 perform set_config('fr25.test_actor',actor::text,true);perform set_config('fr25.test_order',o::text,true);
 perform set_config('fr25.test_late',late_order::text,true);perform set_config('fr25.test_early',early_order::text,true);
 perform set_config('fr25.test_boundary',boundary::text,true);perform set_config('fr25.test_missing',missing_time::text,true);perform set_config('fr25.test_request',rid::text,true);
end $$;
grant all on fr25_results to authenticated,anon;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fr25.test_auth'),'role','authenticated')::text,true);
select public.fr25_prepare(current_setting('fr25.test_request')::uuid,current_setting('fr25.test_order')::bigint);
select pg_temp.denied(format('select public.fr25_prepare(gen_random_uuid(),%s)',current_setting('fr25.test_late')),'expired 24-hour order rejected');
select pg_temp.denied(format('select public.fr25_prepare(gen_random_uuid(),%s)',current_setting('fr25.test_early')),'undelivered order rejected');
select pg_temp.denied(format('select public.fr25_prepare(gen_random_uuid(),%s)',current_setting('fr25.test_missing')),'unknown delivery timestamp rejected');
select pg_temp.assert((public.fr25_prepare(gen_random_uuid(),current_setting('fr25.test_boundary')::bigint)->>'state')='draft','just inside 24-hour boundary permitted');
select pg_temp.denied(format('insert into public.orders(user_id,amount,order_status)values(%s,1,''delivered'')',current_setting('fr25.test_actor')),'customer cannot forge delivery');
select pg_temp.denied('insert into public.disputes(type)values(''Forgery'')','direct customer INSERT denied');
select pg_temp.denied('select public.fr25_finish_upload(gen_random_uuid(),gen_random_uuid(),repeat(''a'',64),''image/png'',100)','customer cannot attest to validated evidence');
reset role;
do $$ declare p text:=current_setting('fr25.test_auth')||'/'||current_setting('fr25.test_request')||'/'||repeat('a',64)||'.png'; begin
 insert into storage.objects(bucket_id,name,metadata) values('dispute-evidence',p,'{"mimetype":"image/png","size":100}'::jsonb);
 perform public.fr25_finish_upload(current_setting('fr25.test_auth')::uuid,current_setting('fr25.test_request')::uuid,repeat('a',64),'image/png',100);
 perform set_config('fr25.test_path',p,true);
end $$;
set local role authenticated;
do $$ declare args text:=format('%s,''Other'',''Valid'',array[%L],%L::uuid',current_setting('fr25.test_order'),current_setting('fr25.test_path'),current_setting('fr25.test_request')); result jsonb; begin
 perform pg_temp.denied(format('select public.create_dispute(%s,''INVALID'',''Valid'',array[%L],%L::uuid)',current_setting('fr25.test_order'),current_setting('fr25.test_path'),current_setting('fr25.test_request')),'invalid reason rejected');
 perform pg_temp.denied(format('select public.create_dispute(%s,''Other'','''',array[%L],%L::uuid)',current_setting('fr25.test_order'),current_setting('fr25.test_path'),current_setting('fr25.test_request')),'empty description rejected');
 perform pg_temp.denied(format('select public.create_dispute(%s,''Other'',repeat(''x'',2001),array[%L],%L::uuid)',current_setting('fr25.test_order'),current_setting('fr25.test_path'),current_setting('fr25.test_request')),'oversized description rejected');
 perform pg_temp.denied(format('select public.create_dispute(%s,''Other'',''Valid'',array[]::text[],%L::uuid)',current_setting('fr25.test_order'),current_setting('fr25.test_request')),'zero images rejected');
 perform pg_temp.denied(format('select public.create_dispute(%s,''Other'',''Valid'',array[''a'',''b'',''c'',''d''],%L::uuid)',current_setting('fr25.test_order'),current_setting('fr25.test_request')),'four images rejected');
 perform pg_temp.denied(format('select public.create_dispute(%s,''Other'',''Valid'',array[''missing''],%L::uuid)',current_setting('fr25.test_order'),current_setting('fr25.test_request')),'nonexistent evidence rejected');
 execute 'select public.create_dispute('||args||')' into result;
 perform pg_temp.assert(result->>'status'='Open','owner creates open dispute');perform set_config('fr25.test_dispute',result->>'id',true);
 perform pg_temp.assert(public.create_dispute(current_setting('fr25.test_order')::bigint,'Other','Valid',array[current_setting('fr25.test_path')],current_setting('fr25.test_request')::uuid)=result,'same successful request is idempotent');
 perform pg_temp.denied(format('select public.fr25_prepare(gen_random_uuid(),%s)',current_setting('fr25.test_order')),'new UUID cannot bypass open order');
 perform pg_temp.denied(format('update public.disputes set status=''Resolved'' where id=%s',current_setting('fr25.test_dispute')),'customer UPDATE denied');
 perform pg_temp.denied(format('delete from public.disputes where id=%s',current_setting('fr25.test_dispute')),'customer DELETE denied');
 perform pg_temp.assert(cardinality(public.fr25_abandon(current_setting('fr25.test_request')::uuid))=0,'submitted cleanup returns no paths');
end $$;
do $$ declare label text; begin
 foreach label in array array['other','vendor','rider'] loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fr25.test_'||label),'role','authenticated')::text,true);
  perform pg_temp.assert(not exists(select 1 from public.disputes where id=current_setting('fr25.test_dispute')::bigint),label||' RLS read denied');
  perform pg_temp.denied(format('select public.fr25_detail(%s)',current_setting('fr25.test_dispute')),label||' detail denied');
  perform pg_temp.denied(format('select public.fr25_evidence_authority(%s,1)',current_setting('fr25.test_dispute')),label||' evidence authority denied');
  perform pg_temp.denied(format('select public.fr25_prepare(gen_random_uuid(),%s)',current_setting('fr25.test_order')),label||' prepare denied');
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fr25.test_admin'),'role','authenticated')::text,true);
 perform pg_temp.assert(exists(select 1 from public.disputes where id=current_setting('fr25.test_dispute')::bigint),'admin authorized read');
 perform pg_temp.denied(format('select public.fr25_prepare(gen_random_uuid(),%s)',current_setting('fr25.test_order')),'admin cannot create customer draft');
 perform pg_temp.denied(format('update public.disputes set status=''Resolved'' where id=%s',current_setting('fr25.test_dispute')),'FR26 admin mutations not implemented');
end $$;
reset role;
select pg_temp.assert((select count(*) from public.disputes where request_id=current_setting('fr25.test_request')::uuid)=1,'one dispute persisted for duplicate retry');
select pg_temp.assert((select count(*) from public.notifications where dispute_id=current_setting('fr25.test_dispute')::bigint)=1,'one notification for a confirmed approved admin');
select pg_temp.assert(not exists(select 1 from public.notifications where dispute_id=current_setting('fr25.test_dispute')::bigint group by user_id having count(*)>1),'notification retries deduplicated');
set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select pg_temp.denied('select public.fr25_prepare(gen_random_uuid(),1)','anonymous RPC execution denied');
select pg_temp.denied('select id from public.disputes','anonymous table grant denied');
reset role;
-- Historical states are simulated by the owner only, within this rollback.
-- No FR-26 client mutation or resolution/refund workflow is enabled.
update public.disputes set status='Closed' where id=current_setting('fr25.test_dispute')::bigint;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fr25.test_auth'),'role','authenticated')::text,true);
select set_config('fr25.second_request',gen_random_uuid()::text,true);
select pg_temp.assert((public.fr25_prepare(current_setting('fr25.second_request')::uuid,current_setting('fr25.test_order')::bigint)->>'state')='draft','historical closed dispute allows a new eligible request');
select pg_temp.assert((public.create_dispute(current_setting('fr25.test_order')::bigint,'Other','Valid',array[current_setting('fr25.test_path')],current_setting('fr25.test_request')::uuid)->>'id')=current_setting('fr25.test_dispute'),'original retry returns historical dispute without a new notification');
select pg_temp.denied(format('select public.create_dispute(%s,''Other'',''New'',array[%L],%L::uuid)',current_setting('fr25.test_order'),current_setting('fr25.test_path'),current_setting('fr25.second_request')),'old draft evidence cannot be attached to new dispute');
reset role;
select test,result from fr25_results order by test;
rollback;
