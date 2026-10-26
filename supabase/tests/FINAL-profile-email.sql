-- Synthetic Auth/profile/session states only. Everything rolls back; no mail is sent.
begin;
-- FINAL_EMAIL_CANDIDATE
create temporary table email_people(label text,id bigint,auth_id uuid,session_id uuid,original_email text);
create temporary table email_results(label text,result text);
grant select on email_people to authenticated;
grant insert,select on email_results to authenticated;
create function pg_temp.email_ok(value boolean,label text)returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'Email assertion failed: %',label;end if;
 insert into email_results values(label,'PASS');end$$;
do $$declare role_name text;aid uuid;sid uuid;uid bigint;address text;begin
 foreach role_name in array array['customer','vendor','rider','admin']loop
  aid:=gen_random_uuid();sid:=gen_random_uuid();address:='email-sql-'||aid||'@example.test';
  insert into auth.users(id,instance_id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
   values(aid,'00000000-0000-0000-0000-000000000000',address,clock_timestamp(),'authenticated','authenticated',
    '{"provider":"email","providers":["email"]}','{"email_fixture":true}');
  insert into public.users(email,name,phone,role,verification_status)
   values(address,'Email SQL synthetic','12345',role_name,'approved')returning id into uid;
  insert into auth.sessions(id,user_id,created_at,updated_at)values(sid,aid,clock_timestamp(),clock_timestamp());
  insert into email_people values(role_name,uid,aid,sid,address);
 end loop;
end$$;
select pg_temp.email_ok(not has_function_privilege('authenticated','final_delivery_private.sync_verified_auth_email()','EXECUTE')
 and not has_function_privilege('service_role','final_delivery_private.sync_verified_auth_email()','EXECUTE'),'private Auth sync is trigger-only and not callable by clients or raw service API');

do $$declare p email_people;s jsonb;next_email text;before_audits bigint;begin
 for p in select *from email_people loop
  next_email:='confirmed-'||p.auth_id||'@example.test';
  update auth.users set email_change=next_email where id=p.auth_id;
  perform pg_temp.email_ok((select email=p.original_email from public.users where id=p.id),p.label||' pending Auth email never changes canonical profile');
  perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',p.auth_id,'session_id',p.session_id,'email',p.original_email)::text,true);
  s:=public.final_delivery_email_status();
  perform pg_temp.email_ok(s->>'code'='OK'and s->>'account'=p.auth_id::text and s->>'email'=p.original_email
   and s->>'pending_email'=next_email and(s->>'verified')::boolean,p.label||' live own status distinguishes verified original and pending target');
  select count(*)into before_audits from public.security_audit_log where actor_id=p.id and action='profile_email_confirmed';
  update auth.users set email=next_email,email_change='',email_confirmed_at=clock_timestamp()where id=p.auth_id;
  perform pg_temp.email_ok((select email=next_email and name='Email SQL synthetic'and phone='12345'and role=p.label and verification_status='approved'from public.users where id=p.id),p.label||' only verified Auth change syncs email while preserving all accepted profile fields and authorization');
  s:=public.final_delivery_email_status();
  perform pg_temp.email_ok(s->>'code'='OK'and s->>'email'=next_email and s->'pending_email'='null'::jsonb,p.label||' confirmed status reads canonical persisted email rather than trusting request acceptance');
  update auth.users set email=email,email_confirmed_at=email_confirmed_at where id=p.auth_id;
  perform pg_temp.email_ok((select count(*)=before_audits+1 from public.security_audit_log where actor_id=p.id and action='profile_email_confirmed'),p.label||' unchanged Auth retries add no duplicate confirmation audit');
 end loop;
end$$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$declare p email_people;next_email text;begin
 select *into p from email_people where label='customer';next_email:='unverified-'||p.auth_id||'@example.test';
 update auth.users set email=next_email,email_confirmed_at=null where id=p.auth_id;
 perform pg_temp.email_ok((select email<>next_email from public.users where id=p.id),'unverified Auth field edit cannot overwrite canonical verified profile email');
 update auth.users set email_confirmed_at=clock_timestamp()where id=p.auth_id;
 perform pg_temp.email_ok((select email=next_email from public.users where id=p.id),'a later actual confirmation timestamp syncs its confirmed address');
end$$;
select set_config('request.jwt.claims',(select jsonb_build_object('role','authenticated','sub',auth_id,'session_id',session_id,'email',original_email)::text from email_people where label='customer'),true);
set local role authenticated;
do $$begin
 begin update public.users set email='forged@example.test'where id=(select id from email_people where label='customer');raise exception 'Direct email write allowed';exception when insufficient_privilege then null;end;
 perform pg_temp.email_ok(true,'ordinary client cannot bypass Auth confirmation with a direct profile email UPDATE');
 begin perform final_delivery_private.sync_verified_auth_email();raise exception 'Private sync allowed';exception when insufficient_privilege then null;end;
 perform pg_temp.email_ok(true,'ordinary client cannot directly invoke private sync trigger');
end$$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where id=(select id from email_people where label='customer');
select set_config('request.jwt.claims',(select jsonb_build_object('role','authenticated','sub',auth_id,'session_id',session_id)::text from email_people where label='customer'),true);
set local role authenticated;
do $$begin
 begin perform public.final_delivery_email_status();raise exception 'Blocked status allowed';exception when insufficient_privilege then null;end;
 perform pg_temp.email_ok(true,'blocked profile cannot request private email status');
end$$;
reset role;
set local role anon;
do $$begin
 begin perform public.final_delivery_email_status();raise exception 'Anonymous status allowed';exception when insufficient_privilege then null;end;
end$$;
reset role;
select pg_temp.email_ok(true,'anonymous email status access denied');
select jsonb_agg(jsonb_build_object('check',label,'result',result,'surface','synthetic authenticated TEST SQL rollback'))as results from email_results;
rollback;
