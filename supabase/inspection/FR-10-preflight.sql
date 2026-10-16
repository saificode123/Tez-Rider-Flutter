-- Read-only contract inspection. No credentials, personal rows or cron commands.
begin read only;
select jsonb_build_object(
 'migration_versions',(select jsonb_agg(version order by version) from supabase_migrations.schema_migrations),
 'extensions',(select jsonb_agg(jsonb_build_object('name',extname,'version',extversion)) from pg_extension where extname in ('pg_cron','pg_net')),
 'jobs',(select jsonb_agg(jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'active',active)) from cron.job),
 'tables',(select jsonb_agg(jsonb_build_object('name',c.relname,'rls',c.relrowsecurity)) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and (c.relname in ('orders','vendor_orders','order_items','payment','payments','notifications','dispute_refund_actions') or c.relname ~ '(timeline|order_event|order_status_history|refund|allocation)')),
 'columns',(select jsonb_agg(jsonb_build_object('table',table_name,'name',column_name,'type',udt_name,'default',column_default)) from information_schema.columns where table_schema='public' and table_name in ('orders','vendor_orders','order_items','payment','payments','notifications','dispute_refund_actions')),
 'constraints',(select jsonb_agg(jsonb_build_object('table',conrelid::regclass::text,'name',conname,'definition',pg_get_constraintdef(oid))) from pg_constraint where conrelid in ('public.orders'::regclass,'public.vendor_orders'::regclass,'public.payments'::regclass,'public.payment'::regclass,'public.dispute_refund_actions'::regclass)),
 'policies',(select jsonb_agg(jsonb_build_object('table',tablename,'name',policyname,'command',cmd,'using',qual,'check',with_check)) from pg_policies where schemaname='public' and tablename in ('orders','vendor_orders','order_items','payment','payments','notifications','dispute_refund_actions')),
 'functions',(select jsonb_agg(jsonb_build_object('name',p.proname,'definer',p.prosecdef,'config',p.proconfig,'definition',pg_get_functiondef(p.oid))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('cancel_timed_out_orders','fr21_guard_vendor_transition','sync_order_status_from_vendor_order','notify_customer_on_order_status','notify_vendor_on_status_change','fr21_guard_order_transition')),
 'order_status_counts',(select jsonb_agg(t) from (select order_status,count(*) from public.orders group by order_status)t),
 'payment_status_counts',(select jsonb_agg(t) from (select method,status,count(*) from public.payments group by method,status)t)
) as inspection;
commit;
