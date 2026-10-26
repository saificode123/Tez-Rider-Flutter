-- Owner policy: docs/POLICY-DECISIONS.md. No production deployment authorized.
begin;
set local lock_timeout='5s';
alter table final_delivery_private.pay_settings add column maximum_amount numeric
 default null check(maximum_amount is null);
create table final_delivery_private.cart_settings(
 singleton boolean primary key default true check(singleton),
 reservations_enabled boolean not null default false check(not reservations_enabled),
 reservation_duration_seconds integer not null default 0 check(reservation_duration_seconds=0),
 expiry_timer_enabled boolean not null default false check(not expiry_timer_enabled),
 check_stock_at_add boolean not null default true check(check_stock_at_add),
 revalidate_at_checkout boolean not null default true check(revalidate_at_checkout),
 decrement_at_placement boolean not null default true check(decrement_at_placement),
 restore_on_cancellation boolean not null default true check(restore_on_cancellation),
 name_short_items boolean not null default true check(name_short_items)
);
insert into final_delivery_private.cart_settings(singleton)values(true);
alter table final_delivery_private.cart_settings enable row level security;
revoke all on final_delivery_private.cart_settings from public,anon,authenticated,service_role;
-- These enforced settings describe the accepted FR07/FR17 transaction design.
-- Enabling reservations requires an explicitly reviewed new implementation,
-- never a client toggle or an arbitrary settings-only behavior change.
create function public.final_delivery_cart_policy()returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare settings final_delivery_private.cart_settings;begin
 if public.fr21_actor()is null or not public.is_current_user_allowed()or public.fr21_role()<>'customer'then
  raise exception 'Approved Customer required'using errcode='42501';end if;
 select *into strict settings from final_delivery_private.cart_settings where singleton;
 return jsonb_build_object('code','OK','reservations_enabled',settings.reservations_enabled,
  'reservation_duration_seconds',settings.reservation_duration_seconds,'expiry_timer_enabled',settings.expiry_timer_enabled,
  'check_stock_at_add',settings.check_stock_at_add,'revalidate_at_checkout',settings.revalidate_at_checkout,
  'decrement_at_placement',settings.decrement_at_placement,'restore_on_cancellation',settings.restore_on_cancellation,
  'name_short_items',settings.name_short_items);
end$$;
revoke all on function public.final_delivery_cart_policy()from public,anon,service_role;
grant execute on function public.final_delivery_cart_policy()to authenticated;

-- FR10 already extended the accepted FR30 durable queue, capability resolver
-- and FCM hints to coalesce(broadcast_id,order_push_event_id). Reuse that exact
-- tested contract for the remaining canonical notification inserts. No message
-- or personal data is added to FCM, no installation/session checks are changed,
-- and old inbox rows are deliberately not backfilled into new push jobs.
create function final_delivery_private.notification_push_identity()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if new.broadcast_id is null and new.order_push_event_id is null
  and coalesce(btrim(new.title),'')<>''and coalesce(btrim(new.message),'')<>''then
  new.order_push_event_id:=gen_random_uuid();
 end if;return new;
end$$;
revoke all on function final_delivery_private.notification_push_identity()from public,anon,authenticated,service_role;
create trigger final_delivery_notification_push_identity before insert on public.notifications
 for each row execute function final_delivery_private.notification_push_identity();
notify pgrst,'reload schema';
commit;
