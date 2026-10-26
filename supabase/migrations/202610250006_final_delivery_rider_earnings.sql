-- Owner-approved policy in docs/POLICY-DECISIONS.md. Records only, no payout.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create schema if not exists final_delivery_private;
revoke all on schema final_delivery_private from public,anon,authenticated;
create table final_delivery_private.pay_settings(
 id integer primary key check(id=1),revision bigint not null default 1 check(revision>0),
 base_amount numeric not null default 60 check(base_amount>=0 and base_amount<'Infinity'::numeric),
 per_km_rate numeric not null default 20 check(per_km_rate>=0 and per_km_rate<'Infinity'::numeric),
 minimum_amount numeric not null default 80 check(minimum_amount>=0 and minimum_amount<'Infinity'::numeric),
 per_minute_rate numeric not null default 0 check(per_minute_rate=0),
 peak_amount numeric not null default 0 check(peak_amount=0),peak_enabled boolean not null default false check(not peak_enabled),
 weather_amount numeric not null default 0 check(weather_amount=0),weather_enabled boolean not null default false check(not weather_enabled),
 bonus_amount numeric not null default 0 check(bonus_amount=0),bonus_enabled boolean not null default false check(not bonus_enabled),
 tip_amount numeric not null default 0 check(tip_amount=0),tip_enabled boolean not null default false check(not tip_enabled),
 cancellation_base_enabled boolean not null default true,
 currency text not null default 'PKR' check(currency='PKR'),
 updated_at timestamptz not null default clock_timestamp()
);
insert into final_delivery_private.pay_settings(id)values(1);
create table final_delivery_private.pay_snapshots(
 order_id bigint primary key references public.orders(id),
 assignment_id bigint not null references public.rider_assignments(id),
 rider_id bigint not null references public.users(id),
 vendor_order_id bigint not null references public.vendor_orders(id),
 started_at timestamptz not null default clock_timestamp(),
 quote jsonb not null
);
create table final_delivery_private.rider_earnings(
 id bigint generated always as identity primary key,
 order_id bigint not null unique references public.orders(id),
 assignment_id bigint not null references public.rider_assignments(id),
 rider_id bigint not null references public.users(id),
 earned_at timestamptz not null default clock_timestamp(),
 kind text not null check(kind in('DELIVERED','CANCEL_AFTER_PICKUP')),
 amount numeric not null check(amount>=0 and amount<'Infinity'::numeric),
 calculation jsonb not null
);
create index final_delivery_earnings_rider on final_delivery_private.rider_earnings(rider_id,id desc);
create table final_delivery_private.earning_reviews(
 earning_id bigint not null references final_delivery_private.rider_earnings(id),
 reason text not null check(reason in('DISPUTE_RESOLVED','REFUND_RECORDED')),
 source_id bigint not null,
 created_at timestamptz not null default clock_timestamp(),
 primary key(earning_id,reason,source_id)
);
create table final_delivery_private.pickup_cancellations(
 request_id uuid primary key,actor_id bigint not null references public.users(id),
 order_id bigint not null unique references public.orders(id),reason text not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table final_delivery_private.pay_settings enable row level security;
alter table final_delivery_private.pay_snapshots enable row level security;
alter table final_delivery_private.rider_earnings enable row level security;
alter table final_delivery_private.earning_reviews enable row level security;
alter table final_delivery_private.pickup_cancellations enable row level security;
revoke all on final_delivery_private.pay_settings,final_delivery_private.pay_snapshots,
 final_delivery_private.rider_earnings,final_delivery_private.earning_reviews,final_delivery_private.pickup_cancellations from public,anon,authenticated,service_role;

create function final_delivery_private.pay_immutable()returns trigger
language plpgsql set search_path=''as $$begin
 raise exception 'Earning calculations and review evidence are append-only'using errcode='42501';end$$;
create trigger pay_snapshot_immutable before update or delete on final_delivery_private.pay_snapshots
 for each row execute function final_delivery_private.pay_immutable();
create trigger pay_earning_immutable before update or delete on final_delivery_private.rider_earnings
 for each row execute function final_delivery_private.pay_immutable();
create trigger pay_review_immutable before update or delete on final_delivery_private.earning_reviews
 for each row execute function final_delivery_private.pay_immutable();
create trigger pay_cancel_immutable before update or delete on final_delivery_private.pickup_cancellations
 for each row execute function final_delivery_private.pay_immutable();

create function final_delivery_private.calculate_quote(oid bigint,rid bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare o public.orders;s final_delivery_private.pay_settings;v public.vendors;vo bigint;
 c public.delivery_route_cache;km numeric;method text;stamp timestamptz:=clock_timestamp();
begin
 select *into o from public.orders where id=oid;
 select *into s from final_delivery_private.pay_settings where id=1;
 -- Same canonical first pickup used by existing assignment; one task is not split.
 select p.id into vo from public.vendor_orders p where p.order_id=oid order by p.id limit 1;
 select x.*into v from public.vendor_orders p join public.vendors x on x.user_id=p.vendor_id where p.id=vo;
 if o.id is null or vo is null or v.latitude is null or v.longitude is null
  or v.latitude not between -90 and 90 or v.longitude not between -180 and 180
  or o.delivery_lat is null or o.delivery_lng is null or o.delivery_lat not between -90 and 90
  or o.delivery_lng not between -180 and 180 or o.destination_confirmed_at is null then
  return jsonb_build_object('code','DISTANCE_UNAVAILABLE','order_id',oid,'reason',case
   when o.id is null then'ORDER_REQUIRED'when vo is null then'PICKUP_ORDER_REQUIRED'
   when v.latitude is null or v.longitude is null then'PICKUP_LOCATION_REQUIRED'
   when o.destination_confirmed_at is null then'DESTINATION_CONFIRMATION_REQUIRED'
   else'VALID_COORDINATES_REQUIRED'end);end if;
 select *into c from public.delivery_route_cache where order_id=oid and expires_at>stamp
  and destination_lat=o.delivery_lat and destination_lng=o.delivery_lng;
 if c.order_id is not null and c.origin_lat is not null and c.origin_lng is not null
  and extensions.st_dwithin(
   extensions.st_setsrid(extensions.st_makepoint(c.origin_lng,c.origin_lat),4326)::extensions.geography,
   extensions.st_setsrid(extensions.st_makepoint(v.longitude::double precision,v.latitude::double precision),4326)::extensions.geography,100)
  and c.data->>'source'='geoapify'and coalesce((c.data->>'isApproximate')::boolean,true)=false then
  km:=(c.data->>'distanceMeters')::numeric/1000;method:='route';
 else
  km:=extensions.st_distance(
   extensions.st_setsrid(extensions.st_makepoint(v.longitude::double precision,v.latitude::double precision),4326)::extensions.geography,
   extensions.st_setsrid(extensions.st_makepoint(o.delivery_lng,o.delivery_lat),4326)::extensions.geography)::numeric/1000;
  method:='straight_line';
 end if;
 return jsonb_build_object('code','OK','order_id',oid,'rider_id',rid,'vendor_order_id',vo,
  'distance_km',km,'distance_method',method,'base_amount',s.base_amount,'per_km_rate',s.per_km_rate,
  'distance_amount',s.per_km_rate*km,'minimum_amount',s.minimum_amount,
  'expected_amount',round(greatest(s.minimum_amount,s.base_amount+s.per_km_rate*km)),
  'policy_revision',s.revision,'currency',s.currency,'frozen',false,'earnings_only',true,
  'per_minute_rate',s.per_minute_rate,'peak_amount',s.peak_amount,'peak_enabled',s.peak_enabled,
  'weather_amount',s.weather_amount,'weather_enabled',s.weather_enabled,
  'bonus_amount',s.bonus_amount,'bonus_enabled',s.bonus_enabled,'tip_amount',s.tip_amount,'tip_enabled',s.tip_enabled);
end$$;

create function public.final_delivery_rider_quote(p_order_id bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();o public.orders;a public.rider_assignments;s final_delivery_private.pay_snapshots;begin
 if actor is null or not public.is_current_user_allowed()or not exists(select 1 from public.users
  where id=actor and verification_status='approved'and not is_blocked and role in('admin','rider'))then
  raise exception 'Approved assigned Rider required'using errcode='42501';end if;
 if p_order_id is null or p_order_id<1 then raise exception 'Invalid order'using errcode='22023';end if;
 select *into o from public.orders where id=p_order_id;
 select *into a from public.rider_assignments where orderid=p_order_id and status in('Pending','Accepted','Delivered')
  and(public.fr21_role()='admin'or riderid=actor)order by id desc limit 1;
 if a.id is null or o.id is null then raise exception 'Assigned delivery required'using errcode='42501';end if;
 select *into s from final_delivery_private.pay_snapshots where order_id=p_order_id and rider_id=a.riderid;
 if s.order_id is not null then return s.quote;end if;
 if o.order_status in('delivered','cancelled')then return jsonb_build_object('code','HISTORICAL_RATE_UNAVAILABLE','order_id',p_order_id);end if;
 return final_delivery_private.calculate_quote(p_order_id,a.riderid);
end$$;

create function final_delivery_private.freeze_delivery_pay()returns trigger
language plpgsql security definer set search_path=''as $$
declare a public.rider_assignments;q jsonb;begin
 if new.order_status='on_the_way'and old.order_status is distinct from new.order_status then
  select *into a from public.rider_assignments where orderid=new.id and riderid=new.rider_id and status='Accepted'order by id desc limit 1;
  if a.id is null then raise exception 'Accepted Rider task required'using errcode='23514';end if;
  q:=final_delivery_private.calculate_quote(new.id,new.rider_id);
  if q->>'code'<>'OK'then raise exception 'Confirmed pickup and destination locations required for earning calculation'using errcode='23514';end if;
  q:=q||jsonb_build_object('frozen',true,'started_at',clock_timestamp());
  insert into final_delivery_private.pay_snapshots(order_id,assignment_id,rider_id,vendor_order_id,quote)
   values(new.id,a.id,a.riderid,(q->>'vendor_order_id')::bigint,q)on conflict(order_id)do nothing;
 end if;return new;end$$;
create trigger final_delivery_freeze_pay after update of order_status on public.orders
 for each row execute function final_delivery_private.freeze_delivery_pay();

create function final_delivery_private.credit_delivered_pay()returns trigger
language plpgsql security definer set search_path=''as $$
declare s final_delivery_private.pay_snapshots;eid bigint;begin
 if new.order_status='delivered'and old.order_status is distinct from new.order_status then
  select *into s from final_delivery_private.pay_snapshots where order_id=new.id and rider_id=new.rider_id;
  if s.order_id is null then return new;end if; -- No fabricated historical start/rate.
  if not exists(select 1 from public.orders o join public.users u on u.id=o.rider_id
   join public.delivery_proof p on p.orderid=o.id::text and p.riderid=u.auth_user_id::text
   where o.id=new.id and o.order_status='delivered'and o.delivered_at is not null
    and p.proofid='fr21-otp-'||o.id and p.otpconfirmed and p.is_verified and p.verified_at is not null)
   or not exists(select 1 from public.delivery_otps d where d.order_id=new.id and d.rider_id=s.rider_id and d.state='USED')then
   raise exception 'Verified OTP receipt required before Rider earnings'using errcode='23514';end if;
  insert into final_delivery_private.rider_earnings(order_id,assignment_id,rider_id,kind,amount,calculation)
   values(new.id,s.assignment_id,s.rider_id,'DELIVERED',(s.quote->>'expected_amount')::numeric,s.quote)
   on conflict(order_id)do nothing returning id into eid;
  if eid is not null then insert into public.security_audit_log(actor_id,action,target_type,target_id)
   values(s.rider_id,'rider_earning_recorded','orders',new.id);end if;
 end if;return new;end$$;
-- OTP transaction writes orders, then receipt, then USED challenge. Verify all at commit.
create constraint trigger final_delivery_credit_pay after update on public.orders
 deferrable initially deferred for each row execute function final_delivery_private.credit_delivered_pay();

create function final_delivery_private.credit_cancelled_pay()returns trigger
language plpgsql security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();a final2_private.rider_assignment_starts;
 cfg final_delivery_private.pay_settings;s final_delivery_private.pay_snapshots;q jsonb;eid bigint;begin
 if new.order_status='cancelled'and old.order_status is distinct from new.order_status
  and old.order_status='on_the_way'and actor is not null and(
   (public.fr21_role()='customer'and old.user_id=actor)or(public.fr21_role()='vendor'and exists(
    select 1 from public.vendor_orders where order_id=new.id and vendor_id=actor)))then
  select *into a from final2_private.rider_assignment_starts where order_id=new.id and rider_id=old.rider_id
   and accepted_at is not null and not history_limited order by assignment_id desc limit 1;
  select *into cfg from final_delivery_private.pay_settings where id=1;
  if a.assignment_id is null or not cfg.cancellation_base_enabled then return new;end if;
  select *into s from final_delivery_private.pay_snapshots where order_id=new.id and rider_id=a.rider_id;
  if s.order_id is null then return new;end if;
  q:=jsonb_build_object('base_amount',coalesce((s.quote->>'base_amount')::numeric,cfg.base_amount),
   'per_km_rate',0,'distance_amount',0,'distance_km',0,'distance_method','not_applicable',
   'currency',cfg.currency,'earnings_only',true,'policy_revision',coalesce((s.quote->>'policy_revision')::bigint,cfg.revision));
  insert into final_delivery_private.rider_earnings(order_id,assignment_id,rider_id,kind,amount,calculation)
   values(new.id,a.assignment_id,a.rider_id,'CANCEL_AFTER_PICKUP',(q->>'base_amount')::numeric,q)
   on conflict(order_id)do nothing returning id into eid;
  if eid is not null then insert into public.security_audit_log(actor_id,action,target_type,target_id)
   values(actor,'rider_cancel_base_recorded','orders',new.id);end if;
 end if;return new;end$$;
create trigger final_delivery_cancel_pay after update of order_status on public.orders
 for each row execute function final_delivery_private.credit_cancelled_pay();

-- Explicit whole-order cancellation after pickup in the approved COD-only scope.
-- Existing timeout/rejection policies remain unchanged. Inventory and tracking
-- cleanup reuse their accepted transactional triggers; no refund is fabricated.
create function public.final_delivery_cancel_after_pickup(p_order_id bigint,p_request_id uuid,p_confirmed boolean,p_reason text)returns jsonb
language plpgsql security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();role_name text:=public.fr21_role();o public.orders;p public.payments;
 prior final_delivery_private.pickup_cancellations;reason_text text;begin
 if actor is null or not public.is_current_user_allowed()or role_name not in('customer','vendor')
  or not exists(select 1 from public.users where id=actor and not is_blocked and verification_status='approved')then
  raise exception 'Approved owning Customer or Vendor required'using errcode='42501';end if;
 if p_order_id is null or p_order_id<1 or p_request_id is null or p_confirmed is distinct from true
  or p_reason is null or char_length(btrim(p_reason))not between 5 and 300 or p_reason~'[[:cntrl:]]'then
  raise exception 'Explicit whole-order confirmation and reason required'using errcode='22023';end if;
 reason_text:=btrim(p_reason);
 select *into o from public.orders where id=p_order_id for update;
 if o.id is null or not((role_name='customer'and o.user_id=actor)or(role_name='vendor'and exists(
  select 1 from public.vendor_orders where order_id=o.id and vendor_id=actor)))then
  raise exception 'Owned order required'using errcode='42501';end if;
 select *into prior from final_delivery_private.pickup_cancellations where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>actor or prior.order_id<>o.id or prior.reason<>reason_text then raise exception 'Request payload changed'using errcode='PT409';end if;
  return jsonb_build_object('code','ALREADY_CANCELLED','order_id',o.id);end if;
 if o.order_status='cancelled'then return jsonb_build_object('code','ALREADY_CANCELLED','order_id',o.id);end if;
 if o.order_status is distinct from'on_the_way'or o.rider_id is null or not exists(
  select 1 from final2_private.rider_assignment_starts s join public.rider_assignments a on a.id=s.assignment_id
  join final_delivery_private.pay_snapshots q on q.order_id=s.order_id and q.assignment_id=a.id and q.rider_id=s.rider_id
  where s.order_id=o.id and s.rider_id=o.rider_id and s.accepted_at is not null and not s.history_limited and a.status='Accepted'
   and checklist_private.allowed(o.id,o.rider_id))then
  return jsonb_build_object('code','PICKUP_REQUIRED','order_id',o.id);end if;
 perform 1 from public.vendor_orders where order_id=o.id order by id for update;
 perform fr17_private.lock_inventory(array[o.id]);
 if(select count(*)from public.payments where orderid=o.id::text)<>1 then return jsonb_build_object('code','PAYMENT_REVIEW_REQUIRED','order_id',o.id);end if;
 select *into p from public.payments where orderid=o.id::text for update;
 if lower(o.payment_method)is distinct from'cod'or lower(p.method)is distinct from'cod'
  or p.customerid is distinct from o.user_id::text or p.amount::numeric is distinct from o.amount
  or lower(p.status)not in('pending','unpaid')or p.status is null or p.paidat is not null
  or exists(select 1 from public.cod_cash_events where order_id=o.id and event_kind='COLLECTED')then
  return jsonb_build_object('code','PAYMENT_REVIEW_REQUIRED','order_id',o.id);end if;
 insert into final_delivery_private.pickup_cancellations(request_id,actor_id,order_id,reason)values(p_request_id,actor,o.id,reason_text);
 update public.orders set order_status='cancelled',cancelled_at=clock_timestamp(),
  cancellation_reason=case when role_name='customer'then'customer_cancelled_after_pickup'else'vendor_cancelled_after_pickup'end,
  acceptance_deadline_at=null,requires_manual_assignment=false where id=o.id;
 update public.vendor_orders set status='cancelled'where order_id=o.id and status is distinct from'cancelled';
 insert into public.security_audit_log(actor_id,action,target_type,target_id)values(actor,'order_cancelled_after_pickup','orders',o.id);
 insert into public.notifications(user_id,title,message,type,order_push_event_id)
  select u.id,'Order cancelled','A picked-up order was cancelled. Open orders for details.','order',gen_random_uuid()
  from public.users u where u.id=o.user_id or u.id=o.rider_id or exists(select 1 from public.vendor_orders v where v.order_id=o.id and v.vendor_id=u.id);
 return jsonb_build_object('code','CANCELLED','order_id',o.id,'payment_state','UNPAID','rider_base_credit_recorded',
  exists(select 1 from final_delivery_private.rider_earnings where order_id=o.id and kind='CANCEL_AFTER_PICKUP'));
exception when lock_not_available or deadlock_detected or serialization_failure then return jsonb_build_object('code','RETRYABLE_ERROR','order_id',p_order_id);
end$$;

create function final_delivery_private.flag_earning_review()returns trigger
language plpgsql security definer set search_path=''as $$
declare oid bigint;eid bigint;why text;sid bigint;begin
 if tg_table_name='disputes'then
  if new.decision is distinct from 'RESOLVED'then return new;end if;
  oid:=new.order_id;sid:=new.id;why:='DISPUTE_RESOLVED';
 elsif tg_table_name='cod_cash_events'then
  if new.event_kind is distinct from 'REFUND_CONFIRMED'then return new;end if;
  oid:=new.order_id;sid:=new.id;why:='REFUND_RECORDED';
 else oid:=new.order_id;sid:=new.id;why:='REFUND_RECORDED';end if;
 select id into eid from final_delivery_private.rider_earnings where order_id=oid and kind='DELIVERED';
 if eid is not null then
  insert into final_delivery_private.earning_reviews(earning_id,reason,source_id)values(eid,why,sid)on conflict do nothing;
 end if;return new;end$$;
create trigger final_delivery_dispute_review after update of decision on public.disputes
 for each row execute function final_delivery_private.flag_earning_review();
create trigger final_delivery_refund_review after insert on public.dispute_refund_actions
 for each row execute function final_delivery_private.flag_earning_review();
create trigger final_delivery_cash_review after insert on public.cod_cash_events
 for each row execute function final_delivery_private.flag_earning_review();

create function public.final_delivery_rider_earnings(p_limit integer default 25,p_before bigint default null,p_rider_id bigint default null)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();rid bigint:=coalesce(p_rider_id,actor);rows jsonb;next_id bigint;total numeric;counted bigint;begin
 if actor is null or not public.is_current_user_allowed()or not exists(select 1 from public.users where id=actor
  and verification_status='approved'and not is_blocked)or(public.fr21_role()<>'admin'and(public.fr21_role()<>'rider'or rid is distinct from actor))
  or not exists(select 1 from public.users where id=rid and role='rider')then
  raise exception 'Authorized Rider earnings required'using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 100 or(p_before is not null and p_before<1)then raise exception 'Invalid page'using errcode='22023';end if;
 select coalesce(sum(amount),0),count(*)into total,counted from final_delivery_private.rider_earnings where rider_id=rid;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'order_id',e.order_id,'earned_at',e.earned_at,
  'kind',case when e.kind='DELIVERED'then'delivery'else'post_pickup_cancellation'end,'amount',e.amount,'distance_km',e.calculation->'distance_km','distance_method',e.calculation->'distance_method',
  'base_amount',e.calculation->'base_amount','per_km_rate',e.calculation->'per_km_rate','distance_amount',e.calculation->'distance_amount',
  'currency','PKR','admin_review_required',exists(select 1 from final_delivery_private.earning_reviews r where r.earning_id=e.id))order by e.id desc),'[]'),min(e.id)
 into rows,next_id from(select *from final_delivery_private.rider_earnings where rider_id=rid and(p_before is null or id<p_before)order by id desc limit p_limit)e;
 if not exists(select 1 from final_delivery_private.rider_earnings where rider_id=rid and id<next_id)then next_id:=null;end if;
 return jsonb_build_object('code','OK','rider_id',rid,'total_amount',total,'record_count',counted,'entries',rows,
  'next_before',next_id,'currency','PKR','earnings_only',true,
  'historical_unpriced_deliveries',(select count(*)from public.orders o where o.rider_id=rid and o.order_status='delivered'
   and not exists(select 1 from final_delivery_private.rider_earnings e where e.order_id=o.id)));
end$$;
-- Retain the accepted performance counters; add only actual recorded fees.
create or replace function public.final2_rider_performance(p_rider_id bigint default null)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();rid bigint:=coalesce(p_rider_id,actor);m final2_private.rider_performance;fees numeric;unpriced bigint;begin
 if actor is null or not exists(select 1 from public.users where id=actor and verification_status='approved'and not is_blocked)
  or(public.fr21_role()<>'admin'and(public.fr21_role()<>'rider'or rid is distinct from actor))
  or not exists(select 1 from public.users where id=rid and role='rider')then
  raise exception 'Authorized Rider performance required'using errcode='42501';end if;
 select *into m from final2_private.rider_performance where rider_id=rid;
 select coalesce(sum(amount),0)into fees from final_delivery_private.rider_earnings where rider_id=rid;
 select count(*)into unpriced from public.orders o where o.rider_id=rid and o.order_status='delivered'
  and not exists(select 1 from final_delivery_private.rider_earnings e where e.order_id=o.id);
 return jsonb_build_object('code','OK','rider_id',rid,'accepted_assignments',coalesce(m.accepted_assignments,0),
  'completed_deliveries',coalesce(m.completed_deliveries,0),'completion_rate',m.completion_rate,
  'timed_deliveries',coalesce(m.timed_deliveries,0),'average_duration_seconds',m.average_duration_seconds,
  'rating_count',coalesce(m.rating_count,0),'average_rating',m.average_rating,
  'legacy_assignments',(select count(*)from final2_private.rider_assignment_starts where rider_id=rid and history_limited),
  'unlinked_deliveries',(select count(*)from public.orders o where o.rider_id=rid and o.order_status='delivered'
    and not exists(select 1 from final2_private.rider_delivery_metrics d where d.order_id=o.id)),
  'fee_status',case when unpriced>0 then'RECORDED_WITH_HISTORICAL_GAPS'else'RECORDED'end,
  'earned_fee_cents',round(fees*100),'historical_unpriced_deliveries',unpriced,'earnings_only',true,'updated_at',m.updated_at);
end$$;
revoke all on function final_delivery_private.pay_immutable(),final_delivery_private.calculate_quote(bigint,bigint),
 final_delivery_private.freeze_delivery_pay(),final_delivery_private.credit_delivered_pay(),
 final_delivery_private.credit_cancelled_pay(),final_delivery_private.flag_earning_review()from public,anon,authenticated,service_role;
revoke all on function public.final_delivery_rider_quote(bigint),public.final_delivery_rider_earnings(integer,bigint,bigint),
 public.final_delivery_cancel_after_pickup(bigint,uuid,boolean,text)from public,anon,service_role;
grant execute on function public.final_delivery_rider_quote(bigint),public.final_delivery_rider_earnings(integer,bigint,bigint),
 public.final_delivery_cancel_after_pickup(bigint,uuid,boolean,text)to authenticated;
notify pgrst,'reload schema';
commit;
