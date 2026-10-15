-- FR-28: reviewed additive account authorization. TEST deployment only.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create extension if not exists pg_trgm with schema extensions;
alter table public.users add column is_blocked boolean not null default false;
alter table public.users add column auth_user_id uuid references auth.users(id);
update public.users u set auth_user_id=a.id from auth.users a where lower(a.email)=lower(u.email);
do $$begin
 if exists(select 1 from public.users where auth_user_id is null)then raise exception 'Unbound identities require review';end if;
end$$;
create unique index fr28_user_auth_idx on public.users(auth_user_id);
create index fr28_user_status_role_date_idx on public.users(is_blocked,role,created_at desc nulls last,id desc);
create index fr28_user_role_date_idx on public.users(role,created_at desc nulls last,id desc);
create index fr28_user_date_idx on public.users(created_at desc nulls last,id desc);
create index fr28_user_name_search_idx on public.users using gin(lower(name) extensions.gin_trgm_ops);
create index fr28_user_email_search_idx on public.users using gin(lower(email) extensions.gin_trgm_ops);
create table public.fr28_operations(
 id uuid primary key,actor_id bigint not null references public.users(id),target_id bigint not null references public.users(id),
 desired_blocked boolean not null,state text not null default 'PENDING' check(state in('PENDING','PARTIAL','SYNCED')),
 created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),
 failure_code text check(failure_code in('AUTH_UNCONFIRMED','SESSIONS_UNCONFIRMED','WORKER_UNCONFIRMED')),
 sessions_revoked_at timestamptz,auth_confirmed_at timestamptz);
create unique index fr28_one_pending_target_idx on public.fr28_operations(target_id)where state<>'SYNCED';
create index fr28_operation_actor_idx on public.fr28_operations(actor_id,created_at desc);
create index fr28_operation_target_date_idx on public.fr28_operations(target_id,created_at desc);
alter table public.fr28_operations enable row level security;
revoke all on public.fr28_operations from public,anon,authenticated;
grant all on public.fr28_operations to service_role;
alter table public.security_audit_log add column user_operation_id uuid references public.fr28_operations(id);
create unique index fr28_audit_once_idx on public.security_audit_log(user_operation_id,action)where user_operation_id is not null;

create function public.fr28_identity()returns bigint language sql stable security definer set search_path='' as $$
 select id from public.users where auth_user_id=(select auth.uid())
$$;
create function public.fr28_token_live()returns boolean language plpgsql stable security definer set search_path='' as $$
declare sid text:=auth.jwt()->>'session_id';begin
 if sid is null or sid!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then return false;end if;
 return exists(select 1 from auth.sessions where id=sid::uuid and user_id=(select auth.uid()) and (not_after is null or not_after>now()));
end$$;
create function public.is_current_user_allowed()returns boolean language sql stable security definer set search_path='' as $$
 select public.fr28_token_live() and not exists(select 1 from public.users where auth_user_id=(select auth.uid())and is_blocked)
$$;
create or replace function public.fr21_actor()returns bigint language sql stable security definer set search_path='' as $$
 select u.id from public.users u join auth.users a on a.id=u.auth_user_id where a.id=(select auth.uid())and a.email_confirmed_at is not null and not u.is_blocked and public.fr28_token_live()
$$;
create or replace function public.fr21_approved_rider(p_id bigint)returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.users where id=p_id and role='rider'and verification_status='approved'and not is_blocked)
$$;
create function public.fr28_require_unblocked(p_uid uuid)returns void language plpgsql stable security definer set search_path='' as $$begin
 if exists(select 1 from public.users where auth_user_id=p_uid and is_blocked)then raise exception 'FR28_ACCOUNT_BLOCKED'using errcode='PT403';end if;
end$$;
create function public.fr28_guard_identity()returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='INSERT'then
  if current_user in('authenticated','anon')then
   if new.is_blocked or(new.auth_user_id is not null and new.auth_user_id is distinct from auth.uid())then raise exception 'Account authorization is server managed'using errcode='42501';end if;
   new.auth_user_id:=auth.uid();
  elsif new.auth_user_id is null then select a.id into new.auth_user_id from auth.users a where lower(a.email)=lower(new.email);end if;
 elsif current_user in('authenticated','anon')and(new.is_blocked is distinct from old.is_blocked or new.auth_user_id is distinct from old.auth_user_id or new.role is distinct from old.role)then
  raise exception 'Account authorization is server managed'using errcode='42501';
 end if;return new;
end$$;
create trigger fr28_guard_identity before insert or update on public.users for each row execute function public.fr28_guard_identity();
-- An own profile remains readable to Realtime when blocked, so its one filtered
-- security subscription can receive the block. REST reads still receive 403.
alter policy fr21_test_users_read on public.users using(id=(select public.fr28_identity())or(select public.fr21_role())='admin');
create policy fr28_users_write_guard on public.users as restrictive for update to authenticated
 using((select public.is_current_user_allowed()))with check((select public.is_current_user_allowed()));
create policy fr28_users_delete_guard on public.users as restrictive for delete to authenticated using((select public.is_current_user_allowed()));
do $$declare t record;begin
 for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'and c.relkind='r'and c.relrowsecurity and c.relname not in('users','fr28_operations')loop
  execute format('create policy fr28_session_guard on public.%I as restrictive for all to authenticated using((select public.is_current_user_allowed()))with check((select public.is_current_user_allowed()))',t.relname);
 end loop;
end$$;
create policy fr28_storage_session_guard on storage.objects as restrictive for all to authenticated
 using((select public.is_current_user_allowed()))with check((select public.is_current_user_allowed()));
create function public.fr28_vendor_visible(p_vendor bigint)returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.users where id=p_vendor and role='vendor'and not is_blocked)or public.fr21_role()='admin'
$$;
create policy fr28_product_vendor_guard on public.products as restrictive for select to anon,authenticated
 using(public.fr28_vendor_visible(vendor_id));

create function public.fr28_account_status()returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u public.users;begin
 if auth.uid()is null then raise exception 'Authentication required'using errcode='42501';end if;
 select * into u from public.users where auth_user_id=auth.uid();
 if u.id is null then return jsonb_build_object('code','PROFILE_MISSING');end if;
 return jsonb_build_object('code',case when u.is_blocked then 'FR28_ACCOUNT_BLOCKED'when not public.fr28_token_live()then 'FR28_SESSION_REVOKED'else 'OK'end,
 'id',u.id,'is_blocked',u.is_blocked,'role',u.role,'verification_status',u.verification_status);
end$$;
create function public.fr28_pre_request()returns void language plpgsql stable security definer set search_path='' as $$begin
 if auth.role()is distinct from 'authenticated'then return;end if;
 if current_setting('request.path',true)='/rpc/fr28_account_status'then return;end if;
 perform public.fr28_require_unblocked(auth.uid());
 if not public.fr28_token_live()then raise exception 'FR28_SESSION_REVOKED'using errcode='PT401';end if;
end$$;
-- Explicit HTTP status on REST SELECT as well as writes/RPCs. Other products
-- retain independent RLS/actor guards; this hook is not their security boundary.
do $$begin
 if exists(select 1 from pg_db_role_setting s join pg_roles r on r.oid=s.setrole cross join lateral unnest(s.setconfig) as settings(value) where r.rolname='authenticator'and settings.value like 'pgrst.db_pre_request=%')then raise exception 'Review existing pre-request hook';end if;
end$$;
alter role authenticator set pgrst.db_pre_request='public.fr28_pre_request';

create function public.fr28_user_list(p_search text default '',p_role text default null,p_blocked boolean default null,p_before_at timestamptz default null,p_before_id bigint default null,p_limit integer default 25)
 returns setof jsonb language plpgsql stable security definer set search_path='' as $$
declare needle text;begin
 if public.fr21_role()is distinct from 'admin'then raise exception 'Admin required'using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 50 or length(coalesce(p_search,''))>80 or(p_role is not null and p_role not in('customer','vendor','rider','admin'))or(p_before_at is null and p_before_id is not null)or(p_before_at is not null and p_before_id is null)then raise exception 'Invalid user-list query'using errcode='22023';end if;
 needle:='%'||replace(replace(replace(lower(coalesce(p_search,'')),E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_')||'%';
 return query select jsonb_build_object('id',u.id,'name',u.name,'email',u.email,'role',u.role,'is_blocked',u.is_blocked,'created_at',coalesce(u.created_at,'1970-01-01'::timestamptz),
 'operation_id',o.id,'sync_state',o.state,'desired_blocked',o.desired_blocked)
 from public.users u left join public.fr28_operations o on o.target_id=u.id and o.state<>'SYNCED'
 where(p_role is null or u.role=p_role)and(p_blocked is null or u.is_blocked=p_blocked)
 and(coalesce(p_search,'')=''or lower(u.name)like needle or lower(u.email)like needle)
 and(p_before_at is null or(coalesce(u.created_at,'1970-01-01'::timestamptz),u.id)<(p_before_at,p_before_id))
 order by coalesce(u.created_at,'1970-01-01'::timestamptz)desc,u.id desc limit p_limit;
end$$;
create index fr28_user_cursor_idx on public.users((coalesce(created_at,'1970-01-01'::timestamptz))desc,id desc);
create function public.fr28_active_orders(p_target bigint)returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('order_ids',coalesce(jsonb_agg(id),'[]'::jsonb),'more_than_twenty',count(*)>20)from(
 select o.id from public.orders o where o.order_status not in('delivered','cancelled')and(o.rider_id=p_target or o.user_id=p_target or o.vendor_id=p_target or exists(select 1 from public.vendor_orders v where v.order_id=o.id and v.vendor_id=p_target))order by o.id desc limit 21)s
$$;
create function public.admin_set_user_blocked(p_actor uuid,p_target bigint,p_blocked boolean,p_request uuid)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor public.users;target public.users;op public.fr28_operations;begin
 if auth.role()is distinct from 'service_role'then raise exception 'Server required'using errcode='42501';end if;
 if p_request is null or p_target is null or p_blocked is null then raise exception 'Invalid block request'using errcode='22023';end if;
 select u.* into actor from public.users u join auth.users a on a.id=u.auth_user_id where a.id=p_actor and a.email_confirmed_at is not null;
 if actor.id is null or actor.role is distinct from 'admin'or actor.verification_status is distinct from 'approved'or actor.is_blocked then raise exception 'Admin required'using errcode='42501';end if;
 select * into target from public.users where id=p_target for update;
 if target.id is null then return jsonb_build_object('code','NOT_FOUND');end if;
 if target.id=actor.id then return jsonb_build_object('code','SELF_FORBIDDEN');end if;
 if target.role='admin'then return jsonb_build_object('code','ADMIN_PROTECTED');end if;
 if target.auth_user_id is null then return jsonb_build_object('code','AUTH_IDENTITY_MISSING');end if;
 select * into op from public.fr28_operations where id=p_request;
 if op.id is not null then
  if op.target_id<>p_target or op.desired_blocked<>p_blocked then return jsonb_build_object('code','REQUEST_CONFLICT');end if;
  return jsonb_build_object('code',case when op.state='SYNCED'then 'ALREADY_APPLIED'else 'PENDING'end,'operation_id',op.id,'is_blocked',target.is_blocked,'desired_blocked',op.desired_blocked,'active_orders',public.fr28_active_orders(p_target));
 end if;
 select * into op from public.fr28_operations where target_id=p_target and state<>'SYNCED';
 if op.id is not null then return jsonb_build_object('code','BUSY','operation_id',op.id,'desired_blocked',op.desired_blocked,'is_blocked',target.is_blocked);end if;
 if target.is_blocked=p_blocked then return jsonb_build_object('code','NO_CHANGE','is_blocked',target.is_blocked);end if;
 insert into public.fr28_operations(id,actor_id,target_id,desired_blocked)values(p_request,actor.id,p_target,p_blocked);
 if p_blocked then
  update public.users set is_blocked=true where id=p_target;
  update public.riders set is_online=false,presence_epoch=presence_epoch+1,presence_sequence=0 where userid=p_target;
  insert into public.security_audit_log(actor_id,action,target_type,target_id,user_operation_id)values(actor.id,'BLOCK_USER','users',p_target,p_request);
 end if;
 return jsonb_build_object('code','PENDING','operation_id',p_request,'is_blocked',true,'desired_blocked',p_blocked,'active_orders',public.fr28_active_orders(p_target));
end$$;
-- Worker methods run only behind the trusted server and serialized driver.
create function public.fr28_sync_context(p_id uuid)returns jsonb language plpgsql security definer set search_path='' as $$
declare op public.fr28_operations;u public.users;begin
 if auth.role()is distinct from 'service_role'then raise exception 'Server required'using errcode='42501';end if;
 select * into op from public.fr28_operations where id=p_id for update;
 if op.id is null then raise exception 'Unknown operation'using errcode='22023';end if;
 select * into u from public.users where id=op.target_id for update;
 if op.state='SYNCED'then return jsonb_build_object('code','ALREADY_APPLIED','is_blocked',u.is_blocked);end if;
 if u.role='admin'or not u.is_blocked then raise exception 'Operation state changed'using errcode='42501';end if;
 return jsonb_build_object('code','PENDING','auth_id',u.auth_user_id,'target_id',u.id,'desired_blocked',op.desired_blocked);
end$$;
create function public.fr28_revoke_sessions(p_id uuid)returns void language plpgsql security definer set search_path='' as $$
declare op public.fr28_operations;u public.users;begin
 if auth.role()is distinct from 'service_role'then raise exception 'Server required'using errcode='42501';end if;
 select * into op from public.fr28_operations where id=p_id for update;
 select * into u from public.users where id=op.target_id for update;
 if op.id is null or op.state='SYNCED'or not u.is_blocked or u.role='admin'then raise exception 'Unsafe revocation context'using errcode='42501';end if;
 -- Requested session revocation only; never delete an identity or app record.
 -- Auth Admin ban alone does not remove these sessions. No tokens are read.
 delete from auth.refresh_tokens where user_id=u.auth_user_id::text;
 delete from auth.sessions where user_id=u.auth_user_id;
 update public.fr28_operations set sessions_revoked_at=clock_timestamp()where id=p_id;
end$$;
create function public.fr28_finish(p_id uuid,p_failure text default null)returns jsonb language plpgsql security definer set search_path='' as $$
declare op public.fr28_operations;u public.users;banned boolean;begin
 if auth.role()is distinct from 'service_role'then raise exception 'Server required'using errcode='42501';end if;
 select * into op from public.fr28_operations where id=p_id for update;
 select * into u from public.users where id=op.target_id for update;
 if op.id is null then raise exception 'Unknown operation'using errcode='22023';end if;
 if op.state='SYNCED'then return jsonb_build_object('code','ALREADY_APPLIED','is_blocked',u.is_blocked);end if;
 if p_failure is not null then
  update public.fr28_operations set state='PARTIAL',failure_code=p_failure,updated_at=clock_timestamp()where id=p_id;
  return jsonb_build_object('code','AUTH_SYNC_PENDING','operation_id',p_id,'is_blocked',true);
 end if;
 select coalesce(banned_until>clock_timestamp(),false)into banned from auth.users where id=u.auth_user_id;
 if banned is distinct from op.desired_blocked or op.sessions_revoked_at is null or exists(select 1 from auth.sessions where user_id=u.auth_user_id)or exists(select 1 from auth.refresh_tokens where user_id=u.auth_user_id::text and not revoked)then
  update public.fr28_operations set state='PARTIAL',failure_code='SESSIONS_UNCONFIRMED',updated_at=clock_timestamp()where id=p_id;
  return jsonb_build_object('code','AUTH_SYNC_PENDING','operation_id',p_id,'is_blocked',true);
 end if;
 if not op.desired_blocked then
  update public.users set is_blocked=false where id=u.id;
  insert into public.security_audit_log(actor_id,action,target_type,target_id,user_operation_id)values(op.actor_id,'UNBLOCK_USER','users',u.id,p_id);
 end if;
 update public.fr28_operations set state='SYNCED',failure_code=null,auth_confirmed_at=clock_timestamp(),updated_at=clock_timestamp()where id=p_id;
 return jsonb_build_object('code','OK','operation_id',p_id,'is_blocked',op.desired_blocked,'active_orders',public.fr28_active_orders(u.id));
end$$;
revoke all on function public.fr28_identity(),public.fr28_token_live(),public.is_current_user_allowed(),public.fr28_require_unblocked(uuid),public.fr28_guard_identity(),public.fr28_vendor_visible(bigint),public.fr28_account_status(),public.fr28_pre_request(),public.fr28_user_list(text,text,boolean,timestamptz,bigint,integer),public.fr28_active_orders(bigint),public.admin_set_user_blocked(uuid,bigint,boolean,uuid),public.fr28_sync_context(uuid),public.fr28_revoke_sessions(uuid),public.fr28_finish(uuid,text)from public,anon,authenticated;
grant execute on function public.fr28_identity(),public.fr28_token_live(),public.is_current_user_allowed(),public.fr28_account_status(),public.fr28_user_list(text,text,boolean,timestamptz,bigint,integer)to authenticated;
grant execute on function public.fr28_pre_request()to anon,authenticated,service_role;
grant execute on function public.fr28_vendor_visible(bigint)to anon,authenticated;
grant execute on function public.admin_set_user_blocked(uuid,bigint,boolean,uuid),public.fr28_sync_context(uuid),public.fr28_revoke_sessions(uuid),public.fr28_finish(uuid,text)to service_role;
-- Complete authoritative existing-function guard additions are appended below.

CREATE OR REPLACE FUNCTION public.fr04_begin_upload(p_auth_uid uuid, p_request_id uuid, p_digest text, p_extension text, p_cnic text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u public.users; a auth.users; n text; path text; begin
 perform public.fr28_require_unblocked(p_auth_uid);
 if auth.role() is distinct from 'service_role' then raise exception 'Backend only' using errcode='42501'; end if;
 if p_request_id is null or p_digest !~ '^[a-f0-9]{64}$' or p_extension not in ('jpg','png')
    or p_digest is null or p_extension is null then raise exception 'Invalid document request' using errcode='22023'; end if;
 n:=fr04_private.normalize_cnic(p_cnic);
 select * into a from auth.users where id=p_auth_uid and email_confirmed_at is not null;
 if a.id is null then raise exception 'Verified identity required' using errcode='42501'; end if;
 select * into u from public.users where email=a.email for update;
 if u.id is null or u.role<>'rider' then raise exception 'Rider profile required' using errcode='42501'; end if;
 path:=a.id::text||'/'||p_request_id::text||'/cnic.'||p_extension;
 if u.cnic_upload_id=p_request_id then
   if u.cnic_image_digest<>p_digest or fr04_private.decrypt_cnic(u.cnic)<>n then
     raise exception 'Request reused with different submission' using errcode='PT409'; end if;
   return jsonb_build_object('path',path,'complete',fr04_private.document_exists(u.id));
 end if;
 if u.cnic_submission_status='uploading' and u.cnic_upload_started_at>clock_timestamp()-interval '2 minutes' then
   raise exception 'Another upload is in progress' using errcode='PT409'; end if;
 if exists(select 1 from public.orders where rider_id=u.id and order_status not in ('cancelled','delivered')) then
   raise exception 'Finish the active delivery before replacing identity documents' using errcode='42501'; end if;
 update public.users set cnic=fr04_private.encrypt_cnic(n),cnic_submission_status='uploading',
   cnic_upload_id=p_request_id,cnic_image_digest=p_digest,cnic_upload_started_at=clock_timestamp(),
   verification_status='pending' where id=u.id;
 return jsonb_build_object('path',path,'complete',false);
end $function$;

CREATE OR REPLACE FUNCTION public.fr04_finish_upload(p_auth_uid uuid, p_request_id uuid, p_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare u public.users; o storage.objects; begin
 perform public.fr28_require_unblocked(p_auth_uid);
 if auth.role() is distinct from 'service_role' then raise exception 'Backend only' using errcode='42501'; end if;
 select u0.* into u from public.users u0 join auth.users a on a.email=u0.email
   where a.id=p_auth_uid and a.email_confirmed_at is not null for update of u0;
 if u.id is null or u.role<>'rider' then raise exception 'Rider profile required' using errcode='42501'; end if;
 if u.cnic_upload_id is distinct from p_request_id then raise exception 'Upload changed; retry' using errcode='PT409'; end if;
 select * into o from storage.objects where bucket_id='rider-cnic' and name=p_path;
 if o.id is null or p_path not in (p_auth_uid::text||'/'||p_request_id::text||'/cnic.jpg',p_auth_uid::text||'/'||p_request_id::text||'/cnic.png')
   or o.metadata->>'mimetype' not in ('image/jpeg','image/png')
   or coalesce((o.metadata->>'size')::bigint,0) not between 1 and 5242880 then
   raise exception 'Uploaded document is missing or invalid' using errcode='22023'; end if;
 if u.cnic_submission_status<>'submitted' then
   update public.users set cnic_image_url=p_path,cnic_submission_status='submitted',
     cnic_submitted_at=clock_timestamp(),verification_status='pending' where id=u.id;
   insert into public.security_audit_log(actor_id,action,target_type,target_id)
     values(u.id,'fr04_document_submitted','users',u.id);
 end if;
 return jsonb_build_object('submission_status','submitted','verification_status','pending','path',p_path);
end $function$;

CREATE OR REPLACE FUNCTION public.fr25_begin_evidence(p_auth_id uuid, p_request_id uuid, p_digest text, p_mime text, p_size integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare d fr25_private.drafts; p text; begin
 perform public.fr28_require_unblocked(p_auth_id);

 select * into d from fr25_private.drafts where id=p_request_id for update;

 if d.id is null or d.auth_id is distinct from p_auth_id or d.state<>'draft' then raise exception 'Evidence access forbidden' using errcode='42501'; end if;

 perform fr25_private.check_order(d.order_id,d.customer_id);

 if p_digest is null or p_digest!~'^[0-9a-f]{64}$' or p_mime is null or p_mime not in ('image/png','image/jpeg')

 or p_size is null or p_size not between 1 and 5242880 then raise exception 'Invalid image' using errcode='22023'; end if;

 p:=d.auth_id||'/'||d.id||'/'||p_digest||case when p_mime='image/png' then '.png' else '.jpg' end;

 if not exists(select 1 from fr25_private.evidence where path=p) and (select count(*) from fr25_private.evidence where draft_id=d.id)>=3 then

  raise exception 'Select 1–3 evidence images.' using errcode='22023'; end if;

 insert into fr25_private.evidence(path,draft_id,digest,mime,size,uploaded) values(p,d.id,p_digest,p_mime,p_size,false) on conflict(path) do nothing;

 return p;

end $function$;

CREATE OR REPLACE FUNCTION public.fr25_finish_upload(p_auth_id uuid, p_request_id uuid, p_digest text, p_mime text, p_size integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare d fr25_private.drafts; p text; o storage.objects; begin
 perform public.fr28_require_unblocked(p_auth_id);

 select * into d from fr25_private.drafts where id=p_request_id for update;

 if d.id is null or d.auth_id is distinct from p_auth_id or d.state<>'draft' then

   raise exception 'Evidence access forbidden' using errcode='42501'; end if;

 perform fr25_private.check_order(d.order_id,d.customer_id);

 if p_digest is null or p_digest!~'^[0-9a-f]{64}$' or p_mime is null or p_mime not in ('image/png','image/jpeg')

 or p_size is null or p_size not between 1 and 5242880 then raise exception 'Invalid image' using errcode='22023'; end if;

 p:=d.auth_id||'/'||d.id||'/'||p_digest||case when p_mime='image/png' then '.png' else '.jpg' end;

 select * into o from storage.objects where bucket_id='dispute-evidence' and name=p;

 if o.id is null or o.metadata->>'mimetype' is distinct from p_mime or (o.metadata->>'size')::bigint is distinct from p_size::bigint then

   raise exception 'Uploaded evidence is missing or invalid' using errcode='22023'; end if;

 if not exists(select 1 from fr25_private.evidence where path=p) and

   (select count(*) from fr25_private.evidence where draft_id=d.id)>=3 then

   raise exception 'Select 1–3 evidence images.' using errcode='22023'; end if;

 insert into fr25_private.evidence(path,draft_id,digest,mime,size,uploaded) values(p,d.id,p_digest,p_mime,p_size,true) on conflict(path) do update set uploaded=true;

 return p;

end $function$;

CREATE OR REPLACE FUNCTION public.issue_delivery_otp(p_order_id bigint, p_request_id uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.orders; a bigint; existing public.delivery_otps; latest timestamptz; n int;
 recipient text; review_admin bigint; random_bytes bytea; number int; code text; salt text; budget int; used_count int; moment timestamptz:=clock_timestamp(); begin
 perform public.fr28_require_unblocked(p_actor);
 if auth.role() is distinct from 'service_role' then raise exception 'Server issuance required' using errcode='42501'; end if;
 select u.id into a from public.users u join auth.users au on au.email=u.email where au.id=p_actor and au.email_confirmed_at is not null and u.role='rider' and u.verification_status='approved';
 select * into o from public.orders where id=p_order_id for update;
 if a is null or o.id is null or o.rider_id is distinct from a or not public.fr21_approved_rider(a) then return jsonb_build_object('code','FORBIDDEN'); end if;
 if o.order_status='delivered' then return jsonb_build_object('code','ALREADY_DELIVERED'); end if;
 if o.order_status is distinct from 'on_the_way' or p_request_id is null then return jsonb_build_object('code','WRONG_STATE'); end if;
 update public.delivery_otps set state=case when state='RESERVED' then 'FAILED' else 'UNKNOWN' end where order_id=o.id and state in ('RESERVED','SENDING') and lease_until<=moment;
 select * into existing from public.delivery_otps where id=p_request_id;
 if found then
  if existing.order_id<>o.id or existing.auth_id<>p_actor then return jsonb_build_object('code','FORBIDDEN'); end if;
  return jsonb_build_object('code',case existing.state when 'ACCEPTED' then case when existing.expires_at>moment then 'EMAIL_ACCEPTED' else 'EXPIRED' end when 'FAILED' then 'EMAIL_FAILED' when 'UNKNOWN' then 'EMAIL_UNKNOWN' when 'RESERVED' then 'EMAIL_PENDING' when 'SENDING' then 'EMAIL_PENDING' else 'EXPIRED' end,'replayed',true);
 end if;
 -- Expired leases never resend. The old accepted issuance is retained until replacement acceptance.
 if exists(select 1 from public.delivery_otps where order_id=o.id and state in ('RESERVED','SENDING')) then return jsonb_build_object('code','EMAIL_PENDING'); end if;
 select count(*),max(created_at) into n,latest from public.delivery_otps where order_id=o.id;
 if n>=5 then return jsonb_build_object('code','ISSUANCE_LIMIT'); end if;
 if latest>moment-interval '60 seconds' then return jsonb_build_object('code','COOLDOWN','retry_after',ceil(extract(epoch from latest+interval '60 seconds'-moment))); end if;
 select au.email into recipient from public.users u join auth.users au on au.email=u.email where u.id=o.user_id and u.role='customer' and au.email_confirmed_at is not null;
 if recipient is null then return jsonb_build_object('code','EMAIL_UNAVAILABLE'); end if;
 select id into review_admin from public.users where role='admin' and verification_status='approved' order by id limit 1;
 if review_admin is null then return jsonb_build_object('code','ADMIN_UNAVAILABLE'); end if;
 insert into public.delivery_otp_budgets(day,used) values((moment at time zone 'UTC')::date,0) on conflict do nothing;
 select used into budget from public.delivery_otp_budgets where day=(moment at time zone 'UTC')::date for update;
 if budget>=300 then return jsonb_build_object('code','QUOTA_EXCEEDED'); end if;
 insert into public.delivery_otp_rates(rider_id,window_at,used) values(a,moment,0) on conflict do nothing;
 perform 1 from public.delivery_otp_rates where rider_id=a for update;
 update public.delivery_otp_rates set used=0,window_at=moment where rider_id=a and window_at<=moment-interval '1 minute';
 select used into used_count from public.delivery_otp_rates where rider_id=a;
 if used_count>=10 then return jsonb_build_object('code','RATE_LIMIT','retry_after',60); end if;
 loop
  random_bytes:=extensions.gen_random_bytes(3);number:=get_byte(random_bytes,0)*65536+get_byte(random_bytes,1)*256+get_byte(random_bytes,2);
  if number<16000000 then
   code:=lpad((number%1000000)::text,6,'0');
   exit when not exists(select 1 from public.delivery_otps history where history.order_id=o.id and public.fr33_equal(history.verifier,public.fr33_tag(o.id,history.nonce,code)));
  end if;
 end loop;
 salt:=encode(extensions.gen_random_bytes(24),'hex');
 insert into public.delivery_otps(id,order_id,rider_id,review_admin_id,auth_id,nonce,verifier,state,lease_until)
 values(p_request_id,o.id,a,review_admin,p_actor,salt,public.fr33_tag(o.id,salt,code),'RESERVED',moment+interval '90 seconds');
 update public.delivery_otp_budgets set used=used+1 where day=(moment at time zone 'UTC')::date;
 update public.delivery_otp_rates set used=used+1 where rider_id=a;
 insert into public.security_audit_log(actor_id,action,target_type,target_id,otp_operation_id) values(a,'delivery_otp_reserved','order',o.id,p_request_id);
 -- Privileged response only. No caller/client gets this data; no plaintext is persisted.
 return jsonb_build_object('code','SEND','otp',code,'recipient',recipient,'issuance_id',p_request_id);
end $function$;
do $$begin if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'and schemaname='public'and tablename='users')then alter publication supabase_realtime add table public.users;end if;end$$;
notify pgrst,'reload config';
notify pgrst,'reload schema';
commit;
