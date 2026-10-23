-- Realtime caches join policies: never publish to a revoked session topic.
-- Additive protocol hardening; no historic media/business data rewrite.
begin;
CREATE OR REPLACE FUNCTION public.fr13_can_receive(p_topic text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select public.fr21_actor()is not null and exists(select 1 from fr13_private.sessions s join public.orders o on o.id=s.order_id
 where p_topic=s.topic||':'||(auth.jwt()->>'session_id') and fr13_private.eligible(o.id,s.assignment_id)
 and(public.fr21_actor()=o.user_id and public.fr21_role()='customer'
 or public.fr21_actor()=s.rider_id and public.fr21_role()='rider'
 or public.fr21_role()='admin'));
$function$
;
CREATE OR REPLACE FUNCTION public.fr13_tracking_context(p_order_id bigint, p_enable boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor bigint:=public.fr21_actor();o public.orders;a public.rider_assignments;s fr13_private.sessions;begin
 if actor is null then return jsonb_build_object('code','FORBIDDEN');end if;
 -- Writes follow parent -> assignment -> user -> rider -> session hierarchy.
 if p_enable is not null then select *into o from public.orders where id=p_order_id for update;
 else select *into o from public.orders where id=p_order_id;end if;
 if o.id is null or not((public.fr21_role()='customer'and o.user_id=actor)or(public.fr21_role()='rider'and o.rider_id=actor)or public.fr21_role()='admin')then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_enable is not null and(public.fr21_role()<>'rider'or o.rider_id<>actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_enable is not null then
  select *into a from public.rider_assignments where orderid=o.id and riderid=actor and status='Accepted'for update;
  perform 1 from public.users where id in(actor,o.user_id)order by id for share;
  perform 1 from public.riders where userid=actor for share;
 else select *into a from public.rider_assignments where orderid=o.id and riderid=o.rider_id and status='Accepted';end if;
 if p_enable is false then
  delete from fr13_private.live_state where assignment_id in(select assignment_id from fr13_private.sessions where order_id=o.id);
  delete from public.delivery_latest_locations where order_id=o.id;
  delete from fr13_private.sessions where order_id=o.id;
  return jsonb_build_object('code','STOPPED');
 end if;
 if a.id is null or not fr13_private.eligible(o.id,a.id)then return jsonb_build_object('code','INELIGIBLE');end if;
 if p_enable is true then
  insert into fr13_private.sessions(assignment_id,order_id,rider_id,topic)
  values(a.id,o.id,actor,'fr13:'||o.id||':'||a.id||':'||extensions.gen_random_uuid())on conflict(assignment_id)do nothing;
 end if;
 select *into s from fr13_private.sessions where assignment_id=a.id;
 return jsonb_build_object('code','OK','order_id',o.id,'assignment_id',a.id,'rider_id',a.riderid,'sharing',s.topic is not null,'topic',case when s.topic is null then null else s.topic||':'||(auth.jwt()->>'session_id') end,
 'server_now',clock_timestamp(),'latest',(select to_jsonb(l)from public.delivery_latest_locations l where l.assignment_id=a.id));
end$function$
;
CREATE OR REPLACE FUNCTION public.fr13_submit_location(p_order_id bigint, p_lat double precision, p_lng double precision, p_accuracy double precision, p_device_at timestamp with time zone, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor bigint:=public.fr21_actor();o public.orders;a public.rider_assignments;s fr13_private.sessions;v fr13_private.live_state;moment timestamptz;persist boolean;payload jsonb;begin
 if actor is null or public.fr21_role()is distinct from'rider'or not public.fr21_approved_rider(actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_request_id is null or p_lat is null or p_lat not between -90 and 90 or p_lng is null or p_lng not between -180 and 180
 or p_accuracy is null or p_accuracy not between 0 and 100 then return jsonb_build_object('code','INVALID_LOCATION');end if;
 if p_device_at is null or not isfinite(p_device_at)or p_device_at<clock_timestamp()-interval '30 seconds'or p_device_at>clock_timestamp()+interval '5 seconds'then return jsonb_build_object('code','STALE_FIX');end if;
 select *into o from public.orders where id=p_order_id for update;
 if o.id is null or o.rider_id is distinct from actor then return jsonb_build_object('code','FORBIDDEN');end if;
 select *into a from public.rider_assignments where orderid=o.id and riderid=actor and status='Accepted'for update;
 perform 1 from public.users where id in(actor,o.user_id)order by id for share;
 perform 1 from public.riders where userid=actor for share;
 if not public.fr21_approved_rider(actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 if a.id is null or not fr13_private.eligible(o.id,a.id)then return jsonb_build_object('code','INELIGIBLE');end if;
 select *into s from fr13_private.sessions where assignment_id=a.id for update;
 if s.assignment_id is null then return jsonb_build_object('code','SHARING_STOPPED');end if;
 select *into v from fr13_private.live_state where assignment_id=a.id;
 moment:=clock_timestamp();
 if v.request_id=p_request_id then return jsonb_build_object('code','REPLAYED');end if;
 if v.received_at>moment-interval '2 seconds'then return jsonb_build_object('code','RATE_LIMIT','retry_after_ms',2000);end if;
 if v.device_at>=p_device_at then return jsonb_build_object('code','STALE_FIX');end if;
 persist:=v.persisted_at is null or v.persisted_at<=moment-interval '15 seconds';
 insert into fr13_private.live_state values(a.id,moment,p_device_at,p_request_id,case when persist then moment else v.persisted_at end)
 on conflict(assignment_id)do update set received_at=excluded.received_at,device_at=excluded.device_at,request_id=excluded.request_id,persisted_at=excluded.persisted_at;
 if persist then
  insert into public.delivery_latest_locations values(a.id,o.id,actor,p_lat,p_lng,p_accuracy,p_device_at,moment)
  on conflict(assignment_id)do update set latitude=excluded.latitude,longitude=excluded.longitude,accuracy=excluded.accuracy,device_at=excluded.device_at,received_at=excluded.received_at;
  -- Keep the existing FR20 assignment coordinates fresh, at the same coarse interval.
  update public.riders set latitude=p_lat,longitude=p_lng,location_updated_at=moment where userid=actor;
 end if;
 payload:=jsonb_build_object('order_id',o.id,'assignment_id',a.id,'latitude',p_lat,'longitude',p_lng,'accuracy',p_accuracy,'device_at',p_device_at,'received_at',moment,'request_id',p_request_id);
 return jsonb_build_object('code','ACCEPTED','topic',s.topic||':'||(auth.jwt()->>'session_id'),'payload',payload,'persisted',persist);
end$function$
;

-- Only trusted publication code can enumerate live session destinations.
create function public.fr13_live_topics(p_sender_topic text) returns text[]
language plpgsql stable security definer set search_path='' as $$
declare result text[];begin
 if auth.role() is distinct from 'service_role' then raise exception 'Server only' using errcode='42501';end if;
 select array_agg(s.topic||':'||a.id::text order by a.id) into result
 from fr13_private.sessions s join public.orders o on o.id=s.order_id
 join public.users u on ((u.id=o.user_id and u.role='customer')or(u.id=s.rider_id and u.role='rider' and u.verification_status='approved')or(u.role='admin'and u.verification_status='approved'))
 join auth.users identity on identity.id=u.auth_user_id and identity.email_confirmed_at is not null
 join auth.sessions a on a.user_id=identity.id
 where not u.is_blocked and final1_private.session_deadline(a.created_at,a.not_after)>statement_timestamp()
 and fr13_private.eligible(o.id,s.assignment_id)
 and exists(select 1 from auth.sessions sender join public.users rider on rider.auth_user_id=sender.user_id
  where rider.id=s.rider_id and rider.role='rider' and not rider.is_blocked and rider.verification_status='approved'
  and s.topic||':'||sender.id::text=p_sender_topic
  and final1_private.session_deadline(sender.created_at,sender.not_after)>statement_timestamp());
 return coalesce(result,array[]::text[]);
end$$;
revoke all on function public.fr13_live_topics(text) from public,anon,authenticated;
grant execute on function public.fr13_live_topics(text) to service_role;

commit;
