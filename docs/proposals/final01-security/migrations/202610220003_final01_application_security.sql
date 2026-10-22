-- Approved deviation C, 2026-10-22: application authorization deadline and
-- shared authenticated REST/Edge budget; not provider refresh/gateway controls.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create function final1_private.session_deadline(p_created timestamptz,p_not_after timestamptz)
returns timestamptz language sql immutable set search_path='' as $$
 select case when p_created is null then null else least(p_created+interval '7 days',p_not_after)end
$$;
revoke all on function final1_private.session_deadline(timestamptz,timestamptz) from public,anon,authenticated;
create or replace function public.fr28_token_live()returns boolean
language plpgsql stable security definer set search_path='' as $$
declare sid text:=auth.jwt()->>'session_id';begin
 if sid is null or sid!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then return false;end if;
 return exists(select 1 from auth.sessions where id=sid::uuid and user_id=(select auth.uid())
 and final1_private.session_deadline(created_at,not_after)>statement_timestamp());
end $$;
create table final1_private.request_limits(
 actor uuid primary key references auth.users(id),window_at timestamptz not null,
 used integer not null check(used between 1 and 100));
alter table final1_private.request_limits enable row level security;
revoke all on final1_private.request_limits from public,anon,authenticated;
create table final1_private.gateway_key(id integer primary key check(id=1),secret bytea not null);
alter table final1_private.gateway_key enable row level security;
revoke all on final1_private.gateway_key from public,anon,authenticated;
insert into final1_private.gateway_key values(1,extensions.gen_random_bytes(32));

-- POST only: commits the counter even though the eventual proxied GET is read-only.
-- No proof/secret leaves this authenticated endpoint.
create function public.final01_authorize_request()returns jsonb
language plpgsql security definer set search_path='' as $$
declare u public.users;uid uuid:=auth.uid();sid text:=auth.jwt()->>'session_id';
 stamp timestamptz:=clock_timestamp();n integer;window_start timestamptz;deadline timestamptz;
begin
 if auth.role()is distinct from 'authenticated' or uid is null then raise exception 'Authentication required'using errcode='42501';end if;
 select * into u from public.users where auth_user_id=uid;
 if u.is_blocked then return jsonb_build_object('code','FR28_ACCOUNT_BLOCKED');end if;
 if not public.fr28_token_live()then return jsonb_build_object('code','FR28_SESSION_REVOKED');end if;
 select final1_private.session_deadline(created_at,not_after)into deadline from auth.sessions where id=sid::uuid and user_id=uid;
 insert into final1_private.request_limits(actor,window_at,used)values(uid,stamp,1)
 on conflict(actor)do update set
 used=case when request_limits.window_at<=stamp-interval '1 minute'then 1 else request_limits.used+1 end,
 window_at=case when request_limits.window_at<=stamp-interval '1 minute'then stamp else request_limits.window_at end
 where request_limits.window_at<=stamp-interval '1 minute'or request_limits.used<100
 returning used,window_at into n,window_start;
 if n is null then
  select window_at into window_start from final1_private.request_limits where actor=uid;
  return jsonb_build_object('code','RATE_LIMITED','retry_after',greatest(1,ceil(extract(epoch from window_start+interval '1 minute'-stamp))::integer));
 end if;
 return jsonb_build_object('code','OK','auth_id',uid,'session_id',sid,'profile_id',u.id,'role',u.role,
 'verification_status',u.verification_status,'session_expires_at',deadline);
end $$;
revoke all on function public.final01_authorize_request()from public,anon,authenticated;
grant execute on function public.final01_authorize_request()to authenticated;

-- Server-only short capability. Forwarded server-to-server, never to Flutter.
create function public.final01_request_ticket(p_actor uuid,p_session uuid,p_method text,p_path text)returns text
language plpgsql security definer set search_path='' as $$
declare stamp text:=floor(extract(epoch from clock_timestamp()))::bigint::text;k bytea;message text;
begin
 if auth.role()is distinct from 'service_role'then raise exception 'Trusted server required'using errcode='42501';end if;
 if p_actor is null or p_session is null or p_method is null or p_method not in('GET','POST','PATCH','DELETE','HEAD')
 or p_path is null or p_path!~'^/(rpc/)?[a-z][a-z0-9_]{0,100}$'then raise exception 'Invalid request'using errcode='22023';end if;
 if not exists(select 1 from auth.sessions where id=p_session and user_id=p_actor and final1_private.session_deadline(created_at,not_after)>clock_timestamp())
 or exists(select 1 from public.users where auth_user_id=p_actor and is_blocked)then raise exception 'Session unavailable'using errcode='42501';end if;
 select secret into strict k from final1_private.gateway_key where id=1;
 message:=p_actor::text||':'||p_session::text||':'||p_method||':'||p_path||':'||stamp;
 return stamp||'.'||encode(extensions.hmac(convert_to(message,'UTF8'),k,'sha256'),'hex');
end $$;
revoke all on function public.final01_request_ticket(uuid,uuid,text,text)from public,anon,authenticated;
grant execute on function public.final01_request_ticket(uuid,uuid,text,text)to service_role;

create or replace function public.fr28_pre_request()returns void
language plpgsql stable security definer set search_path='' as $$
declare route text:='/'||ltrim(coalesce(current_setting('request.path',true),''),'/');
 proof text;stamp text;signature text;k bytea;expected text;sid text:=auth.jwt()->>'session_id';
begin
 if auth.role()is distinct from 'authenticated'then return;end if;
 route:=regexp_replace(route,'^/rest/v1','');
 if route='/rpc/final01_authorize_request'then return;end if;
 perform public.fr28_require_unblocked(auth.uid());
 if not public.fr28_token_live()then raise exception 'FR28_SESSION_REVOKED'using errcode='PT401';end if;
 proof:=coalesce(current_setting('request.headers',true),'{}')::jsonb->>'x-final01-proof';
 if proof is null or proof!~'^[0-9]{10,12}\.[0-9a-f]{64}$'then raise exception 'APPLICATION_GATEWAY_REQUIRED'using errcode='PT403';end if;
 stamp:=split_part(proof,'.',1);signature:=split_part(proof,'.',2);
 if abs(extract(epoch from clock_timestamp())-stamp::bigint)>15 then raise exception 'APPLICATION_GATEWAY_REQUIRED'using errcode='PT403';end if;
 select secret into strict k from final1_private.gateway_key where id=1;
 expected:=encode(extensions.hmac(convert_to(auth.uid()::text||':'||sid||':'||current_setting('request.method',true)||':'||route||':'||stamp,'UTF8'),k,'sha256'),'hex');
 if signature is distinct from expected then raise exception 'APPLICATION_GATEWAY_REQUIRED'using errcode='PT403';end if;
end $$;
-- Existing blocked-account status visibility retained while session is live;
-- the absolute deadline now also constrains own-profile Realtime reads.
create policy final01_users_session_read on public.users as restrictive for select to authenticated using((select public.fr28_token_live()));

-- Bounded failure aggregation; only trusted servers supply classifications.
-- Retention affects ONLY this new action namespace, never existing Admin history.
create table final1_private.failure_limits(actor text not null,endpoint text not null,kind text not null,
 window_at timestamptz not null,primary key(actor,endpoint,kind));
alter table final1_private.failure_limits enable row level security;
revoke all on final1_private.failure_limits from public,anon,authenticated;
create function public.final01_record_failure(p_actor uuid,p_endpoint text,p_kind text)returns boolean
language plpgsql security definer set search_path='' as $$
declare audit_actor bigint;stamp timestamptz:=clock_timestamp();claimed timestamptz;
begin
 if auth.role()is distinct from 'service_role'then raise exception 'Trusted server required'using errcode='42501';end if;
 if p_endpoint is null or p_endpoint not in('rest','security-gateway','admin-user-status','fr04-cnic','fr13-location','fr25-evidence','fr30-dispatch-push','fr32-email-worker','fr32-invoice-url','get-delivery-route','send-delivery-otp','shopping-assistant')
 or p_kind is null or p_kind not in('authentication','authorization','server')then raise exception 'Invalid failure class'using errcode='22023';end if;
 select id into audit_actor from public.users where auth_user_id=p_actor;
 insert into final1_private.failure_limits values(coalesce(p_actor::text,'anonymous'),p_endpoint,p_kind,stamp)
 on conflict(actor,endpoint,kind)do update set window_at=excluded.window_at
 where failure_limits.window_at<=stamp-interval '1 hour' returning window_at into claimed;
 if claimed is null then return false;end if;
 insert into public.security_audit_log(actor_id,action,target_type,target_id)
 values(audit_actor,'final01_api_'||p_kind,p_endpoint,coalesce(audit_actor,0));
 delete from public.security_audit_log where id in(select id from public.security_audit_log
 where action in('final01_api_authentication','final01_api_authorization','final01_api_server')
 and target_type in('rest','security-gateway','admin-user-status','fr04-cnic','fr13-location','fr25-evidence','fr30-dispatch-push','fr32-email-worker','fr32-invoice-url','get-delivery-route','send-delivery-otp','shopping-assistant')
 and created_at<stamp-interval '30 days' order by id limit 100);
 return true;
end $$;
revoke all on function public.final01_record_failure(uuid,text,text)from public,anon,authenticated;
grant execute on function public.final01_record_failure(uuid,text,text)to service_role;
notify pgrst,'reload schema';
commit;
