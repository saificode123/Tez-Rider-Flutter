-- FR-04, TEST-approved encryption design. No existing identity backfill.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create schema if not exists fr04_private;
revoke all on schema fr04_private from public,anon,authenticated;
do $$ begin
  if not exists(select 1 from vault.secrets where name='tezrider_cnic_key_v1') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),
      'tezrider_cnic_key_v1','FR-04 CNIC encryption; retain for ciphertext/backup recovery');
  end if;
end $$;
alter table public.users add column if not exists cnic_submission_status text not null default 'missing'
  check(cnic_submission_status in ('missing','uploading','submitted'));
alter table public.users add column if not exists cnic_upload_id uuid;
alter table public.users add column if not exists cnic_image_digest text;
alter table public.users add column if not exists cnic_upload_started_at timestamptz;
alter table public.users add column if not exists cnic_submitted_at timestamptz;
create index if not exists fr04_approval_queue_idx on public.users(role,verification_status,id desc);
create table if not exists public.security_audit_log(
 id bigint generated always as identity primary key,
 actor_id bigint references public.users(id),action text not null,
 target_type text not null,target_id bigint not null,created_at timestamptz not null default clock_timestamp());
alter table public.security_audit_log enable row level security;
revoke all on public.security_audit_log from public,anon,authenticated;
create index if not exists fr04_audit_actor_idx on public.security_audit_log(actor_id,created_at desc);
create index if not exists fr04_audit_target_idx on public.security_audit_log(target_id,created_at desc);

create function fr04_private.normalize_cnic(p_value text) returns text
language plpgsql immutable set search_path='' as $$ begin
 if p_value is null or p_value !~ '^([0-9]{13}|[0-9]{5}-[0-9]{7}-[0-9])$' then
   raise exception 'CNIC must contain 13 digits or standard dashes' using errcode='22023'; end if;
 return replace(p_value,'-','');
end $$;
create function fr04_private.encrypt_cnic(p_value text) returns text
language plpgsql security definer set search_path='' as $$ declare k text; begin
 select decrypted_secret into strict k from vault.decrypted_secrets where name='tezrider_cnic_key_v1';
 return 'pgp:v1:'||encode(extensions.pgp_sym_encrypt(fr04_private.normalize_cnic(p_value),k,'cipher-algo=aes256,compress-algo=1'),'base64');
end $$;
create function fr04_private.decrypt_cnic(p_value text) returns text
language plpgsql security definer set search_path='' as $$ declare k text; n text; begin
 if p_value is null then return null; end if;
 if p_value like 'pgp:v1:%' then
   select decrypted_secret into strict k from vault.decrypted_secrets where name='tezrider_cnic_key_v1';
   n:=extensions.pgp_sym_decrypt(decode(substr(p_value,8),'base64'),k);
 else n:=fr04_private.normalize_cnic(p_value); end if;
 return n;
end $$;
create function fr04_private.mask_cnic(p_value text) returns text
language plpgsql security definer set search_path='' as $$ declare n text; begin
 n:=fr04_private.decrypt_cnic(p_value);
 if n is null then return null; end if;
 return substr(n,1,1)||'***'||substr(n,5,1)||'-*******-*';
end $$;
create function fr04_private.document_exists(p_user bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.users u join auth.users a on a.email=u.email
   join storage.objects o on o.bucket_id='rider-cnic' and o.name=u.cnic_image_url
   where u.id=p_user and u.role='rider' and u.cnic_submission_status='submitted'
   and u.cnic is not null and u.cnic like 'pgp:v1:%'
   and u.cnic_image_url=a.id::text||'/'||u.cnic_upload_id::text||'/cnic.'||
     case when o.metadata->>'mimetype'='image/jpeg' then 'jpg' else 'png' end
   and o.metadata->>'mimetype' in ('image/jpeg','image/png')
   and (o.metadata->>'size')::bigint between 1 and 5242880
   and u.cnic_image_digest ~ '^[a-f0-9]{64}$')
$$;
create function fr04_private.guard_user() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 if coalesce(auth.role(),'')='authenticated' then
   if tg_op='INSERT' then
     if new.cnic_image_url is not null or new.cnic_submission_status<>'missing'
       or new.cnic_upload_id is not null or new.cnic_image_digest is not null
       or new.cnic_submitted_at is not null or new.cnic_upload_started_at is not null then
       raise exception 'Use the document submission endpoint' using errcode='42501'; end if;
     if new.role='rider' and new.cnic is not null then new.cnic:=fr04_private.encrypt_cnic(new.cnic); end if;
   elsif new.cnic is distinct from old.cnic or new.cnic_image_url is distinct from old.cnic_image_url
       or new.cnic_submission_status is distinct from old.cnic_submission_status
       or new.cnic_upload_id is distinct from old.cnic_upload_id
       or new.cnic_image_digest is distinct from old.cnic_image_digest
       or new.cnic_submitted_at is distinct from old.cnic_submitted_at
       or new.cnic_upload_started_at is distinct from old.cnic_upload_started_at then
     raise exception 'Use the document submission endpoint' using errcode='42501';
   end if;
   if tg_op='UPDATE' and new.role='rider' and new.verification_status='approved'
       and old.verification_status is distinct from 'approved'
       and not fr04_private.document_exists(new.id) then
     raise exception 'A valid CNIC document is required before approval' using errcode='42501'; end if;
 end if;
 return new;
end $$;
create trigger fr04_guard_user before insert or update on public.users
 for each row execute function fr04_private.guard_user();
revoke update(cnic,cnic_image_url) on public.users from authenticated;

create function public.fr04_application_status() returns jsonb
language plpgsql security definer set search_path='' as $$ declare u public.users; begin
 select * into u from public.users where id=public.fr21_actor();
 if u.id is null or u.role<>'rider' then raise exception 'Rider authentication required' using errcode='42501'; end if;
 return jsonb_build_object('id',u.id,'verification_status',u.verification_status,
   'submission_status',u.cnic_submission_status,'document_path',u.cnic_image_url,
   'cnic_masked',fr04_private.mask_cnic(u.cnic),'document_valid',fr04_private.document_exists(u.id));
end $$;
create function public.fr04_begin_upload(p_auth_uid uuid,p_request_id uuid,p_digest text,p_extension text,p_cnic text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u public.users; a auth.users; n text; path text; begin
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
end $$;
create function public.fr04_finish_upload(p_auth_uid uuid,p_request_id uuid,p_path text) returns jsonb
language plpgsql security definer set search_path='' as $$ declare u public.users; o storage.objects; begin
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
end $$;

create function public.fr04_document_authority(p_user_id bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$ declare actor bigint:=public.fr21_actor(); u public.users; begin
 if actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_user_id is null then p_user_id:=actor; end if;
 if actor<>p_user_id and public.fr21_role() is distinct from 'admin' then
   raise exception 'Document access forbidden' using errcode='42501'; end if;
 select * into u from public.users where id=p_user_id and role='rider';
 if u.id is null or not fr04_private.document_exists(u.id) then
   raise exception 'Document not available; ask the rider to resubmit' using errcode='22023'; end if;
 return jsonb_build_object('path',u.cnic_image_url,'user_id',u.id);
end $$;
create function public.fr04_admin_riders(p_before bigint default null,p_limit integer default 30,p_status text default null)
returns setof jsonb language plpgsql security definer set search_path='' as $$ begin
 if public.fr21_role() is distinct from 'admin' then raise exception 'Admin required' using errcode='42501'; end if;
 if p_limit not between 1 and 50 or p_limit is null or (p_status is not null and p_status not in ('pending','approved','rejected','suspended')) then
   raise exception 'Invalid pagination' using errcode='22023'; end if;
 return query select jsonb_build_object('id',u.id,'name',u.name,'email',u.email,'role',u.role,
   'verification_status',u.verification_status,'cnic_masked',fr04_private.mask_cnic(u.cnic),
   'cnic_image_url',u.cnic_image_url,'submission_status',u.cnic_submission_status,
   'document_valid',fr04_private.document_exists(u.id),'rejection_reason',u.rejection_reason)
   from public.users u where u.role='rider' and (p_before is null or u.id<p_before)
   and (p_status is null or u.verification_status=p_status) order by u.id desc limit p_limit;
end $$;
create function public.fr04_review_rider(p_user_id bigint,p_status text) returns jsonb
language plpgsql security definer set search_path='' as $$ declare u public.users; actor bigint:=public.fr21_actor(); begin
 if public.fr21_role() is distinct from 'admin' then raise exception 'Admin required' using errcode='42501'; end if;
 if p_status is null or p_status not in ('approved','rejected') then raise exception 'Invalid review status' using errcode='22023'; end if;
 select * into u from public.users where id=p_user_id and role='rider' for update;
 if u.id is null then raise exception 'Rider not found' using errcode='22023'; end if;
 if p_status='approved' and not fr04_private.document_exists(u.id) then
   raise exception 'A valid CNIC document is required before approval' using errcode='42501'; end if;
 if u.verification_status<>p_status then
   update public.users set verification_status=p_status where id=u.id;
   insert into public.security_audit_log(actor_id,action,target_type,target_id)
     values(actor,'fr04_rider_'||p_status,'users',u.id);
 end if;
 return jsonb_build_object('id',u.id,'verification_status',p_status);
end $$;
create function public.fr04_order_rider_identity(p_order_id bigint) returns jsonb
language plpgsql security definer set search_path='' as $$ declare o public.orders; u public.users; begin
 select * into o from public.orders where id=p_order_id and user_id=public.fr21_actor();
 if o.id is null or public.fr21_role() is distinct from 'customer' then raise exception 'Owned customer order required' using errcode='42501'; end if;
 select * into u from public.users where id=o.rider_id and role='rider';
 if u.id is null then return null; end if;
 return jsonb_build_object('name',u.name,'photo',u.profile_image,'cnic_masked',fr04_private.mask_cnic(u.cnic));
end $$;

-- Clients cannot bypass byte validation or mint a longer-lived signed URL.
-- Authenticated own-folder/admin access is provided by the reviewed Edge API.
create policy fr04_cnic_direct_deny on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id<>'rider-cnic') with check(bucket_id<>'rider-cnic');
revoke all on all functions in schema fr04_private from public,anon,authenticated;
revoke all on function public.fr04_application_status(),public.fr04_document_authority(bigint),
 public.fr04_admin_riders(bigint,integer,text),public.fr04_review_rider(bigint,text),
 public.fr04_order_rider_identity(bigint),public.fr04_begin_upload(uuid,uuid,text,text,text),
 public.fr04_finish_upload(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.fr04_application_status(),public.fr04_document_authority(bigint),
 public.fr04_admin_riders(bigint,integer,text),public.fr04_review_rider(bigint,text),
 public.fr04_order_rider_identity(bigint) to authenticated;
grant execute on function public.fr04_begin_upload(uuid,uuid,text,text,text),public.fr04_finish_upload(uuid,uuid,text) to service_role;
notify pgrst,'reload schema';
commit;
