-- Role-owned active-order warnings use independent indexed branches.
begin;
set local lock_timeout='5s';
create index fr28_active_customer_idx on public.orders(user_id,id desc)
 where order_status not in ('delivered','cancelled');
create index fr28_active_rider_idx on public.orders(rider_id,id desc)
 where order_status not in ('delivered','cancelled');
create index fr28_active_vendor_idx on public.orders(vendor_id,id desc)
 where order_status not in ('delivered','cancelled');
create or replace function public.fr28_active_orders(p_target bigint) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('order_ids',coalesce(jsonb_agg(id),'[]'::jsonb),'more_than_twenty',count(*)>20)
 from (
  select id from (
   (select id from public.orders where user_id=p_target and order_status not in ('delivered','cancelled') order by id desc limit 21)
   union
   (select id from public.orders where rider_id=p_target and order_status not in ('delivered','cancelled') order by id desc limit 21)
   union
   (select id from public.orders where vendor_id=p_target and order_status not in ('delivered','cancelled') order by id desc limit 21)
   union
   (select o.id from public.vendor_orders v join public.orders o on o.id=v.order_id
    where v.vendor_id=p_target and o.order_status not in ('delivered','cancelled') order by o.id desc limit 21)
  ) candidates order by id desc limit 21
 ) bounded
$$;
revoke all on function public.fr28_active_orders(bigint) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
