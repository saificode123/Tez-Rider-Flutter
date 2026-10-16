begin read only;
select jsonb_build_object(
 'versions',(select jsonb_agg(version order by version)from supabase_migrations.schema_migrations),
 'columns',(select jsonb_agg(jsonb_build_object('table',table_name,'column',column_name,'type',data_type,'nullable',is_nullable,'default',column_default))from information_schema.columns where table_schema='public'and table_name in('products','order_items')),
 'product_counts',(select jsonb_build_object('total',count(*),'available',count(*)filter(where p.is_available),'unknown_stock',count(*)filter(where coalesce(to_jsonb(p)->>'stock_qty',to_jsonb(p)->>'stock')is null),'unmarked_owner',count(*)filter(where not exists(select 1 from public.users u join auth.users a on a.id=u.auth_user_id where u.id=p.vendor_id and exists(select 1 from jsonb_each(coalesce(a.raw_user_meta_data,'{}'))e where e.key like '%fixture'and e.value='true'::jsonb))))from public.products p),
 'product_indexes',(select jsonb_agg(indexdef)from pg_indexes where schemaname='public'and tablename='products'),
 'policies',(select jsonb_agg(jsonb_build_object('name',policyname,'table',tablename,'command',cmd,'roles',roles,'using',qual,'check',with_check))from pg_policies where schemaname='public'and tablename in('products','order_items','orders','vendor_orders')),
 'triggers',(select jsonb_agg(pg_get_triggerdef(t.oid))from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'and c.relname in('products','orders','vendor_orders','order_items','payments')and not t.tgisinternal),
 'product_grants',(select jsonb_agg(jsonb_build_object('role',grantee,'privilege',privilege_type))from information_schema.role_table_grants where table_schema='public'and table_name='products'),
 'jobs',(select jsonb_agg(jsonb_build_object('name',jobname,'active',active))from cron.job where jobname in('fr10-order-timeout','fr30-android-push'))
)as inspection;
rollback;
