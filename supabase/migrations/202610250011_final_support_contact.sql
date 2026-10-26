-- Owner-authorized temporary public Help contact; replacement is one server row.
begin;
lock table public.app_settings in share row exclusive mode;
-- Legacy explicit-ID settings left this sequence behind existing rows.
-- Advance monotonically; never rewrite a setting ID or reduce the sequence.
select setval('public.app_settings_id_seq',greatest(
 (select coalesce(max(id),1)from public.app_settings),
 (select last_value from public.app_settings_id_seq)),true);
insert into public.app_settings(setting_key,setting_value)
values('support_email','urrehmansaif406@gmail.com')
on conflict(setting_key)do update set setting_value=excluded.setting_value;
commit;
