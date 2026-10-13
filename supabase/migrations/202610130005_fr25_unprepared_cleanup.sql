-- A rejected preparation has no draft/files. Allow its owner-side UI to discard
-- the local retry context without bypassing another customer's ownership.
begin;
set local lock_timeout='5s';
create or replace function public.fr25_abandon(p_request_id uuid) returns text[]
language plpgsql security definer set search_path='' as $$ declare d fr25_private.drafts; begin
 if public.fr21_actor() is null or public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 if p_request_id is null then raise exception 'Submission identifier required' using errcode='22023'; end if;
 select * into d from fr25_private.drafts where id=p_request_id and customer_id=public.fr21_actor() for update;
 if d.id is null then
  if exists(select 1 from fr25_private.drafts where id=p_request_id) then raise exception 'Submission access forbidden' using errcode='42501'; end if;
  -- Preparation may have been rejected before a row or any upload existed.
  return array[]::text[];
 end if;
 if d.state='submitted' or exists(select 1 from public.disputes where request_id=d.id) then return array[]::text[]; end if;
 update fr25_private.drafts set state='abandoned' where id=d.id;
 return array(select name from storage.objects where bucket_id='dispute-evidence' and name like d.auth_id||'/'||d.id||'/%');
end $$;
create or replace function public.fr25_request_status(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare d fr25_private.drafts; result jsonb; begin
 if public.fr21_actor() is null or public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 if p_request_id is null then raise exception 'Submission identifier required' using errcode='22023'; end if;
 select * into d from fr25_private.drafts where id=p_request_id;
 if d.id is null then return null; end if;
 if d.customer_id is distinct from public.fr21_actor() or public.fr21_role() is distinct from 'customer' then raise exception 'Submission access forbidden' using errcode='42501'; end if;
 select jsonb_build_object('id',id,'request_id',request_id,'status',status) into result from public.disputes where request_id=d.id;
 return result;
end $$;
notify pgrst,'reload schema';
commit;
