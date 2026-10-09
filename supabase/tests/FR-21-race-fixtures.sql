-- Committed fixtures for the dblink test only, in the localhost test database.
do $$ begin
  if current_database()<>'fr21_isolated_test' then raise exception 'Local test database required'; end if;
end $$;
insert into auth.users(id,email,email_confirmed_at,aud,role) values
('22000000-0000-0000-0000-000000000001','fr21-race-c@example.test',now(),'authenticated','authenticated'),
('22000000-0000-0000-0000-000000000002','fr21-race-v@example.test',now(),'authenticated','authenticated'),
('22000000-0000-0000-0000-000000000003','fr21-race-r@example.test',now(),'authenticated','authenticated') on conflict do nothing;
insert into public.users(id,name,email,role,verification_status) values
(-22001,'Race customer','fr21-race-c@example.test','customer','approved'),
(-22002,'Race vendor','fr21-race-v@example.test','vendor','approved'),
(-22003,'Race rider','fr21-race-r@example.test','rider','approved') on conflict do nothing;
insert into public.riders(userid,is_online,last_seen,latitude,longitude)
values(-22003,false,now(),31.52,74.35) on conflict(userid) do nothing;
insert into public.vendors(user_id,store_name,latitude,longitude) values(-22002,'Race shop',31.52,74.35) on conflict do nothing;
insert into public.orders(id,user_id,amount,order_status) values
(-22001,-22001,100,'accepted'),(-22002,-22001,100,'accepted') on conflict do nothing;
insert into public.vendor_orders(id,order_id,vendor_id,status) values
(-22001,-22001,-22002,'accepted'),(-22002,-22002,-22002,'accepted') on conflict do nothing;
-- Reset only these committed dummy records for another race run.
delete from public.rider_assignments where orderid in (-22001,-22002);
update public.orders set rider_id=null,delivery_otp=null,order_status='accepted' where id in (-22001,-22002);
update public.vendor_orders set status='accepted' where id in (-22001,-22002);
update public.riders set is_online=false,is_available=true,isavailable=true where userid=-22003;
