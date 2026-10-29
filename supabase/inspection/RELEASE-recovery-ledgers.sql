-- Read-only service-owned migration ledgers required for runtime recovery.
begin read only;
select jsonb_build_object(
 'auth', (select jsonb_agg(to_jsonb(a) order by version) from auth.schema_migrations a),
 'storage', (select jsonb_agg(to_jsonb(s) order by id) from storage.migrations s)
) as ledgers;
rollback;
