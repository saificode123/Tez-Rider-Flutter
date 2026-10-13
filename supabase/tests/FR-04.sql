-- Rollback-only role tests. Run only with the guarded TEST runner.
do $$ begin
 if current_setting('fr04.test_project_ref',true) is distinct from 'igeisilhtmglgnqvllrx' then
   raise exception 'Dedicated TEST marker required'; end if;
end $$;
begin;
create temporary table fr04_roles as
 select a.id as auth_id,u.id as user_id,u.email,u.role,
 case u.email when 'fr04-rider-a@example.test' then 'approved rider'
   when 'fr04-rider-b@example.test' then 'other rider'
   when 'fr04-rider-missing@example.test' then 'pending rider' else u.role end as label
 from public.users u join auth.users a on a.email=u.email
 where u.email in ('fr04-rider-a@example.test','fr04-rider-b@example.test','fr04-rider-missing@example.test',
 'fr21-device-customer@example.test','fr21-device-vendor@example.test','fr21-device-admin@example.test');
create temporary table fr04_results(label text);
grant select on fr04_roles to authenticated,anon;
create function pg_temp.fr04_ok(value boolean,label text) returns void
language plpgsql security definer set search_path=pg_temp,pg_catalog as $$ begin
 if value is distinct from true then raise exception 'FAILED: %',label; end if;
 insert into fr04_results values(label);
end $$;
select pg_temp.fr04_ok((select count(*)=6 from fr04_roles),'six authoritative synthetic role fixtures');
select pg_temp.fr04_ok(fr04_private.normalize_cnic('32000-1234567-1')='3200012345671','server normalization');
select pg_temp.fr04_ok(fr04_private.mask_cnic(fr04_private.encrypt_cnic('3200012345671'))='3***0-*******-*','encrypted number processed to masked response');
do $$ begin
 begin perform fr04_private.normalize_cnic('123X'); raise exception 'invalid accepted';
 exception when invalid_parameter_value then perform pg_temp.fr04_ok(true,'invalid server CNIC rejected'); end;
end $$;
create temporary table fr04_test_order(order_id bigint);
with inserted as (
 insert into public.orders(user_id,rider_id,amount,order_status,delivery_address)
 values((select user_id from fr04_roles where label='customer'),
 (select user_id from fr04_roles where label='approved rider'),1,'delivered','FR04 rollback-only synthetic fixture') returning id
) insert into fr04_test_order select id from inserted;
grant select on fr04_test_order to authenticated,anon;
set local role anon;
do $$ begin
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 begin perform public.fr04_application_status();raise exception 'anonymous accepted';
 exception when insufficient_privilege then perform pg_temp.fr04_ok(true,'anonymous application denied');end;
end $$;
reset role;
set local role authenticated;
do $$ declare actor record; value jsonb; target bigint; begin
 select user_id into target from fr04_roles where label='approved rider';
 for actor in select * from fr04_roles loop
   perform set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_id,'email',actor.email,'role','authenticated')::text,true);
   perform pg_temp.fr04_ok(not has_schema_privilege(current_user,'fr04_private','USAGE'),actor.label||': encryption schema inaccessible');
   begin
     perform pg_temp.fr04_ok(not has_table_privilege(current_user,'vault.decrypted_secrets','SELECT'),actor.label||': Vault key inaccessible');
   exception when insufficient_privilege then
     perform pg_temp.fr04_ok(true,actor.label||': Vault key inaccessible');
   end;
   if actor.role='rider' then
     value:=public.fr04_application_status();
     perform pg_temp.fr04_ok(value->>'id'=actor.user_id::text,actor.label||': own submission only');
     if actor.label='approved rider' then
       perform pg_temp.fr04_ok(value->>'cnic_masked'='3***0-*******-*','approved rider: masked number only');
       perform pg_temp.fr04_ok((public.fr04_document_authority(null)->>'user_id')=actor.user_id::text,'rider: own document authority');
     else
       begin perform public.fr04_document_authority(target);raise exception 'cross rider accepted';
       exception when insufficient_privilege then perform pg_temp.fr04_ok(true,actor.label||': other document denied');end;
     end if;
   end if;
   if actor.role<>'admin' then
     begin perform public.fr04_admin_riders(null,30,null);raise exception 'non-admin accepted';
     exception when insufficient_privilege then perform pg_temp.fr04_ok(true,actor.label||': approval queue denied');end;
     begin perform public.fr04_review_rider(target,'approved');raise exception 'non-admin approval accepted';
     exception when insufficient_privilege then perform pg_temp.fr04_ok(true,actor.label||': approval denied');end;
   else
     perform pg_temp.fr04_ok((public.fr04_document_authority(target)->>'user_id')=target::text,'admin: document authority');
     begin perform public.fr04_review_rider((select user_id from fr04_roles where label='pending rider'),'approved');
       raise exception 'incomplete approval accepted';
     exception when insufficient_privilege then perform pg_temp.fr04_ok(true,'admin: missing document approval denied');end;
     begin update public.users set verification_status='approved' where id=(select user_id from fr04_roles where label='pending rider');
       raise exception 'direct incomplete approval accepted';
     exception when insufficient_privilege then perform pg_temp.fr04_ok(true,'admin: direct approval bypass denied');end;
   end if;
   begin perform public.fr04_begin_upload(actor.auth_id,gen_random_uuid(),repeat('a',64),'png','3200012345671');
     raise exception 'backend lease bypass accepted';
   exception when insufficient_privilege then perform pg_temp.fr04_ok(true,actor.label||': backend-only lease denied');end;
   if actor.role='customer' then
     value:=public.fr04_order_rider_identity((select order_id from fr04_test_order));
     perform pg_temp.fr04_ok(value->>'cnic_masked'='3***0-*******-*' and not(value?'cnic'),'customer: owned order masked identity');
     perform pg_temp.fr04_ok((select count(*)=0 from public.users where id=target),'customer: raw rider profile hidden');
   else
     begin perform public.fr04_order_rider_identity((select order_id from fr04_test_order));raise exception 'wrong order identity accepted';
     exception when insufficient_privilege then perform pg_temp.fr04_ok(true,actor.label||': customer identity endpoint denied');end;
   end if;
 end loop;
end $$;
reset role;
select jsonb_build_object('passed',count(*),'failed',0,'checks',jsonb_agg(label)) as fr04_sql from fr04_results;
rollback;
