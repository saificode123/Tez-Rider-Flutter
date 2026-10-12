-- TEST-only authorization for the verified FR-21/mobile paths.
-- Unreviewed legacy modules retain their schema but receive no client grants.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path='' as $$
  select public.fr21_role()='admin'
$$;
grant execute on function public.is_admin() to authenticated;

-- The exported tailoring table lacks a field queried at rider dashboard startup.
alter table public.tailoring_requests add column if not exists rider_id bigint
  references public.users(id) on delete set null;
create index if not exists fr21_tailoring_rider_idx on public.tailoring_requests(rider_id,status);
create index if not exists fr21_tailoring_vendor_idx on public.tailoring_requests(vendor_id,created_at desc);
create index if not exists fr21_tailoring_customer_idx on public.tailoring_requests(customer_id);
create index if not exists fr21_notification_owner_idx on public.notifications(user_id,created_at desc);
create index if not exists fr21_order_customer_idx on public.orders(user_id,created_at desc);
create index if not exists fr21_order_vendor_idx on public.orders(vendor_id);
create index if not exists fr21_items_vendor_order_idx on public.order_items(vendor_order_id);
create index if not exists fr21_items_product_idx on public.order_items(product_id);
create index if not exists fr21_product_vendor_idx on public.products(vendor_id);
create index if not exists fr21_stores_vendor_idx on public.stores(vendor_id);

-- Restrictive policies intersect the original permissive policies; no legacy
-- policy or table is deleted. Unknown modules stay inaccessible after baseline.
create policy fr21_test_users_read on public.users as restrictive for select to authenticated
  using(id=(select public.fr21_actor()) or (select public.fr21_role())='admin');
create policy fr21_test_users_signup on public.users as restrictive for insert to authenticated
  with check(email=(select auth.jwt()->>'email') and role in ('customer','vendor','rider'));
grant select,insert on public.users to authenticated;
grant update(name,phone,profile_image,cnic,cnic_image_url,rejection_reason,verification_status) on public.users to authenticated;
grant usage,select on sequence public.users_id_seq to authenticated;

create policy fr21_test_riders_read on public.riders as restrictive for select to authenticated
  using(userid=(select public.fr21_actor()) or (select public.fr21_role())='admin');
grant select on public.riders to authenticated;

create policy fr21_test_orders_read on public.orders as restrictive for select to authenticated
  using(public.fr21_order_visible(id));
create policy fr21_test_orders_insert on public.orders as restrictive for insert to authenticated
  with check(user_id=(select public.fr21_actor()) and (select public.fr21_role())='customer');
create policy fr21_test_orders_update on public.orders as restrictive for update to authenticated
  using(user_id=(select public.fr21_actor()) or (select public.fr21_role())='admin'
    or ((select public.fr21_role())='vendor' and exists(select 1 from public.vendor_orders vo
      where vo.order_id=orders.id and vo.vendor_id=(select public.fr21_actor()))))
  with check(order_status='cancelled');
grant select,insert on public.orders to authenticated;
grant update(order_status) on public.orders to authenticated;
grant usage,select on sequence public.orders_id_seq to authenticated;

create policy fr21_test_vendor_orders_read on public.vendor_orders as restrictive for select to authenticated
  using(public.fr21_order_visible(order_id));
create policy fr21_test_vendor_orders_insert on public.vendor_orders as restrictive for insert to authenticated
  with check((select public.fr21_role())='customer' and exists(select 1 from public.orders o
    where o.id=order_id and o.user_id=(select public.fr21_actor())));
create policy fr21_test_vendor_orders_update on public.vendor_orders as restrictive for update to authenticated
  using(vendor_id=(select public.fr21_actor()) and (select public.fr21_role())='vendor')
  with check(vendor_id=(select public.fr21_actor()) and status in ('accepted','preparing','cancelled'));
grant select,insert on public.vendor_orders to authenticated;
grant update(status) on public.vendor_orders to authenticated;
grant usage,select on sequence public.vendor_orders_id_seq to authenticated;

create policy fr21_test_assignments_read on public.rider_assignments as restrictive for select to authenticated
  using(public.fr21_order_visible(orderid));
grant select on public.rider_assignments to authenticated;

create policy fr21_test_notifications_read on public.notifications as restrictive for select to authenticated
  using(user_id=(select public.fr21_actor()));
create policy fr21_test_notifications_update on public.notifications as restrictive for update to authenticated
  using(user_id=(select public.fr21_actor())) with check(user_id=(select public.fr21_actor()));
grant select on public.notifications to authenticated;
grant update(is_read) on public.notifications to authenticated;

-- Existing invoker notification/status triggers must retain their side effects
-- without granting clients INSERT to notifications or UPDATE to parent orders.
alter function public.notify_customer_on_order_status() security definer;
alter function public.notify_customer_on_order_status() set search_path='';
alter function public.notify_vendor_on_new_order() security definer;
alter function public.notify_vendor_on_new_order() set search_path='';
alter function public.notify_vendor_on_status_change() security definer;
alter function public.notify_vendor_on_status_change() set search_path='';
alter function public.sync_order_status_from_vendor_order() security definer;
alter function public.sync_order_status_from_vendor_order() set search_path='';

create policy fr21_test_vendors_read on public.vendors as restrictive for select to authenticated using(true);
grant select on public.vendors,public.stores,public.products,public.categories to authenticated;
-- These tables have no private customer/document fields; original catalog reads
-- are preserved. All catalog writes remain denied to avoid enabling legacy bypasses.
create policy fr21_test_items_read on public.order_items as restrictive for select to authenticated
  using(exists(select 1 from public.vendor_orders vo where vo.id=vendor_order_id
    and public.fr21_order_visible(vo.order_id)));
create policy fr21_test_items_insert on public.order_items as restrictive for insert to authenticated
  with check((select public.fr21_role())='customer' and exists(
    select 1 from public.vendor_orders vo join public.orders o on o.id=vo.order_id
    where vo.id=vendor_order_id and o.user_id=(select public.fr21_actor())));
grant select,insert on public.order_items to authenticated;
grant usage,select on sequence public.order_items_id_seq to authenticated;

create policy fr21_test_tailoring_read on public.tailoring_requests as restrictive for select to authenticated
  using(customer_id=(select public.fr21_actor()) or vendor_id=(select public.fr21_actor())
    or rider_id=(select public.fr21_actor()) or (select public.fr21_role())='admin');
grant select on public.tailoring_requests to authenticated;

-- Preserve vendor customer-contact UI through a bounded projection, without
-- granting access to another user's CNIC, email or full profile.
create function public.fr21_order_contacts(p_order_ids bigint[]) returns table(order_id bigint,name text,phone text)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_order_ids is null or cardinality(p_order_ids)>100 then
    raise exception 'At most 100 order IDs required' using errcode='22023'; end if;
  return query select o.id,u.name,u.phone from public.orders o join public.users u on u.id=o.user_id
    where o.id=any(p_order_ids) and public.fr21_order_visible(o.id);
end $$;
grant execute on function public.fr21_order_contacts(bigint[]) to authenticated;

-- Publish only the FR-21 dashboard/notification tables with reviewed visibility.
do $$ declare t text; begin
  foreach t in array array['orders','vendor_orders','rider_assignments','tailoring_requests','notifications'] loop
    if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
      select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
      execute format('alter publication supabase_realtime add table public.%I',t);
    end if;
  end loop;
end $$;
notify pgrst,'reload schema';
commit;
