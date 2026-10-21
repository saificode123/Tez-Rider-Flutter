-- Stage1: additive TEST security changes. No backfill, deletion or secret changes.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create schema if not exists final1_private;
revoke all on schema final1_private from public,anon,authenticated;
alter table fr30_private.limits enable row level security;

create table if not exists final1_private.assistant_limits(
 actor_id bigint primary key references public.users(id),
 window_at timestamptz not null,
 used integer not null check(used between 1 and 10)
);
alter table final1_private.assistant_limits enable row level security;
revoke all on final1_private.assistant_limits from public,anon,authenticated;

create or replace function public.final1_claim_assistant() returns boolean
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); t timestamptz:=clock_timestamp(); n integer;
begin
 if actor is null or not exists(select 1 from public.users where id=actor
   and(role='customer' or verification_status='approved')) then
   raise exception 'Authorized account required' using errcode='42501';
 end if;
 insert into final1_private.assistant_limits(actor_id,window_at,used) values(actor,t,1)
 on conflict(actor_id) do update set
   used=case when assistant_limits.window_at<=t-interval '1 minute' then 1 else assistant_limits.used+1 end,
   window_at=case when assistant_limits.window_at<=t-interval '1 minute' then t else assistant_limits.window_at end
 where assistant_limits.window_at<=t-interval '1 minute' or assistant_limits.used<10
 returning used into n;
 return n is not null;
end $$;
revoke all on function public.final1_claim_assistant() from public,anon,authenticated;
grant execute on function public.final1_claim_assistant() to authenticated;

-- Trigger validation also covers legacy direct client profile updates.
-- No mandatory field added; unchanged legacy values remain compatible.
create or replace function final1_private.validate_profile() returns trigger
language plpgsql set search_path='' as $$
begin
 if auth.role()='authenticated' then
   if tg_op='INSERT' or new.name is distinct from old.name then
     if new.name is null or length(btrim(new.name)) not between 1 and 120
       or new.name ~ '[[:cntrl:]]' then
       raise exception 'Invalid profile name' using errcode='22023';
     end if;
   end if;
   if tg_op='INSERT' or new.phone is distinct from old.phone then
     if new.phone is not null and(new.phone !~ '^[+0-9() .-]{0,32}$') then
       raise exception 'Invalid phone number' using errcode='22023';
     end if;
   end if;
 end if;
 return new;
end $$;
revoke all on function final1_private.validate_profile() from public,anon,authenticated;
drop trigger if exists final1_validate_profile on public.users;
create trigger final1_validate_profile before insert or update of name,phone on public.users
 for each row execute function final1_private.validate_profile();

-- Audit actual vendor moderation even through the legacy direct UPDATE path.
-- Ordinary clients cannot invoke this trigger function or insert an audit row.
create or replace function final1_private.audit_vendor_review() returns trigger
language plpgsql security definer set search_path='' as $$
declare actor bigint;
begin
 if old.role='vendor' and new.verification_status is distinct from old.verification_status
   and auth.role()='authenticated' then
   actor:=public.fr21_actor();
   if actor is null or public.fr21_role() is distinct from 'admin' then
     raise exception 'Approved administrator required' using errcode='42501';
   end if;
   insert into public.security_audit_log(actor_id,action,target_type,target_id)
   values(actor,'vendor_'||new.verification_status,'users',new.id);
 end if;
 return new;
end $$;
revoke all on function final1_private.audit_vendor_review() from public,anon,authenticated;
drop trigger if exists final1_vendor_review_audit on public.users;
create trigger final1_vendor_review_audit after update of verification_status on public.users
 for each row execute function final1_private.audit_vendor_review();

create or replace function public.final1_review_vendor(p_user_id bigint,p_status text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); u public.users;
begin
 if actor is null or public.fr21_role() is distinct from 'admin' then
   raise exception 'Approved administrator required' using errcode='42501';
 end if;
 if p_user_id is null or p_user_id<=0 or p_status is null or p_status not in('approved','rejected') then
   raise exception 'Invalid review' using errcode='22023';
 end if;
 -- Canonical admin first; same user-lock order as other admin decisions.
 perform 1 from public.users where id=actor for update;
 if public.fr21_role() is distinct from 'admin' then
   raise exception 'Approved administrator required' using errcode='42501';
 end if;
 select * into u from public.users where id=p_user_id and role='vendor' for update;
 if u.id is null then raise exception 'Vendor not found' using errcode='22023'; end if;
 if u.verification_status is distinct from p_status then
   update public.users set verification_status=p_status where id=u.id;
 end if;
 return jsonb_build_object('id',u.id,'verification_status',p_status);
end $$;
revoke all on function public.final1_review_vendor(bigint,text) from public,anon,authenticated;
grant execute on function public.final1_review_vendor(bigint,text) to authenticated;

-- Literal search, not user-supplied PostgREST filter grammar or dynamic SQL.
-- SECURITY INVOKER intentionally retains catalogue RLS and blocked-session rules.
create or replace function public.final1_search_products(p_query text)
returns setof public.products language plpgsql stable security invoker set search_path='' as $$
declare needle text;
begin
 if public.fr21_actor() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_query is null or length(btrim(p_query)) not between 1 and 120 or p_query ~ '[[:cntrl:]]' then
   raise exception 'Invalid search' using errcode='22023';
 end if;
 needle:='%'||replace(replace(replace(btrim(p_query),E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_')||'%';
 return query select p.* from public.products p where p.name ilike needle
   or p.description ilike needle or p.category ilike needle order by p.name,p.id limit 40;
end $$;
revoke all on function public.final1_search_products(text) from public,anon,authenticated;
grant execute on function public.final1_search_products(text) to authenticated;
notify pgrst,'reload schema';
commit;
