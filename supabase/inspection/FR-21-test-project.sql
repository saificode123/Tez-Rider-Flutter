-- READ ONLY. Execute only in the dashboard for igeisilhtmglgnqvllrx.
-- The dashboard project URL/name must be checked first; current_database()
-- alone cannot identify a hosted project (each uses database name postgres).
select jsonb_build_object(
  'database', current_database(),
  'public_tables', (select coalesce(jsonb_agg(table_name order by table_name), '[]'::jsonb)
    from information_schema.tables
    where table_schema='public' and table_type='BASE TABLE'),
  'migration_history_exists', to_regclass('supabase_migrations.schema_migrations') is not null,
  'fr21_functions', (select count(*) from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'fr21_%')
) as test_schema_audit;
