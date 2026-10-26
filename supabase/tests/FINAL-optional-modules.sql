begin;
-- OPTIONAL_CANDIDATE
create temporary table optional_people(label text primary key,id bigint,auth_id uuid,session_id uuid,email text);
create temporary table optional_results(label text);
create temporary table optional_state(oid bigint,vid bigint,pid bigint,tid bigint,image uuid default gen_random_uuid(),reference text,path text,rid uuid default gen_random_uuid());
insert into optional_state default values;
do $$declare label text;aid uuid;uid bigint;sid uuid;mail text;begin
 foreach label in array array['customer','vendor','other','rider','admin']loop
 aid:=gen_random_uuid();sid:=gen_random_uuid();mail:='optional-sql-'||label||'-'||aid||'@example.test';
 insert into auth.users(id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
 values(aid,mail,now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{}');
 insert into public.users(auth_user_id,email,name,phone,role,verification_status)
 values(aid,mail,'OPTIONAL ROLLBACK ONLY','123456',case when label='other'then'customer'else label end,'approved')returning id into uid;
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after)values(sid,aid,now(),now(),clock_timestamp()+interval '1 hour');
 insert into optional_people values(label,uid,aid,sid,mail);end loop;end$$;
create function pg_temp.optional_claim(who text)returns void language plpgsql security definer as $$declare p optional_people;begin
 select *into p from optional_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id,
 'email',p.email,'exp',extract(epoch from clock_timestamp()+interval '1 hour')::bigint)::text,true);end$$;
create function pg_temp.optional_ok(v boolean,label text)returns void language plpgsql security definer as $$begin
 if v is distinct from true then raise exception 'Optional assertion: %',label;end if;insert into optional_results values(label);end$$;
grant execute on function pg_temp.optional_claim(text),pg_temp.optional_ok(boolean,text)to authenticated,anon;
grant select,update on optional_state to authenticated;
grant select on optional_people to authenticated;
insert into public.orders(user_id,order_status,amount,payment_method,delivery_address,checkout_finalized_at)
 values((select id from optional_people where label='customer'),'pending',1,'COD','OPTIONAL SQL ONLY',clock_timestamp());
update optional_state set oid=(select max(id)from public.orders);
insert into public.vendor_orders(order_id,vendor_id,sub_total,status,requires_prescription)
 values((select oid from optional_state),(select id from optional_people where label='vendor'),1,'pending_prescription',true);
update optional_state set vid=(select max(id)from public.vendor_orders);
select pg_temp.optional_claim('customer');
set local role authenticated;
select pg_temp.optional_ok(public.optional_media_authority('prescription',(select vid from optional_state))=(select id from optional_people where label='customer'),'own active prescription upload authority');
select pg_temp.optional_claim('other');
do $$begin begin perform public.optional_media_authority('prescription',(select vid from optional_state));raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.optional_ok(true,'foreign customer upload denied');end;end$$;
select pg_temp.optional_claim('vendor');
do $$begin begin perform public.optional_media_authority('tailoring');raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.optional_ok(true,'vendor cannot submit customer media');end;end$$;
select pg_temp.optional_claim('customer');
do $$begin begin perform public.optional_media_begin(null,null,null,'tailoring',null,null,null,null);raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.optional_ok(true,'client cannot invoke service finalizer');end;end$$;
reset role;
update optional_state set path=public.optional_media_begin((select auth_id from optional_people where label='customer'),(select session_id from optional_people where label='customer'),image,'prescription',vid,repeat('a',64),'image/png',68);
do $$begin begin perform public.optional_media_finish((select auth_id from optional_people where label='customer'),(select session_id from optional_people where label='customer'),image,'prescription',vid,repeat('a',64),'image/png',68)from optional_state;raise exception 'unexpected allow';exception when invalid_parameter_value then perform pg_temp.optional_ok(true,'missing Storage object cannot finalize');end;end$$;
insert into storage.objects(bucket_id,name,metadata)select'optional-private-media',path,'{"mimetype":"image/png","size":68}'from optional_state;
update optional_state set reference=public.optional_media_finish((select auth_id from optional_people where label='customer'),(select session_id from optional_people where label='customer'),image,'prescription',vid,repeat('a',64),'image/png',68);
select pg_temp.optional_ok(reference='tezphoto:'||image,'confirmed private media reference')from optional_state;
select pg_temp.optional_ok(public.optional_media_finish((select auth_id from optional_people where label='customer'),(select session_id from optional_people where label='customer'),image,'prescription',vid,repeat('a',64),'image/png',68)=reference,'same image finish retries idempotently')from optional_state;
select pg_temp.optional_ok((select count(*)from public.security_audit_log where actor_id=(select id from optional_people where label='customer')and action='optional_image_uploaded')=1,'upload audit exactly once');
set local role authenticated;
select pg_temp.optional_claim('customer');
update optional_state set pid=(public.optional_save_prescription(vid,reference,rid)->>'id')::bigint;
select pg_temp.optional_ok((public.optional_save_prescription(vid,reference,rid)->>'id')::bigint=pid,'prescription persistence retry same row')from optional_state;
select pg_temp.optional_ok(jsonb_array_length(public.optional_list_prescriptions(oid))=1,'own customer reads actual saved prescription')from optional_state;
select pg_temp.optional_ok(public.optional_media_view(image)->>'mime'='image/png','owner views prescription privately')from optional_state;
select pg_temp.optional_claim('other');
do $$begin begin perform public.optional_list_prescriptions((select oid from optional_state));raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.optional_ok(true,'foreign order prescription list denied');end;end$$;
do $$begin begin perform public.optional_media_view((select image from optional_state));raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.optional_ok(true,'foreign image view denied');end;end$$;
select pg_temp.optional_claim('vendor');
select pg_temp.optional_ok(jsonb_array_length(public.optional_list_prescriptions())=1,'own vendor sees actual pending prescription');
select pg_temp.optional_ok(public.optional_media_view(image)->>'mime'='image/png','assigned vendor views validated prescription')from optional_state;
select pg_temp.optional_ok(public.optional_review_prescription(pid,'approved','checked')->>'status'='approved','vendor review confirms canonical status')from optional_state;
select pg_temp.optional_ok(public.optional_review_prescription(pid,'approved','checked')->>'status'='approved','same review retry accepted without duplicate effect')from optional_state;
do $$begin begin perform public.optional_review_prescription((select pid from optional_state),'rejected','changed');raise exception 'unexpected allow';exception when sqlstate 'PT409'then perform pg_temp.optional_ok(true,'review decision cannot be reversed');end;end$$;
reset role;
select pg_temp.optional_ok((select status='pending'and prescription_id=(select pid from optional_state)and acceptance_deadline_at>acceptance_started_at from public.vendor_orders where id=(select vid from optional_state)),'approval unlocks existing acceptance workflow with real deadline');
select pg_temp.optional_ok((select count(*)from public.security_audit_log where actor_id=(select id from optional_people where label='vendor')and action='prescription_approved')=1,'review audit exactly once');
select pg_temp.optional_ok((select count(*)from public.notifications where user_id=(select id from optional_people where label='customer')and title='Prescription reviewed')=1,'actual in-app notification exactly once');
set local role authenticated;
select pg_temp.optional_claim('customer');
update optional_state set rid=gen_random_uuid();
update optional_state set tid=(public.optional_submit_tailoring('Stitch shirt', '{"length":"40","chest":""}',null,rid)->>'id')::bigint;
select pg_temp.optional_ok((public.optional_submit_tailoring('Stitch shirt','{"length":"40","chest":""}',null,rid)->>'id')::bigint=tid,'tailoring immutable retry returns persisted row')from optional_state;
do $$begin begin perform public.optional_submit_tailoring('Changed','{}',null,(select rid from optional_state));raise exception 'unexpected allow';exception when sqlstate 'PT409'then perform pg_temp.optional_ok(true,'changed tailoring retry rejected');end;end$$;
reset role;
select pg_temp.optional_ok((select measurements->>'length'='40'and vendor_id is null and status='pickup_requested'from public.tailoring_requests where id=(select tid from optional_state)),'measurements persisted without invented vendor assignment');
set local role anon;
do $$begin begin perform public.optional_list_prescriptions();raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.optional_ok(true,'anonymous optional data denied');end;end$$;
reset role;
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','rollback SQL candidate'))as results from optional_results;
rollback;
