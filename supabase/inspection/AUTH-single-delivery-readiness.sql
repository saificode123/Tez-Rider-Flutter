-- Read-only inspection of the one owner-authorized TEST order. No coordinates.
begin read only;
set local statement_timeout='15s';
select jsonb_build_object(
 'project','igeisilhtmglgnqvllrx','observed_at',clock_timestamp(),
 'order_id',o.id,'status',o.order_status,'assigned_rider_id',o.rider_id,
 'destination_confirmed',o.destination_confirmed_at is not null,
 'pickup_to_destination_km',round((extensions.st_distance(
   extensions.st_setsrid(extensions.st_makepoint(v.longitude::double precision,v.latitude::double precision),4326)::extensions.geography,
   extensions.st_setsrid(extensions.st_makepoint(o.delivery_lng,o.delivery_lat),4326)::extensions.geography)/1000)::numeric,3),
 'rider_available',r.is_available and r.isavailable,
 'rider_presence_fresh',r.is_online and r.last_seen>clock_timestamp()-interval '90 seconds'
   and r.location_updated_at>clock_timestamp()-interval '90 seconds',
 'rider_within_5km',extensions.st_dwithin(r.assignment_location,
   extensions.st_setsrid(extensions.st_makepoint(v.longitude::double precision,v.latitude::double precision),4326)::extensions.geography,5000),
 'rider_pending_assignments',(select count(*)from public.rider_assignments where riderid=999 and status in('Pending','Accepted')),
 'assignment_statuses',(select coalesce(jsonb_agg(status),'[]')from public.rider_assignments where orderid=o.id and riderid=999),
 'cash_records',(select count(*)from public.cod_cash_events where order_id=o.id),
 'earned_records',(select count(*)from final_delivery_private.rider_earnings where order_id=o.id),
 'invoice_records',(select count(*)from public.invoices where order_id=o.id),
 'delivery_proof_records',(select count(*)from public.delivery_proof where orderid=o.id::text),
 'uploaded_delivery_photos',(select count(*)from final2_private.photos where order_id=o.id and uploaded and kind<>'avatar'),
 'otp_requests',(select count(*)from public.delivery_otps where order_id=o.id),
 'assignment_push',(select coalesce(jsonb_agg(jsonb_build_object('user_id',d.user_id,'state',d.state,'attempts',d.attempts,'failure_code',d.failure_code,'provider_accepted',d.provider_message is not null)),'[]')from fr30_private.push_deliveries d join public.notifications n on n.id=d.notification_id where n.assignment_order_id=o.id),
 'payment_statuses',(select coalesce(jsonb_agg(status),'[]')from public.payments where orderid=o.id::text)
)as readiness
from public.orders o join public.vendor_orders vo on vo.order_id=o.id and vo.vendor_id=997
join public.vendors v on v.user_id=vo.vendor_id join public.riders r on r.userid=999
where o.id=3180 and o.user_id=159;
rollback;
