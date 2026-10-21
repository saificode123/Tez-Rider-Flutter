-- Catalog only. Never select credentials, Vault values or personal records.
begin read only;
select jsonb_build_object(
 'versions',(select jsonb_agg(version order by version) from supabase_migrations.schema_migrations),
 'tables',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'rls',c.relrowsecurity,
   'policies',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from pg_policies p where p.schemaname=n.nspname and p.tablename=c.relname),
   'grants',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from information_schema.role_table_grants g where g.table_schema=n.nspname and g.table_name=c.relname),
   'columns',(select coalesce(jsonb_agg(to_jsonb(g)),'[]') from information_schema.column_privileges g where g.table_schema=n.nspname and g.table_name=c.relname and g.grantee in('anon','authenticated') and g.privilege_type in('UPDATE','INSERT'))))
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in('r','p') and (n.nspname='public' or n.nspname like '%private' or(n.nspname='storage' and c.relname in('objects','buckets'))or(n.nspname='realtime' and c.relname='messages'))),
 'functions',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'signature',pg_get_function_identity_arguments(p.oid),
   'definer',p.prosecdef,'owner',pg_get_userbyid(p.proowner),'config',p.proconfig,'acl',p.proacl::text,'definition',pg_get_functiondef(p.oid),
   'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE')))
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.prokind='f' and(n.nspname='public' or n.nspname like '%private')),
 'schemas',(select jsonb_agg(jsonb_build_object('schema',nspname,'acl',nspacl::text,'anon_usage',has_schema_privilege('anon',oid,'USAGE'),'authenticated_usage',has_schema_privilege('authenticated',oid,'USAGE'))) from pg_namespace where nspname='public' or nspname like '%private'),
 'publication',(select jsonb_agg(jsonb_build_object('publication',pubname,'schema',schemaname,'table',tablename)) from pg_publication_tables where pubname='supabase_realtime'),
 'buckets',(select jsonb_agg(jsonb_build_object('name',name,'public',public,'max_bytes',file_size_limit,'mime',allowed_mime_types)) from storage.buckets),
 'triggers',(select jsonb_agg(to_jsonb(t)) from information_schema.triggers t where trigger_schema='public'),
 'pre_request',(select jsonb_agg(setting) from pg_db_role_setting s cross join unnest(s.setconfig) setting where setting like 'pgrst.db_pre_request=%'),
 'synthetic_auth',(select jsonb_build_object('password_hash_present',bool_and(coalesce(length(encrypted_password),0)>0),
   'bcrypt_format',bool_and(left(encrypted_password,3)in('$2a','$2b','$2y')))
   from auth.users where email in('fr28-customer@example.test','fr28-vendor@example.test','fr28-rider@example.test','fr28-admin@example.test')),
 'synthetic_session_bounds',(select jsonb_build_object('sessions',count(*),'without_not_after',count(*)filter(where s.not_after is null))
   from auth.sessions s join auth.users u on u.id=s.user_id where u.email in('fr28-customer@example.test','fr28-vendor@example.test','fr28-rider@example.test','fr28-admin@example.test'))
) as inspection;
rollback;
