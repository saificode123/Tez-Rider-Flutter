-- Rollback review only: create genuine pre-migration transit and pickup data.
create temp table checklist_before_migration(oid bigint,pickup_oid bigint,aid bigint,rid bigint,auth_id uuid,session_id uuid);
do $$declare a uuid:=gen_random_uuid();ca uuid:=gen_random_uuid();s uuid:=gen_random_uuid();uid bigint;cid bigint;oid bigint;pid bigint;aid bigint;mail text;begin
 mail:='checklist-legacy-'||a||'@example.test';
 insert into auth.users(id,email,email_confirmed_at,role,aud)values(a,mail,now(),'authenticated','authenticated');
 insert into public.users(email,name,role,verification_status)values(mail,'CHECKLIST LEGACY SYNTHETIC','rider','approved')returning id into uid;
 insert into auth.sessions(id,user_id,created_at,updated_at)values(s,a,now(),now());
 insert into auth.users(id,email,email_confirmed_at,role,aud)values(ca,'checklist-legacy-customer-'||ca||'@example.test',now(),'authenticated','authenticated');
 insert into public.users(email,name,role,verification_status)values('checklist-legacy-customer-'||ca||'@example.test','CHECKLIST LEGACY CUSTOMER SYNTHETIC','customer','approved')returning id into cid;
 insert into public.orders(user_id,rider_id,order_status,amount,payment_method,delivery_address)values(cid,uid,'on_the_way',200,'COD','CHECKLIST LEGACY SYNTHETIC')returning id into oid;
 insert into public.rider_assignments(orderid,riderid,status)values(oid,uid,'Accepted')returning id into aid;
 insert into public.orders(user_id,order_status,amount,payment_method,delivery_address)values(cid,'ready',200,'COD','CHECKLIST LEGACY PICKUP SYNTHETIC')returning id into pid;
 insert into checklist_before_migration values(oid,pid,aid,uid,a,s);
end$$;
