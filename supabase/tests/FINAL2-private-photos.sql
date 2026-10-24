begin;
-- FINAL2_CANDIDATE
create temporary table photo_people(label text primary key,id bigint,auth_id uuid,session_id uuid,email text);
create temporary table photo_results(label text);
create temporary table photo_state(oid bigint,avatar uuid,delivery uuid,path text);
insert into photo_state(avatar,delivery)values(gen_random_uuid(),gen_random_uuid());
do $$declare label text;aid uuid;uid bigint;sid uuid;mail text;begin
 foreach label in array array['customer','vendor','rider','rider2','admin']loop
  aid:=gen_random_uuid();sid:=gen_random_uuid();mail:='final2-photo-'||label||'-'||aid||'@example.test';
  insert into auth.users(id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
   values(aid,mail,now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{}');
  insert into public.users(auth_user_id,email,name,phone,role,verification_status)
   values(aid,mail,'FINAL2 PHOTO SQL ONLY','123456',case when label='rider2'then'rider'else label end,'approved')returning id into uid;
  insert into auth.sessions(id,user_id,created_at,updated_at,not_after)values(sid,aid,now(),now(),clock_timestamp()+interval '1 hour');
  insert into photo_people values(label,uid,aid,sid,mail);
 end loop;
end$$;

create function pg_temp.photo_claim(who text)returns void language plpgsql security definer as $$declare p photo_people;begin
 select *into p from photo_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id,
 'email',p.email,'exp',extract(epoch from clock_timestamp()+interval '1 hour')::bigint)::text,true);end$$;
create function pg_temp.photo_ok(v boolean,label text)returns void language plpgsql security definer as $$begin
 if v is distinct from true then raise exception 'Photo assertion: %',label;end if;insert into photo_results values(label);end$$;
grant execute on function pg_temp.photo_claim(text),pg_temp.photo_ok(boolean,text)to authenticated,anon;
grant select on photo_people,photo_state to authenticated;
insert into public.orders(user_id,rider_id,order_status,amount,payment_method,delivery_address)
 values((select id from photo_people where label='customer'),(select id from photo_people where label='rider'),'ready',1,'COD','SQL PHOTO ONLY');
update photo_state set oid=(select max(id)from public.orders);
insert into public.rider_assignments(orderid,riderid,status)select oid,(select id from photo_people where label='rider'),'Accepted'from photo_state;
select pg_temp.photo_claim('rider');
set local role authenticated;
select public.submit_pre_delivery_checklist((select id from public.rider_assignments where orderid=(select oid from photo_state)),1,'[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]');
select public.start_checklisted_delivery((select id from public.rider_assignments where orderid=(select oid from photo_state)));

select pg_temp.photo_ok(public.final2_photo_authority('avatar')=(select id from photo_people where label='rider'),'own avatar authority');
select pg_temp.photo_ok(public.final2_photo_authority('delivery',(select oid from photo_state))=(select id from photo_people where label='rider'),'assigned active delivery authority');
select pg_temp.photo_claim('rider2');
do $$begin begin perform public.final2_photo_authority('delivery',(select oid from photo_state));raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.photo_ok(true,'unrelated Rider upload denied');end;end$$;
select pg_temp.photo_claim('customer');
do $$begin begin perform public.final2_photo_authority('delivery',(select oid from photo_state));raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.photo_ok(true,'Customer cannot fabricate delivery photo');end;end$$;
reset role;
select pg_temp.photo_claim('rider');
update photo_state set path=public.final2_photo_begin((select auth_id from photo_people where label='rider'),(select session_id from photo_people where label='rider'),avatar,'avatar',null,repeat('a',64),'image/png',68);
insert into storage.objects(bucket_id,name,metadata)select 'final2-private-photos',path,'{"mimetype":"image/png","size":68}'from photo_state;
select pg_temp.photo_ok(public.final2_photo_finish((select auth_id from photo_people where label='rider'),(select session_id from photo_people where label='rider'),avatar,'avatar',null,repeat('a',64),'image/png',68)='tezphoto:'||avatar,'validated avatar persisted')from photo_state;
select pg_temp.photo_ok((select profile_image from public.users where id=(select id from photo_people where label='rider'))='tezphoto:'||avatar,'canonical own profile updated')from photo_state;
select public.final2_photo_finish((select auth_id from photo_people where label='rider'),(select session_id from photo_people where label='rider'),avatar,'avatar',null,repeat('a',64),'image/png',68)from photo_state;
select pg_temp.photo_ok((select count(*)from public.security_audit_log where actor_id=(select id from photo_people where label='rider')and action='profile_photo_uploaded')=1,'upload retry audit exactly once');
do $$begin begin perform public.final2_photo_begin((select auth_id from photo_people where label='rider'),(select session_id from photo_people where label='rider'),avatar,'avatar',null,repeat('b',64),'image/png',68)from photo_state;raise exception 'unexpected allow';exception when sqlstate 'PT409' then perform pg_temp.photo_ok(true,'changed image retry rejected');end;end$$;
update photo_state set path=public.final2_photo_begin((select auth_id from photo_people where label='rider'),(select session_id from photo_people where label='rider'),delivery,'delivery',oid,repeat('b',64),'image/png',68);
insert into storage.objects(bucket_id,name,metadata)select 'final2-private-photos',path,'{"mimetype":"image/png","size":68}'from photo_state;
select public.final2_photo_finish((select auth_id from photo_people where label='rider'),(select session_id from photo_people where label='rider'),delivery,'delivery',oid,repeat('b',64),'image/png',68)from photo_state;
select pg_temp.photo_ok((select order_status from public.orders where id=oid)='on_the_way'and not exists(select 1 from public.delivery_proof where orderid=oid::text),'photo never invents OTP or delivered status')from photo_state;
-- SQL transaction fixture only; not a real physical delivery or emailed OTP.
insert into public.delivery_proof(proofid,orderid,riderid,otpconfirmed,is_verified,verified_at)
 select 'fr21-otp-'||oid,oid::text,(select auth_id::text from photo_people where label='rider'),true,true,clock_timestamp()from photo_state;
select pg_temp.photo_ok((select photourl from public.delivery_proof where orderid=oid::text)='tezphoto:'||delivery,'canonical OTP receipt attaches validated photo')from photo_state;
set local role authenticated;
select pg_temp.photo_claim('customer');
select pg_temp.photo_ok(public.final2_photo_view(avatar)->>'mime'='image/png','assigned Customer can view Rider avatar')from photo_state;
select pg_temp.photo_ok(public.final2_photo_view(delivery)->>'mime'='image/png','own Customer delivery photo read')from photo_state;
select pg_temp.photo_ok(public.fr04_order_rider_identity(oid)->>'photo'='tezphoto:'||avatar,'owned identity returns controlled photo reference')from photo_state;
select pg_temp.photo_ok(public.final2_customer_delivery_identity(oid)->>'order_status'='on_the_way','identity stepper reports actual order status')from photo_state;
select pg_temp.photo_ok(public.final2_delivery_photo(oid)->>'reference'='tezphoto:'||delivery,'order photo context is canonical')from photo_state;
select pg_temp.photo_claim('admin');
select pg_temp.photo_ok(public.final2_photo_view(delivery)->>'mime'='image/png','approved Admin private photo read')from photo_state;
select pg_temp.photo_claim('vendor');
do $$declare img uuid;begin foreach img in array array[(select avatar from photo_state),(select delivery from photo_state)]loop
 begin perform public.final2_photo_view(img);raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.photo_ok(true,'unrelated Vendor private photo denied');end;end loop;end$$;
select pg_temp.photo_claim('rider2');
do $$declare img uuid;begin foreach img in array array[(select avatar from photo_state),(select delivery from photo_state)]loop
 begin perform public.final2_photo_view(img);raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.photo_ok(true,'unrelated Rider private photo denied');end;end loop;end$$;
select pg_temp.photo_ok((select count(*)from storage.objects where bucket_id='final2-private-photos')=0,'raw Storage listing denied');
do $$begin begin perform public.final2_photo_begin(null,null,null,'avatar',null,null,null,null);raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.photo_ok(true,'authenticated cannot call trusted upload finalizer');end;end$$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where id=(select id from photo_people where label='customer');
set local role authenticated;
select pg_temp.photo_claim('customer');
do $$begin begin perform public.final2_photo_view((select delivery from photo_state));raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.photo_ok(true,'blocked account private photo denied');end;end$$;
reset role;
-- FINAL2_DEADLINE
delete from auth.sessions where id=(select session_id from photo_people where label='rider');
do $$begin begin perform public.final2_photo_begin((select auth_id from photo_people where label='rider'),(select session_id from photo_people where label='rider'),gen_random_uuid(),'avatar',null,repeat('a',64),'image/png',68);raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.photo_ok(true,'revoked session trusted upload denied');end;end$$;
set local role anon;
do $$begin begin perform public.final2_photo_view(gen_random_uuid());raise exception 'unexpected allow';exception when insufficient_privilege then perform pg_temp.photo_ok(true,'anonymous photo denied');end;end$$;
reset role;
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated SQL rollback fixture'))as results from photo_results;
rollback;
