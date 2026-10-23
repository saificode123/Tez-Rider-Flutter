-- Close legacy RPC bypass of the existing client media guard.
-- Keep existing references, permit clearing; no historical object changes.
begin;
CREATE OR REPLACE FUNCTION public.fr17_save_product(p_request_id uuid, p_product_id bigint, p_data jsonb, p_stock integer, p_threshold integer, p_expected_version bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor bigint:=public.fr21_actor();p public.products;m public.inventory_movements;payload jsonb;result jsonb;v_price numeric;begin
 if actor is null or public.fr21_role()is distinct from'vendor'then return jsonb_build_object('code','FORBIDDEN');end if;
 perform 1 from public.users where id=actor and not is_blocked and verification_status='approved'for no key update;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_request_id is null or jsonb_typeof(p_data)is distinct from'object'or nullif(btrim(p_data->>'name'),'')is null
 or char_length(p_data->>'name')>200 or char_length(p_data->>'description')>5000 or char_length(p_data->>'image_url')>2000
 or p_stock is null or p_stock not between 0 and 1000000000 or p_threshold is null or p_threshold<0 then raise exception 'Invalid product inventory'using errcode='22023';end if;
 v_price:=(p_data->>'price')::numeric;
 if v_price is null or v_price<0 or v_price>1000000000000 then raise exception 'Invalid product price'using errcode='22023';end if;
 payload:=jsonb_build_object('product_id',p_product_id,'data',p_data,'stock',p_stock,'threshold',p_threshold,'version',p_expected_version);
 select * into m from public.inventory_movements where vendor_id=actor and request_id=p_request_id;
 if found then
  if m.request_payload is distinct from payload then return jsonb_build_object('code','IDEMPOTENCY_CONFLICT');end if;
  select * into p from public.products where id=m.product_id and vendor_id=actor;
  if not found then return jsonb_build_object('code','PRODUCT_REMOVED');end if;
  return jsonb_build_object('code','ALREADY_UPDATED','product_id',m.product_id,'stock_qty',p.stock_qty,'stock_version',p.stock_version,'low_stock_threshold',p.low_stock_threshold);
 end if;
 if p_product_id is null then
  if nullif(btrim(p_data->>'image_url'),'') is not null then raise exception 'Secure product media upload is not configured' using errcode='22023';end if;
  insert into public.products(vendor_id,name,price)values(actor,btrim(p_data->>'name'),v_price)returning * into p;
 else
  select * into p from public.products where id=p_product_id and vendor_id=actor for update;
  if not found then return jsonb_build_object('code','FORBIDDEN');end if;
  if nullif(btrim(p_data->>'image_url'),'') is not null and p_data->>'image_url' is distinct from p.image_url then raise exception 'Secure product media upload is not configured' using errcode='22023';end if;
  if p_expected_version is null or p_expected_version<>p.stock_version then return jsonb_build_object('code','STOCK_CHANGED','stock_qty',p.stock_qty,'stock_version',p.stock_version);end if;
 end if;
 update public.products set name=btrim(p_data->>'name'),description=p_data->>'description',price=v_price,
 image_url=p_data->>'image_url',category=coalesce(nullif(p_data->>'category',''),'General'),
 is_available=coalesce((p_data->>'is_available')::boolean,true),requires_prescription=coalesce((p_data->>'requires_prescription')::boolean,p.requires_prescription)where id=p.id;
 result:=fr17_private.adjust(p.id,p_stock,'set','Vendor product save',p_request_id,p_threshold,p.stock_version,payload);
 if result->>'code'<>'UPDATED'then raise exception 'Product stock save not confirmed'using errcode='40001';end if;
 return result;
end$function$
;
commit;
