"""Reconcile the one authorized delivery; no order/status/message writes."""
import datetime as dt
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('single_delivery_backend', Path(__file__).with_name('FR-04-hosted.py'))
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)

def read(path):
    status, data = b.api(path, admin=True)
    assert status == 200 and isinstance(data, list), 'Canonical delivery inspection unconfirmed'
    return data

def main():
    b.target()
    file = b.PRIVATE / 'accept-single-delivery.dpapi'
    state = json.loads(b.crypt(file.read_bytes(), True))
    assert state['project'] == b.REF and state['customer_id'] == 159 and state['product_id'] == 224
    orders = read('/rest/v1/orders?user_id=eq.159&select=id,order_status,amount,payment_method,rider_id,created_at&limit=1000')
    assert len(orders) < 1000
    new = [row for row in orders if row['id'] not in state['baseline_order_ids']]
    assert len(new) <= 1, 'Unexpected multiple orders; never submit another checkout'
    result = {'project': b.REF, 'utc': dt.datetime.now(dt.timezone.utc).isoformat(), 'new_order_count': len(new)}
    if new:
        order = new[0]
        assert state['order_id'] in (None, order['id']), 'Never replace the original order checkpoint'
        vendors = read('/rest/v1/vendor_orders?order_id=eq.' + str(order['id']) + '&select=id,vendor_id,status,sub_total')
        assert len(vendors) == 1 and vendors[0]['vendor_id'] == 997 and vendors[0]['sub_total'] == 350
        items = read('/rest/v1/order_items?vendor_order_id=eq.' + str(vendors[0]['id']) + '&select=product_id,quantity,price_at_time')
        assert len(items) == 1 and items[0]['product_id'] == 224 and items[0]['quantity'] == 1 and items[0]['price_at_time'] == 350
        assert order['payment_method'].lower() in ('cod','cash on delivery') and order['amount'] == 470
        state['order_id'] = order['id']
        temporary = file.with_suffix('.dpapi.tmp')
        temporary.write_bytes(b.crypt(json.dumps(state).encode()))
        assert json.loads(b.crypt(temporary.read_bytes(), True)) == state
        temporary.replace(file)
        result.update(order=order, vendor_order=vendors[0], items=items,
            product=read('/rest/v1/products?id=eq.224&select=id,stock_qty,is_available')[0],
            email_jobs=read('/rest/v1/email_outbox?entity_type=eq.order&entity_id=eq.' + str(order['id']) + '&select=id,email_type,status,test_approved,attempts,sent_at'),
            inventory=read('/rest/v1/inventory_movements?order_id=eq.' + str(order['id']) + '&select=movement_type,quantity_delta'))
    result['scope'] = 'Canonical read-only TEST inspection; encrypted local original-order checkpoint only. No lifecycle, payment, email or push write. Never create another order after a confirmed or ambiguous result.'
    (b.ROOT / 'docs/evidence/AUTH-single-order.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))

if __name__ == '__main__':
    main()
