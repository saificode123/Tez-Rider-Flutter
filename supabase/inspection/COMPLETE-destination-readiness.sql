begin read only;
set local statement_timeout='15s';
select jsonb_build_object('project','igeisilhtmglgnqvllrx','observed_at',clock_timestamp(),
 'order_id',o.id,'status',o.order_status,'customer_id',o.user_id,'rider_id',o.rider_id,'amount',o.amount,'fare',o.fare,
 'rider_online',(select is_online from public.riders where userid=o.rider_id),
 'tracking_sessions',(select count(*)from fr13_private.sessions where order_id=o.id),
 'stock_qty',(select stock_qty from public.products where id=224),
 'frozen_expected_amount',(select quote->'expected_amount'from final_delivery_private.pay_snapshots where order_id=o.id),
 'earned_records',(select count(*)from final_delivery_private.rider_earnings where order_id=o.id),
 'cash_records',(select count(*)from public.cod_cash_events where order_id=o.id),
 'proof_records',(select count(*)from public.delivery_proof where orderid=o.id::text),
 'otp_requests',(select count(*)from public.delivery_otps where order_id=o.id),
 'otp_states',(select jsonb_agg(state)from public.delivery_otps where order_id=o.id),
 'amendments',(select count(*)from final_delivery_private.destination_amendments where order_id=o.id),
 'current_point_matches_latest_amendment',(select(d.new_lat,d.new_lng,d.changed_at)is not distinct from(o.delivery_lat,o.delivery_lng,o.destination_confirmed_at)from final_delivery_private.destination_amendments d where d.order_id=o.id order by d.changed_at desc limit 1),
 'private_history_read_denied',not has_table_privilege('authenticated','final_delivery_private.destination_amendments','select'),
 'anonymous_amendment_denied',not has_function_privilege('anon','public.final_delivery_change_destination(bigint,uuid,timestamptz,numeric,numeric,text,boolean)','execute'),
 'service_impersonation_denied',not has_function_privilege('service_role','public.final_delivery_change_destination(bigint,uuid,timestamptz,numeric,numeric,text,boolean)','execute'),
 'route_context_destination_contract',exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and p.proname='fr14_route_context'and position('destination_revision'in p.prosrc)>0),
 'destination_guard_enabled',exists(select 1 from pg_trigger where tgname='fr14_destination_guard'and tgenabled='O')
)as readiness from public.orders o where o.id=3180 and o.user_id=159 and o.rider_id=999;
rollback;
