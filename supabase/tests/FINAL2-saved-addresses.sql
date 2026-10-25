begin;
-- FINAL2_CANDIDATE
create temporary table address_people(label text primary key,id bigint,auth_id uuid,session_id uuid,email text);
create temporary table address_results(label text);
create temporary table address_state(request uuid,edit_request uuid,delete_request uuid,id bigint);
insert into address_state values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),null);
do $$declare label text;aid uuid;uid bigint;sid uuid;mail text;begin
 foreach label in array array['customer','vendor','rider','customer2','admin']loop
  aid:=gen_random_uuid();sid:=gen_random_uuid();mail:='final2-photo-'||label||'-'||aid||'@example.test';
  insert into auth.users(id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
   values(aid,mail,now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{}');
  insert into public.users(auth_user_id,email,name,phone,role,verification_status)
   values(aid,mail,'FINAL2 PHOTO SQL ONLY','123456',case when label='customer2'then'customer'else label end,'approved')returning id into uid;
  insert into auth.sessions(id,user_id,created_at,updated_at,not_after)values(sid,aid,now(),now(),clock_timestamp()+interval '1 hour');
  insert into address_people values(label,uid,aid,sid,mail);
 end loop;
end$$;

create function pg_temp.address_claim(who text)returns void language plpgsql security definer as $$declare p address_people;begin
 select *into p from address_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id,
 'email',p.email,'exp',extract(epoch from clock_timestamp()+interval '1 hour')::bigint)::text,true);end$$;
create function pg_temp.address_ok(v boolean,label text)returns void language plpgsql security definer as $$begin
 if v is distinct from true then raise exception 'Photo assertion: %',label;end if;insert into address_results values(label);end$$;
grant execute on function pg_temp.address_claim(text),pg_temp.address_ok(boolean,text)to authenticated,anon;
grant select on address_people,address_state to authenticated;


grant all on address_state to authenticated;
set local role authenticated;
select pg_temp.address_claim('customer');
do $$declare r jsonb;begin
 r:=public.final2_change_address((select request from address_state),'create',null,null,'Home','SQL SYNTHETIC ADDRESS');
 update address_state set id=(r->>'address_id')::bigint;
 perform pg_temp.address_ok(r->>'code'='APPLIED'and(r->>'changed')::boolean,'owned real address create confirmed');
 r:=public.final2_change_address((select request from address_state),'create',null,null,'Home','SQL SYNTHETIC ADDRESS');
 perform pg_temp.address_ok(r->>'code'='ALREADY_APPLIED'and(r->>'address_id')::bigint=(select id from address_state),'same create retry cannot duplicate address');
 begin perform public.final2_change_address((select request from address_state),'create',null,null,'Other','SQL SYNTHETIC ADDRESS');raise exception 'unexpected allow';exception when sqlstate 'PT409'then perform pg_temp.address_ok(true,'changed UUID create payload conflicts');end;
 r:=public.final2_change_address((select edit_request from address_state),'edit',(select id from address_state),0,'Work','SQL EDITED ADDRESS');
 perform pg_temp.address_ok(r->>'code'='APPLIED'and(public.final2_saved_addresses()#>>'{items,0,revision}')::bigint=1,'owned edit increments revision and persists label');
 begin perform public.final2_change_address(gen_random_uuid(),'edit',(select id from address_state),0,'Stale','Stale Address');raise exception 'unexpected allow';exception when sqlstate 'PT409'then perform pg_temp.address_ok(true,'stale revision cannot overwrite current address');end;
 r:=public.final2_change_address(gen_random_uuid(),'edit',(select id from address_state),1,'Work','SQL EDITED ADDRESS');
 perform pg_temp.address_ok(not(r->>'changed')::boolean,'unchanged edit is explicitly classified as no change');
 perform public.final2_change_address(gen_random_uuid(),'create',null,null,'Second','SQL SECOND ADDRESS');
 r:=public.final2_saved_addresses(p_limit=>1);
 perform pg_temp.address_ok(jsonb_array_length(r->'items')=1 and(r->>'has_more')::boolean,'bounded address page discloses continuation');
 r:=public.final2_saved_addresses((r->>'cursor')::bigint,1);
 perform pg_temp.address_ok(jsonb_array_length(r->'items')=1 and not(r->>'has_more')::boolean,'cursor returns remaining owned address exactly once');
 begin perform public.final2_change_address(gen_random_uuid(),'create',null,null,'','Address');raise exception 'unexpected allow';exception when invalid_parameter_value then perform pg_temp.address_ok(true,'empty label rejected on server');end;
 begin perform public.final2_change_address(gen_random_uuid(),'create',null,null,'Label',repeat('x',2001));raise exception 'unexpected allow';exception when invalid_parameter_value then perform pg_temp.address_ok(true,'oversize address rejected on server');end;
 begin delete from public.addresses where id=(select id from address_state);raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.address_ok(true,'direct delete cannot bypass owner RPC');end;
 begin perform 1 from final2_private.address_receipts;raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.address_ok(true,'private address receipts are not client readable');end;
end$$;
select pg_temp.address_claim('customer2');
select pg_temp.address_ok(jsonb_array_length(public.final2_saved_addresses()->'items')=0,'unrelated Customer cannot list private addresses');
do $$begin
 begin perform public.final2_change_address(gen_random_uuid(),'edit',(select id from address_state),1,'Attack','Other Address');raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.address_ok(true,'unrelated Customer edit denied');end;
 begin perform public.final2_change_address(gen_random_uuid(),'delete',(select id from address_state),1);raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.address_ok(true,'unrelated Customer delete denied');end;
end$$;
select pg_temp.address_claim('vendor');
do $$begin begin perform public.final2_saved_addresses();raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.address_ok(true,'Vendor owner-address read denied');end;end$$;
select pg_temp.address_claim('rider');
do $$begin begin perform public.final2_change_address(gen_random_uuid(),'create',null,null,'Bad','Bad Address');raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.address_ok(true,'Rider owner-address mutation denied');end;end$$;
select pg_temp.address_claim('admin');
do $$begin begin perform public.final2_change_address(gen_random_uuid(),'delete',(select id from address_state),1);raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.address_ok(true,'Admin cannot impersonate Customer address deletion');end;end$$;
select pg_temp.address_claim('customer');
do $$declare r jsonb;begin
 r:=public.final2_change_address((select delete_request from address_state),'delete',(select id from address_state),1);
 perform pg_temp.address_ok(r->>'code'='APPLIED','owned confirmed address delete succeeds');
 r:=public.final2_change_address((select delete_request from address_state),'delete',(select id from address_state),1);
 perform pg_temp.address_ok(r->>'code'='ALREADY_APPLIED','delete response-loss retry confirms original removal');
 perform pg_temp.address_ok(not exists(select 1 from jsonb_array_elements(public.final2_saved_addresses()->'items')x where(x->>'id')::bigint=(select id from address_state)),'deleted address is absent from owned projection');
end$$;
reset role;
select pg_temp.address_ok(not exists(select 1 from public.addresses where id=(select id from address_state)),'deleted address absent in privileged persistence read');
select pg_temp.address_ok((select count(*)from public.security_audit_log where actor_id=(select id from address_people where label='customer')and target_type='addresses'and target_id=(select id from address_state))=3,'create/edit/delete record exactly three canonical audits; retries and no-op edit add none');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where id=(select id from address_people where label='customer');
set local role authenticated;
select pg_temp.address_claim('customer');
do $$begin begin perform public.final2_saved_addresses();raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.address_ok(true,'blocked account private addresses denied');end;end$$;
reset role;
delete from auth.sessions where id=(select session_id from address_people where label='customer2');
set local role authenticated;
select pg_temp.address_claim('customer2');
do $$begin begin perform public.final2_saved_addresses();raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.address_ok(true,'revoked session private addresses denied');end;end$$;
reset role;
set local role anon;
do $$begin begin perform public.final2_saved_addresses();raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.address_ok(true,'anonymous private addresses denied');end;end$$;
reset role;
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated SQL rollback fixture'))as results from address_results;
rollback;
