-- New notification/device/Auth fixtures and queue leases all roll back.
begin;
-- FINAL_EVENT_CANDIDATE
create temporary table event_results(label text,result text);
create temporary table event_people(label text,id bigint,auth_id uuid,session_id uuid,installation uuid);
create temporary table event_context(notification_id bigint,event_id uuid,job_id uuid,lease uuid);
create function pg_temp.event_ok(value boolean,label text)returns void language plpgsql security definer as $$begin
 if value is distinct from true then raise exception 'Event push assertion failed: %',label;end if;
 insert into event_results values(label,'PASS');end$$;
do $$declare kind text;aid uuid;sid uuid;uid bigint;iid uuid;email text;begin
 foreach kind in array array['customer','vendor']loop
  aid:=gen_random_uuid();sid:=gen_random_uuid();iid:=gen_random_uuid();email:='event-sql-'||aid||'@example.test';
  insert into auth.users(id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
   values(aid,email,clock_timestamp(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{"event_push_fixture":true}');
  insert into public.users(email,name,role,verification_status)values(email,'Event push SQL synthetic',kind,'approved')returning id into uid;
  insert into auth.sessions(id,user_id,created_at,updated_at)values(sid,aid,clock_timestamp(),clock_timestamp());
  insert into fr30_private.push_devices(id,user_id,session_id,token,token_hash,secret_hash)
   values(iid,uid,sid,'synthetic-event-'||iid,encode(extensions.digest('synthetic-event-'||iid,'sha256'),'hex'),encode(extensions.digest(repeat('a',64),'sha256'),'hex'));
  insert into event_people values(kind,uid,aid,sid,iid);
 end loop;
end$$;
select pg_temp.event_ok((select not reservations_enabled and reservation_duration_seconds=0 and not expiry_timer_enabled
 and check_stock_at_add and revalidate_at_checkout and decrement_at_placement and restore_on_cancellation and name_short_items
 from final_delivery_private.cart_settings where singleton),'owner-approved no-reservation policy stored server-side');
select pg_temp.event_ok((select maximum_amount is null from final_delivery_private.pay_settings where id=1),'owner-approved no maximum earning stored explicitly without changing pay math');
select pg_temp.event_ok(not has_table_privilege('authenticated','final_delivery_private.cart_settings','SELECT')
 and not has_table_privilege('service_role','final_delivery_private.cart_settings','SELECT'),'private cart settings have no direct client or service table reads');
do $$begin
 begin update final_delivery_private.cart_settings set reservations_enabled=true;raise exception 'unsupported policy accepted';exception when check_violation then null;end;
 perform pg_temp.event_ok(true,'reservation activation cannot bypass the reviewed transaction design');
end$$;
update fr30_private.limits set android_push_enabled=true;
do $$declare kind text;n public.notifications;uid bigint;begin
 select id into uid from event_people where label='customer';
 foreach kind in array array['order','dispute','delivery','otp_review','account','auto_low_rating']loop
  insert into public.notifications(user_id,title,message,type)values(uid,'SQL synthetic event','Open the application for this recorded event.',kind)returning *into n;
  perform pg_temp.event_ok(n.broadcast_id is null and n.order_push_event_id is not null,kind||' receives only a transport UUID');
  perform pg_temp.event_ok((select count(*)=1 from fr30_private.push_deliveries where notification_id=n.id),kind||' creates one existing session-bound durable push job');
 end loop;
 insert into event_context select n.id,n.order_push_event_id,j.id,null from fr30_private.push_deliveries j where j.notification_id=n.id;
end$$;
select pg_temp.event_ok(public.fr30_resolve_push((select installation from event_people where label='customer'),repeat('a',64),(select event_id from event_context))->>'code'='OK','existing device capability resolves an ordinary event');
select pg_temp.event_ok(public.fr30_resolve_push((select installation from event_people where label='vendor'),repeat('a',64),(select event_id from event_context))->>'code'='FORBIDDEN','unrelated installation cannot resolve another owner event');
select pg_temp.event_ok(public.fr30_resolve_push((select installation from event_people where label='customer'),repeat('b',64),(select event_id from event_context))->>'code'='FORBIDDEN','wrong device secret denies ordinary event text');
select pg_temp.event_ok(not has_table_privilege('authenticated','public.notifications','INSERT'),'client cannot forge system notifications or push hints');
do $$declare event uuid:=gen_random_uuid();n public.notifications;begin
 insert into public.notifications(user_id,title,message,type,order_push_event_id)
  values((select id from event_people where label='customer'),'Existing producer','Preserve existing immutable transport UUID.','order',event)returning *into n;
 perform pg_temp.event_ok(n.order_push_event_id=event,'existing timeout/stock/cancellation transport UUID remains unchanged');
end$$;
update fr30_private.push_deliveries set due_at=clock_timestamp()-interval'1 day'where id=(select job_id from event_context);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update event_context c set lease=(select(j->>'lease')::uuid from public.fr30_claim_push(50)j where(j->>'job_id')::uuid=c.job_id);
select pg_temp.event_ok((select lease is not null from event_context),'existing worker claims an ordinary notification');
select pg_temp.event_ok(public.fr30_push_eligible((select job_id from event_context),(select lease from event_context)),'ordinary event is reauthorized before provider dispatch');
select pg_temp.event_ok(public.fr30_finish_push((select job_id from event_context),(select lease from event_context),'ACCEPTED','projects/test/messages/synthetic')->>'code'='RECORDED','provider acceptance remains distinct from actual device receipt');
update public.notifications set is_read=true where id=(select notification_id from event_context);
select pg_temp.event_ok(public.fr30_resolve_push((select installation from event_people where label='customer'),repeat('a',64),(select event_id from event_context))->>'code'='FORBIDDEN','read ordinary event is not rendered again');
update public.notifications set is_read=false where id=(select notification_id from event_context);
update fr30_private.push_deliveries set expires_at=clock_timestamp()-interval'1 second'where id=(select job_id from event_context);
select pg_temp.event_ok(public.fr30_resolve_push((select installation from event_people where label='customer'),repeat('a',64),(select event_id from event_context))->>'code'='FORBIDDEN','expired ordinary event cannot reveal message');
update fr30_private.push_deliveries set expires_at=clock_timestamp()+interval'1 hour'where id=(select job_id from event_context);
update auth.sessions set created_at=clock_timestamp()-interval'8 days'where id=(select session_id from event_people where label='customer');
select pg_temp.event_ok(public.fr30_resolve_push((select installation from event_people where label='customer'),repeat('a',64),(select event_id from event_context))->>'code'='FORBIDDEN','absolute expired Auth session cannot resolve ordinary event');
update auth.sessions set created_at=clock_timestamp()where id=(select session_id from event_people where label='customer');
update fr30_private.push_devices set secret_hash=encode(extensions.digest(repeat('c',64),'sha256'),'hex')where id=(select installation from event_people where label='customer');
select pg_temp.event_ok(public.fr30_resolve_push((select installation from event_people where label='customer'),repeat('c',64),(select event_id from event_context))->>'code'='FORBIDDEN','rebound installation cannot reveal old snapshot event');
select jsonb_agg(jsonb_build_object('check',label,'result',result,'surface','rollback SQL; synthetic Auth/device and provider outcome, no FCM delivery'))as results from event_results;
rollback;
