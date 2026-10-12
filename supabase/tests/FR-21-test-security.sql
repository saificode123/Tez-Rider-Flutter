-- TEST ONLY. Synthetic identities and metadata checks; transaction always rolls back.
begin;
create temporary table fr21_security_results(label text);
create function pg_temp.fr21_check(ok boolean,label text) returns void
language plpgsql security definer set search_path=pg_temp,pg_catalog as $$
begin
  if ok is distinct from true then raise exception 'FAILED: %',label; end if;
  insert into fr21_security_results values(label);
end $$;
do $$ declare n text; begin
  select nspname into n from pg_namespace where oid=pg_my_temp_schema();
  execute format('grant usage on schema %I to authenticated,anon',n);
end $$;
insert into auth.users(id,email,email_confirmed_at,aud,role)
select ('23000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
  'fr21-security-'||i||'@example.test',now(),'authenticated','authenticated'
from generate_series(1,6)i;
insert into public.users(id,name,email,role,verification_status,cnic)
select -23000-i,'Security fixture '||i,'fr21-security-'||i||'@example.test',
  (array['customer','vendor','rider','admin','vendor','rider'])[i],
  'approved','synthetic-private-document' from generate_series(1,6)i;
insert into public.riders(userid) values(-23003),(-23006);

do $$ declare t record; r text; begin
  for t in select c.oid,c.relname,c.relrowsecurity from pg_class c
    join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' loop
    perform pg_temp.fr21_check(t.relrowsecurity,'RLS enabled: '||t.relname);
    foreach r in array array['anon','authenticated'] loop
      perform pg_temp.fr21_check(not has_table_privilege(r,t.oid,'TRUNCATE'),'TRUNCATE denied: '||r||'/'||t.relname);
      perform pg_temp.fr21_check(not has_table_privilege(r,t.oid,'TRIGGER'),'TRIGGER denied: '||r||'/'||t.relname);
      perform pg_temp.fr21_check(not has_table_privilege(r,t.oid,'REFERENCES'),'REFERENCES denied: '||r||'/'||t.relname);
    end loop;
  end loop;
  foreach r in array array['anon','authenticated'] loop
    perform pg_temp.fr21_check(not has_schema_privilege(r,'public','CREATE'),'schema CREATE denied: '||r);
    perform pg_temp.fr21_check(not has_table_privilege(r,'public.admins','SELECT'),'legacy admins denied: '||r);
    perform pg_temp.fr21_check(not has_table_privilege(r,'public.app_settings','SELECT'),'unreviewed settings denied: '||r);
    perform pg_temp.fr21_check(not has_function_privilege(r,'public.assign_available_rider()','EXECUTE'),'broken legacy assignment RPC denied: '||r);
    perform pg_temp.fr21_check(not has_table_privilege(r,'public.notifications','INSERT'),'forged notifications denied: '||r);
  end loop;
end $$;

do $$ declare i integer; begin
  for i in 1..6 loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',
      '23000000-0000-0000-0000-'||lpad(i::text,12,'0'),'role','authenticated',
      'email','fr21-security-'||i||'@example.test')::text,true);
    execute 'set local role authenticated';
    perform pg_temp.fr21_check((select count(*) from public.users where id between -23006 and -23001)
      =case when i=4 then 6 else 1 end,'profile/CNIC visibility role fixture '||i);
    if i<>4 then
      perform pg_temp.fr21_check(not exists(select 1 from public.riders where userid in(-23003,-23006)
        and userid<>-23000-i),'other rider hidden: '||i);
    end if;
    execute 'reset role';
  end loop;
end $$;

insert into public.orders(id,user_id,amount,order_status) values(-23001,-23001,100,'accepted');
insert into public.vendor_orders(id,order_id,vendor_id,sub_total,status)
  values(-23001,-23001,-23002,100,'pending');
insert into public.vendor_orders(id,order_id,vendor_id,sub_total,status)
  values(-23002,-23001,-23005,20,'pending');
select set_config('request.jwt.claims',
  '{"sub":"23000000-0000-0000-0000-000000000002","email":"fr21-security-2@example.test","role":"authenticated"}',true);
set local role authenticated;
select pg_temp.fr21_check((public.fr21_dashboard_stats()->>'total')::numeric=0,'real vendor aggregate without fabricated earnings');
select pg_temp.fr21_check(not exists(select 1 from public.vendor_orders where id=-23002),
  'vendor cannot read another vendor line on the same parent order');
update public.vendor_orders set status='accepted' where id=-23001;
update public.vendor_orders set status='preparing' where id=-23001;
do $$ begin
  begin
    update public.vendor_orders set status='accepted' where id=-23001;
    raise exception 'Vendor reverted an active workflow';
  exception when sqlstate '22023' then null;
  end;
  perform pg_temp.fr21_check((select status='preparing' from public.vendor_orders where id=-23001),
    'invalid vendor workflow transition rejected');
end $$;
reset role;
update public.orders set rider_id=-23003,order_status='on_the_way' where id=-23001;
select set_config('request.jwt.claims',
  '{"sub":"23000000-0000-0000-0000-000000000005","email":"fr21-security-5@example.test","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  begin
    update public.vendor_orders set status='accepted' where id=-23002;
    raise exception 'Assigned parent was reverted';
  exception when sqlstate '22023' then null;
  end;
  perform pg_temp.fr21_check((select status='pending' from public.vendor_orders where id=-23002),
    'vendor cannot regress an assigned parent order');
end $$;
reset role;
select pg_temp.fr21_check(not has_function_privilege('anon','public.fr21_dashboard_stats()','EXECUTE'),
  'anonymous dashboard aggregate denied');

select count(*) as security_assertions_passed from fr21_security_results;
rollback;
