-- Quote an eligible unassigned request before acceptance; do not assign, freeze,
-- credit earnings, change inventory or call a routing provider here.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create or replace function public.final_delivery_rider_quote(p_order_id bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();o public.orders;a public.rider_assignments;s final_delivery_private.pay_snapshots;begin
 if actor is null or not public.is_current_user_allowed()or not exists(select 1 from public.users
  where id=actor and verification_status='approved'and not is_blocked and role in('admin','rider'))then
  raise exception 'Approved Rider required'using errcode='42501';end if;
 if p_order_id is null or p_order_id<1 then raise exception 'Invalid order'using errcode='22023';end if;
 select *into o from public.orders where id=p_order_id;
 if o.id is null then raise exception 'Eligible delivery required'using errcode='42501';end if;
 select *into a from public.rider_assignments where orderid=p_order_id and status in('Pending','Accepted','Delivered')
  and(public.fr21_role()='admin'or riderid=actor)order by id desc limit 1;
 if a.id is null then
  -- Match the existing manual acceptance prerequisites, without exposing another
  -- Rider's task or offering an unaccepted Vendor order as ready work.
  if public.fr21_role()is distinct from'rider'or not public.fr21_approved_rider(actor)
   or o.rider_id is not null or coalesce(o.order_status,'') not in('accepted','ready')
   or not exists(select 1 from public.riders r where r.userid=actor and r.is_online
    and r.is_available and r.isavailable and r.last_seen>=clock_timestamp()-interval '2 minutes')
   or exists(select 1 from public.rider_assignments x where x.orderid=o.id and x.status in('Pending','Accepted'))
   or exists(select 1 from public.orders x where x.rider_id=actor and x.id<>o.id
    and(x.order_status is null or x.order_status not in('delivered','cancelled')))
   or exists(select 1 from public.rider_assignments x where x.riderid=actor and x.orderid<>o.id and x.status in('Pending','Accepted'))then
   raise exception 'Eligible available Rider request required'using errcode='42501';end if;
  return final_delivery_private.calculate_quote(p_order_id,actor)||jsonb_build_object('preview_before_acceptance',true);
 end if;
 select *into s from final_delivery_private.pay_snapshots where order_id=p_order_id and rider_id=a.riderid;
 if s.order_id is not null then return s.quote;end if;
 if o.order_status in('delivered','cancelled')then return jsonb_build_object('code','HISTORICAL_RATE_UNAVAILABLE','order_id',p_order_id);end if;
 return final_delivery_private.calculate_quote(p_order_id,a.riderid);
end$$;
revoke all on function public.final_delivery_rider_quote(bigint)from public,anon,service_role;
grant execute on function public.final_delivery_rider_quote(bigint)to authenticated;
notify pgrst,'reload schema';
commit;
