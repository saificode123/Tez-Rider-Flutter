"""Exercise legacy Customer completion using real restored Auth, rollback-only."""
import base64
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import sys
import uuid

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('recovery', HERE / 'RELEASE-storage-recovery.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


def main(mode):
    assert mode in ('before', 'after')
    db = json.loads(r.docker('inspect', r.DB))[0]
    assert db['HostConfig']['NetworkMode'] == 'none' and db['Config']['Labels']['tezrider.purpose'] == 'isolated-restore'
    private = Path(os.environ['LOCALAPPDATA']) / 'TezRider-FR21'
    fixtures = json.loads(r.decrypt((private / 'fr14-accounts.bin').read_bytes()))
    demo = json.loads(r.decrypt((private / 'master-demo-credentials.dpapi').read_bytes()))
    accounts = [fixtures['accounts']['physical-customer'], demo['accounts']['bilal'], demo['accounts']['sana']]
    node = r'''
const fs=require('fs');(async()=>{const accounts=JSON.parse(fs.readFileSync(0,'utf8')),results=[];
for(const a of accounts){const response=await fetch('http://127.0.0.1:9999/token?grant_type=password',{
method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:a.email,password:a.password})});
if(!response.ok)throw Error();const value=await response.json();if(value.user.id!==a.auth_id)throw Error();
results.push(JSON.parse(Buffer.from(value.access_token.split('.')[1],'base64url').toString()));}
console.log(JSON.stringify(results));})().catch(()=>process.exit(1));
'''
    claims = json.loads(r.docker('exec', '-i', r.STORAGE, 'node', '-e', node, data=json.dumps(accounts).encode()))
    customer, rider, vendor_claim = claims
    profile = int(accounts[0]['profile_id'])
    rider_id = int(accounts[1]['profile_id'])
    vendor = int(demo['accounts']['sana']['profile_id'])
    product = int(demo['products']['Chicken Biryani']['id'])
    order = int(fixtures['physical_order']['oid'])
    checks = []

    def case(label, claim, work, setup='', finish=''):
        encoded = base64.b64encode(json.dumps(claim).encode()).decode()
        sql = f"""begin;
{setup}
set local role authenticated;
do $claims$ begin perform set_config('request.jwt.claims',convert_from(decode('{encoded}','base64'),'UTF8'),true);end $claims$;
do $case$ declare value jsonb;before_fields jsonb;after_fields jsonb;stock_before integer;begin {work} end $case$;
reset role;
{finish}
rollback;"""
        r.docker('exec', '-i', r.DB, 'psql', '-qAt', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', data=sql.encode())
        checks.append({'check': label, 'result': 'PASS'})

    def denied(statement, states="'42501'"):
        return f"begin {statement};raise exception 'Unexpected permission';exception when sqlstate {states} then null;end;"

    legacy = f"if public.fr21_actor() is distinct from {profile} or public.fr21_role()<>'customer' or not exists(select 1 from public.users where id={profile} and verification_status='pending')then raise exception 'Legacy condition changed';end if;"
    case('Actual confirmed legacy Customer retains pending profile before completion', customer, legacy)
    if mode == 'before':
        case('Original completion leaves pending Customer unable to restore cart or ratings', customer,
             "value:=public.final2_complete_registration();if value->>'verification_status' is distinct from 'pending'then raise exception 'Not original behavior';end if;" +
             denied('perform public.final2_cart_get()') + denied(f'perform public.final2_rating_summary({vendor})'))
        print(json.dumps({'baseline_reproduced': True, 'checks': checks}))
        return
    # Snapshot only counts of external-message queues, not recipients or content.
    setup = f"""create temp table registration_before on commit drop as select
 (select count(*)from public.email_outbox)as emails,(select count(*)from public.notifications)as notifications,
 (select count(*)from public.security_audit_log where actor_id={profile} and action='customer_registration_reconciled')as audit;
grant select on registration_before to authenticated;"""
    work = f"""
select jsonb_build_object('name',name,'phone',phone,'email',email,'role',role,'auth',auth_user_id)into before_fields from public.users where id={profile};
value:=public.final2_complete_registration(p_role=>'admin');
if value->>'code' is distinct from 'PROFILE_REQUIRED'or(select verification_status from public.users where id={profile})<>'pending'then raise exception 'Missing phone bypassed';end if;
value:=public.final2_complete_registration(p_name=>before_fields->>'name',p_phone=>'0000000000',p_role=>'admin',p_update_profile=>true);
if value->>'role' is distinct from 'customer'or value->>'verification_status' is distinct from 'approved'then raise exception 'Customer completion failed';end if;
select jsonb_build_object('name',name,'phone',phone,'email',email,'role',role,'auth',auth_user_id)into after_fields from public.users where id={profile};
if(after_fields-'phone')is distinct from(before_fields-'phone')or after_fields->>'phone'<>'0000000000'then raise exception 'Profile fields changed';end if;
value:=public.final2_cart_get();if value->>'code' is distinct from 'OK'then raise exception 'Cart unavailable';end if;
select stock_qty into stock_before from public.products where id={product};
value:=public.final2_cart_replace((value->>'revision')::bigint,extensions.gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',{product},'qty',1)));
if value->>'code' is distinct from 'OK'or(select stock_qty from public.products where id={product})is distinct from stock_before then raise exception 'Cart/stock invalid';end if;
value:=public.final2_rating_summary({vendor});if value->>'code' is distinct from 'OK'or value->'average' is distinct from 'null'::jsonb then raise exception 'Ratings unavailable';end if;
value:=public.final2_complete_registration();if value->>'verification_status' is distinct from 'approved'then raise exception 'Repeated completion invalid';end if;
""" + denied(f'perform public.final2_feedback_context({order})', "'PT409'")
    finish = f"""do $counts$begin
if(select count(*)from public.email_outbox)<>(select emails from registration_before)
or(select count(*)from public.notifications)<>(select notifications from registration_before)
or(select count(*)from public.security_audit_log where actor_id={profile} and action='customer_registration_reconciled')<>(select audit+1 from registration_before)
then raise exception 'Unexpected messages or duplicate audit';end if;end $counts$;"""
    case('Missing profile requires completion; supplied phone activates only Customer, preserves identity/role, enables cart/ratings, retains stock/delivery guard, emits one audit and no messages', customer, work, setup, finish)
    case('Pending Rider stays pending despite client requesting Customer role', rider,
         f"value:=public.final2_complete_registration(p_role=>'customer');if value->>'role' is distinct from 'rider'or value->>'verification_status' is distinct from 'pending'then raise exception 'Rider approval changed';end if;" +
         denied(f'perform public.final2_rating_summary({vendor})'))
    case('Pending Vendor stays pending despite client requesting Customer role', vendor_claim,
         "value:=public.final2_complete_registration(p_role=>'customer');if value->>'role' is distinct from 'vendor'or value->>'verification_status' is distinct from 'pending'then raise exception 'Vendor approval changed';end if;",
         setup=f"update public.users set verification_status='pending'where id={vendor};")
    for status in ('rejected', 'suspended'):
        case(status + ' Customer is not automatically activated', customer,
             f"value:=public.final2_complete_registration();if value->>'verification_status' is distinct from '{status}'then raise exception 'Explicit status ignored';end if;" + denied('perform public.final2_cart_get()'),
             setup=f"update public.users set verification_status='{status}'where id={profile};")
    session = str(uuid.UUID(customer['session_id']))
    case('Revoked session cannot complete registration', customer,
         denied('perform public.final2_complete_registration()'), setup=f"delete from auth.sessions where id='{session}'::uuid;")
    case('Blocked Customer cannot complete registration', customer,
         denied('perform public.final2_complete_registration()', "'PT403' or sqlstate '42501'"),
         setup=f"update public.users set is_blocked=true where id={profile};")
    case('Anonymous registration-completion execution remains denied', customer,
         "if has_function_privilege('anon','public.final2_complete_registration(text,text,text,text,text,boolean)','execute')then raise exception 'Anonymous grant';end if;")
    result = {'project': 'igeisilhtmglgnqvllrx', 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'environment': 'Owned offline restored database and real local Auth sessions', 'checks': checks,
              'scope': 'Rollback-only checks on existing profiles and an undelivered order. Canonical Customer completion tested without bulk backfill, changed feature grants, Vendor/Rider approval, external messages or delivered/earning fabrication.'}
    (r.ROOT / 'docs/evidence/RELEASE-registration-local.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'registration_checks_passed': len(checks)}))


if __name__ == '__main__':
    main(sys.argv[1])
