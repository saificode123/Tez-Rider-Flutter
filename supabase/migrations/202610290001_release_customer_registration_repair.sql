-- FR01/03/07/23/24: reconcile a confirmed legacy Customer during the existing
-- authenticated registration-completion call. No bulk backfill, role changes,
-- CNIC approval, new notification or feature-level permission relaxation.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create or replace function public.final2_complete_registration(
 p_name text default null,p_phone text default null,p_role text default null,
 p_store_name text default null,p_store_address text default null,p_update_profile boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a auth.users;u public.users;v public.vendors;chosen text;begin
 if auth.role()is distinct from'authenticated'or auth.uid()is null or not public.fr28_token_live()then
  raise exception 'A live authenticated session is required'using errcode='42501';end if;
 select *into a from auth.users where id=auth.uid()for update;
 if a.id is null or a.email_confirmed_at is null then raise exception 'Verified email required'using errcode='42501';end if;
 select *into u from public.users where auth_user_id=a.id for update;
 if u.is_blocked then raise exception 'FR28_ACCOUNT_BLOCKED'using errcode='PT403';end if;
 chosen:=coalesce(u.role,p_role,'customer');
 if u.id is null then
  if chosen not in('customer','vendor','rider')then raise exception 'Invalid registration role'using errcode='22023';end if;
 end if;
 if u.id is null or p_update_profile is true then
  if nullif(btrim(p_name),'')is null or nullif(btrim(p_phone),'')is null then
   return jsonb_build_object('code','PROFILE_REQUIRED','role',chosen);end if;
  if char_length(btrim(p_name))>120 or p_name~'[[:cntrl:]]'or char_length(p_phone)>32
   or p_phone!~'^[+0-9() .-]+$'or p_phone!~'[0-9]'then raise exception 'Invalid profile details'using errcode='22023';end if;
 end if;
 if chosen='vendor'then
  select *into v from public.vendors where user_id=u.id for update;
  if v.id is null then
   if nullif(btrim(p_store_name),'')is null or nullif(btrim(p_store_address),'')is null then
    return jsonb_build_object('code','STORE_REQUIRED','role',chosen);end if;
   if char_length(btrim(p_store_name))>200 or char_length(btrim(p_store_address))>500
    or p_store_name~'[[:cntrl:]]'or p_store_address~'[[:cntrl:]]'then
    raise exception 'Invalid store details'using errcode='22023';end if;
  end if;
 end if;
 if u.id is null then
  if exists(select 1 from public.users where lower(email)=lower(a.email))then
   raise exception 'Existing profile requires identity reconciliation'using errcode='PT409';end if;
  insert into public.users(name,email,phone,role,verification_status,auth_user_id)
  values(btrim(p_name),a.email,btrim(p_phone),chosen,case when chosen='customer'then'approved'else'pending'end,a.id)
  returning *into u;
 elsif p_update_profile is true then
  update public.users set name=btrim(p_name),phone=btrim(p_phone)where id=u.id returning *into u;
 end if;
 -- Customer registration is automatic after confirmed email. Legacy profiles
 -- created before this API may still carry the generic pending default.
 -- Reconcile only this authenticated Customer, not Vendors/Riders or an
 -- explicitly rejected/suspended/blocked account. Preserve all profile fields.
 if chosen='customer'and u.verification_status='pending'then
  if nullif(btrim(u.name),'')is null or char_length(btrim(u.name))>120 or u.name~'[[:cntrl:]]'
   or nullif(btrim(u.phone),'')is null or char_length(u.phone)>32
   or u.phone!~'^[+0-9() .-]+$'or u.phone!~'[0-9]'then
   return jsonb_build_object('code','PROFILE_REQUIRED','role',chosen);
  end if;
  update public.users set verification_status='approved'
   where id=u.id and role='customer'and not is_blocked and verification_status='pending'
   returning *into u;
  insert into public.security_audit_log(actor_id,action,target_type,target_id)
   values(u.id,'customer_registration_reconciled','users',u.id);
 end if;
 if chosen='vendor'and v.id is null then
  insert into public.vendors(user_id,store_name,address,is_active)
  values(u.id,btrim(p_store_name),btrim(p_store_address),u.verification_status='approved')returning *into v;
 end if;
 return jsonb_build_object('code','OK','id',u.id,'role',u.role,'verification_status',u.verification_status,
  'rejection_reason',u.rejection_reason,'store_id',v.id,'name',u.name,'phone',u.phone);
end$$;

revoke all on function public.final2_complete_registration(text,text,text,text,text,boolean)from public,anon;
grant execute on function public.final2_complete_registration(text,text,text,text,text,boolean)to authenticated;
notify pgrst,'reload schema';
commit;
