-- Restrict session fan-out to identities that requested this delivery context.
-- Prevent unrelated dormant login sessions from multiplying every GPS fix.
begin;
create table fr13_private.watchers(
 assignment_id bigint not null references fr13_private.sessions(assignment_id) on delete cascade,
 session_id uuid not null references auth.sessions(id) on delete cascade,
 topic text not null,primary key(assignment_id,session_id));
alter table fr13_private.watchers enable row level security;
revoke all on fr13_private.watchers from public,anon,authenticated,service_role;

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
 if s.topic is not null then
  insert into fr13_private.watchers(assignment_id,session_id,topic)values(s.assignment_id,(auth.jwt()->>'session_id')::uuid,s.topic)
  on conflict(assignment_id,session_id)do update set topic=excluded.topic;
 end if;
 return jsonb_build_object('code','OK','order_id',o.id,'assignment_id',a.id,'rider_id',a.riderid,'sharing',s.topic is not null,'topic',case when s.topic is null then null else s.topic||':'||(auth.jwt()->>'session_id') end,
 'server_now',clock_timestamp(),'latest',(select to_jsonb(l)from public.delivery_latest_locations l where l.assignment_id=a.id));
end$function$
;
create or replace function public.fr13_live_topics(p_sender_topic text) returns text[]
language plpgsql stable security definer set search_path='' as $$
declare result text[];begin
 if auth.role() is distinct from 'service_role' then raise exception 'Server only' using errcode='42501';end if;
 select array_agg(s.topic||':'||a.id::text order by a.id) into result
 from fr13_private.sessions s join public.orders o on o.id=s.order_id
 join public.users u on ((u.id=o.user_id and u.role='customer')or(u.id=s.rider_id and u.role='rider' and u.verification_status='approved')or(u.role='admin'and u.verification_status='approved'))
 join auth.users identity on identity.id=u.auth_user_id and identity.email_confirmed_at is not null
 join auth.sessions a on a.user_id=identity.id
 join fr13_private.watchers w on w.assignment_id=s.assignment_id and w.session_id=a.id and w.topic=s.topic
 where not u.is_blocked and final1_private.session_deadline(a.created_at,a.not_after)>statement_timestamp()
 and fr13_private.eligible(o.id,s.assignment_id)
 and exists(select 1 from auth.sessions sender join public.users rider on rider.auth_user_id=sender.user_id
  where rider.id=s.rider_id and rider.role='rider' and not rider.is_blocked and rider.verification_status='approved'
  and s.topic||':'||sender.id::text=p_sender_topic
  and final1_private.session_deadline(sender.created_at,sender.not_after)>statement_timestamp());
 return coalesce(result,array[]::text[]);
end$$;
commit;
