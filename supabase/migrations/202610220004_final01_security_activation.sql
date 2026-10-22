-- Activate ONLY after compatible TEST Edge/client and hosted regressions pass.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create or replace function public.fr28_token_live()returns boolean
language plpgsql stable security definer set search_path='' as $$
declare sid text:=auth.jwt()->>'session_id';begin
 if sid is null or sid!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then return false;end if;
 return exists(select 1 from auth.sessions where id=sid::uuid and user_id=(select auth.uid())
 and final1_private.session_deadline(created_at,not_after)>statement_timestamp());
end $$;
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

-- Installation-secret reads also expire with the issuing server session.
CREATE OR REPLACE FUNCTION public.fr30_resolve_push(p_installation uuid, p_secret text, p_broadcast uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare result jsonb;begin
 if p_installation is null or p_secret is null or p_secret!~'^[0-9a-f]{64}$'or p_broadcast is null then return jsonb_build_object('code','FORBIDDEN');end if;
 select jsonb_build_object('code','OK','id',n.id,'title',n.title,'message',n.message,'broadcast_id',coalesce(n.broadcast_id,n.order_push_event_id))into result
 from fr30_private.push_devices d join fr30_private.push_deliveries j on j.device_id=d.id
 and j.user_id=d.user_id and j.session_id=d.session_id and j.token_hash=d.token_hash and j.secret_hash=d.secret_hash
 join public.users u on u.id=d.user_id and not u.is_blocked
 join auth.users a on a.id=u.auth_user_id and a.email_confirmed_at is not null
 join auth.sessions s on s.id=d.session_id and s.user_id=a.id
 join public.notifications n on n.id=j.notification_id and n.user_id=u.id
 where d.id=p_installation and d.secret_hash=encode(extensions.digest(p_secret,'sha256'),'hex')
 and coalesce(n.broadcast_id,n.order_push_event_id)=p_broadcast and not n.is_read and j.expires_at>clock_timestamp()
 and j.state in('PENDING','PROCESSING','RETRY','PROVIDER_ACCEPTED')
 and final1_private.session_deadline(s.created_at,s.not_after)>clock_timestamp();
 return coalesce(result,jsonb_build_object('code','FORBIDDEN'));
end$function$
;
notify pgrst,'reload schema';
commit;
