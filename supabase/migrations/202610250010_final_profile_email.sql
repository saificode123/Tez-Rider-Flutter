-- SRDS2.3.1 email edits use Supabase Auth confirmation, never a client profile write.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function final_delivery_private.sync_verified_auth_email()returns trigger
language plpgsql security definer set search_path=''as $$
declare profile_id bigint;begin
 if new.email_confirmed_at is null or nullif(btrim(new.email),'')is null then return new;end if;
 if new.email is not distinct from old.email and new.email_confirmed_at is not distinct from old.email_confirmed_at then return new;end if;
 if char_length(new.email)>254 or new.email~'[[:cntrl:][:space:]]'then
  raise exception 'Verified email requires identity review'using errcode='22023';end if;
 if exists(select 1 from public.users where auth_user_id is distinct from new.id and lower(email)=lower(new.email))then
  raise exception 'Verified email requires identity reconciliation'using errcode='PT409';end if;
 update public.users set email=new.email where auth_user_id=new.id and email is distinct from new.email returning id into profile_id;
 if profile_id is not null then
  insert into public.security_audit_log(actor_id,action,target_type,target_id)
   values(profile_id,'profile_email_confirmed','users',profile_id);
 end if;
 return new;
end$$;
revoke all on function final_delivery_private.sync_verified_auth_email()from public,anon,authenticated,service_role;
create trigger final_delivery_auth_email_confirmed after update of email,email_confirmed_at on auth.users
 for each row execute function final_delivery_private.sync_verified_auth_email();

create function public.final_delivery_email_status()returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare a auth.users;u public.users;begin
 if auth.role()is distinct from'authenticated'or auth.uid()is null or not public.fr28_token_live()then
  raise exception 'Live authenticated account required'using errcode='42501';end if;
 select *into a from auth.users where id=auth.uid();
 select *into u from public.users where auth_user_id=auth.uid();
 if a.id is null or a.email_confirmed_at is null or u.id is null or u.is_blocked then
  raise exception 'Verified active account required'using errcode='42501';end if;
 return jsonb_build_object('code',case when u.email is distinct from a.email then'PROFILE_SYNC_REQUIRED'else'OK'end,
  'account',a.id,'email',u.email,'pending_email',nullif(to_jsonb(a)->>'email_change',''),
  'verified',true);
end$$;
revoke all on function public.final_delivery_email_status()from public,anon,service_role;
grant execute on function public.final_delivery_email_status()to authenticated;
notify pgrst,'reload schema';
commit;
