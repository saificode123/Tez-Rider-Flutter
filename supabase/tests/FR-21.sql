-- psql -v ON_ERROR_STOP=1 -v FR21_ISOLATED_TEST=true -f supabase/tests/FR-21.sql "$TEST_DB_URL"
-- Requires the FR-21 migration and the application's existing schema on a clone.
-- Refuse accidental execution without the explicit isolated-project marker.
\if :{?FR21_ISOLATED_TEST}
\if :FR21_ISOLATED_TEST
\else
\quit 3
\endif
\else
\quit 3
\endif

begin;
set local search_path = public, pg_temp;
create temporary table fr21_results(label text);
create function pg_temp.ok(success boolean, label text) returns boolean
language plpgsql security definer set search_path = pg_temp, pg_catalog as $$
begin
  if success is distinct from true then raise exception 'FAILED: %', label; end if;
  insert into fr21_results values(label);
  raise notice 'PASS: %', label;
  return true;
end $$;
create function pg_temp.is(actual anyelement, expected anyelement, label text)
returns boolean language sql security definer set search_path = pg_temp, pg_catalog as $$
  select pg_temp.ok(actual is not distinct from expected, label)
$$;

insert into auth.users(id,email,email_confirmed_at,aud,role)
select ('21000000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,
  'fr21-' || i || '@example.test', now(), 'authenticated','authenticated'
from generate_series(1,6) i;
insert into public.users(id,name,email,role,verification_status) values
(-21001,'FR21 Customer','fr21-1@example.test','customer','approved'),
(-21002,'FR21 Vendor','fr21-2@example.test','vendor','approved'),
(-21003,'FR21 Rider','fr21-3@example.test','rider','approved'),
(-21004,'FR21 Admin','fr21-4@example.test','admin','approved'),
(-21005,'FR21 Other Vendor','fr21-5@example.test','vendor','approved'),
(-21006,'FR21 Other Rider','fr21-6@example.test','rider','approved');
insert into public.riders(userid,is_online,is_verified,last_seen,latitude,longitude)
values (-21003,false,true,now(),31.52,74.35),(-21006,false,true,now(),31.53,74.36);
-- Transactional test fixture coordinates only; these DDL changes roll back.
alter table public.vendors add column if not exists latitude numeric;
alter table public.vendors add column if not exists longitude numeric;
insert into public.vendors(user_id,store_name,latitude,longitude)
values(-21002,'FR21 Test Store',31.52,74.35);
insert into public.orders(id,user_id,amount,order_status) values
(-21001,-21001,100,'accepted'),(-21002,-21001,100,'accepted');
insert into public.vendor_orders(id,order_id,vendor_id,status) values
(-21001,-21001,-21002,'accepted'),(-21002,-21002,-21002,'accepted');

-- SQLSTATE checks, rather than accepting arbitrary backend failures.
create function pg_temp.denied(statement text, code text default '42501')
returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then return sqlstate = code;
end $$;
grant usage on schema pg_temp to authenticated, anon;
grant execute on function pg_temp.denied(text,text) to authenticated, anon;

do $$ declare i int; label text; begin
  for i in 1..6 loop
    label := (array['customer','vendor','rider','admin','other vendor','other rider'])[i];
    perform set_config('request.jwt.claims', jsonb_build_object('sub',
      '21000000-0000-0000-0000-' || lpad(i::text,12,'0'), 'role','authenticated',
      'email','fr21-' || i || '@example.test')::text, true);
    execute 'set local role authenticated';
    if i not in (3,6) then
      perform pg_temp.ok(pg_temp.denied('select public.fr21_begin_presence()'),label || ' cannot begin rider presence');
      perform pg_temp.ok(pg_temp.denied('select public.fr21_set_presence(true,1,1)'),label || ' cannot heartbeat');
    end if;
    if i <> 2 then
      perform pg_temp.ok(pg_temp.denied('select public.fr21_ready_and_assign(-21001)'),label || ' cannot assign vendor order');
    end if;
    perform pg_temp.ok(pg_temp.denied('update public.riders set is_verified=true where userid=-21003'),
      label || ' cannot directly change rider verification');
    perform pg_temp.ok(pg_temp.denied('update public.riders set userid=-21001 where userid=-21003'),
      label || ' cannot change rider ownership');
    execute 'reset role';
  end loop;
end $$;

set local role anon;
select pg_temp.ok(pg_temp.denied('select public.fr21_begin_presence()'),'anonymous begin denied');
select pg_temp.ok(pg_temp.denied('select public.fr21_set_presence(true,1,1)'),'anonymous heartbeat denied');
select pg_temp.ok(pg_temp.denied('select public.fr21_ready_and_assign(-21001)'),'anonymous assignment denied');
reset role;

select set_config('request.jwt.claims','{"sub":"21000000-0000-0000-0000-000000000003","role":"authenticated","email":"fr21-3@example.test"}',true);
set local role authenticated;
create temporary table fr21_session as select public.fr21_begin_presence() result;
select pg_temp.ok((select (result->>'is_online')::boolean = false from fr21_session),'offline restored');
select pg_temp.ok((public.fr21_set_presence(true,(select (result->>'epoch')::bigint from fr21_session),1)->>'is_online')::boolean,'rider online confirmed');
create temporary table fr21_first_write as select last_seen from public.riders where userid=-21003;
select public.fr21_set_presence(true,(select (result->>'epoch')::bigint from fr21_session),1);
select pg_temp.is((select last_seen from public.riders where userid=-21003),
  (select last_seen from fr21_first_write),'duplicate heartbeat does not renew lease');
select public.fr21_set_presence(false,(select (result->>'epoch')::bigint from fr21_session),3);
select pg_temp.ok(pg_temp.denied(format('select public.fr21_set_presence(true,%s,2)',
  (select (result->>'epoch')::bigint from fr21_session)),'40001'),'late online request loses to offline');
select pg_temp.ok(pg_temp.denied('select public.fr21_set_presence(null,1,4)','22023'),'null input denied');
select pg_temp.ok(pg_temp.denied('select public.fr21_set_presence(true,1,0)','22023'),'invalid sequence denied');
update public.riders set is_online=true,last_seen='2099-01-01' where userid=-21003;
select pg_temp.ok((select last_seen <= clock_timestamp() from public.riders where userid=-21003),'client cannot forge future last_seen');
with affected as (update public.riders set is_online=true where userid=-21006 returning userid)
select pg_temp.is((select count(*) from affected),0::bigint,'rider cannot update other rider presence');
select pg_temp.ok(pg_temp.denied('update public.users set role=''admin'' where id=-21003'),'role escalation denied');
reset role;

-- Server age/verification controls; stale and unverified candidates excluded.
update public.riders set last_seen=now()-interval '121 seconds' where userid=-21003;
select set_config('request.jwt.claims','{"sub":"21000000-0000-0000-0000-000000000002","role":"authenticated","email":"fr21-2@example.test"}',true);
set local role authenticated;
select pg_temp.ok((public.fr21_ready_and_assign(-21001)->>'rider_id') is null,'stale rider excluded');
reset role;
update public.riders set last_seen=now(),is_verified=false where userid=-21003;
set local role authenticated;
select pg_temp.ok((public.fr21_ready_and_assign(-21001)->>'rider_id') is null,'unverified rider excluded');
reset role;
update public.riders set last_seen=now(),is_verified=true,is_online=true where userid=-21003;
set local role authenticated;
select pg_temp.is((public.fr21_ready_and_assign(-21001)->>'rider_id')::bigint,-21003::bigint,'fresh verified online rider assigned');
select pg_temp.is((public.fr21_ready_and_assign(-21001)->>'rider_id')::bigint,-21003::bigint,'duplicate assignment returns same rider');
select pg_temp.ok((public.fr21_ready_and_assign(-21002)->>'rider_id') is null,'busy rider excluded from another order');
select pg_temp.ok(pg_temp.denied('update public.riders set is_available=true where userid=-21003'),'vendor cannot bypass rider reservation');
reset role;
select pg_temp.is((select count(*) from public.rider_assignments where orderid=-21001),1::bigint,'exactly one assignment');
select pg_temp.is((select count(*) from public.notifications where user_id=-21003),1::bigint,'exactly one assignment notification');

select set_config('request.jwt.claims','{"sub":"21000000-0000-0000-0000-000000000003","role":"authenticated","email":"fr21-3@example.test"}',true);
set local role authenticated;
select public.fr21_begin_presence();
select pg_temp.ok(pg_temp.denied(format('select public.fr21_set_presence(true,%s,4)',
  (select (result->>'epoch')::bigint from fr21_session)),'40001'),'previous app epoch rejected');
reset role;
update public.riders set last_seen=now()-interval '121 seconds',is_online=true where userid=-21003;
set local role authenticated;
select pg_temp.ok(not (public.fr21_begin_presence()->>'is_online')::boolean,'crashed app restores offline');
reset role;
select count(*) as assertions_passed from fr21_results;
rollback;

-- Actual concurrent transaction tests use committed fixture orders from the
-- load fixture file (never production). Supply the following optional psql vars:
-- FR21_RACE_DSN, FR21_RACE_VENDOR_UUID, FR21_RACE_ORDER_A/B, FR21_RACE_RIDER_ID.
\if :{?FR21_RACE_DSN}
create extension if not exists dblink with schema extensions;
select extensions.dblink_connect('fr21_a', :'FR21_RACE_DSN');
select extensions.dblink_connect('fr21_b', :'FR21_RACE_DSN');
-- Hold the first transaction open after assignment. A competing order must skip
-- its locked rider rather than reserve the same rider a second time.
select extensions.dblink_exec('fr21_a','begin');
select extensions.dblink_exec('fr21_a',format('set request.jwt.claims=%L',jsonb_build_object('sub',:'FR21_RACE_VENDOR_UUID','role','authenticated')::text));
select extensions.dblink_exec('fr21_a','set role authenticated');
select * from extensions.dblink('fr21_a',format('select public.fr21_ready_and_assign(%s)',:'FR21_RACE_ORDER_A')) as t(result jsonb);
select extensions.dblink_exec('fr21_b','begin');
select extensions.dblink_exec('fr21_b',format('set request.jwt.claims=%L',jsonb_build_object('sub',:'FR21_RACE_VENDOR_UUID','role','authenticated')::text));
select extensions.dblink_exec('fr21_b','set role authenticated');
create temporary table fr21_race_result as
select * from extensions.dblink('fr21_b',format('select public.fr21_ready_and_assign(%s)',:'FR21_RACE_ORDER_B')) as t(result jsonb);
select extensions.dblink_exec('fr21_b','commit');
-- Duplicate request to the same order waits on the parent order lock.
select extensions.dblink_send_query('fr21_b',format('select public.fr21_ready_and_assign(%s)',:'FR21_RACE_ORDER_A'));
select pg_sleep(0.1);
select 1 / case when extensions.dblink_is_busy('fr21_b')=1 then 1
  else 0 end as duplicate_waits_for_order_lock;
select extensions.dblink_exec('fr21_a','commit');
select * from extensions.dblink_get_result('fr21_b') as t(result jsonb);
select 1 / case when coalesce((select (result->>'rider_id')::bigint from fr21_race_result),0)
  <> :FR21_RACE_RIDER_ID then 1 else 0 end as rider_not_double_reserved;
select 1 / case when (select count(*) from public.rider_assignments where orderid=:FR21_RACE_ORDER_A)=1
  then 1 else 0 end as single_assignment;
select extensions.dblink_disconnect('fr21_a');
select extensions.dblink_disconnect('fr21_b');
\else
\echo 'Concurrent dblink cases NOT EXECUTED: race fixture variables not provided.'
\endif
