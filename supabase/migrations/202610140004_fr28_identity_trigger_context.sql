-- The Auth schema is not readable by the PostgREST service_role. Bind identity
-- inside a fixed-path definer trigger, retaining caller checks from trusted JWT.
begin;
set local lock_timeout='5s';
create or replace function public.fr28_guard_identity() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if tg_op='INSERT' then
  if auth.role() in ('authenticated','anon') then
   if new.is_blocked or (new.auth_user_id is not null and new.auth_user_id is distinct from auth.uid()) then
    raise exception 'Account authorization is server managed' using errcode='42501';
   end if;
   new.auth_user_id:=auth.uid();
  elsif new.auth_user_id is null then
   select a.id into new.auth_user_id from auth.users a where lower(a.email)=lower(new.email);
  end if;
 elsif auth.role() in ('authenticated','anon') and
  (new.is_blocked is distinct from old.is_blocked or new.auth_user_id is distinct from old.auth_user_id or new.role is distinct from old.role) then
  raise exception 'Account authorization is server managed' using errcode='42501';
 end if;
 return new;
end$$;
revoke all on function public.fr28_guard_identity() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
