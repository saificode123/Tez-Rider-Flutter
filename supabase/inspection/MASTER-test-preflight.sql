-- TEST inspection only: no user rows, credentials, documents or coordinates.
begin read only;
set local statement_timeout = '30s';
select jsonb_build_object(
  'application_schemas', (select jsonb_agg(nspname order by nspname)
    from pg_namespace where nspname in ('public','auth','storage','supabase_migrations')
    or nspname like '%private'),
  'versions', (select jsonb_agg(version order by version)
    from supabase_migrations.schema_migrations),
  'tables', (select jsonb_agg(jsonb_build_object(
    'schema', n.nspname, 'name', c.relname, 'rls', c.relrowsecurity,
    'forced_rls', c.relforcerowsecurity,
    'estimated_rows', c.reltuples::bigint) order by n.nspname, c.relname)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind='r' and n.nspname in ('public','auth','storage')),
  'policy_count', (select count(*) from pg_policies
    where schemaname in ('public','storage')),
  'constraint_count', (select count(*) from pg_constraint con
    join pg_namespace n on n.oid=con.connamespace
    where n.nspname='public'),
  'buckets', (select jsonb_agg(jsonb_build_object('id', id,
    'public', public, 'file_size_limit', file_size_limit,
    'allowed_mime_types', allowed_mime_types) order by id) from storage.buckets),
  'storage_object_count', (select count(*) from storage.objects),
  'auth_user_count', (select count(*) from auth.users),
  'profile_count', (select count(*) from public.users),
  'marked_synthetic_profiles', (select count(*) from public.users
    where email like '%@example.test'),
  'linked_auth_profiles', (select count(*) from public.users u
    join auth.users a on a.id=u.auth_user_id),
  'jobs', (select jsonb_agg(jsonb_build_object('name', jobname,
    'schedule', schedule, 'active', active) order by jobname) from cron.job)
) as inspection;
rollback;
