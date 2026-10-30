"""Read the completed order through existing TEST Customer/Vendor/Admin roles.

Uses retained synthetic fixtures only. Never logs credentials or signs in as
the genuine Rider, changes an order, sends messages or requests any route.
"""
import datetime as dt
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('backend',Path(__file__).with_name('FR-04-hosted.py'))
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
b.target()
physical = json.loads(b.crypt((b.PRIVATE/'fr14-accounts.bin').read_bytes(),True))
demo = json.loads(b.crypt((b.PRIVATE/'master-demo-credentials.dpapi').read_bytes(),True))
accounts = {'customer':physical['accounts']['physical-customer'],
            'vendor':demo['accounts']['sana'],'admin':demo['accounts']['mariam']}
checks = []
tokens = {}
for role,account in accounts.items():
    assert account['profile_id'] != 999,'Never sign in as the genuine Rider'
    code,rows = b.api('/rest/v1/users?id=eq.'+str(account['profile_id'])+'&select=id,role,auth_user_id,verification_status,is_blocked',admin=True)
    assert code == 200 and len(rows) == 1
    row = rows[0]
    assert row['role'] == role and row['auth_user_id'] == account['auth_id'] and row['verification_status'] == 'approved' and not row['is_blocked']
    assert role != 'customer' or row['id'] == 159
    assert role != 'vendor' or row['id'] == 997
    tokens[role] = b.login(account)

def gateway(role,method,path,query='',body=None):
    assert (method,path) in {('GET','/orders'),('POST','/rpc/final2_vendor_report'),('POST','/rpc/final2_rider_performance')}
    return b.api('/functions/v1/security-gateway','POST',{'method':method,'path':path,'query':query,
        'headers':{'content-type':'application/json'},'body':json.dumps(body)if body is not None else ''},tokens[role])

result = {'project':b.REF,'order_id':3180,'observed_at':dt.datetime.now(dt.timezone.utc).isoformat(),'checks':checks}
def check(ok,label):
    assert ok,label
    checks.append(label)
    print(json.dumps({'check':label,'passed':True}),flush=True)

for role in ('customer','admin'):
    code,rows = gateway(role,'GET','/orders','id=eq.3180&select=id,order_status,amount,rider_id')
    check(code == 200 and len(rows) == 1 and rows[0] == {'id':3180,'order_status':'delivered','amount':470,'rider_id':999},role+' reads the same delivered order through normal authorization')

code,report = gateway('vendor','POST','/rpc/final2_vendor_report',body={'p_after':None,'p_limit':50})
check(code == 200 and report.get('code') == 'OK' and report.get('vendor_id') == 997,'own Vendor report authorized')
items = [row for row in report['items']if row['order_id'] == 3180]
check(len(items) == 1 and items[0]['delivered'] is True and items[0]['subtotal'] == 350,'Vendor delivered itemization includes order 3180 once')
result['vendor_payment_state'] = items[0]['payment']['state']
check(result['vendor_payment_state'] == 'UNPAID','Vendor report retains unpaid COD instead of claiming cash')

code,metrics = gateway('admin','POST','/rpc/final2_rider_performance',body={'p_rider_id':999})
check(code == 200 and metrics.get('code') == 'OK' and metrics['rider_id'] == 999,'Admin can read stored Rider performance')
result['metrics'] = {key:metrics[key]for key in ('accepted_assignments','completed_deliveries','timed_deliveries','completion_rate','earned_fee_cents','earnings_only')}
check(metrics['completed_deliveries'] >= 1 and metrics['timed_deliveries'] >= 1 and metrics['earned_fee_cents'] == 11300 and metrics['earnings_only'] is True,'stored post-delivery performance includes recorded PKR 113 and completed/timed counts')
for role in ('customer','vendor'):
    code,_ = gateway(role,'POST','/rpc/final2_rider_performance',body={'p_rider_id':999})
    check(code == 403,role+' cannot inspect private Rider performance')
result['scope'] = 'Fresh authenticated read-only TEST report checks using retained synthetic Customer/Vendor/Admin fixtures. No genuine Rider password, lifecycle/payment write, messages, routes, positions, contacts or tokens retained. Not physical Vendor/Admin screen acceptance.'
(b.ROOT/'docs/evidence/COMPLETE-cross-role-reports.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'checks_passed':len(checks),'evidence_saved':True}))
