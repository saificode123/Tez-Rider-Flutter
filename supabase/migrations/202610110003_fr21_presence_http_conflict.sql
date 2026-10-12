-- Stale leases are permanent HTTP conflicts, never serialization retries.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create or replace function public.fr21_set_presence(p_online boolean,p_epoch bigint,p_sequence bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.riders; actor bigint:=public.fr21_actor(); begin
  if actor is null or public.fr21_role() is distinct from 'rider' then
    raise exception 'Rider authentication required' using errcode='42501'; end if;
  if p_online is null or p_epoch is null or p_epoch<1 or p_sequence is null or p_sequence<1 then
    raise exception 'Invalid presence request' using errcode='22023'; end if;
  select * into r from public.riders where userid=actor for update;
  if not found then raise exception 'Rider profile missing' using errcode='P0002'; end if;
  if coalesce(r.presence_epoch,0)<>p_epoch or p_sequence<coalesce(r.presence_sequence,0) then
    raise exception 'Stale presence request' using errcode='PT409'; end if;
  if p_sequence=coalesce(r.presence_sequence,0) then
    if p_online is distinct from r.is_online then
      raise exception 'Sequence reused with different intent' using errcode='22023'; end if;
    return jsonb_build_object('is_online',r.is_online,'last_seen',r.last_seen);
  end if;
  if p_online and not public.fr21_approved_rider(actor) then
    raise exception 'Rider approval required' using errcode='42501'; end if;
  update public.riders set is_online=p_online,last_seen=clock_timestamp(),presence_sequence=p_sequence
    where id=r.id returning * into r;
  return jsonb_build_object('is_online',r.is_online,'last_seen',r.last_seen);
end $$;
notify pgrst,'reload schema';
commit;
