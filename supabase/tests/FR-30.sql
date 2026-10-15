-- All fan-out is rolled back: no unrelated TEST recipient receives a message.
begin;
create temp table fr30_results(name text,result text);
create function pg_temp.ok(value boolean,label text)returns void language plpgsql security definer as $$begin
 if value is distinct from true then raise exception 'FR30 assertion failed: %',label;end if;
 insert into fr30_results values(label,'PASS');end$$;
create temp table fr30_people(label text,id bigint,auth_id uuid,session_id uuid,email text);
do $$declare who text;aid uuid;uid bigint;sid uuid;email text;begin
 foreach who in array array['admin','other-admin','customer','vendor','rider','blocked']loop
  aid:=gen_random_uuid();sid:=gen_random_uuid();email:='fr30-sql-'||aid||'@example.test';
  insert into auth.users(id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
  values(aid,email,now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{"fr30_fixture":true}');
  insert into public.users(email,name,role,verification_status,is_blocked)values(email,'FR30 SQL SYNTHETIC',case when who='other-admin'then 'admin'when who='blocked'then 'customer'else who end,'approved',who='blocked')returning id into uid;
  insert into auth.sessions(id,user_id,created_at,updated_at)values(sid,aid,now(),now());
  insert into fr30_people values(who,uid,aid,sid,email);
 end loop;
end$$;
create function pg_temp.claim(label text)returns void language plpgsql security definer as $$declare p fr30_people;begin
 select * into p from fr30_people where fr30_people.label=claim.label;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id,'email',p.email)::text,true);
end$$;
grant execute on function pg_temp.ok(boolean,text),pg_temp.claim(text)to authenticated,anon;
grant select on fr30_people to authenticated;
do $$declare who text;res jsonb;begin
 foreach who in array array['customer','vendor','rider','blocked']loop
  perform pg_temp.claim(who);res:=public.admin_send_broadcast(gen_random_uuid(),'title','message','ALL');perform pg_temp.ok(res->>'code'='FORBIDDEN',who||' send denied');
 end loop;
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 update public.users set is_blocked=true where id=(select id from fr30_people where label='other-admin');
 perform pg_temp.claim('other-admin');res:=public.admin_send_broadcast(gen_random_uuid(),'title','message','ALL');perform pg_temp.ok(res->>'code'='FORBIDDEN','blocked administrator denied');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 update public.users set is_blocked=false,verification_status='pending'where id=(select id from fr30_people where label='other-admin');
 perform pg_temp.claim('other-admin');res:=public.admin_send_broadcast(gen_random_uuid(),'title','message','ALL');perform pg_temp.ok(res->>'code'='FORBIDDEN','unapproved administrator denied');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 update public.users set verification_status='approved'where id=(select id from fr30_people where label='other-admin');
end$$;
select pg_temp.claim('admin');
do $$declare res jsonb;aud text;bid uuid;expected bigint;row_id bigint;begin
 foreach aud in array array['ALL','CUSTOMERS','VENDORS','RIDERS']loop
  update fr30_private.limits set cooldown_seconds=0;
  expected:=public.fr30_estimate(aud);bid:=gen_random_uuid();
  res:=public.admin_send_broadcast(bid,' Title ',' <script>alert(1)</script> ',aud);
  perform pg_temp.ok(res->>'code'='SENT',aud||' accepted');
  perform pg_temp.ok((res->>'recipient_count')::bigint=expected,aud||' estimate and committed count');
  perform pg_temp.ok((select count(*)from public.notifications where broadcast_id=bid)=expected,aud||' snapshot count');
  perform pg_temp.ok(not exists(select 1 from public.notifications where broadcast_id=bid and user_id=(select id from fr30_people where label='blocked')),aud||' blocked recipient excluded');
  perform pg_temp.ok((select message='<script>alert(1)</script>'from public.admin_broadcasts where id=bid),'HTML-like input literal plain text');
  res:=public.admin_send_broadcast(bid,'Title','<script>alert(1)</script>',aud);perform pg_temp.ok(res->>'code'='ALREADY_SENT','trimmed replay');
  res:=public.admin_send_broadcast(bid,'different','<script>alert(1)</script>',aud);perform pg_temp.ok(res->>'code'='IDEMPOTENCY_CONFLICT','changed payload conflict');
  perform pg_temp.ok((select count(*)from public.security_audit_log where broadcast_id=bid and action='SEND_BROADCAST')=1,'audit exactly once');
  perform pg_temp.ok((select a.actor_id=b.sender_id and a.target_id=b.audit_number from public.security_audit_log a join public.admin_broadcasts b on b.id=a.broadcast_id where b.id=bid),'trusted audit UUID relation');
 end loop;
 update fr30_private.limits set cooldown_seconds=60;
 res:=public.admin_send_broadcast(gen_random_uuid(),'Title','Message','ALL');perform pg_temp.ok(res->>'code'='COOLDOWN','cooldown enforced');
 update fr30_private.limits set cooldown_seconds=0,daily_max=4;
 res:=public.admin_send_broadcast(gen_random_uuid(),'Title','Message','ALL');perform pg_temp.ok(res->>'code'='DAILY_LIMIT','rolling daily limit enforced');
 update fr30_private.limits set daily_max=10;
 res:=public.admin_send_broadcast(gen_random_uuid(),'','Message','ALL');perform pg_temp.ok(res->>'code'='INVALID_INPUT','empty title');
 res:=public.admin_send_broadcast(gen_random_uuid(),'Title','  ','ALL');perform pg_temp.ok(res->>'code'='INVALID_INPUT','empty message');
  res:=public.admin_send_broadcast(gen_random_uuid(),E'\n\t','Message','ALL');perform pg_temp.ok(res->>'code'='INVALID_INPUT','whitespace title');
 res:=public.admin_send_broadcast(gen_random_uuid(),repeat('x',101),'Message','ALL');perform pg_temp.ok(res->>'code'='INVALID_INPUT','oversized title');
 res:=public.admin_send_broadcast(gen_random_uuid(),'Title',repeat('x',1001),'ALL');perform pg_temp.ok(res->>'code'='INVALID_INPUT','oversized message');
 res:=public.admin_send_broadcast(gen_random_uuid(),'Title','Message','ADMINS');perform pg_temp.ok(res->>'code'='INVALID_INPUT','invalid audience');
 res:=public.admin_send_broadcast(null,'Title','Message','ALL');perform pg_temp.ok(res->>'code'='INVALID_INPUT','null key');
 select id into bid from public.admin_broadcasts where sender_id=(select id from fr30_people where label='admin')and audience='CUSTOMERS';
 perform pg_temp.claim('other-admin');res:=public.admin_send_broadcast(bid,'Title','<script>alert(1)</script>','CUSTOMERS');perform pg_temp.ok(res->>'code'='IDEMPOTENCY_CONFLICT','key bound to actor');
 -- Role changes cannot create new historical recipients.
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 update public.users set role='customer'where id=(select id from fr30_people where label='vendor');
 perform pg_temp.ok(not exists(select 1 from public.notifications where broadcast_id=bid and user_id=(select id from fr30_people where label='vendor')),'later role join cannot see old targeted broadcast');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 update public.users set role='vendor'where id=(select id from fr30_people where label='customer');
 perform pg_temp.ok(exists(select 1 from public.notifications where broadcast_id=bid and user_id=(select id from fr30_people where label='customer')),'original send-time snapshot retained');
 perform pg_temp.claim('customer');
end$$;
set local role authenticated;
do $$declare n bigint;begin
 perform pg_temp.ok((select count(*)from public.admin_broadcasts)=0,'ordinary history hidden');
 perform pg_temp.ok(not exists(select 1 from public.notifications where user_id<>(select id from fr30_people where label='customer')),'own notifications only');
 update public.notifications set is_read=true where user_id<>(select id from fr30_people where label='customer');get diagnostics n=row_count;perform pg_temp.ok(n=0,'cross-user read state denied');
 update public.notifications set is_read=true where broadcast_id is not null;get diagnostics n=row_count;perform pg_temp.ok(n=2,'own mark read works');
 begin insert into public.notifications(user_id,title,message)values(1,'forged','forged');raise exception 'insert permitted';exception when insufficient_privilege then perform pg_temp.ok(true,'notification forgery denied');end;
 begin insert into public.admin_broadcasts(id,sender_id,title,message,audience,recipient_count)values(gen_random_uuid(),1,'forged','forged','ALL',0);raise exception 'insert permitted';exception when insufficient_privilege then perform pg_temp.ok(true,'broadcast forgery denied');end;
 begin insert into public.security_audit_log(action,target_type,target_id)values('SEND_BROADCAST','broadcast',1);raise exception 'insert permitted';exception when insufficient_privilege then perform pg_temp.ok(true,'audit forgery denied');end;
end$$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where id=(select id from fr30_people where label='customer');
select pg_temp.claim('customer');
set local role authenticated;
select pg_temp.ok((select count(*)from public.notifications)=0,'blocked after send protected');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=false where id=(select id from fr30_people where label='customer');
select pg_temp.claim('customer');
set local role authenticated;
select pg_temp.ok((select count(*)from public.notifications where broadcast_id is not null)=2,'reconnect authoritative snapshot visible');
reset role;
-- Zero recipient test uses rollback-only temporary block flags; no live block sessions altered.
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where role='rider';
select pg_temp.claim('other-admin');
do $$declare res jsonb;begin
 res:=public.admin_send_broadcast(gen_random_uuid(),'Zero','Nobody','RIDERS');perform pg_temp.ok(res->>'code'='SENT'and(res->>'recipient_count')::bigint=0,'zero audience commits truthful count');
end$$;
set local role anon;
do $$begin
 begin perform public.admin_send_broadcast(gen_random_uuid(),'a','b','ALL');raise exception 'anon permitted';exception when insufficient_privilege then perform pg_temp.ok(true,'anonymous execute denied');end;
end$$;
reset role;
select jsonb_agg(jsonb_build_object('name',name,'result',result))as results from fr30_results;
rollback;
