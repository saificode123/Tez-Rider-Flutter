-- LOCAL ONLY. Applied by FR-32-load.py through the named local Docker container.
-- Never include this file in Supabase migrations or hosted deployment.
begin;
do $$begin if current_setting('fr32.local_test',true)is distinct from'true'then raise exception 'Explicit unlinked LOCAL runner required';end if;end$$;
create schema if not exists fr32_load;
revoke all on schema fr32_load from public,anon,authenticated,service_role;
create table if not exists fr32_load.fixture(singleton boolean primary key check(singleton),user_id bigint,run_prefix text,old_configuration jsonb);
do $$declare aid uuid:=gen_random_uuid();uid bigint;prefix text:=replace(gen_random_uuid()::text,'-','');begin
 if exists(select 1 from fr32_load.fixture)then raise exception 'Finish/clean previous LOCAL load run first';end if;
 if exists(select 1 from public.email_outbox where status in('pending','sending','deferred')and(test_approved or email_type='paid_invoice'))then raise exception 'Unrelated LOCAL active queue must be preserved; use a clean approved fixture state';end if;
 insert into auth.users(id,email,email_confirmed_at,role,aud)values(aid,'fr32-load-'||prefix||'@example.test',now(),'authenticated','authenticated');
 insert into public.users(email,name,role,verification_status)values('fr32-load-'||prefix||'@example.test','FR32 LOCAL LOAD SYNTHETIC','customer','approved')returning id into uid;
 insert into fr32_load.fixture select true,uid,prefix,to_jsonb(c)from fr32_private.configuration c;
 update fr32_private.configuration set quota_mode='rolling_26h',daily_budget=10,otp_reserve=3,dispatch_enabled=false;
end$$;
create or replace function public.fr32_load_enqueue(p_key text)returns uuid language plpgsql security definer set search_path=''as $$declare f fr32_load.fixture;j uuid;begin
 perform fr32_private.server_only();select *into strict f from fr32_load.fixture;
 if p_key is null or p_key!~'^[A-Za-z0-9_-]{1,100}$'or p_key not like f.run_prefix||'-%'then raise exception 'Current synthetic LOCAL run required';end if;
 j:=fr32_private.enqueue('order_confirmation',f.user_id,'local_load','1','local-load:'||p_key,jsonb_build_object('local_run',f.run_prefix));
 update public.email_outbox set test_approved=true where id=j;return j;
end$$;
create or replace function public.fr32_load_stats()returns jsonb language plpgsql security definer set search_path=''as $$declare f fr32_load.fixture;result jsonb;begin
 perform fr32_private.server_only();select *into strict f from fr32_load.fixture;
 select jsonb_build_object('jobs',count(*),'due',count(*)filter(where status in('pending','deferred')and next_attempt_at<=clock_timestamp()),'sending',count(*)filter(where status='sending'),
 'deferred',count(*)filter(where status='deferred'),'retry_at',min(next_attempt_at)filter(where status='deferred'and last_error='PROVIDER_RATE_LIMIT'),
 'duplicates',count(*)-count(distinct dedupe_key))into result from public.email_outbox where payload->>'local_run'=f.run_prefix;
 return result||jsonb_build_object('active_quota',(select coalesce(sum(units),0)from fr32_private.quota_reservations where expires_at>clock_timestamp()),
 'transactional_quota',(select coalesce(sum(units),0)from fr32_private.quota_reservations where kind='transactional'and expires_at>clock_timestamp()),
 'budget',(select daily_budget from fr32_private.configuration),'otp_reserve',(select otp_reserve from fr32_private.configuration));
end$$;
create or replace function public.fr32_load_recover()returns jsonb language plpgsql security definer set search_path=''as $$declare f fr32_load.fixture;j uuid;first_job jsonb;recovered jsonb;begin
 perform fr32_private.server_only();select *into strict f from fr32_load.fixture;
 j:=public.fr32_load_enqueue(f.run_prefix||'-recovery');update public.email_outbox set priority=-100 where id=j;
 select *into first_job from fr32_private.claim(1);
 if first_job->>'id'<>j::text then raise exception 'Synthetic recovery row not claimed';end if;
 update public.email_outbox set lease_expires_at=clock_timestamp()-interval'1 second'where id=j;
 select *into recovered from fr32_private.claim(1);
 if recovered->>'id'<>j::text or recovered->>'lease'=first_job->>'lease'then raise exception 'Lease not recovered with a new token';end if;
 perform public.fr32_finish_email(j,(recovered->>'lease')::uuid,'prepare_retry',null,30,'LOCAL_RECOVERY_TEST');
 return jsonb_build_object('recovered',true);
end$$;
revoke all on function public.fr32_load_enqueue(text),public.fr32_load_stats(),public.fr32_load_recover()from public,anon,authenticated;
grant execute on function public.fr32_load_enqueue(text),public.fr32_load_stats(),public.fr32_load_recover()to service_role;
notify pgrst,'reload schema';
commit;
