-- FR22: actual accepted assignments and completed deliveries, with explicit
-- missing-history counts. No compensation rate is invented or cash transferred.
begin;
create table final2_private.rider_assignment_starts(
 assignment_id bigint not null references public.rider_assignments(id),
 order_id bigint not null references public.orders(id),
 rider_id bigint not null references public.users(id),
 accepted_at timestamptz,
 history_limited boolean not null default false,
 primary key(assignment_id,rider_id)
);
create table final2_private.rider_delivery_metrics(
 order_id bigint primary key references public.orders(id),
 rider_id bigint not null references public.users(id),
 assignment_id bigint not null references public.rider_assignments(id),
 delivered_at timestamptz not null,
 duration_seconds numeric check(duration_seconds>=0),
 earned_fee_cents bigint check(earned_fee_cents>=0),
 fee_status text not null default 'POLICY_REQUIRED' check(fee_status='POLICY_REQUIRED'),
 check(earned_fee_cents is null)
);
create table final2_private.rider_performance(
 rider_id bigint primary key references public.users(id),
 accepted_assignments bigint not null check(accepted_assignments>=0),
 completed_deliveries bigint not null check(completed_deliveries>=0),
 completion_rate numeric,
 timed_deliveries bigint not null check(timed_deliveries>=0),
 average_duration_seconds numeric check(average_duration_seconds>=0),
 rating_count bigint not null check(rating_count>=0),
 average_rating numeric,
 updated_at timestamptz not null default clock_timestamp()
);
alter table final2_private.rider_assignment_starts enable row level security;
alter table final2_private.rider_delivery_metrics enable row level security;
alter table final2_private.rider_performance enable row level security;
revoke all on final2_private.rider_assignment_starts,final2_private.rider_delivery_metrics,final2_private.rider_performance from public,anon,authenticated,service_role;

create function final2_private.refresh_rider_performance(rid bigint)returns void
language plpgsql security definer set search_path=''as $$
declare assigned bigint;completed bigint;timed bigint;duration numeric;ratings public.rating_summaries;begin
 if rid is null then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('final2:rider-metrics:'||rid::text,0));
 select count(*)into assigned from final2_private.rider_assignment_starts where rider_id=rid;
 select count(*),count(duration_seconds),avg(duration_seconds)into completed,timed,duration
  from final2_private.rider_delivery_metrics where rider_id=rid;
 select *into ratings from public.rating_summaries where target_user_id=rid and target_role='rider';
 insert into final2_private.rider_performance(rider_id,accepted_assignments,completed_deliveries,completion_rate,
  timed_deliveries,average_duration_seconds,rating_count,average_rating)
 values(rid,assigned,completed,case when assigned>0 then round(100.0*completed/assigned,2)end,
  timed,duration,coalesce(ratings.rating_count,0),ratings.average_rating)
 on conflict(rider_id)do update set accepted_assignments=excluded.accepted_assignments,
  completed_deliveries=excluded.completed_deliveries,completion_rate=excluded.completion_rate,
  timed_deliveries=excluded.timed_deliveries,average_duration_seconds=excluded.average_duration_seconds,
  rating_count=excluded.rating_count,average_rating=excluded.average_rating,updated_at=clock_timestamp();
end$$;

create function final2_private.capture_rider_assignment()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if new.status='Accepted'and new.riderid is not null then
  insert into final2_private.rider_assignment_starts(assignment_id,order_id,rider_id,accepted_at)
  values(new.id,new.orderid,new.riderid,clock_timestamp())on conflict(assignment_id,rider_id)do nothing;
  perform final2_private.refresh_rider_performance(new.riderid);
 end if;
 return new;end$$;
create trigger final2_metrics_assignment after insert or update of status,riderid on public.rider_assignments
 for each row execute function final2_private.capture_rider_assignment();

create function final2_private.capture_rider_delivery()returns trigger
language plpgsql security definer set search_path=''as $$
declare a final2_private.rider_assignment_starts;inserted bigint;begin
 if new.order_status='delivered'and new.delivered_at is not null and new.rider_id is not null then
  select *into a from final2_private.rider_assignment_starts
   where order_id=new.id and rider_id=new.rider_id order by assignment_id desc limit 1;
  if a.assignment_id is not null then
   insert into final2_private.rider_delivery_metrics(order_id,rider_id,assignment_id,delivered_at,duration_seconds)
   values(new.id,new.rider_id,a.assignment_id,new.delivered_at,
    case when a.accepted_at is not null and new.delivered_at>=a.accepted_at
      then extract(epoch from new.delivered_at-a.accepted_at)end)
   on conflict(order_id)do nothing returning order_id into inserted;
   if inserted is not null then
    perform final2_private.refresh_rider_performance(new.rider_id);
    insert into public.security_audit_log(actor_id,action,target_type,target_id)
     values(new.rider_id,'rider_metrics_recorded','orders',new.id);
   end if;
  end if;
 end if;return new;end$$;
create trigger final2_metrics_delivery after insert or update of order_status,delivered_at on public.orders
 for each row execute function final2_private.capture_rider_delivery();

create function final2_private.refresh_rider_rating()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if new.target_role='rider'then perform final2_private.refresh_rider_performance(new.target_user_id);end if;
 return new;end$$;
create trigger final2_metrics_rating after insert or update on public.rating_summaries
 for each row execute function final2_private.refresh_rider_rating();

-- Baseline existing accepted/delivered assignments without manufacturing their
-- acceptance time. Unknown old duration is excluded, never replaced with zero.
insert into final2_private.rider_assignment_starts(assignment_id,order_id,rider_id,history_limited)
 select a.id,a.orderid,a.riderid,true from public.rider_assignments a
 join public.users u on u.id=a.riderid and u.role='rider'
 where a.status in('Accepted','Delivered');
insert into final2_private.rider_delivery_metrics(order_id,rider_id,assignment_id,delivered_at)
 select distinct on(o.id)o.id,o.rider_id,a.assignment_id,o.delivered_at from public.orders o
 join final2_private.rider_assignment_starts a on a.order_id=o.id and a.rider_id=o.rider_id
 where o.order_status='delivered'and o.delivered_at is not null order by o.id,a.assignment_id desc;
do $$declare r record;begin
 for r in select id from public.users where role='rider'loop perform final2_private.refresh_rider_performance(r.id);end loop;
end$$;

create function public.final2_rider_performance(p_rider_id bigint default null)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();rid bigint:=coalesce(p_rider_id,actor);m final2_private.rider_performance;begin
 if actor is null or not exists(select 1 from public.users where id=actor and verification_status='approved'and not is_blocked)
  or(public.fr21_role()<>'admin'and(public.fr21_role()<>'rider'or rid is distinct from actor))
  or not exists(select 1 from public.users where id=rid and role='rider')then
  raise exception 'Authorized Rider performance required'using errcode='42501';end if;
 select *into m from final2_private.rider_performance where rider_id=rid;
 return jsonb_build_object('code','OK','rider_id',rid,'accepted_assignments',coalesce(m.accepted_assignments,0),
  'completed_deliveries',coalesce(m.completed_deliveries,0),'completion_rate',m.completion_rate,
  'timed_deliveries',coalesce(m.timed_deliveries,0),'average_duration_seconds',m.average_duration_seconds,
  'rating_count',coalesce(m.rating_count,0),'average_rating',m.average_rating,
  'legacy_assignments',(select count(*)from final2_private.rider_assignment_starts where rider_id=rid and history_limited),
  'unlinked_deliveries',(select count(*)from public.orders o where o.rider_id=rid and o.order_status='delivered'
    and not exists(select 1 from final2_private.rider_delivery_metrics d where d.order_id=o.id)),
  'fee_status','POLICY_REQUIRED','earned_fee_cents',null,'updated_at',m.updated_at);
end$$;
revoke all on function final2_private.refresh_rider_performance(bigint),final2_private.capture_rider_assignment(),
 final2_private.capture_rider_delivery(),final2_private.refresh_rider_rating()from public,anon,authenticated,service_role;
revoke all on function public.final2_rider_performance(bigint)from public,anon;
grant execute on function public.final2_rider_performance(bigint)to authenticated;
commit;
