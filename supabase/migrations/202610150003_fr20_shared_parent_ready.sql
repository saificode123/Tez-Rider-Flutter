-- Preserve the existing multi-vendor Ready transition when the parent already
-- has an active rider, without reserving again or repeating rider notices.
begin;
set local lock_timeout='5s';
do $$declare source text;old text;replacement text;begin
 source:=pg_get_functiondef('public.fr21_ready_and_assign(bigint)'::regprocedure);
 old:='if o.rider_id is not null then return public.fr20_assignment_status(p_vendor_order_id);end if;';
 replacement:='if o.rider_id is not null then
  if not exists(select 1 from public.rider_assignments where orderid=o.id and riderid=o.rider_id and status in(''Pending'',''Accepted''))then return jsonb_build_object(''code'',''INVALID_ORDER_STATE'');end if;
  update public.vendor_orders set status=''on_the_way''where id=vo.id and status is distinct from ''on_the_way'';
  return public.fr20_assignment_status(p_vendor_order_id);
 end if;';
 if position(old in source)=0 then raise exception 'Review changed FR20 assigned-parent implementation';end if;
 execute replace(source,old,replacement);
end$$;
notify pgrst,'reload schema';
commit;
