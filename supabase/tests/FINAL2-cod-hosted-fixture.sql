-- Authorized TEST only, called by the ref-guarded helper. Persistent synthetic
-- financial states; no claim of physical delivery, uploaded dispute evidence,
-- cash changing hands, provider transfer or FR14/FR33 acceptance.
begin;
select pg_advisory_xact_lock(hashtextextended(__MARKER__,0));
create temporary table final2_cash_fixture(value jsonb);
do $fixture$declare customer bigint:=(select id from public.users where auth_user_id=(__CUSTOMER_CLAIMS__::jsonb->>'sub')::uuid);
 rider bigint:=(select id from public.users where auth_user_id=(__RIDER_CLAIMS__::jsonb->>'sub')::uuid);
 oid bigint;pid bigint;did bigint;aid bigint;cancelled bigint;cancel_payment bigint;refund_id bigint;result jsonb;
 marker text:=__MARKER__;begin
 select orderid::bigint,id into oid,pid from public.payments where paymentid=marker||'-delivered';
 if oid is null then
  if exists(select 1 from public.rider_assignments where riderid=rider and status in('Pending','Accepted'))then
   raise exception 'Synthetic Rider busy; no existing assignment may be modified';end if;
  insert into public.orders(user_id,vendor_id,rider_id,amount,fare,order_status,payment_method,delivery_address)
   values(customer,__VENDOR_ID__,rider,25.75,0,'ready','COD','FINAL2 SYNTHETIC FINANCIAL FIXTURE '||marker)returning id into oid;
  insert into public.vendor_orders(order_id,vendor_id,sub_total,status)values(oid,__VENDOR_ID__,25.75,'ready');
  insert into public.rider_assignments(orderid,riderid,status)values(oid,rider,'Accepted')returning id into aid;
  perform set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
  result:=public.submit_pre_delivery_checklist(aid,1,'[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]');
  if result->>'code'<>'COMPLETED'then raise exception 'Trusted checklist fixture failed';end if;
  -- Financial rule fixture only; delivery/OTP guards are not disabled and no GPS is fabricated.
  update public.orders set order_status='delivered',delivered_at=clock_timestamp()where id=oid;
  update public.vendor_orders set status='delivered'where order_id=oid;
  update public.rider_assignments set status='Completed'where id=aid;
  insert into public.payments(paymentid,orderid,customerid,method,status,amount)
   values(marker||'-delivered',oid::text,customer::text,'COD','pending',25.75)returning id into pid;
  -- Explicit legacy-shaped synthetic dispute: no invented uploaded file.
  insert into public.disputes(type,by,customer_id,order_id,status,reason,description)
   values('Other','Customer',customer,oid,'Open','Other','FINAL2 synthetic financial fixture; no physical delivery or uploaded evidence asserted.')returning id into did;
  insert into public.orders(user_id,vendor_id,amount,fare,order_status,payment_method,delivery_address)
   values(customer,__VENDOR_ID__,31.50,0,'cancelled','COD','FINAL2 SYNTHETIC LEGACY CASH REFUND '||marker)returning id into cancelled;
  insert into public.payments(paymentid,orderid,customerid,method,status,amount,paidat)
   values(marker||'-cancelled',cancelled::text,customer::text,'COD','PAID',31.50,clock_timestamp())returning id into cancel_payment;
  insert into public.order_refund_actions(order_id,payment_id,customer_id,amount,reason)
   values(cancelled,cancel_payment,customer,31.50,'vendor_rejected')returning id into refund_id;
 else
  if not exists(select 1 from public.orders where id=oid and user_id=customer and rider_id=rider and delivery_address='FINAL2 SYNTHETIC FINANCIAL FIXTURE '||marker)then
   raise exception 'Fixture identity mismatch; do not infer ownership';end if;
  select id into did from public.disputes where order_id=oid;
  select orderid::bigint,id into cancelled,cancel_payment from public.payments where paymentid=marker||'-cancelled';
  select id into refund_id from public.order_refund_actions where order_id=cancelled and payment_id=cancel_payment;
 end if;
 if oid is null or pid is null or did is null or cancelled is null or refund_id is null then raise exception 'Incomplete fixture; no partial success';end if;
 insert into final2_cash_fixture values(jsonb_build_object('order_id',oid,'payment_id',pid,'dispute_id',did,
  'cancelled_order_id',cancelled,'cancelled_payment_id',cancel_payment,'order_refund_id',refund_id));
end$fixture$;
select value from final2_cash_fixture;
commit;
