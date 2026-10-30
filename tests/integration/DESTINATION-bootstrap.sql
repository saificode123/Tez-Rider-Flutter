-- Local-only synthetic authorization stand-ins; never apply to hosted TEST.
do $$begin if current_database()not like'tezrider_destination_validation_%'then raise exception'Isolated local database required';end if;end$$;
create schema fr14_private;
create schema fr13_private;
create schema final_delivery_private;
create schema final2_private;
create table public.users(id bigint primary key);
insert into public.users values(159),(999),(160),(161);
create table public.orders(id bigint primary key,user_id bigint,rider_id bigint,order_status text,
 payment_method text,amount numeric,fare numeric,delivery_lat numeric,delivery_lng numeric,
 delivery_address text,destination_source text,destination_confirmed_at timestamptz,
 route_estimated_arrival_at timestamptz,otp_admin_review boolean default false);
insert into public.orders values(3180,159,999,'on_the_way','COD',470,120,33.7,73.1,'old synthetic pin','map_pin','2026-10-29T00:00:00Z',null,false);
insert into public.orders select 3181,160,rider_id,order_status,payment_method,amount,fare,delivery_lat,delivery_lng,delivery_address,destination_source,destination_confirmed_at,null,false from public.orders where id=3180;
grant select,update on public.orders to authenticated;
create table public.riders(userid bigint primary key,is_online boolean);
insert into public.riders values(999,false);
create table fr13_private.sessions(order_id bigint);
create table public.delivery_proof(orderid text);
create table public.cod_cash_events(order_id bigint);
create table final_delivery_private.rider_earnings(order_id bigint,amount numeric);
create table final_delivery_private.pay_snapshots(order_id bigint,quote jsonb);
insert into final_delivery_private.pay_snapshots values(3180,'{"expected_amount":113}');
create table final2_private.photos(order_id bigint,uploaded boolean,kind text);
create table public.payments(orderid text,status text);
insert into public.payments values('3180','pending');
create table public.delivery_otps(order_id bigint,state text,expires_at timestamptz,attempts int,sent_at timestamptz);
create table public.delivery_route_cache(order_id bigint,data jsonb);
insert into public.delivery_route_cache values(3180,'{"synthetic_old_route":true}');
create table fr14_private.attempts(order_id bigint,token text);
insert into fr14_private.attempts values(3180,'synthetic-quota-lease');
create table public.security_audit_log(actor_id bigint,action text,target_type text,target_id bigint);
create table public.products(id bigint,stock_qty int);
insert into public.products values(224,29);
create function public.fr21_actor()returns bigint language sql as $$select nullif(current_setting('test.actor',true),'')::bigint$$;
create function public.fr21_role()returns text language sql as $$select current_setting('test.role',true)$$;
create function public.is_current_user_allowed()returns boolean language sql as $$select coalesce(current_setting('test.allowed',true),'true')='true'$$;
select set_config('test.actor','159',true),set_config('test.role','customer',true);
create function fr14_private.allowed(oid bigint,actor bigint)returns boolean language sql as $$
 select exists(select 1 from public.orders where id=oid and(user_id=actor or rider_id=actor))$$;
