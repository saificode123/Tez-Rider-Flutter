-- Approved Android TEST push. Disabled until valid Firebase configuration exists.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
alter table fr30_private.limits add column android_push_enabled boolean not null default false;
create table fr30_private.push_devices(
 id uuid primary key,
 user_id bigint not null references public.users(id),
 session_id uuid not null references auth.sessions(id)on delete cascade,
 token text not null check(char_length(token)between 16 and 4096 and token~'^[A-Za-z0-9:_-]+$'),
 token_hash text not null unique,
 secret_hash text not null,
 updated_at timestamptz not null default clock_timestamp());
create index fr30_push_device_owner_idx on fr30_private.push_devices(user_id);
create table fr30_private.push_deliveries(
 id uuid primary key default gen_random_uuid(),
 notification_id bigint not null references public.notifications(id),
 device_id uuid references fr30_private.push_devices(id)on delete set null,
 user_id bigint not null references public.users(id),
 session_id uuid not null,
 token_hash text not null,
 secret_hash text not null,
 state text not null default 'PENDING'check(state in('PENDING','PROCESSING','RETRY','PROVIDER_ACCEPTED','SKIPPED','EXPIRED','FAILED')),
 attempts integer not null default 0 check(attempts between 0 and 5),
 due_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default clock_timestamp()+interval '1 hour',
 lease uuid,leased_at timestamptz,
 provider_message text check(char_length(provider_message)<=300),
 failure_code text check(failure_code in('TRANSIENT','INVALID_TOKEN','PROVIDER_REJECTED','SESSION_CHANGED')),
 created_at timestamptz not null default clock_timestamp(),
 unique(notification_id,device_id));
create index fr30_push_due_idx on fr30_private.push_deliveries(due_at,id)where state in('PENDING','RETRY');
create index fr30_push_lease_idx on fr30_private.push_deliveries(leased_at)where state='PROCESSING';
create index fr30_push_delivery_device_idx on fr30_private.push_deliveries(device_id);
revoke all on fr30_private.push_devices,fr30_private.push_deliveries from public,anon,authenticated;
alter table fr30_private.push_devices enable row level security;
alter table fr30_private.push_deliveries enable row level security;

create function public.fr30_register_push(p_installation uuid,p_token text,p_secret text)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();sid uuid;digest text;begin
 if actor is null then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_installation is null or p_token is null or char_length(p_token)not between 16 and 4096 or p_token!~'^[A-Za-z0-9:_-]+$'
 or p_secret is null or p_secret!~'^[0-9a-f]{64}$'then return jsonb_build_object('code','INVALID_INPUT');end if;
 if not(select android_push_enabled from fr30_private.limits where singleton)then return jsonb_build_object('code','PUSH_NOT_CONFIGURED');end if;
 sid:=(auth.jwt()->>'session_id')::uuid;
 perform 1 from public.users where id=actor for no key update;
 if not public.is_current_user_allowed()then return jsonb_build_object('code','FORBIDDEN');end if;
 if(select count(*)from fr30_private.push_devices where user_id=actor and id<>p_installation)>=5 then return jsonb_build_object('code','DEVICE_LIMIT');end if;
 digest:=encode(extensions.digest(p_token,'sha256'),'hex');
 -- A registration token is opaque device capability, never returned to readers.
 -- Rebinding to a fresh authenticated session invalidates old snapshot jobs.
 delete from fr30_private.push_devices where token_hash=digest and id<>p_installation;
 insert into fr30_private.push_devices(id,user_id,session_id,token,token_hash,secret_hash)
 values(p_installation,actor,sid,p_token,digest,encode(extensions.digest(p_secret,'sha256'),'hex'))
 on conflict(id)do update set user_id=excluded.user_id,session_id=excluded.session_id,
 token=excluded.token,token_hash=excluded.token_hash,secret_hash=excluded.secret_hash,updated_at=clock_timestamp();
 return jsonb_build_object('code','REGISTERED');
end$$;
create function public.fr30_unregister_push(p_installation uuid)returns jsonb
language plpgsql security definer set search_path='' as $$begin
 if public.fr21_actor()is null then return jsonb_build_object('code','FORBIDDEN');end if;
 delete from fr30_private.push_devices where id=p_installation and user_id=public.fr21_actor()
 and session_id=(auth.jwt()->>'session_id')::uuid;
 return jsonb_build_object('code','UNREGISTERED');
end$$;
create function fr30_private.queue_push()returns trigger
language plpgsql security definer set search_path='' as $$begin
 if new.broadcast_id is not null and(select android_push_enabled from fr30_private.limits where singleton)then
  insert into fr30_private.push_deliveries(notification_id,device_id,user_id,session_id,token_hash,secret_hash)
  select new.id,d.id,d.user_id,d.session_id,d.token_hash,d.secret_hash from fr30_private.push_devices d
  join public.users u on u.id=d.user_id join auth.sessions s on s.id=d.session_id and s.user_id=u.auth_user_id
  where d.user_id=new.user_id and not u.is_blocked and(s.not_after is null or s.not_after>clock_timestamp())
  on conflict(notification_id,device_id)do nothing;
 end if;return new;
end$$;
create trigger fr30_queue_push after insert on public.notifications for each row execute function fr30_private.queue_push();
create function fr30_private.block_push()returns trigger
language plpgsql security definer set search_path='' as $$begin
 if new.is_blocked and not old.is_blocked then
  delete from fr30_private.push_devices where user_id=new.id;
  update fr30_private.push_deliveries set state='SKIPPED',failure_code='SESSION_CHANGED',lease=null
  where user_id=new.id and state in('PENDING','RETRY','PROCESSING');
 end if;return new;
end$$;
create trigger fr30_block_push after update of is_blocked on public.users for each row execute function fr30_private.block_push();

create function public.fr30_claim_push(p_limit integer default 50)returns setof jsonb
language plpgsql security definer set search_path='' as $$begin
 if auth.role()is distinct from 'service_role'then raise exception 'Worker only'using errcode='42501';end if;
 if not(select android_push_enabled from fr30_private.limits where singleton)then return;end if;
 -- Bounded recovery after worker interruption. Provider delivery is at-least-once;
 -- device rendering uses a stable broadcast tag and no confidential FCM payload.
 update fr30_private.push_deliveries set state='RETRY',lease=null,due_at=clock_timestamp()
 where id in(select id from fr30_private.push_deliveries where state='PROCESSING'and leased_at<clock_timestamp()-interval '2 minutes'order by leased_at limit 100 for update skip locked);
 update fr30_private.push_deliveries j set state=case when j.expires_at<=clock_timestamp()then 'EXPIRED'else 'SKIPPED'end,lease=null
 where j.id in(select q.id from fr30_private.push_deliveries q
  where q.state in('PENDING','RETRY')and(q.expires_at<=clock_timestamp()or q.attempts>=5 or not exists(
   select 1 from fr30_private.push_devices d join public.users u on u.id=d.user_id
   join auth.sessions s on s.id=d.session_id and s.user_id=u.auth_user_id
   where d.id=q.device_id and d.user_id=q.user_id and d.session_id=q.session_id and d.token_hash=q.token_hash and d.secret_hash=q.secret_hash
   and not u.is_blocked and(s.not_after is null or s.not_after>clock_timestamp())))
  order by q.due_at limit 100 for update skip locked);
 return query with selected as(
  select j.id from fr30_private.push_deliveries j where j.state in('PENDING','RETRY')and j.due_at<=clock_timestamp()
  and j.expires_at>clock_timestamp()and j.attempts<5
  order by j.due_at,j.id limit least(greatest(coalesce(p_limit,50),1),50)for update skip locked
 ),claimed as(
  update fr30_private.push_deliveries j set state='PROCESSING',lease=gen_random_uuid(),leased_at=clock_timestamp(),attempts=j.attempts+1
  from selected s where j.id=s.id returning j.*
 )select jsonb_build_object('job_id',j.id,'lease',j.lease,'token',d.token,'broadcast_id',n.broadcast_id)
 from claimed j join fr30_private.push_devices d on d.id=j.device_id and d.user_id=j.user_id
 and d.session_id=j.session_id and d.token_hash=j.token_hash and d.secret_hash=j.secret_hash
 join public.users u on u.id=d.user_id and not u.is_blocked
 join auth.sessions s on s.id=d.session_id and s.user_id=u.auth_user_id
 join public.notifications n on n.id=j.notification_id
 where(s.not_after is null or s.not_after>clock_timestamp());
end$$;
create function public.fr30_finish_push(p_job uuid,p_lease uuid,p_outcome text,p_provider_message text default null)returns jsonb
language plpgsql security definer set search_path='' as $$declare j fr30_private.push_deliveries;begin
 if auth.role()is distinct from 'service_role'then raise exception 'Worker only'using errcode='42501';end if;
 if p_outcome is null or p_outcome not in('ACCEPTED','RETRY','INVALID_TOKEN','REJECTED','SKIPPED')or char_length(p_provider_message)>300 then raise exception 'Invalid outcome'using errcode='22023';end if;
 select * into j from fr30_private.push_deliveries where id=p_job for update;
 if not found or j.state<>'PROCESSING'or j.lease is distinct from p_lease then return jsonb_build_object('code','STALE_LEASE');end if;
 update fr30_private.push_deliveries set
  state=case p_outcome when 'ACCEPTED'then 'PROVIDER_ACCEPTED'when 'SKIPPED'then 'SKIPPED'when 'RETRY'then case when j.attempts>=5 then 'FAILED'else 'RETRY'end else 'FAILED'end,
  due_at=clock_timestamp()+make_interval(secs=>least(3600,30*(2^j.attempts)::integer)),lease=null,
  provider_message=case when p_outcome='ACCEPTED'then p_provider_message else null end,
  failure_code=case p_outcome when 'ACCEPTED'then null when 'SKIPPED'then 'SESSION_CHANGED'when 'RETRY'then 'TRANSIENT'when 'INVALID_TOKEN'then 'INVALID_TOKEN'else 'PROVIDER_REJECTED'end
 where id=j.id;
 if p_outcome='INVALID_TOKEN'then delete from fr30_private.push_devices where id=j.device_id and token_hash=j.token_hash;end if;
 return jsonb_build_object('code','RECORDED');
end$$;
create function public.fr30_push_eligible(p_job uuid,p_lease uuid)returns boolean
language plpgsql stable security definer set search_path='' as $$begin
 if auth.role()is distinct from 'service_role'then raise exception 'Worker only'using errcode='42501';end if;
 return exists(select 1 from fr30_private.push_deliveries j
 join fr30_private.push_devices d on d.id=j.device_id and d.user_id=j.user_id
 and d.session_id=j.session_id and d.token_hash=j.token_hash and d.secret_hash=j.secret_hash
 join public.users u on u.id=d.user_id and not u.is_blocked
 join auth.users a on a.id=u.auth_user_id and a.email_confirmed_at is not null
 join auth.sessions s on s.id=d.session_id and s.user_id=a.id
 join public.notifications n on n.id=j.notification_id and n.user_id=u.id and not n.is_read
 where j.id=p_job and j.lease=p_lease and j.state='PROCESSING'and j.expires_at>clock_timestamp()
 and(s.not_after is null or s.not_after>clock_timestamp()));
end$$;
-- Background rendering uses a narrowly scoped device capability, not a stored
-- access JWT (which can expire while the app is terminated). It can resolve only
-- an existing one-hour job for this installation, snapshot, live Auth session and
-- unblocked confirmed owner. No registration/list/read-state operations allowed.
create function public.fr30_resolve_push(p_installation uuid,p_secret text,p_broadcast uuid)returns jsonb
language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 if p_installation is null or p_secret is null or p_secret!~'^[0-9a-f]{64}$'or p_broadcast is null then return jsonb_build_object('code','FORBIDDEN');end if;
 select jsonb_build_object('code','OK','id',n.id,'title',n.title,'message',n.message,'broadcast_id',n.broadcast_id)into result
 from fr30_private.push_devices d join fr30_private.push_deliveries j on j.device_id=d.id
 and j.user_id=d.user_id and j.session_id=d.session_id and j.token_hash=d.token_hash and j.secret_hash=d.secret_hash
 join public.users u on u.id=d.user_id and not u.is_blocked
 join auth.users a on a.id=u.auth_user_id and a.email_confirmed_at is not null
 join auth.sessions s on s.id=d.session_id and s.user_id=a.id
 join public.notifications n on n.id=j.notification_id and n.user_id=u.id
 where d.id=p_installation and d.secret_hash=encode(extensions.digest(p_secret,'sha256'),'hex')
 and n.broadcast_id=p_broadcast and not n.is_read and j.expires_at>clock_timestamp()
 and j.state in('PENDING','PROCESSING','RETRY','PROVIDER_ACCEPTED')
 and(s.not_after is null or s.not_after>clock_timestamp());
 return coalesce(result,jsonb_build_object('code','FORBIDDEN'));
end$$;
revoke all on function public.fr30_register_push(uuid,text,text),public.fr30_unregister_push(uuid)from public,anon;
grant execute on function public.fr30_register_push(uuid,text,text),public.fr30_unregister_push(uuid)to authenticated;
revoke all on function public.fr30_resolve_push(uuid,text,uuid)from public;
grant execute on function public.fr30_resolve_push(uuid,text,uuid)to anon,authenticated;
revoke all on function public.fr30_claim_push(integer),public.fr30_finish_push(uuid,uuid,text,text),public.fr30_push_eligible(uuid,uuid)from public,anon,authenticated;
grant execute on function public.fr30_claim_push(integer),public.fr30_finish_push(uuid,uuid,text,text),public.fr30_push_eligible(uuid,uuid)to service_role;
revoke all on function fr30_private.queue_push(),fr30_private.block_push()from public,anon,authenticated;
-- Free Supabase scheduler; no HTTP work while disabled or without due jobs.
-- The worker key is provisioned separately in Vault and Edge secrets, never SQL source.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create function fr30_private.dispatch_push()returns void
language plpgsql security definer set search_path='' as $$declare worker text;begin
 if not(select android_push_enabled from fr30_private.limits where singleton)then return;end if;
 if not exists(select 1 from fr30_private.push_deliveries where
 (state in('PENDING','RETRY')and due_at<=clock_timestamp())or
 (state='PROCESSING'and leased_at<clock_timestamp()-interval '2 minutes'))then return;end if;
 select decrypted_secret into worker from vault.decrypted_secrets where name='fr30_android_push_worker'limit 1;
 if worker is null or char_length(worker)<32 then return;end if;
 perform net.http_post(url:='https://igeisilhtmglgnqvllrx.supabase.co/functions/v1/fr30-dispatch-push',
 headers:=jsonb_build_object('Content-Type','application/json','x-fr30-worker-key',worker),
 body:='{"source":"cron"}'::jsonb,timeout_milliseconds:=10000);
end$$;
revoke all on function fr30_private.dispatch_push()from public,anon,authenticated;
select cron.schedule('fr30-android-push','* * * * *','select fr30_private.dispatch_push()');
notify pgrst,'reload schema';
commit;
