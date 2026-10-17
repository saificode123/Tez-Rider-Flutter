-- Read-only metadata; never select recipient addresses, Vault values or cron commands.
select jsonb_build_object(
 'versions',(select jsonb_agg(version order by version)from supabase_migrations.schema_migrations),
 'columns',(select jsonb_agg(jsonb_build_object('table',table_name,'name',column_name,'type',data_type))from information_schema.columns where table_schema='public'and table_name in('users','orders','vendor_orders','order_items','payments','security_audit_log','fr28_operations','delivery_otps','delivery_otp_budgets')),
 'policies',(select jsonb_agg(jsonb_build_object('schema',schemaname,'table',tablename,'name',policyname,'command',cmd,'using',qual,'check',with_check))from pg_policies where(schemaname='public'and tablename in('payments','order_items','orders','users'))or(schemaname='storage'and tablename='objects')),
 'grants',(select jsonb_agg(jsonb_build_object('role',grantee,'table',table_name,'privilege',privilege_type))from information_schema.role_table_grants where table_schema='public'and table_name in('payments','order_items','orders','users')and grantee in('PUBLIC','anon','authenticated','service_role')),
 'triggers',(select jsonb_agg(jsonb_build_object('table',event_object_table,'name',trigger_name,'event',event_manipulation,'timing',action_timing,'function',action_statement))from information_schema.triggers where event_object_schema='public'and event_object_table in('payments','orders','users','security_audit_log','fr28_operations')),
 'extensions',(select jsonb_agg(extname)from pg_extension where extname in('pg_cron','pg_net','pgcrypto','supabase_vault')),
 'jobs',(select jsonb_agg(jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'active',active))from cron.job),
 'buckets',(select jsonb_agg(jsonb_build_object('id',id,'public',public,'limit',file_size_limit))from storage.buckets),
 'invoice_url_count',(select count(*)from public.payments where invoiceurl is not null),
 'payment_status_counts',(select jsonb_agg(x)from(select status,count(*)from public.payments group by status)x),
 'existing_email_objects',(select jsonb_agg(table_schema||'.'||table_name)from information_schema.tables where table_name in('email_outbox','invoices'))
)as inspection;
