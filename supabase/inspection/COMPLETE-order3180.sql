-- Read-only resumption checkpoint. Never output OTP values, coordinates or contacts.
begin read only;
set local statement_timeout='15s';
select jsonb_build_object(
 'project','igeisilhtmglgnqvllrx','observed_at',clock_timestamp(),
 'order',jsonb_build_object('id',o.id,'status',o.order_status,'customer_id',o.user_id,
   'rider_id',o.rider_id,'amount',o.amount,'payment_method',o.payment_method,
   'destination_confirmed',o.destination_confirmed_at is not null),
 'vendors',(select jsonb_agg(jsonb_build_object('id',v.id,'vendor_id',v.vendor_id,'status',v.status,'sub_total',v.sub_total))from public.vendor_orders v where v.order_id=o.id),
 'items',(select jsonb_agg(jsonb_build_object('product_id',i.product_id,'quantity',i.quantity,'price_at_time',i.price_at_time,'stock_qty',p.stock_qty))
   from public.order_items i join public.vendor_orders v on v.id=i.vendor_order_id join public.products p on p.id=i.product_id where v.order_id=o.id),
 'assignments',(select jsonb_agg(jsonb_build_object('id',id,'rider_id',riderid,'status',status))from public.rider_assignments where orderid=o.id),
 'otp_attempts',(select coalesce(jsonb_agg(jsonb_build_object('state',state,'attempts',attempts,'created_at',created_at,'sent_at',sent_at,'expires_at',expires_at)),'[]')from public.delivery_otps where order_id=o.id),
 'email_jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'email_type',email_type,'status',status,'test_approved',test_approved,'attempts',attempts,'sent_at',sent_at)),'[]')from public.email_outbox where entity_type='order'and entity_id=o.id::text),
 'inventory',(select coalesce(jsonb_agg(jsonb_build_object('movement_type',movement_type,'quantity_delta',quantity_delta)),'[]')from public.inventory_movements where order_id=o.id),
 'payment_statuses',(select jsonb_agg(status)from public.payments where orderid=o.id::text),
 'cash_records',(select count(*)from public.cod_cash_events where order_id=o.id),
 'earned_records',(select count(*)from final_delivery_private.rider_earnings where order_id=o.id),
 'earned_amount',(select coalesce(sum(amount),0)from final_delivery_private.rider_earnings where order_id=o.id),
 'frozen_expected_amount',(select quote->'expected_amount'from final_delivery_private.pay_snapshots where order_id=o.id),
 'invoice_records',(select count(*)from public.invoices where order_id=o.id),
 'proof_records',(select count(*)from public.delivery_proof where orderid=o.id::text),
 'uploaded_delivery_photos',(select count(*)from final2_private.photos where order_id=o.id and uploaded and kind<>'avatar'),
 'assignment_push',(select coalesce(jsonb_agg(jsonb_build_object('user_id',d.user_id,'state',d.state,'attempts',d.attempts,'failure_code',d.failure_code,'provider_accepted',d.provider_message is not null)),'[]')from fr30_private.push_deliveries d join public.notifications n on n.id=d.notification_id where n.assignment_order_id=o.id)
)as checkpoint from public.orders o where o.id=3180 and o.user_id=159 and o.rider_id=999;
rollback;
