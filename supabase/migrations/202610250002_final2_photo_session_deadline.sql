-- Recheck the accepted 168-hour application deadline at trusted upload completion.
begin;
set local lock_timeout='5s';
create or replace function final2_private.photo_actor(p_auth uuid,p_session uuid)returns bigint
language plpgsql stable security definer set search_path=''as $$declare actor bigint;begin
 select u.id into actor from public.users u join auth.users a on a.id=u.auth_user_id
 where u.auth_user_id=p_auth and not u.is_blocked and u.verification_status='approved'
 and a.email_confirmed_at is not null and exists(select 1 from auth.sessions s
 where s.id=p_session and s.user_id=p_auth and final1_private.session_deadline(s.created_at,s.not_after)>clock_timestamp());
 if actor is null then raise exception 'Approved live account required'using errcode='42501';end if;
 return actor;end$$;
revoke all on function final2_private.photo_actor(uuid,uuid)from public,anon,authenticated,service_role;

commit;
