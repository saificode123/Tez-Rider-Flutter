-- Synthetic LOCAL isolated database only. Never run this bootstrap on Supabase.
do $$begin if current_database()not like 'tezrider_map_ui_validation_%'then raise exception 'Owned local test database required';end if;end$$;
create schema extensions;
create extension postgis with schema extensions;
create extension pgcrypto with schema extensions;
create schema fr14_private;
revoke all on schema fr14_private from public,anon,authenticated,service_role;
create table public.users(id bigint primary key,role text,verification_status text,is_blocked boolean default false);
create table public.orders(id bigint primary key,user_id bigint,rider_id bigint,order_status text);
create table public.riders(userid bigint primary key,is_online boolean,last_seen timestamptz,location_updated_at timestamptz,
 latitude double precision,longitude double precision,assignment_location extensions.geography);
create table public.rider_assignments(id bigint primary key,orderid bigint,riderid bigint,status text);
create table public.vendors(user_id bigint primary key,latitude double precision,longitude double precision);
create table public.vendor_orders(id bigint primary key,order_id bigint,vendor_id bigint);
create table fr14_private.configuration(singleton boolean primary key default true,daily_limit int default 2800,
 minute_limit int default 120,second_limit int default 4,concurrent_limit int default 4,
 refresh_seconds int default 240,minimum_seconds int default 60,deviation_meters int default 150);
create table fr14_private.attempts(order_id bigint primary key,token uuid,lease_until timestamptz,last_attempt_at timestamptz,
 origin_lat double precision,origin_lng double precision,destination_lat double precision,destination_lng double precision);
create table fr14_private.quota_reservations(token uuid primary key,units int,reserved_at timestamptz,settled boolean default false);
create table fr14_private.user_limits(actor bigint primary key,window_at timestamptz,requests int);
create function fr14_private.cleanup()returns void language plpgsql as $$begin end$$;
-- Test stand-ins ONLY: the deployed migration uses the existing live Auth functions.
create function public.fr21_actor()returns bigint language sql as $$select nullif(current_setting('map.actor',true),'')::bigint$$;
create function public.is_current_user_allowed()returns boolean language sql as $$select coalesce(current_setting('map.allowed',true),'true')<>'false'$$;
insert into public.users values(1,'rider','approved',false),(2,'rider','approved',false),(3,'customer','approved',false),(4,'admin','approved',false);
insert into public.orders values(1,3,1,'ready');
insert into public.rider_assignments values(10,1,1,'Pending');
insert into public.riders values(1,true,clock_timestamp(),clock_timestamp(),0,0,
 extensions.st_setsrid(extensions.st_makepoint(0,0),4326)::extensions.geography);
insert into public.vendors values(7,.003,.003);
insert into public.vendor_orders values(11,1,7);
insert into fr14_private.configuration default values;
-- Sentinels: pickup routing must never change delivery geometry or pay snapshots.
create table public.delivery_route_cache(order_id bigint,data jsonb);
create table public.map_pay_sentinel(order_id bigint,amount numeric);
insert into public.delivery_route_cache values(1,'{"delivery":"retained"}');
insert into public.map_pay_sentinel values(1,113);
