-- Owner-requested correction for existing TEST order 3180 only. Never deploy to production.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create table final_delivery_private.destination_amendments(
 request_id uuid primary key, order_id bigint not null references public.orders(id),
 customer_id bigint not null references public.users(id), transaction_id bigint not null,
 old_lat numeric not null,old_lng numeric not null,old_address text,
 old_confirmed_at timestamptz not null,old_source text not null check(old_source in('my_location','map_pin')),
 new_lat numeric not null,new_lng numeric not null,new_address text not null,
 changed_at timestamptz not null
);
alter table final_delivery_private.destination_amendments enable row level security;
revoke all on final_delivery_private.destination_amendments from public,anon,authenticated,service_role;
create index destination_amendments_order on final_delivery_private.destination_amendments(order_id,changed_at);

-- A private, same-transaction audit record authorizes exactly this tuple change.
-- Direct client writes, other orders/tuples and future transactions stay locked.
create or replace function fr14_private.guard_destination()returns trigger
language plpgsql set search_path=''as $$
declare amendment boolean:=false;begin
 if current_user not in('postgres','supabase_admin')and
 ((tg_op='INSERT'and new.route_estimated_arrival_at is not null)or
 (tg_op='UPDATE'and new.route_estimated_arrival_at is distinct from old.route_estimated_arrival_at))then
  raise exception 'Server route calculation required'using errcode='42501';end if;
 if tg_op='UPDATE'and(new.delivery_lat,new.delivery_lng,new.delivery_address,new.destination_source,new.destination_confirmed_at)
 is distinct from(old.delivery_lat,old.delivery_lng,old.delivery_address,old.destination_source,old.destination_confirmed_at)then
  if old.destination_confirmed_at is not null or old.order_status in('ready','on_the_way','delivered','cancelled')then
   if current_user in('postgres','supabase_admin')then
    select exists(select 1 from final_delivery_private.destination_amendments d
     where old.id=3180 and old.user_id=159 and old.rider_id=999
     and d.order_id=old.id and d.customer_id=public.fr21_actor()and d.transaction_id=txid_current()
     and(d.old_lat,d.old_lng,d.old_address,d.old_confirmed_at,d.old_source)is not distinct from
       (old.delivery_lat,old.delivery_lng,old.delivery_address,old.destination_confirmed_at,old.destination_source)
     and(d.new_lat,d.new_lng,d.new_address,d.changed_at)is not distinct from
       (new.delivery_lat,new.delivery_lng,new.delivery_address,new.destination_confirmed_at)
     and new.destination_source='map_pin'and old.order_status='on_the_way'
     and(new.order_status,new.user_id,new.rider_id,new.amount,new.fare)is not distinct from
       (old.order_status,old.user_id,old.rider_id,old.amount,old.fare))into amendment;
   end if;
   if not amendment then raise exception 'Delivery destination is locked'using errcode='42501';end if;
  end if;
 end if;
 if(tg_op='INSERT'and new.destination_confirmed_at is not null)
 or(tg_op='UPDATE'and(new.destination_source,new.destination_confirmed_at)is distinct from(old.destination_source,old.destination_confirmed_at))then
  if current_user not in('postgres','supabase_admin')then raise exception 'Trusted checkout required'using errcode='42501';end if;
 end if;
 return new;
end$$;

create function final_delivery_private.destination_change_problem(o public.orders)returns text
language plpgsql set search_path=''as $$begin
 if o.order_status is distinct from'on_the_way'or o.destination_confirmed_at is null
 or o.delivery_lat is null or o.delivery_lng is null or o.rider_id is null
 or coalesce(o.destination_source,'')not in('my_location','map_pin')then return'WRONG_STATE';end if;
 if coalesce(lower(o.payment_method),'')not in('cod','cash on delivery')then return'UNSUPPORTED_PAYMENT';end if;
 if not exists(select 1 from public.riders where userid=o.rider_id and not is_online)
 or exists(select 1 from fr13_private.sessions where order_id=o.id)then return'RIDER_MUST_PAUSE';end if;
 if o.otp_admin_review or exists(select 1 from public.delivery_proof where orderid=o.id::text)
 or exists(select 1 from public.cod_cash_events where order_id=o.id)
 or exists(select 1 from final_delivery_private.rider_earnings where order_id=o.id)
 or exists(select 1 from final2_private.photos where order_id=o.id and kind<>'avatar')
 or exists(select 1 from public.payments where orderid=o.id::text and status is distinct from'pending')then
  return'HANDOVER_STARTED';end if;
 if exists(select 1 from public.delivery_otps where order_id=o.id
  and(state in('RESERVED','SENDING','UNKNOWN','USED')or(state='ACCEPTED'and expires_at>clock_timestamp())))then
  return'OTP_ACTIVE';end if;
 return null;
end$$;
revoke all on function final_delivery_private.destination_change_problem(public.orders)from public,anon,authenticated,service_role;

create function public.final_delivery_destination_context(p_order_id bigint)returns jsonb
language plpgsql security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();o public.orders;problem text;begin
 if actor is null or actor<>159 or p_order_id is distinct from 3180
 or public.fr21_role()is distinct from'customer'or not public.is_current_user_allowed()then
  return jsonb_build_object('code','FORBIDDEN');end if;
 select *into o from public.orders where id=p_order_id and user_id=actor and rider_id=999;
 if o.id is null then return jsonb_build_object('code','FORBIDDEN');end if;
 problem:=final_delivery_private.destination_change_problem(o);
 return jsonb_build_object('code','OK','order_id',o.id,'can_change',problem is null,
  'reason',problem,'revision',o.destination_confirmed_at,'latitude',o.delivery_lat,'longitude',o.delivery_lng);
end$$;

create function public.final_delivery_change_destination(p_order_id bigint,p_request_id uuid,
 p_expected_revision timestamptz,p_lat numeric,p_lng numeric,p_address text,p_confirmed boolean)returns jsonb
language plpgsql security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();o public.orders;prior final_delivery_private.destination_amendments;
 problem text;stamp timestamptz;address_text text:=btrim(p_address);begin
 if actor is null or actor<>159 or p_order_id is distinct from 3180
 or public.fr21_role()is distinct from'customer'or not public.is_current_user_allowed()then
  return jsonb_build_object('code','FORBIDDEN');end if;
 if p_order_id is null or p_request_id is null or p_expected_revision is null or p_confirmed is distinct from true
 or p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180
 or address_text is null or char_length(address_text)not between 1 and 500 or address_text~'[[:cntrl:]]'then
  return jsonb_build_object('code','INVALID_DESTINATION');end if;
 select *into o from public.orders where id=p_order_id for update;
 if o.id is null or o.user_id<>actor or o.rider_id is distinct from 999 then return jsonb_build_object('code','FORBIDDEN');end if;
 select *into prior from final_delivery_private.destination_amendments where request_id=p_request_id;
 if found then
  if(prior.order_id,prior.customer_id,prior.old_confirmed_at,prior.new_lat,prior.new_lng,prior.new_address)
   is distinct from(o.id,actor,p_expected_revision,p_lat,p_lng,address_text)then
   return jsonb_build_object('code','REQUEST_CONFLICT');end if;
  return jsonb_build_object('code','OK','order_id',o.id,'revision',prior.changed_at,'replayed',true);
 end if;
 if o.destination_confirmed_at is distinct from p_expected_revision then return jsonb_build_object('code','DESTINATION_CHANGED');end if;
 perform 1 from public.riders where userid=o.rider_id for update;
 problem:=final_delivery_private.destination_change_problem(o);
 if problem is not null then return jsonb_build_object('code',problem);end if;
 if(o.delivery_lat,o.delivery_lng)is not distinct from(p_lat,p_lng)then return jsonb_build_object('code','NO_CHANGE');end if;
 stamp:=clock_timestamp();
 insert into final_delivery_private.destination_amendments values(p_request_id,o.id,actor,txid_current(),
  o.delivery_lat,o.delivery_lng,o.delivery_address,o.destination_confirmed_at,o.destination_source,p_lat,p_lng,address_text,stamp);
 update public.orders set delivery_lat=p_lat,delivery_lng=p_lng,delivery_address=address_text,
  destination_source='map_pin',destination_confirmed_at=stamp,route_estimated_arrival_at=null where id=o.id;
 delete from public.delivery_route_cache where order_id=o.id;
 -- Retain in-flight quota reservations. FR14 finish checks the destination tuple
 -- and settles the old lease without accepting its obsolete geometry.
 update public.delivery_otps set state='INVALIDATED'where order_id=o.id and state='ACCEPTED'and expires_at<=stamp;
 insert into public.security_audit_log(actor_id,action,target_type,target_id)
 values(actor,'delivery_destination_changed','order',o.id);
 return jsonb_build_object('code','OK','order_id',o.id,'revision',stamp,'replayed',false);
exception when lock_not_available or deadlock_detected or serialization_failure then
 return jsonb_build_object('code','RETRYABLE_ERROR');
end$$;
revoke all on function public.final_delivery_destination_context(bigint),
 public.final_delivery_change_destination(bigint,uuid,timestamptz,numeric,numeric,text,boolean)from public,anon,service_role;
grant execute on function public.final_delivery_destination_context(bigint),
 public.final_delivery_change_destination(bigint,uuid,timestamptz,numeric,numeric,text,boolean)to authenticated;
notify pgrst,'reload schema';
commit;
