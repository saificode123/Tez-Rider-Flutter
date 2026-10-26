begin;
-- SUPPORT_CANDIDATE
create temporary table support_results(check_name text,result text)on commit drop;
do $$begin
 if(select setting_value from public.app_settings where setting_key='support_email')is distinct from'urrehmansaif406@gmail.com'then raise exception 'Support contact not configured';end if;
 insert into support_results values('owner-authorized public email stored in one server setting row','PASS');
 if(select count(*)from public.app_settings where setting_key='support_email')<>1 then raise exception 'Duplicate setting';end if;
 insert into support_results values('unique setting permits a one-row replacement without app release','PASS');
 if has_table_privilege('anon','public.app_settings','select')or has_table_privilege('authenticated','public.app_settings','select')then raise exception 'Settings client isolation changed';end if;
 insert into support_results values('public contact does not grant access to settings or provider credentials','PASS');
 if not(select relrowsecurity from pg_class where oid='public.app_settings'::regclass)then raise exception 'RLS missing';end if;
 insert into support_results values('existing settings RLS remains enabled','PASS');
 update public.app_settings set setting_value='replacement@example.test'where setting_key='support_email';
 if(select setting_value from public.app_settings where setting_key='support_email')is distinct from'replacement@example.test'then raise exception 'Setting replacement failed';end if;
 insert into support_results values('one-row replacement verified inside rollback only; real contact preserved','PASS');
end$$;
select jsonb_agg(jsonb_build_object('check',check_name,'result',result,'surface','TEST SQL rollback'))results from support_results;
rollback;
