begin read only;
set local statement_timeout='15s';
select jsonb_build_object('project','igeisilhtmglgnqvllrx','observed_at',clock_timestamp(),
 'migration_applied',exists(select 1 from supabase_migrations.schema_migrations where version='202610300001'),
 'order_status',(select order_status from public.orders where id=3180 and user_id=159 and rider_id=999),
 'stock_qty',(select stock_qty from public.products where id=224),
 'rider_online',(select is_online from public.riders where userid=999),
 'pickup_allowed_for_started_order',fr14_private.pickup_allowed(3180,999),
 'otp_requests',(select count(*)from public.delivery_otps where order_id=3180),
 'cash_records',(select count(*)from public.cod_cash_events where order_id=3180),
 'earned_records',(select count(*)from final_delivery_private.rider_earnings where order_id=3180),
 'public_pickup_cache_read',has_table_privilege('authenticated','fr14_private.pickup_cache','select'),
 'authenticated_pickup_prepare',has_function_privilege('authenticated','public.fr14_pickup_prepare(bigint,bigint,boolean)','execute'),
 'anonymous_pickup_context',has_function_privilege('anon','public.fr14_pickup_context(bigint)','execute'),
 'pickup_phase_trigger_enabled',exists(select 1 from pg_trigger where tgname='fr14_pickup_phase_end'and tgenabled='O'),
 'existing_schedules',(select jsonb_agg(jsonb_build_object('name',jobname,'active',active,'schedule',schedule))from cron.job where jobname in('fr14-route-cleanup','fr10-order-timeout','fr30-android-push','fr32-email-worker'))
)as readiness;
rollback;
