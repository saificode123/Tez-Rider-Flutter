-- Essential authorization integration: the existing order UPDATE policy
-- queried vendor_orders, whose SELECT policy queried orders again. Replace
-- only that membership subquery with a fixed-path owner-checked helper.
begin;
set local lock_timeout='5s';
create function public.fr28_vendor_owns_order(p_order bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select public.fr21_role()='vendor' and exists(
  select 1 from public.vendor_orders where order_id=p_order
  and vendor_id=(select public.fr21_actor()))
$$;
revoke all on function public.fr28_vendor_owns_order(bigint) from public,anon;
grant execute on function public.fr28_vendor_owns_order(bigint) to authenticated;
alter policy fr21_test_orders_update on public.orders using (
 user_id=(select public.fr21_actor()) or (select public.fr21_role())='admin'
 or public.fr28_vendor_owns_order(id)
) with check (order_status='cancelled');
notify pgrst,'reload schema';
commit;
