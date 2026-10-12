-- READ ONLY. Execute only with explicit --linked --project-ref igeisilhtmglgnqvllrx.
-- Reports metadata, never user records or secrets.
select jsonb_build_object(
  'public_table_count',(select count(*) from pg_tables where schemaname='public'),
  'missing_app_tables',(select coalesce(jsonb_agg(t),'[]'::jsonb) from unnest(array[
    'addresses','app_settings','categories','chat_messages','chat_participants',
    'chat_rooms','delivery_proof','disputes','favourite','gps_locations',
    'notifications','order_items','orders','prescriptions','products','reviews',
    'rider_assignments','riders','stores','tailoring_requests','users',
    'vendor_orders','vendors']) t where to_regclass('public.'||t) is null),
  'missing_required_functions',(select coalesce(jsonb_agg(f),'[]'::jsonb) from unnest(array[
    'public.get_vendor_ratings(bigint[])','public.is_current_vendor(bigint)',
    'public.fr21_actor()','public.fr21_begin_presence()',
    'public.fr21_set_presence(boolean,bigint,bigint)',
    'public.fr21_update_location(numeric,numeric)',
    'public.fr21_ready_and_assign(bigint)','public.fr21_accept_order(bigint)',
    'public.fr21_complete_delivery(bigint,text)']) f where to_regprocedure(f) is null),
  'rider_columns',(select coalesce(jsonb_agg(jsonb_build_object('name',column_name,
    'type',udt_name,'nullable',is_nullable,'default',column_default) order by ordinal_position),'[]'::jsonb)
    from information_schema.columns where table_schema='public' and table_name='riders'),
  'fr21_indexes',(select coalesce(jsonb_agg(indexdef order by indexname),'[]'::jsonb)
    from pg_indexes where schemaname='public' and indexname like 'fr21_%'),
  'tables_without_rls',(select coalesce(jsonb_agg(c.relname order by c.relname),'[]'::jsonb)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity),
  'tables_without_policies',(select coalesce(jsonb_agg(c.relname order by c.relname),'[]'::jsonb)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relrowsecurity
    and not exists(select 1 from pg_policy p where p.polrelid=c.oid)),
  'client_truncate_grants',(select coalesce(jsonb_agg(jsonb_build_object('table',table_name,'role',grantee)),'[]'::jsonb)
    from information_schema.table_privileges where table_schema='public'
    and grantee in ('anon','authenticated') and privilege_type='TRUNCATE'),
  'foreign_key_count',(select count(*) from pg_constraint c join pg_namespace n on n.oid=c.connamespace
    where n.nspname='public' and c.contype='f'),
  'foreign_keys_without_leading_index',(select coalesce(jsonb_agg(jsonb_build_object(
      'table',c.conrelid::regclass::text,'constraint',c.conname)),'[]'::jsonb)
    from pg_constraint c join pg_namespace n on n.oid=c.connamespace
    where n.nspname='public' and c.contype='f' and not exists(
      select 1 from pg_index i where i.indrelid=c.conrelid and i.indisvalid
      and i.indkey[0]=c.conkey[1]))
) as schema_contract;
