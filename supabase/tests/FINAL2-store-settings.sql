begin;
-- FINAL2_CANDIDATE
create temporary table store_people(label text primary key,id bigint,auth_id uuid,session_id uuid,email text);
create temporary table store_results(label text);
create temporary table store_state(request uuid);
insert into store_state values(gen_random_uuid());
do $$declare label text;aid uuid;uid bigint;sid uuid;mail text;begin
 foreach label in array array['customer','vendor','rider','vendor2','admin']loop
  aid:=gen_random_uuid();sid:=gen_random_uuid();mail:='final2-photo-'||label||'-'||aid||'@example.test';
  insert into auth.users(id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
   values(aid,mail,now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{}');
  insert into public.users(auth_user_id,email,name,phone,role,verification_status)
   values(aid,mail,'FINAL2 PHOTO SQL ONLY','123456',case when label='vendor2'then'vendor'else label end,'approved')returning id into uid;
  insert into auth.sessions(id,user_id,created_at,updated_at,not_after)values(sid,aid,now(),now(),clock_timestamp()+interval '1 hour');
  insert into store_people values(label,uid,aid,sid,mail);
 end loop;
end$$;

create function pg_temp.store_claim(who text)returns void language plpgsql security definer as $$declare p store_people;begin
 select *into p from store_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id,
 'email',p.email,'exp',extract(epoch from clock_timestamp()+interval '1 hour')::bigint)::text,true);end$$;
create function pg_temp.store_ok(v boolean,label text)returns void language plpgsql security definer as $$begin
 if v is distinct from true then raise exception 'Photo assertion: %',label;end if;insert into store_results values(label);end$$;
grant execute on function pg_temp.store_claim(text),pg_temp.store_ok(boolean,text)to authenticated,anon;
grant select on store_people,store_state to authenticated;

insert into public.vendors(user_id,store_name,address,is_active)select id,'SQL STORE','SQL SYNTHETIC ADDRESS',false from store_people where label in('vendor','vendor2');
set local role authenticated;
select pg_temp.store_claim('vendor');
select pg_temp.store_ok(public.final2_store_settings()->>'store_name'='SQL STORE','own approved Vendor reads real store');
do $$declare r jsonb;begin
 r:=public.final2_save_store_settings((select request from store_state),0,'Updated Store','Updated Address',12.25,34.5);
 perform pg_temp.store_ok(r->>'code'='SAVED'and r#>>'{store,store_name}'='Updated Store'and(r#>>'{store,version}')::bigint=1,'owner saves validated metadata with version increment');
 perform pg_temp.store_ok(not(r#>>'{store,is_active}')::boolean,'owner save cannot activate an inactive store');
 r:=public.final2_save_store_settings((select request from store_state),0,'Updated Store','Updated Address',12.25,34.5);
 perform pg_temp.store_ok(r->>'code'='ALREADY_APPLIED'and(r#>>'{store,version}')::bigint=1,'identical request retry does not repeat update');
 begin perform public.final2_save_store_settings((select request from store_state),0,'Other','Updated Address',12.25,34.5);raise exception 'unexpected allow';exception when sqlstate 'PT409'then perform pg_temp.store_ok(true,'changed same-UUID payload denied');end;
 end$$;
do $$begin
 begin perform public.final2_save_store_settings(gen_random_uuid(),0,'Stale','Updated Address',12.25,34.5);raise exception 'unexpected allow';exception when sqlstate 'PT409'then perform pg_temp.store_ok(true,'stale independent save cannot overwrite newer store');end;
 begin perform public.final2_save_store_settings(gen_random_uuid(),1,'','Address',null,null);raise exception 'unexpected allow';exception when invalid_parameter_value then perform pg_temp.store_ok(true,'empty store name rejected server-side');end;
 begin perform public.final2_save_store_settings(gen_random_uuid(),1,'Store',repeat('x',501),null,null);raise exception 'unexpected allow';exception when invalid_parameter_value then perform pg_temp.store_ok(true,'oversize address rejected server-side');end;
 begin perform public.final2_save_store_settings(gen_random_uuid(),1,'Store','Address',1,null);raise exception 'unexpected allow';exception when invalid_parameter_value then perform pg_temp.store_ok(true,'incomplete coordinate pair rejected');end;
 begin perform public.final2_save_store_settings(gen_random_uuid(),1,'Store','Address','NaN'::double precision,2);raise exception 'unexpected allow';exception when invalid_parameter_value then perform pg_temp.store_ok(true,'nonfinite pickup coordinate rejected');end;
 begin update public.vendors set is_active=true;raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.store_ok(true,'raw vendor update denied; no direct activation bypass');end;
 begin perform 1 from final2_private.store_settings_receipts;raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.store_ok(true,'private receipts unreadable by clients');end;
 end$$;
select pg_temp.store_claim('vendor2');
select pg_temp.store_ok(public.final2_store_settings()->>'store_name'='SQL STORE','unrelated Vendor sees only own unchanged store');
select pg_temp.store_claim('customer');
do $$begin begin perform public.final2_store_settings();raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.store_ok(true,'Customer read denied');end;
 begin perform public.final2_save_store_settings(gen_random_uuid(),0,'Bad','Address',null,null);raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.store_ok(true,'Customer store mutation denied');end;end$$;
select pg_temp.store_claim('rider');
do $$begin begin perform public.final2_store_settings();raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.store_ok(true,'Rider owner-settings read denied');end;end$$;
select pg_temp.store_claim('admin');
do $$begin begin perform public.final2_save_store_settings(gen_random_uuid(),0,'Bad','Address',null,null);raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.store_ok(true,'Admin cannot impersonate owner-settings mutation');end;end$$;
reset role;
select pg_temp.store_ok((select count(*)from public.security_audit_log where actor_id=(select id from store_people where label='vendor')and action='store_settings_updated')=1,'exactly one canonical actor audit for changed store and retry');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where id=(select id from store_people where label='vendor');
set local role authenticated;
select pg_temp.store_claim('vendor');
do $$begin begin perform public.final2_store_settings();raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.store_ok(true,'blocked Vendor store access denied');end;end$$;
reset role;
delete from auth.sessions where id=(select session_id from store_people where label='vendor2');
set local role authenticated;
select pg_temp.store_claim('vendor2');
do $$begin begin perform public.final2_store_settings();raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.store_ok(true,'revoked Vendor session denied');end;end$$;
reset role;
set local role anon;
do $$begin begin perform public.final2_store_settings();raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.store_ok(true,'anonymous store settings denied');end;end$$;
reset role;
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated SQL rollback fixture'))as results from store_results;
rollback;
