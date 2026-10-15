-- Do not report administrator notification when no eligible recipient exists.
begin;
set local lock_timeout='5s';
do $$declare source text;old text;replacement text;begin
 source:=pg_get_functiondef('public.fr21_ready_and_assign(bigint)'::regprocedure);
 old:='''manual_assignment'',true,''search_radius_m'',10000';
 replacement:='''admin_notified'',exists(select 1 from public.notifications where assignment_order_id=o.id and assignment_event=''manual_assignment''),''manual_assignment'',true,''search_radius_m'',10000';
 if position(old in source)=0 then raise exception 'Review changed FR20 assignment implementation';end if;
 source:=replace(source,old,replacement);
 source:=replace(source,'''Order ready. No eligible rider within 10 km. Administrators notified for manual assignment.''',
  'case when exists(select 1 from public.notifications where assignment_order_id=o.id and assignment_event=''manual_assignment'')then ''Order ready. No eligible rider within 10 km. Administrators notified for manual assignment.''else ''Order ready. Manual assignment required; no eligible administrator is available for notification.''end');
 execute source;
 source:=pg_get_functiondef('public.fr20_assignment_status(bigint)'::regprocedure);
 old:='''manual_assignment'',o.requires_manual_assignment';
 replacement:='''admin_notified'',exists(select 1 from public.notifications where assignment_order_id=o.id and assignment_event=''manual_assignment''),''manual_assignment'',o.requires_manual_assignment';
 if position(old in source)=0 then raise exception 'Review changed FR20 status implementation';end if;
 execute replace(source,old,replacement);
end$$;
notify pgrst,'reload schema';
commit;
