-- Preserve per-admin serialization without conflicting with recipient FK locks
-- when different admins concurrently broadcast to ALL (including one another).
begin;
set local lock_timeout='5s';
do $$declare definition text;begin
 select pg_get_functiondef('public.admin_send_broadcast(uuid,text,text,text)'::regprocedure)into definition;
 if position('where id=actor for update;'in definition)=0 then raise exception 'Unexpected FR30 sender lock definition';end if;
 execute replace(definition,'where id=actor for update;','where id=actor for no key update;');
end$$;
notify pgrst,'reload schema';
commit;
