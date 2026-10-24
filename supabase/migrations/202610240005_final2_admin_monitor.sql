-- Stage2 Admin monitoring and explicit manual assignment after FR20 escalation.
-- Does not replace radius matching, Rider acceptance, checklist or OTP.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create table final2_private.manual_assignments(
 request_id uuid primary key,
 actor_id bigint not null references public.users(id),
 order_id bigint not null references public.orders(id),
 rider_id bigint not null references public.users(id),
 assignment_id bigint not null references public.rider_assignments(id),
 created_at timestamptz not null default clock_timestamp()
);
alter table final2_private.manual_assignments enable row level security;
revoke all on final2_private.manual_assignments from public,anon,authenticated,service_role;

create function final2_private.require_monitor_admin()returns bigint
language plpgsql stable security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();begin
 if actor is null or public.fr21_role()is distinct from'admin'or not exists(
  select 1 from public.users where id=actor and role='admin'and verification_status='approved'and not is_blocked)then
  raise exception 'Approved Administrator required'using errcode='42501';end if;
 return actor;end$$;

create function public.final2_admin_order_monitor(p_before bigint default null,p_status text default null,
 p_from timestamptz default null,p_to timestamptz default null,p_limit integer default 30,p_export boolean default false)
returns jsonb language plpgsql stable security definer set search_path=''as $$
declare result_rows jsonb;summary jsonb;pins jsonb;count_rows bigint;online_count bigint;page_limit integer;begin
 perform final2_private.require_monitor_admin();
 if p_limit is null or p_limit not between 1 and 200 or(p_before is not null and p_before<=0)
  or(p_status is not null and p_status not in('placed','pending','accepted','preparing','ready','on_the_way','delivered','cancelled'))
  or(p_from is not null and p_to is not null and p_from>=p_to)or p_export is null then
  raise exception 'Invalid monitoring filter'using errcode='22023';end if;
 select count(*)into count_rows from public.orders o where(p_status is null or o.order_status=p_status)
  and(p_from is null or o.created_at>=p_from)and(p_to is null or o.created_at<p_to);
 if p_export and count_rows>5000 then raise exception 'Narrow the export filter to at most 5000 orders'using errcode='22023';end if;
 page_limit:=case when p_export then 5000 else p_limit end;
 select coalesce(jsonb_agg(jsonb_build_object('order_id',o.id,'status',o.order_status,'created_at',o.created_at,
  'delivered_at',o.delivered_at,'rider_id',o.rider_id,'manual_assignment',o.requires_manual_assignment,
  'amount_cents',case when o.amount>=0 and o.amount<1000000000000 and o.amount::text not in('NaN','Infinity','-Infinity')
   and o.amount=round(o.amount,2)then(round(o.amount*100)::bigint)::text end)order by o.id desc),'[]')into result_rows
 from(select *from public.orders o where(p_export or p_before is null or o.id<p_before)
  and(p_status is null or o.order_status=p_status)and(p_from is null or o.created_at>=p_from)and(p_to is null or o.created_at<p_to)
  order by id desc limit page_limit)o;
 select jsonb_build_object('total_orders',count(*),
  'active_orders',count(*)filter(where coalesce(o.order_status,'')not in('delivered','cancelled')),
  'delivered_orders',count(*)filter(where o.order_status='delivered'),
  'delivered_value_cents',(coalesce(sum(round(o.amount*100)::bigint)filter(where o.order_status='delivered'and o.amount>=0
    and o.amount<1000000000000 and o.amount::text not in('NaN','Infinity','-Infinity')and o.amount=round(o.amount,2)),0))::text,
  'unconfirmed_amounts',count(*)filter(where o.amount is null or o.amount<0 or o.amount>=1000000000000
    or o.amount::text in('NaN','Infinity','-Infinity')or o.amount<>round(o.amount,2)),
  'status_counts',(select coalesce(jsonb_object_agg(status,n),'{}')from(
    select coalesce(x.order_status,'unknown')as status,count(*)as n from public.orders x
    where(p_status is null or x.order_status=p_status)and(p_from is null or x.created_at>=p_from)and(p_to is null or x.created_at<p_to)
    group by x.order_status)c))into summary
 from public.orders o where(p_status is null or o.order_status=p_status)
  and(p_from is null or o.created_at>=p_from)and(p_to is null or o.created_at<p_to);
 select coalesce(jsonb_agg(jsonb_build_object('rider_id',r.userid,'latitude',r.latitude,'longitude',r.longitude,
  'observed_at',r.location_updated_at,'available',r.is_available and r.isavailable)order by r.userid),'[]')into pins
 from(select rr.*from public.riders rr join public.users u on u.id=rr.userid
  where u.role='rider'and u.verification_status='approved'and not u.is_blocked and rr.is_online
   and rr.last_seen>=clock_timestamp()-interval '2 minutes'and rr.location_updated_at>=clock_timestamp()-interval '2 minutes'
   and rr.assignment_location is not null order by rr.userid limit 200)r;
 select count(*)into online_count from public.riders r join public.users u on u.id=r.userid
  where u.role='rider'and u.verification_status='approved'and not u.is_blocked and r.is_online
   and r.last_seen>=clock_timestamp()-interval '2 minutes'and r.location_updated_at>=clock_timestamp()-interval '2 minutes'
   and r.assignment_location is not null;
 summary:=summary||jsonb_build_object('online_riders',online_count);
 return jsonb_build_object('code','OK','generated_at',statement_timestamp(),'summary',summary,'orders',result_rows,
  'has_more',not p_export and exists(select 1 from public.orders o
   where(p_status is null or o.order_status=p_status)and(p_from is null or o.created_at>=p_from)and(p_to is null or o.created_at<p_to)
    and o.id<(select min((v->>'order_id')::bigint)from jsonb_array_elements(result_rows)v)),
  'rider_locations',pins,'location_limit',200,'locations_truncated',online_count>200,'export_complete',p_export,
  'export_scope','filtered orders; order values are gross and do not represent Rider or platform earnings');
end$$;

create function public.final2_admin_assignment_candidates(p_order_id bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare o public.orders;pickup extensions.geography;portion bigint;result jsonb;begin
 perform final2_private.require_monitor_admin();
 select *into o from public.orders where id=p_order_id;
 if o.id is null then raise exception 'Order unavailable'using errcode='P0002';end if;
 if o.rider_id is not null or not o.requires_manual_assignment or o.order_status is distinct from'ready'then
  return jsonb_build_object('code','NOT_ELIGIBLE','order_id',o.id,'candidates','[]'::jsonb);end if;
 select vo.id,extensions.st_setsrid(extensions.st_makepoint(v.longitude::double precision,v.latitude::double precision),4326)::extensions.geography
 into portion,pickup from public.vendor_orders vo join public.vendors v on v.user_id=vo.vendor_id
 where vo.order_id=o.id and vo.status='ready'and v.latitude between -90 and 90 and v.longitude between -180 and 180
 order by vo.id limit 1;
 if pickup is null then return jsonb_build_object('code','PICKUP_LOCATION_REQUIRED','order_id',o.id,'candidates','[]'::jsonb);end if;
 select coalesce(jsonb_agg(jsonb_build_object('rider_id',x.userid,'name',x.name,'distance_m',x.meters)
  order by x.meters,x.userid),'[]')into result from(
  select r.userid,u.name,extensions.st_distance(r.assignment_location,pickup)as meters
  from public.riders r join public.users u on u.id=r.userid
  where u.role='rider'and u.verification_status='approved'and not u.is_blocked
   and r.is_online and r.is_available and r.isavailable and r.assignment_location is not null
   and r.last_seen>=clock_timestamp()-interval '2 minutes'and r.location_updated_at>=clock_timestamp()-interval '2 minutes'
   and not exists(select 1 from public.orders busy where busy.rider_id=r.userid and coalesce(busy.order_status,'')not in('delivered','cancelled'))
   and not exists(select 1 from public.rider_assignments busy where busy.riderid=r.userid and busy.status in('Pending','Accepted'))
  order by meters,r.userid limit 10)x;
 return jsonb_build_object('code','OK','order_id',o.id,'pickup_vendor_order_id',portion,'candidates',result);
end$$;

create function public.final2_admin_assign_rider(p_order_id bigint,p_rider_id bigint,p_request_id uuid)returns jsonb
language plpgsql security definer set search_path=''as $$
declare actor bigint:=final2_private.require_monitor_admin();o public.orders;r public.riders;u public.users;
 previous final2_private.manual_assignments;assignment bigint;begin
 if p_order_id is null or p_order_id<=0 or p_rider_id is null or p_rider_id<=0 or p_request_id is null then
  raise exception 'Valid order, Rider and request required'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('final2:manual:'||p_request_id::text,0));
 select *into previous from final2_private.manual_assignments where request_id=p_request_id;
 if found then
  if previous.actor_id<>actor or previous.order_id<>p_order_id or previous.rider_id<>p_rider_id then
   raise exception 'Assignment request cannot be changed'using errcode='PT409';end if;
  return jsonb_build_object('code','ALREADY_APPLIED','order_id',previous.order_id,'rider_id',previous.rider_id,'assignment_id',previous.assignment_id);
 end if;
 select *into o from public.orders where id=p_order_id for update;
 if o.id is null then raise exception 'Order unavailable'using errcode='P0002';end if;
 perform 1 from public.users where id=actor and role='admin'and verification_status='approved'and not is_blocked for share;
 if not found then raise exception 'Administrator access changed'using errcode='42501';end if;
 if o.rider_id is not null or not o.requires_manual_assignment or o.order_status is distinct from'ready'then
  return jsonb_build_object('code','ORDER_CHANGED','order_id',o.id);end if;
 if not exists(select 1 from public.vendor_orders vo join public.vendors v on v.user_id=vo.vendor_id
  where vo.order_id=o.id and vo.status='ready'and v.latitude between -90 and 90 and v.longitude between -180 and 180)then
  return jsonb_build_object('code','PICKUP_LOCATION_REQUIRED','order_id',o.id);end if;
 select *into u from public.users where id=p_rider_id for update;
 select *into r from public.riders where userid=p_rider_id for update;
 if u.id is null or u.role is distinct from'rider'or u.verification_status is distinct from'approved'or u.is_blocked
  or r.id is null or r.is_online is distinct from true or r.is_available is distinct from true or r.isavailable is distinct from true
  or r.assignment_location is null or r.last_seen is null or r.last_seen<clock_timestamp()-interval '2 minutes'
  or r.location_updated_at is null or r.location_updated_at<clock_timestamp()-interval '2 minutes'
  or exists(select 1 from public.orders busy where busy.rider_id=r.userid and coalesce(busy.order_status,'')not in('delivered','cancelled'))
  or exists(select 1 from public.rider_assignments busy where busy.riderid=r.userid and busy.status in('Pending','Accepted'))then
  return jsonb_build_object('code','RIDER_CHANGED','order_id',o.id);end if;
 insert into public.rider_assignments(riderid,orderid,status)values(r.userid,o.id,'Pending')returning id into assignment;
 update public.orders set rider_id=r.userid,requires_manual_assignment=false,delivery_otp=null where id=o.id;
 update public.riders set is_available=false,isavailable=false where id=r.id;
 insert into final2_private.manual_assignments(request_id,actor_id,order_id,rider_id,assignment_id)
  values(p_request_id,actor,o.id,r.userid,assignment);
 -- Receipt deduplicates each real assignment; do not overwrite old notifications.
 insert into public.notifications(user_id,title,message,type,assignment_order_id,rider_assignment_id)
  values(r.userid,'New Delivery Assigned','An Administrator assigned a delivery. Open the request to review and accept.','order',o.id,assignment);
 insert into public.security_audit_log(actor_id,action,target_type,target_id)
  values(actor,'RIDER_MANUALLY_ASSIGNED','orders',o.id);
 return jsonb_build_object('code','ASSIGNED','order_id',o.id,'rider_id',r.userid,'assignment_id',assignment);
exception when lock_not_available or deadlock_detected or unique_violation or serialization_failure then
 return jsonb_build_object('code','RETRYABLE_CONFLICT','order_id',p_order_id);
end$$;
revoke all on function final2_private.require_monitor_admin()from public,anon,authenticated,service_role;
revoke all on function public.final2_admin_order_monitor(bigint,text,timestamptz,timestamptz,integer,boolean),
 public.final2_admin_assignment_candidates(bigint),public.final2_admin_assign_rider(bigint,bigint,uuid)from public,anon;
grant execute on function public.final2_admin_order_monitor(bigint,text,timestamptz,timestamptz,integer,boolean),
 public.final2_admin_assignment_candidates(bigint),public.final2_admin_assign_rider(bigint,bigint,uuid)to authenticated;
-- Preserve the existing restrictive own-Rider/Admin and live-session SELECT
-- policies. Realtime changes never grant other roles raw Rider locations.
alter publication supabase_realtime add table public.riders;
commit;
