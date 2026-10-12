-- READ ONLY. Use --project-ref igeisilhtmglgnqvllrx after checking the local link.
-- No user records, credentials, object contents or private Auth settings selected.
select jsonb_build_object(
  'database',current_database(),
  'server_version',current_setting('server_version'),
  'public_tables',(select coalesce(jsonb_agg(tablename order by tablename),'[]'::jsonb)
    from pg_tables where schemaname='public'),
  'public_functions',(select coalesce(jsonb_agg(p.proname order by p.proname),'[]'::jsonb)
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'),
  'migration_history_exists',to_regclass('supabase_migrations.schema_migrations') is not null,
  'extensions',(select jsonb_agg(jsonb_build_object('name',e.extname,'schema',n.nspname))
    from pg_extension e join pg_namespace n on n.oid=e.extnamespace),
  'auth_dependencies',jsonb_build_object('users',to_regclass('auth.users') is not null,
    'uid',to_regprocedure('auth.uid()') is not null,'jwt',to_regprocedure('auth.jwt()') is not null),
  'required_roles',(select jsonb_agg(rolname order by rolname) from pg_roles
    where rolname in ('anon','authenticated','service_role','postgres','supabase_admin')),
  'storage_buckets',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'public',public,
    'file_size_limit',file_size_limit,'allowed_mime_types',allowed_mime_types)),'[]'::jsonb) from storage.buckets),
  'storage_policies',(select coalesce(jsonb_agg(jsonb_build_object('table',tablename,'name',policyname,
    'command',cmd,'roles',roles,'using',qual,'check',with_check)),'[]'::jsonb)
    from pg_policies where schemaname='storage'),
  'realtime_publications',(select coalesce(jsonb_agg(pubname),'[]'::jsonb) from pg_publication
    where pubname='supabase_realtime'),
  'realtime_tables',(select coalesce(jsonb_agg(jsonb_build_object('schema',schemaname,'table',tablename)),'[]'::jsonb)
    from pg_publication_tables where pubname='supabase_realtime')
) as test_environment;
