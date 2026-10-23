-- FR18: delivered-only gross sales and private, bounded per-order reporting.
-- No fee, profit, payout or shared-refund allocation rule is invented.
begin;
create function final2_private.vendor_report_rows(p_vendor bigint)
returns table(order_id bigint,vendor_order_id bigint,created_at timestamptz,
 order_status text,portion_status text,subtotal numeric,delivered boolean,source text)
language sql stable security definer set search_path='' as $$
 select o.id,v.id,o.created_at,o.order_status,v.status,v.sub_total,
  o.order_status='delivered'and v.status='delivered','vendor_order'::text
 from public.vendor_orders v join public.orders o on o.id=v.order_id where v.vendor_id=p_vendor
 union all
 select o.id,0::bigint,o.created_at,o.order_status,o.order_status,
  case when o.amount::text not in('NaN','Infinity','-Infinity')and o.fare::text not in('NaN','Infinity','-Infinity')
   and o.fare>=0 and o.amount>=o.fare then o.amount-o.fare else null end,
  o.order_status='delivered','legacy_order'::text
 from public.orders o where o.vendor_id=p_vendor
  and not exists(select 1 from public.vendor_orders v where v.order_id=o.id)
$$;
revoke all on function final2_private.vendor_report_rows(bigint)from public,anon,authenticated,service_role;

create function public.final2_vendor_report(p_after jsonb default null,p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();after_order bigint;after_portion bigint;
 summary jsonb;top_items jsonb;rows_json jsonb:='[]';r record;row_items jsonb;payment jsonb;
 n integer:=0;more boolean:=false;cursor jsonb;row_amount_valid boolean;begin
 if actor is null or public.fr21_role()is distinct from'vendor'or not exists(
  select 1 from public.users where id=actor and role='vendor'and verification_status='approved'and not is_blocked
 )then raise exception 'Approved Vendor required'using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'Invalid report page size'using errcode='22023';end if;
 if p_after is not null then
  if jsonb_typeof(p_after)is distinct from'object'then raise exception 'Invalid report cursor'using errcode='22023';end if;
  if exists(select 1 from jsonb_object_keys(p_after)k where k not in('order_id','vendor_order_id'))
   or jsonb_typeof(p_after->'order_id')is distinct from'number'
   or jsonb_typeof(p_after->'vendor_order_id')is distinct from'number'
   or(p_after->>'order_id')!~'^[1-9][0-9]{0,18}$'
   or(p_after->>'vendor_order_id')!~'^(0|[1-9][0-9]{0,18})$'then
   raise exception 'Invalid report cursor'using errcode='22023';end if;
  begin after_order:=(p_after->>'order_id')::bigint;after_portion:=(p_after->>'vendor_order_id')::bigint;
  exception when numeric_value_out_of_range then raise exception 'Invalid report cursor'using errcode='22023';end;
 end if;
 with owned as(select *,subtotal is not null and subtotal::text not in('NaN','Infinity','-Infinity')
  and subtotal>=0 and subtotal<=1000000000000 and subtotal=round(subtotal,2)as valid_amount
  from final2_private.vendor_report_rows(actor)),counts as(
  select coalesce(case when order_status in('cancelled','rejected')then order_status else portion_status end,'unknown')as status,count(*)as status_count
  from owned group by 1)
 select jsonb_build_object('total_orders',(select count(*)from owned),
  'delivered_orders',(select count(*)from owned where delivered),
  'delivered_sales',coalesce((select sum(subtotal)from owned where delivered and valid_amount),0),
  'amounts_requiring_review',(select count(*)from owned where not valid_amount),
  'status_counts',coalesce((select jsonb_object_agg(status,status_count)from counts),'{}'::jsonb))into summary;

 select coalesce(jsonb_agg(to_jsonb(t)order by quantity desc,product_id),'[]')into top_items from(
  select i.product_id,coalesce(max(p.name),'Product #'||i.product_id)as name,sum(i.quantity)as quantity
  from final2_private.vendor_report_rows(actor)sales_rows join public.order_items i on i.vendor_order_id=sales_rows.vendor_order_id
  left join public.products p on p.id=i.product_id
  where sales_rows.delivered and i.quantity>0 and i.price_at_time>=0 and i.price_at_time::text not in('NaN','Infinity','-Infinity')
  group by i.product_id order by sum(i.quantity)desc,i.product_id limit 5)t;

 for r in select *from final2_private.vendor_report_rows(actor)
  where after_order is null or(order_id,vendor_order_id)<(after_order,after_portion)
  order by order_id desc,vendor_order_id desc limit p_limit+1 loop
  n:=n+1;if n>p_limit then more:=true;exit;end if;
  row_amount_valid:=r.subtotal is not null and r.subtotal::text not in('NaN','Infinity','-Infinity')
   and r.subtotal>=0 and r.subtotal<=1000000000000 and r.subtotal=round(r.subtotal,2);
  select coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')into row_items from(
   select i.id,i.product_id,coalesce(p.name,'Product #'||i.product_id)as name,i.quantity,
    case when i.price_at_time>=0 and i.price_at_time::text not in('NaN','Infinity','-Infinity')then i.price_at_time else null end as unit_price
   from public.order_items i left join public.products p on p.id=i.product_id
   where i.vendor_order_id=r.vendor_order_id order by i.id limit 101)t;
  payment:=public.final2_order_payment(r.order_id);
  rows_json:=rows_json||jsonb_build_array(jsonb_build_object('order_id',r.order_id,'vendor_order_id',r.vendor_order_id,
   'created_at',r.created_at,'order_status',r.order_status,'portion_status',r.portion_status,'source',r.source,
   'subtotal',case when row_amount_valid then r.subtotal else null end,'delivered',coalesce(r.delivered,false),
   'items',row_items,'items_require_review',jsonb_array_length(row_items)>100,'payment',payment));
  cursor:=jsonb_build_object('order_id',r.order_id,'vendor_order_id',r.vendor_order_id);
 end loop;
 return jsonb_build_object('code','OK','vendor_id',actor,'currency','PKR','summary',summary,'top_products',top_items,
  'items',rows_json,'has_more',more,'next_cursor',case when more then cursor else null end);
end$$;
revoke all on function public.final2_vendor_report(jsonb,integer)from public,anon;
grant execute on function public.final2_vendor_report(jsonb,integer)to authenticated;
commit;
