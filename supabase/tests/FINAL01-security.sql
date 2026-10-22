-- Metadata and pure-boundary checks only: no hosted user/order fixtures or deletes.
begin;
do $$begin if current_setting('final01.test_project_ref',true)is distinct from 'igeisilhtmglgnqvllrx'then raise exception 'TEST marker required';end if;end$$;
select jsonb_agg(jsonb_build_object('check',label,'result',case when passed then 'PASS'else'FAIL'end))as results from(values
 ('deadline absolute168hours',final1_private.session_deadline('2026-10-22T00:00Z',null)='2026-10-29T00:00Z'::timestamptz),
 ('earlier provider not_after retained',final1_private.session_deadline('2026-10-22T00:00Z','2026-10-23T00:00Z')='2026-10-23T00:00Z'::timestamptz),
 ('later provider bound cannot extend deadline',final1_private.session_deadline('2026-10-22T00:00Z','2026-12-23T00:00Z')='2026-10-29T00:00Z'::timestamptz),
 ('missing created_at fails closed',final1_private.session_deadline(null,'2026-12-23T00:00Z')is null),
 ('expired deadline recognized',final1_private.session_deadline(now()-interval '169 hours',null)<now()),
 ('boundary deadline equals expiry',final1_private.session_deadline(now()-interval '168 hours',null)=now()),
 ('fresh deadline remains valid',final1_private.session_deadline(now(),null)>now()),
 ('new request counter RLS', (select relrowsecurity from pg_class where oid='final1_private.request_limits'::regclass)),
 ('new private proof key RLS',(select relrowsecurity from pg_class where oid='final1_private.gateway_key'::regclass)),
 ('new failure limiter RLS',(select relrowsecurity from pg_class where oid='final1_private.failure_limits'::regclass)),
 ('private schema client denied',not has_schema_privilege('authenticated','final1_private','USAGE')and not has_schema_privilege('anon','final1_private','USAGE')),
 ('counter client write denied',not has_table_privilege('authenticated','final1_private.request_limits','UPDATE')and not has_table_privilege('authenticated','final1_private.request_limits','INSERT')),
 ('proof material client read denied',not has_table_privilege('authenticated','final1_private.gateway_key','SELECT')and not has_table_privilege('anon','final1_private.gateway_key','SELECT')),
 ('only authenticated can claim',has_function_privilege('authenticated','public.final01_authorize_request()','EXECUTE')and not has_function_privilege('anon','public.final01_authorize_request()','EXECUTE')),
 ('client cannot mint proof',not has_function_privilege('authenticated','public.final01_request_ticket(uuid,uuid,text,text)','EXECUTE')and not has_function_privilege('anon','public.final01_request_ticket(uuid,uuid,text,text)','EXECUTE')),
 ('trusted server may mint proof',has_function_privilege('service_role','public.final01_request_ticket(uuid,uuid,text,text)','EXECUTE')),
 ('client cannot forge failure audit',not has_function_privilege('authenticated','public.final01_record_failure(uuid,text,text)','EXECUTE')and not has_function_privilege('anon','public.final01_record_failure(uuid,text,text)','EXECUTE')),
 ('trusted server may record classified failure',has_function_privilege('service_role','public.final01_record_failure(uuid,text,text)','EXECUTE')),
 ('audit direct writes still denied',not has_table_privilege('authenticated','public.security_audit_log','INSERT')and not has_table_privilege('authenticated','public.security_audit_log','UPDATE')and not has_table_privilege('authenticated','public.security_audit_log','DELETE')),
 ('all inspected tables retain RLS',not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in('r','p')and(n.nspname='public'or n.nspname like '%private'or(n.nspname='storage'and c.relname in('objects','buckets'))or(n.nspname='realtime'and c.relname='messages'))and not c.relrowsecurity)),
 ('new definer paths fixed',not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and p.proname like 'final01_%'and(p.proconfig is null or not 'search_path=""'=any(p.proconfig)))),
 ('counter cap checked',exists(select 1 from pg_constraint where conrelid='final1_private.request_limits'::regclass and contype='c'and pg_get_constraintdef(oid)like '%100%')),
 ('proof key unique fixed row',exists(select 1 from pg_constraint where conrelid='final1_private.gateway_key'::regclass and contype='p')),
 ('activation state matches review',case when current_setting('final01.activation',true)='true'then exists(select 1 from pg_proc where oid='public.fr28_pre_request()'::regprocedure and prosrc like '%APPLICATION_GATEWAY_REQUIRED%')else not exists(select 1 from pg_proc where oid='public.fr28_pre_request()'::regprocedure and prosrc like '%APPLICATION_GATEWAY_REQUIRED%')end),
 ('retention restricted to new namespace',exists(select 1 from pg_proc where oid='public.final01_record_failure(uuid,text,text)'::regprocedure and prosrc like '%final01_api_authentication%'and prosrc like '%30 days%'))
)as checks(label,passed);
rollback;
