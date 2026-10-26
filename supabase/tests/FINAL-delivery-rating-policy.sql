-- All identity/review/order/Auth-state fixtures roll back. SQL Auth simulation
-- is not proof of a real Auth Admin API ban or physical delivery.
begin;
-- FINAL_RATING_CANDIDATE
create temporary table rating_results(label text,result text);
create temporary table rating_people(label text,id bigint,auth_id uuid);
create temporary table rating_state(active_order bigint,review_order bigint);
create function pg_temp.rating_ok(value boolean,label text)returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'Rating policy assertion failed: %',label;end if;
 insert into rating_results values(label,'PASS');end$$;
create function pg_temp.add_ratings(label text,n integer,stars integer,age_days integer default 0)returns void
language plpgsql as $$declare target rating_people;reviewer rating_people;oid bigint;begin
 select *into target from rating_people p where p.label=add_ratings.label;
 select *into reviewer from rating_people where rating_people.label='customer';
 for i in 1..n loop
  insert into public.orders(user_id,amount,order_status,payment_method,delivery_address)
   values(reviewer.id,1,'pending','COD','SQL synthetic rating-window fixture')returning id into oid;
  insert into public.reviews(id,reviewer_id,reviewee_id,order_id,rating,target_user_id,target_role,verified_at,request_payload)
   values(gen_random_uuid(),reviewer.auth_id,target.auth_id,oid,stars,target.id,
    case when label in('vendor','active_vendor')then'vendor'else'rider'end,
    clock_timestamp()-make_interval(days=>age_days),'{}');
 end loop;end$$;
do $$declare fixture_label text;aid uuid;uid bigint;customer bigint;vendor bigint;oid bigint;begin
 foreach fixture_label in array array['admin','customer','vendor','active_vendor','rider','few','threshold','expired']loop
  aid:=gen_random_uuid();
  insert into auth.users(id,instance_id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
   values(aid,'00000000-0000-0000-0000-000000000000','rating-sql-'||fixture_label||'-'||aid||'@example.test',now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{"rating_fixture":true}');
  insert into public.users(email,name,role,verification_status)
   values('rating-sql-'||fixture_label||'-'||aid||'@example.test','Rating SQL synthetic',
    case when fixture_label='admin'then'admin'when fixture_label='customer'then'customer'when fixture_label in('vendor','active_vendor')then'vendor'else'rider'end,'approved')returning id into uid;
  insert into rating_people values(fixture_label,uid,aid);
  if fixture_label not in('admin','customer','vendor','active_vendor')then insert into public.riders(userid)values(uid);end if;
 end loop;
 update final_delivery_private.rating_settings set policy_actor_id=(select id from rating_people where label='admin'),last_evaluated_day=null where singleton;
 select id into customer from rating_people where label='customer';select id into vendor from rating_people where label='active_vendor';
 insert into public.orders(user_id,vendor_id,amount,order_status,payment_method,delivery_address)
  values(customer,vendor,1,'pending','COD','SQL active deferral fixture')returning id into oid;
 insert into rating_state values(oid,null);
end$$;
select pg_temp.rating_ok((select minimum_reviews=10 and window_days=30 and threshold=2 and defer_active_work and admin_only_unblock and reset_window_on_unblock from final_delivery_private.rating_settings where singleton),'owner-approved policy values stored server-side');
select pg_temp.rating_ok(not has_schema_privilege('authenticated','final_delivery_private','USAGE')and not has_table_privilege('service_role','final_delivery_private.rating_settings','SELECT'),'private policy values cannot be read or changed by clients or raw service table requests');
select pg_temp.rating_ok(not has_function_privilege('authenticated','public.final_rating_work(boolean)','EXECUTE')and has_function_privilege('service_role','public.final_rating_work(boolean)','EXECUTE'),'rating worker RPC is service-only');
select pg_temp.add_ratings('vendor',10,1);
select pg_temp.add_ratings('active_vendor',10,1);
select pg_temp.add_ratings('rider',10,1);
select pg_temp.add_ratings('few',9,1);
select pg_temp.add_ratings('threshold',10,2);
select pg_temp.add_ratings('expired',10,1,31);
select pg_temp.add_ratings('admin',10,1);
select pg_temp.add_ratings('customer',10,1);
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
do $$begin
 begin perform public.final_rating_work(true);raise exception 'ordinary caller accepted';exception when insufficient_privilege then null;end;
 perform pg_temp.rating_ok(true,'authenticated role cannot invoke service-only evaluation even through a definer caller');
end$$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.final_rating_work(true);
select pg_temp.rating_ok((select bool_and(u.is_blocked)from rating_people p join public.users u on u.id=p.id where p.label in('vendor','rider')),'ten verified recent ratings below threshold block inactive Vendor and Rider through FR28');
select pg_temp.rating_ok((select not u.is_blocked from rating_people p join public.users u on u.id=p.id where p.label='active_vendor')and(select state='DEFERRED'from final_delivery_private.rating_queue where user_id=(select id from rating_people where label='active_vendor')),'active Vendor work defers blocking without cancellation or reassignment');
select pg_temp.rating_ok((select bool_and(not u.is_blocked)from rating_people p join public.users u on u.id=p.id where p.label in('few','threshold','expired','admin','customer')),'fewer than ten, exact threshold, expired window, Admin and Customer never auto-block');
do $$declare customer bigint:=(select id from rating_people where label='customer');
 vendor bigint:=(select id from rating_people where label='vendor');rider bigint:=(select id from rating_people where label='rider');oid bigint;begin
 begin
  insert into public.orders(user_id,vendor_id,amount,order_status,payment_method,delivery_address)values(customer,vendor,1,'pending','COD','SQL unavailable account fixture');
  raise exception 'new work entered blocked Vendor';exception when sqlstate'PT409'then null;
 end;
 perform pg_temp.rating_ok(true,'new parent work cannot enter a concurrently blocked Vendor');
 insert into public.orders(user_id,amount,order_status,payment_method,delivery_address)values(customer,1,'pending','COD','SQL unavailable account fixture')returning id into oid;
 begin
  insert into public.vendor_orders(order_id,vendor_id,sub_total,status)values(oid,vendor,1,'pending');
  raise exception 'new portion entered blocked Vendor';exception when sqlstate'PT409'then null;
 end;
 perform pg_temp.rating_ok(true,'multi-Vendor child insertion rechecks and locks account availability');
 begin
  insert into public.rider_assignments(orderid,riderid,status)values(oid,rider,'Pending');
  raise exception 'new assignment entered blocked Rider';exception when sqlstate'PT409'then null;
 end;
 perform pg_temp.rating_ok(true,'delivery-assignment insertion rechecks and locks Rider availability');
end$$;
select pg_temp.rating_ok((select count(*)=2 from public.security_audit_log where action='auto_low_rating'and target_id in(select id from rating_people)),'each automatic breach writes exactly one explicit reason audit');
select pg_temp.rating_ok((select count(*)=2 from public.notifications where user_id=(select id from rating_people where label='admin')and type='auto_low_rating'),'policy notifies the synthetic Admin for each new block');
select public.final_rating_work(true);
select pg_temp.rating_ok((select count(*)=2 from public.security_audit_log where action='auto_low_rating'and target_id in(select id from rating_people)),'same-day retries neither duplicate block audits nor reevaluate the population');
-- A review submitted after the daily evaluation cannot create a new same-day
-- candidate, even when the retry endpoint is called.
select pg_temp.add_ratings('few',1,1);
select public.final_rating_work(true);
select pg_temp.rating_ok((select not u.is_blocked from public.users u join rating_people p on p.id=u.id where p.label='few'),'daily population evaluation is exact-once while deferred work may retry');
-- Retire only the synthetic active order; no real order changes survive rollback.
update public.orders set order_status='cancelled'where id=(select active_order from rating_state);
select public.final_rating_work(false);
select pg_temp.rating_ok((select is_blocked from public.users where id=(select id from rating_people where label='active_vendor')),'deferred breach applies once active work becomes terminal');
select pg_temp.rating_ok((select order_status='cancelled'from public.orders where id=(select active_order from rating_state)),'policy preserves the actual terminal order state');
-- Simulate external Auth completion only inside this rollback transaction.
do $$declare operation record;begin
 for operation in select q.operation_id,p.auth_id from final_delivery_private.rating_queue q join rating_people p on p.id=q.user_id where q.state='BLOCKING'loop
  update auth.users set banned_until=clock_timestamp()+interval'1 day'where id=operation.auth_id;
  perform public.fr28_revoke_sessions(operation.operation_id);
  perform pg_temp.rating_ok(public.fr28_finish(operation.operation_id)->>'code'='OK','existing FR28 finish requires confirmed mocked ban and revoked sessions');
 end loop;end$$;
select public.final_rating_work(false);
do $$declare target rating_people;actor rating_people;op uuid:=gen_random_uuid();begin
 select *into target from rating_people where label='rider';select *into actor from rating_people where label='admin';
 perform public.admin_set_user_blocked(actor.auth_id,target.id,false,op);
 update auth.users set banned_until=null where id=target.auth_id;
 perform public.fr28_revoke_sessions(op);
 perform pg_temp.rating_ok(public.fr28_finish(op)->>'code'='OK','existing Admin unblock mechanism completes through confirmed mocked Auth state');
 perform pg_temp.rating_ok(exists(select 1 from final_delivery_private.rating_cutoffs where user_id=target.id and ignore_before is not null),'Admin unblock resets the reputation-policy cutoff');
 update final_delivery_private.rating_settings set last_evaluated_day=null where singleton;
 perform public.final_rating_work(true);
 perform pg_temp.rating_ok(not(select is_blocked from public.users where id=target.id),'old ratings cannot reblock an Admin-unblocked account');
end$$;
-- Schedule values remain configurable in their private settings row.
select pg_temp.rating_ok(exists(select 1 from cron.job where jobname='final-rating-daily'and schedule=(select daily_schedule from final_delivery_private.rating_settings where singleton)),'daily schedule is installed from persisted settings');
select jsonb_agg(jsonb_build_object('check',label,'result',result,'surface','rollback SQL; Auth completion explicitly simulated'))as results from rating_results;
rollback;
