-- Executed read-only through the authenticated production dashboard 2026-10-09.
select jsonb_pretty(jsonb_build_object(
  'history',to_regclass('supabase_migrations.schema_migrations') is not null,
  'rider_columns',(select jsonb_agg(to_jsonb(c)) from (
    select column_name,udt_name,is_nullable,column_default from information_schema.columns
    where table_schema='public' and table_name='riders' order by ordinal_position)c),
  'rider_roles',(select jsonb_agg(to_jsonb(v)) from (
    select u.role,u.verification_status,count(*) riders from public.riders r
    join public.users u on u.id=r.userid group by u.role,u.verification_status)v),
  'policies',(select jsonb_agg(to_jsonb(p)) from pg_policies p where schemaname='public'
    and tablename in ('users','riders','orders','rider_assignments','vendor_orders')),
  'trigger_functions',(select jsonb_agg(jsonb_build_object('name',p.proname,'definition',pg_get_functiondef(p.oid)))
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
    and p.proname in ('sync_order_status_from_vendor_order','assign_available_rider',
      'notify_vendor_on_status_change','notify_customer_on_order_status'))
)) as fr21_current;
