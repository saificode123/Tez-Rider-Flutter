-- TEST-only financial-state fixture after a real stock-aware customer checkout.
-- No physical delivery, GPS progression or OTP acceptance is asserted.
begin;
select pg_advisory_xact_lock(__ORDER_ID__);
do $$declare o public.orders;a public.rider_assignments;result jsonb;
 rider bigint:=(select id from public.users where auth_user_id=(__RIDER_CLAIMS__::jsonb->>'sub')::uuid);
 customer bigint:=(select id from public.users where auth_user_id=(__CUSTOMER_CLAIMS__::jsonb->>'sub')::uuid);begin
 select *into o from public.orders where id=__ORDER_ID__ for update;
 if o.user_id is distinct from customer or o.delivery_address is distinct from __MARKER__
  or o.checkout_finalized_at is null or not exists(select 1 from fr32_private.order_snapshots where order_id=o.id)
  or not exists(select 1 from public.vendor_orders where order_id=o.id and vendor_id=__VENDOR_ID__)
  or exists(select 1 from public.vendor_orders where order_id=o.id and vendor_id<>__VENDOR_ID__)then
  raise exception 'Owned actual checkout fixture and immutable item snapshot required';end if;
 if o.order_status='delivered'then
  if o.rider_id is distinct from rider or not checklist_private.allowed(o.id,rider)then raise exception 'Fixture identity changed';end if;
  return;
 end if;
 if o.order_status not in('pending','accepted','ready')then raise exception 'Fixture no longer eligible; do not rewrite terminal history';end if;
 if exists(select 1 from public.rider_assignments where riderid=rider and status in('Pending','Accepted')and orderid<>o.id)then
  raise exception 'Rider busy; existing assignments must not be modified';end if;
 update public.vendor_orders set status='ready'where order_id=o.id;
 update public.orders set order_status='ready',rider_id=rider where id=o.id;
 select *into a from public.rider_assignments where orderid=o.id;
 if a.id is null then
  insert into public.rider_assignments(orderid,riderid,status)values(o.id,rider,'Accepted')returning *into a;
 elsif a.riderid is distinct from rider or a.status is distinct from'Accepted'then raise exception 'Unexpected fixture assignment';end if;
 perform set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
 result:=public.submit_pre_delivery_checklist(a.id,1,'[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]');
 if result->>'code'<>'COMPLETED'then raise exception 'Required fixture checklist failed';end if;
 update public.orders set order_status='delivered',delivered_at=clock_timestamp()where id=o.id;
 update public.rider_assignments set status='Completed'where id=a.id;
 update public.vendor_orders set status='delivered'where order_id=o.id;
end$$;
select true as seeded_financial_state_only;
commit;
