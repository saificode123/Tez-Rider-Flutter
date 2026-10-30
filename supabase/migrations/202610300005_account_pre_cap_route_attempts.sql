-- Two pre-cap automatic reservations were observed from a conservative
-- approval window before sharing was paused. Consume both slots, even if a
-- reservation did not reach the provider. Never reset or grant three more.
begin;
select pg_advisory_xact_lock(318014);
do $$begin
 if exists(select 1 from fr14_private.verification_requests)then
  raise exception 'Review existing consumed requests before accounting';
 end if;
 insert into fr14_private.verification_requests(request_count,status)
 values(1,'PRE_CAP_RESERVED'),(2,'PRE_CAP_RESERVED');
end$$;
commit;
