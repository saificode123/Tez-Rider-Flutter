-- TEST rollback only; preserve the actual selected destination and private audit history.
-- Roll back the matching client build as well. This never resets status, prices or stock.
begin;
set local lock_timeout='5s';
create or replace function fr14_private.guard_destination()returns trigger language plpgsql set search_path='' as $$begin
 if current_user not in('postgres','supabase_admin')and
 ((tg_op='INSERT'and new.route_estimated_arrival_at is not null)or
 (tg_op='UPDATE'and new.route_estimated_arrival_at is distinct from old.route_estimated_arrival_at))then
  raise exception 'Server route calculation required'using errcode='42501';end if;
 if tg_op='UPDATE'and (new.delivery_lat,new.delivery_lng,new.delivery_address,new.destination_source,new.destination_confirmed_at)
 is distinct from(old.delivery_lat,old.delivery_lng,old.delivery_address,old.destination_source,old.destination_confirmed_at)then
  if old.destination_confirmed_at is not null or old.order_status in('ready','on_the_way','delivered','cancelled')then
   raise exception 'Delivery destination is locked'using errcode='42501';end if;
 end if;
 if (tg_op='INSERT'and new.destination_confirmed_at is not null)
 or (tg_op='UPDATE'and(new.destination_source,new.destination_confirmed_at)is distinct from(old.destination_source,old.destination_confirmed_at))then
  if current_user not in('postgres','supabase_admin')then raise exception 'Trusted checkout required'using errcode='42501';end if;
 end if;
 return new;
end$$;

drop function public.final_delivery_destination_context(bigint);
drop function public.final_delivery_change_destination(bigint,uuid,timestamptz,numeric,numeric,text,boolean);
commit;
