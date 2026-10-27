"""Compare sampled assistant facts to actual caller-authorized TEST reads."""
from pathlib import Path
import json, hashlib

helper = Path(__file__).with_name('REPAIR-assistant-eval.py')
source = helper.read_text(encoding='utf-8').split('cases = [', 1)[0]
scope = {'__file__': str(helper.resolve())}
exec(compile(source, str(helper), 'exec'), scope)
call, token, root = scope['call'], scope['token'], scope['ROOT']

def rpc(name, params):
    return call('/functions/v1/security-gateway', {
        'method': 'POST', 'path': '/rpc/'+name, 'query': '',
        'headers': {'content-type':'application/json'}, 'body':json.dumps(params),
    }, token)

status, orders = rpc('fr25_order_history', {'p_before':None})
assert status == 200 and isinstance(orders,list)
order_matches = any(r.get('id') == 389 and r.get('order_status') == 'on_the_way' for r in orders)
status, page = rpc('final2_catalog', {'p_query':'','p_category':None,'p_after':None,'p_limit':20})
assert status == 200 and isinstance(page,dict)
product_matches = any(r.get('name') == 'CHECKLIST SYNTHETIC PICKUP' and r.get('price') == 80
    and r.get('is_available') is True and r.get('stock_confirmed') is True and r.get('stock_qty',0)>0
    for r in page['items'])
status, denied = rpc('final2_order_detail', {'p_order_id':999999999999})
proof = {'project':scope['REF'], 'read_only':True,
    'owned_order_sample_matches_actual_RPC':order_matches,
    'catalogue_sample_matches_actual_RPC':product_matches,
    'invalid_order_denied':status in (400,403,404),
    'scope':'Authenticated gateway reads. No production, credentials or private fields in evidence.'}
(root/'docs/evidence/REPAIR-assistant-grounding.json').write_text(json.dumps(proof,indent=2)+'\n')
print(json.dumps(proof))
assert all(proof[k] for k in ('owned_order_sample_matches_actual_RPC','catalogue_sample_matches_actual_RPC','invalid_order_denied'))
