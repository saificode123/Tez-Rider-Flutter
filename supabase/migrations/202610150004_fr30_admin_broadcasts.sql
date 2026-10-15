-- FR30 additive, transactional fan-out. No production deployment authorized.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create table public.admin_broadcasts(
 id uuid primary key,
 audit_number bigint generated always as identity unique not null,
 sender_id bigint not null references public.users(id),
 title text not null check(title=btrim(title) and char_length(title) between 1 and 100),
 message text not null check(message=btrim(message) and char_length(message) between 1 and 1000),
 audience text not null check(audience in('ALL','CUSTOMERS','VENDORS','RIDERS')),
 recipient_count bigint not null check(recipient_count>=0),
 status text not null default 'ACCEPTED' check(status='ACCEPTED'),
 created_at timestamptz not null default clock_timestamp());
create index fr30_history_idx on public.admin_broadcasts(created_at desc,id desc);
create index fr30_sender_time_idx on public.admin_broadcasts(sender_id,created_at desc);
alter table public.admin_broadcasts enable row level security;
revoke all on public.admin_broadcasts from public,anon,authenticated;
grant select on public.admin_broadcasts to authenticated;
grant all on public.admin_broadcasts to service_role;
grant usage,select on sequence public.admin_broadcasts_audit_number_seq to service_role;
create policy fr30_admin_history on public.admin_broadcasts for select to authenticated
 using((select public.fr21_role())='admin' and exists(select 1 from public.users where id=(select public.fr21_actor()) and verification_status='approved'));
create policy fr28_session_guard on public.admin_broadcasts as restrictive for all to authenticated
 using((select public.is_current_user_allowed()))with check((select public.is_current_user_allowed()));
create schema fr30_private;
revoke all on schema fr30_private from public,anon,authenticated;
create table fr30_private.limits(
 singleton boolean primary key default true check(singleton),
 cooldown_seconds integer not null default 60 check(cooldown_seconds between 0 and 86400),
 daily_max integer not null default 10 check(daily_max between 1 and 1000));
insert into fr30_private.limits default values;
revoke all on fr30_private.limits from public,anon,authenticated;
alter table public.notifications add column broadcast_id uuid references public.admin_broadcasts(id);
create unique index fr30_recipient_once_idx on public.notifications(broadcast_id,user_id)where broadcast_id is not null;
create index fr30_unread_idx on public.notifications(user_id)where is_read=false;
alter table public.security_audit_log add column broadcast_id uuid references public.admin_broadcasts(id);
create unique index fr30_audit_once_idx on public.security_audit_log(broadcast_id)where broadcast_id is not null;

create function public.fr30_estimate(p_audience text)returns bigint
language plpgsql stable security definer set search_path='' as $$begin
 if public.fr21_role() is distinct from 'admin' or not exists(select 1 from public.users where id=public.fr21_actor() and verification_status='approved')then
  raise exception 'Admin authorization required'using errcode='42501';end if;
 if p_audience is null or p_audience not in('ALL','CUSTOMERS','VENDORS','RIDERS')then raise exception 'Invalid audience'using errcode='22023';end if;
 return(select count(*)from public.users u join auth.users a on a.id=u.auth_user_id
  where not u.is_blocked and a.email_confirmed_at is not null
  and(p_audience='ALL'or u.role=case p_audience when 'CUSTOMERS'then 'customer'when 'VENDORS'then 'vendor'else 'rider'end));
end$$;
create function public.admin_send_broadcast(p_request_id uuid,p_title text,p_message text,p_audience text)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();old public.admin_broadcasts;cfg fr30_private.limits;
 heading text:=btrim(p_title,E' \t\n\r');body text:=btrim(p_message,E' \t\n\r');n bigint;number bigint;sent_at timestamptz;last_sent timestamptz;
begin
 -- Serialize all sends by this canonical actor; recheck authorization after waiting.
 perform 1 from public.users where id=actor for update;
 if actor is null or not exists(select 1 from public.users where id=actor and role='admin' and verification_status='approved' and not is_blocked)
 or not public.is_current_user_allowed()then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_request_id is null or heading is null or body is null or char_length(heading)not between 1 and 100 or char_length(body)not between 1 and 1000
 or p_audience is null or p_audience not in('ALL','CUSTOMERS','VENDORS','RIDERS')then return jsonb_build_object('code','INVALID_INPUT');end if;
 -- Plain text is stored and displayed literally, including HTML-like strings.
 -- Lock the UUID across actors too; collisions must return conflict, never a unique violation.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text,3030));
 select * into old from public.admin_broadcasts where id=p_request_id;
 if found then
  if old.sender_id<>actor or old.title<>heading or old.message<>body or old.audience<>p_audience then return jsonb_build_object('code','IDEMPOTENCY_CONFLICT');end if;
  return jsonb_build_object('code','ALREADY_SENT','id',old.id,'recipient_count',old.recipient_count,'created_at',old.created_at);
 end if;
 select * into strict cfg from fr30_private.limits where singleton;
 sent_at:=clock_timestamp();
 select max(created_at)into last_sent from public.admin_broadcasts where sender_id=actor and created_at>sent_at-interval '24 hours';
 if last_sent is not null and last_sent+make_interval(secs=>cfg.cooldown_seconds)>sent_at then
  return jsonb_build_object('code','COOLDOWN','retry_after_seconds',ceil(extract(epoch from last_sent+make_interval(secs=>cfg.cooldown_seconds)-sent_at)));end if;
 if(select count(*)from public.admin_broadcasts where sender_id=actor and created_at>sent_at-interval '24 hours')>=cfg.daily_max then
  return jsonb_build_object('code','DAILY_LIMIT');end if;
 insert into public.admin_broadcasts(id,sender_id,title,message,audience,recipient_count,created_at)
 values(p_request_id,actor,heading,body,p_audience,0,sent_at)returning audit_number into number;
 -- Single statement snapshot: block/role changes later never add recipients retroactively.
 insert into public.notifications(user_id,title,message,type,broadcast_id)
 select u.id,heading,body,'broadcast',p_request_id from public.users u join auth.users a on a.id=u.auth_user_id
 where not u.is_blocked and a.email_confirmed_at is not null
 and(p_audience='ALL'or u.role=case p_audience when 'CUSTOMERS'then 'customer'when 'VENDORS'then 'vendor'else 'rider'end);
 get diagnostics n=row_count;
 -- No client has update privileges; the count and all deliveries commit atomically.
 update public.admin_broadcasts set recipient_count=n where id=p_request_id;
 insert into public.security_audit_log(actor_id,action,target_type,target_id,broadcast_id)
 values(actor,'SEND_BROADCAST','broadcast',number,p_request_id);
 return jsonb_build_object('code','SENT','id',p_request_id,'recipient_count',n,'created_at',sent_at);
exception when lock_not_available or deadlock_detected or query_canceled then
 return jsonb_build_object('code','RETRYABLE_ERROR');
end$$;
revoke all on function public.admin_send_broadcast(uuid,text,text,text),public.fr30_estimate(text)from public,anon;
grant execute on function public.admin_send_broadcast(uuid,text,text,text),public.fr30_estimate(text)to authenticated;
notify pgrst,'reload schema';
commit;
