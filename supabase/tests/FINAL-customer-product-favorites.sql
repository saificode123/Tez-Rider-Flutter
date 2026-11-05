begin;
-- Run in a transaction; this regression always rolls back.
create temp table favorite_test_state as
select u.id as owner_id,u.role,a.id as auth_id,s.id as session_id,
 jsonb_build_object('sub',a.id,'role','authenticated','session_id',s.id)::text as claims
from public.users u join auth.users a on a.id=u.auth_user_id
join lateral(select id from auth.sessions where user_id=a.id order by created_at desc limit 1)s on true
where a.raw_user_meta_data->>'fr25_fixture'='true' and u.email in
 ('fr25-customer-a@example.test','fr25-customer-b@example.test','fr25-vendor@example.test');
create temp table favorite_test_product as select p.id from public.products p
where not exists(select 1 from public.favourite f where f.product_id=p.id
 and f.user_id in(select owner_id from favorite_test_state)) order by p.id limit 1;
grant select on favorite_test_state,favorite_test_product to authenticated;
create function pg_temp.favorite_assert(ok boolean,label text)returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'Favorite regression failed: %',label;end if;
end$$;
select pg_temp.favorite_assert((select count(*)=3 from favorite_test_state),'three existing authenticated fixture identities');
select set_config('request.jwt.claims',(select claims from favorite_test_state where role='customer' order by owner_id limit 1),true);
set local role authenticated;
insert into public.favourite(user_id,product_id)
select public.fr21_actor(),id from favorite_test_product;
select pg_temp.favorite_assert((select count(*)=1 from public.favourite f join favorite_test_product p on p.id=f.product_id),'owner reads inserted favorite');
do $$begin
 begin
  insert into public.favourite(user_id,product_id) select public.fr21_actor(),id from favorite_test_product;
  raise exception 'Duplicate accepted';
 exception when unique_violation then null;end;
 begin
  insert into public.favourite(user_id,product_id)
   select owner_id,p.id from favorite_test_state cross join favorite_test_product p where role='customer'and owner_id<>public.fr21_actor();
  raise exception 'Foreign favorite insert accepted';
 exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claims',(select claims from favorite_test_state where role='customer' order by owner_id desc limit 1),true);
set local role authenticated;
select pg_temp.favorite_assert((select count(*)=0 from public.favourite f join favorite_test_product p on p.id=f.product_id),'foreign customer cannot read');
do $$declare affected integer;begin
 delete from public.favourite where product_id=(select id from favorite_test_product);
 get diagnostics affected=row_count;
 perform pg_temp.favorite_assert(affected=0,'foreign customer cannot delete');
end$$;
reset role;
select set_config('request.jwt.claims',(select claims from favorite_test_state where role='vendor'),true);
set local role authenticated;
select pg_temp.favorite_assert((select count(*)=0 from public.favourite),'vendor has no customer favorites');
do $$begin
 begin
  insert into public.favourite(user_id,product_id) select public.fr21_actor(),id from favorite_test_product;
  raise exception 'Vendor insert accepted';
 exception when insufficient_privilege then null;end;
end$$;
reset role;
set local role anon;
do $$begin
 begin perform count(*)from public.favourite;raise exception 'Anonymous read accepted';
 exception when insufficient_privilege then null;end;
end$$;
reset role;
select 'PASS: owner/foreign/vendor/anonymous/duplicate boundaries; no retained test rows' as result;
rollback;
