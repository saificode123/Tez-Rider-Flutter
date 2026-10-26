-- Owner-approved policy: docs/POLICY-DECISIONS.md. TEST deployment only.
begin;
set local lock_timeout='5s';
create schema if not exists final_delivery_private;
revoke all on schema final_delivery_private from public,anon,authenticated;
create table final_delivery_private.rating_settings(
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default true,
 minimum_reviews integer not null default 10 check(minimum_reviews>0),
 window_days integer not null default 30 check(window_days>0),
 threshold numeric not null default 2.0 check(threshold>0 and threshold<=5),
 daily_schedule text not null default '0 0 * * *',
 retry_schedule text not null default '*/5 * * * *',
 defer_active_work boolean not null default true check(defer_active_work),
 admin_only_unblock boolean not null default true check(admin_only_unblock),
 reset_window_on_unblock boolean not null default true check(reset_window_on_unblock),
 policy_actor_id bigint references public.users(id),
 worker_url text not null default 'https://igeisilhtmglgnqvllrx.supabase.co/functions/v1/final-rating-worker'
  check(worker_url='https://igeisilhtmglgnqvllrx.supabase.co/functions/v1/final-rating-worker'),
 last_evaluated_day date
);
insert into final_delivery_private.rating_settings(singleton,policy_actor_id)
 values(true,(select id from public.users where role='admin'and verification_status='approved'and not is_blocked order by id limit 1));
create table final_delivery_private.rating_cutoffs(
 user_id bigint primary key references public.users(id),
 ignore_before timestamptz not null
);
create table final_delivery_private.rating_queue(
 user_id bigint primary key references public.users(id),
 operation_id uuid not null unique default gen_random_uuid(),
 state text not null check(state in('DEFERRED','BLOCKING','COMPLETED','CLEARED')),
 rating_count bigint not null,
 average_rating numeric not null,
 evaluated_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp()
);
alter table final_delivery_private.rating_settings enable row level security;
alter table final_delivery_private.rating_cutoffs enable row level security;
alter table final_delivery_private.rating_queue enable row level security;
revoke all on final_delivery_private.rating_settings,final_delivery_private.rating_cutoffs,
 final_delivery_private.rating_queue from public,anon,authenticated,service_role;
create index final_delivery_rating_window on public.reviews(target_user_id,verified_at)where verified_at is not null;

create function final_delivery_private.rating_unblock_cutoff()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if old.is_blocked and not new.is_blocked and new.role in('vendor','rider')then
  insert into final_delivery_private.rating_cutoffs(user_id,ignore_before)values(new.id,clock_timestamp())
   on conflict(user_id)do update set ignore_before=excluded.ignore_before;
  update final_delivery_private.rating_queue set state='CLEARED',updated_at=clock_timestamp()where user_id=new.id;
 end if;return new;
end$$;
create trigger final_delivery_rating_unblock after update of is_blocked on public.users
 for each row execute function final_delivery_private.rating_unblock_cutoff();

-- Serialize new work against the evaluator's account lock. Without these
-- shared locks, a checkout could validate an unblocked Vendor, then insert its
-- child portion after a concurrent auto-block had already checked for work.
create function final_delivery_private.rating_new_work_guard()returns trigger
language plpgsql security definer set search_path=''as $$
declare targets bigint[]:='{}';target bigint;blocked boolean;begin
 if tg_table_name='orders'then
  if coalesce(new.order_status,'')in('delivered','cancelled')then return new;end if;
  if tg_op='INSERT'then targets:=array[new.vendor_id,new.rider_id];
  elsif new.vendor_id is distinct from old.vendor_id or new.rider_id is distinct from old.rider_id then targets:=array[new.vendor_id,new.rider_id];end if;
 elsif tg_table_name='vendor_orders'then
  if coalesce(new.status,'')in('delivered','cancelled')or not exists(select 1 from public.orders where id=new.order_id and coalesce(order_status,'')not in('delivered','cancelled'))then return new;end if;
  if tg_op='INSERT'then targets:=array[new.vendor_id];
  elsif new.vendor_id is distinct from old.vendor_id or new.order_id is distinct from old.order_id then targets:=array[new.vendor_id];end if;
 else
  if new.status not in('Pending','Accepted')or not exists(select 1 from public.orders where id=new.orderid and coalesce(order_status,'')not in('delivered','cancelled'))then return new;end if;
  if tg_op='INSERT'then targets:=array[new.riderid];
  elsif new.riderid is distinct from old.riderid or new.orderid is distinct from old.orderid or old.status not in('Pending','Accepted')then targets:=array[new.riderid];end if;
 end if;
 for target in select distinct id from unnest(targets)id where id is not null order by id loop
  select is_blocked into blocked from public.users where id=target and role in('vendor','rider')for share;
  if blocked then raise exception 'Account became unavailable. Refresh and retry.'using errcode='PT409';end if;
 end loop;return new;
end$$;
create trigger final_delivery_rating_new_order before insert or update on public.orders
 for each row execute function final_delivery_private.rating_new_work_guard();
create trigger final_delivery_rating_new_portion before insert or update on public.vendor_orders
 for each row execute function final_delivery_private.rating_new_work_guard();
create trigger final_delivery_rating_new_assignment before insert or update on public.rider_assignments
 for each row execute function final_delivery_private.rating_new_work_guard();

create function public.final_rating_work(p_evaluate boolean default false)returns jsonb
language plpgsql security definer set search_path=''as $$
declare settings final_delivery_private.rating_settings;candidate record;target public.users;actor public.users;
 result jsonb;stats record;pending jsonb;today date:=(clock_timestamp()at time zone'UTC')::date;
begin
 if auth.role()is distinct from'service_role'then raise exception 'Server required'using errcode='42501';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('final-delivery:rating-policy',0))then return jsonb_build_object('code','BUSY','operations','[]'::jsonb);end if;
 select *into settings from final_delivery_private.rating_settings where singleton for update;
 if not settings.enabled then return jsonb_build_object('code','DISABLED','operations','[]'::jsonb);end if;
 select *into actor from public.users where id=settings.policy_actor_id and role='admin'and verification_status='approved'and not is_blocked;
 if actor.id is null then return jsonb_build_object('code','POLICY_ADMIN_REQUIRED','operations','[]'::jsonb);end if;
 if p_evaluate and settings.last_evaluated_day is distinct from today then
  insert into final_delivery_private.rating_queue(user_id,state,rating_count,average_rating)
  select u.id,'DEFERRED',count(*),avg(r.rating)from public.users u
   join public.reviews r on r.target_user_id=u.id and r.target_role=u.role and r.verified_at is not null
   left join final_delivery_private.rating_cutoffs c on c.user_id=u.id
  where u.role in('vendor','rider')and u.verification_status='approved'and not u.is_blocked
   and r.verified_at>=clock_timestamp()-make_interval(days=>settings.window_days)
   and r.verified_at<=clock_timestamp()and(c.ignore_before is null or r.verified_at>c.ignore_before)
  group by u.id having count(*)>=settings.minimum_reviews and avg(r.rating)<settings.threshold
  on conflict(user_id)do update set state='DEFERRED',operation_id=case when final_delivery_private.rating_queue.state in('COMPLETED','CLEARED')then gen_random_uuid()else final_delivery_private.rating_queue.operation_id end,
   rating_count=excluded.rating_count,average_rating=excluded.average_rating,evaluated_at=clock_timestamp(),updated_at=clock_timestamp()
   where final_delivery_private.rating_queue.state<>'BLOCKING';
  update final_delivery_private.rating_settings set last_evaluated_day=today where singleton;
 end if;
 -- Deferred work retries do not perform a new population-wide daily evaluation.
 for candidate in select *from final_delivery_private.rating_queue where state in('DEFERRED','BLOCKING')order by evaluated_at,user_id for update skip locked loop
  select *into target from public.users where id=candidate.user_id for update;
  if target.role not in('vendor','rider')or target.verification_status<>'approved'then
   update final_delivery_private.rating_queue set state='CLEARED',updated_at=clock_timestamp()where user_id=target.id;continue;
  end if;
  if candidate.state='BLOCKING'then
   if exists(select 1 from public.fr28_operations where id=candidate.operation_id and state='SYNCED')then
    update final_delivery_private.rating_queue set state='COMPLETED',updated_at=clock_timestamp()where user_id=target.id;
   end if;continue;
  end if;
  if target.is_blocked then
   update final_delivery_private.rating_queue set state='CLEARED',updated_at=clock_timestamp()where user_id=target.id;continue;
  end if;
  if exists(select 1 from public.orders o where coalesce(o.order_status,'')not in('delivered','cancelled')
   and(o.rider_id=target.id or o.vendor_id=target.id or exists(select 1 from public.vendor_orders v where v.order_id=o.id and v.vendor_id=target.id)))or exists(
   select 1 from public.rider_assignments a join public.orders o on o.id=a.orderid
   where a.riderid=target.id and a.status in('Pending','Accepted')and coalesce(o.order_status,'')not in('delivered','cancelled'))then continue;end if;
  -- A cleared/improved/expired window must not block an account from a stale queue.
  select count(*)as n,avg(r.rating)as average into stats from public.reviews r
   left join final_delivery_private.rating_cutoffs c on c.user_id=r.target_user_id
   where r.target_user_id=target.id and r.target_role=target.role and r.verified_at is not null
    and r.verified_at>=clock_timestamp()-make_interval(days=>settings.window_days)and r.verified_at<=clock_timestamp()
    and(c.ignore_before is null or r.verified_at>c.ignore_before);
  if stats.n<settings.minimum_reviews or stats.average>=settings.threshold then
   update final_delivery_private.rating_queue set state='CLEARED',updated_at=clock_timestamp()where user_id=target.id;continue;
  end if;
  result:=public.admin_set_user_blocked(actor.auth_user_id,target.id,true,candidate.operation_id);
  if result->>'code'='PENDING'then
   update final_delivery_private.rating_queue set state='BLOCKING',updated_at=clock_timestamp()where user_id=target.id;
   insert into public.security_audit_log(actor_id,action,target_type,target_id,user_operation_id)
    values(actor.id,'auto_low_rating','users',target.id,candidate.operation_id);
   insert into public.notifications(user_id,title,message,type)
    select id,'Account automatically blocked','Account #'||target.id||' was blocked by the approved low-rating policy. Reason: auto_low_rating.','auto_low_rating'
    from public.users where role='admin';
  end if;
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('operation_id',q.operation_id,'target_id',q.user_id)),'[]'::jsonb)into pending
  from(select q.operation_id,q.user_id from final_delivery_private.rating_queue q join public.fr28_operations o on o.id=q.operation_id
   where q.state='BLOCKING'and o.state<>'SYNCED'order by q.updated_at,q.user_id limit 20)q;
 return jsonb_build_object('code','OK','operations',pending);
end$$;
revoke all on function public.final_rating_work(boolean)from public,anon,authenticated;
grant execute on function public.final_rating_work(boolean)to service_role;
revoke all on function final_delivery_private.rating_unblock_cutoff(),final_delivery_private.rating_new_work_guard()from public,anon,authenticated,service_role;

-- The worker secret is generated privately on TEST, then provisioned to Edge by
-- the guarded deployment harness. Never return it to mobile clients.
do $$begin
 if not exists(select 1 from vault.secrets where name='final_rating_worker')then
  perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'final_rating_worker');
 end if;
end$$;
create function final_delivery_private.dispatch_rating_worker(p_daily boolean)returns void
language plpgsql security definer set search_path=''as $$
declare settings final_delivery_private.rating_settings;worker text;begin
 select *into settings from final_delivery_private.rating_settings where singleton;
 if not settings.enabled then return;end if;
 if not p_daily and not exists(select 1 from final_delivery_private.rating_queue where state in('DEFERRED','BLOCKING'))then return;end if;
 select decrypted_secret into worker from vault.decrypted_secrets where name='final_rating_worker'limit 1;
 if worker is null or char_length(worker)<32 then return;end if;
 perform net.http_post(url:=settings.worker_url,headers:=jsonb_build_object('Content-Type','application/json','x-final-rating-worker-key',worker),
  body:=jsonb_build_object('source',case when p_daily then'daily'else'retry'end),timeout_milliseconds:=10000);
end$$;
create function final_delivery_private.schedule_rating_worker()returns trigger
language plpgsql security definer set search_path=''as $$begin
 perform cron.schedule('final-rating-daily',new.daily_schedule,'select final_delivery_private.dispatch_rating_worker(true);');
 perform cron.schedule('final-rating-retry',new.retry_schedule,'select final_delivery_private.dispatch_rating_worker(false);');
 return new;end$$;
revoke all on function final_delivery_private.dispatch_rating_worker(boolean),final_delivery_private.schedule_rating_worker()from public,anon,authenticated,service_role;
create trigger final_delivery_rating_schedule after update of daily_schedule,retry_schedule on final_delivery_private.rating_settings
 for each row execute function final_delivery_private.schedule_rating_worker();
select cron.schedule('final-rating-daily',(select daily_schedule from final_delivery_private.rating_settings where singleton),'select final_delivery_private.dispatch_rating_worker(true);');
select cron.schedule('final-rating-retry',(select retry_schedule from final_delivery_private.rating_settings where singleton),'select final_delivery_private.dispatch_rating_worker(false);');
notify pgrst,'reload schema';
commit;
