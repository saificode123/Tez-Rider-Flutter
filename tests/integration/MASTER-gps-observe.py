"""Observe only genuine GPS from the retained physical TEST delivery.

No lifecycle changes, generated coordinates or raw fix/credential output.
Uses the actual owner's customer authorization through the existing gateway.
The explicit stopped mode also revokes consent with the assigned rider account.
"""
import importlib.util
from pathlib import Path
import json
import sys
import time
import urllib.request
import urllib.error
import datetime as dt

HERE = Path(__file__).resolve().parent


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


observer = load('master_observer', 'FR-13-observe.py')
delivery = load('master_physical', 'FR-14-hosted.py')
delivery.b.target()
observer.h.state['physical_order_id'] = delivery.state['physical_order']['oid']
observer.h.state['accounts']['physical-customer'] = delivery.state['accounts']['physical-customer']
observer.h.OUT = observer.h.ROOT / '.fr21-local/master-gps'
observer.h.OUT.mkdir(parents=True, exist_ok=True)


def customer_rpc(name, params, token=None, admin=False):
    assert not admin, 'This observation uses only customer authorization'
    assert name == 'fr13_tracking_context', 'Only tracking context reads allowed'
    return observer.h.b.api('/functions/v1/security-gateway', 'POST', {
        'method': 'POST', 'path': '/rpc/' + name, 'query': '',
        'headers': {'content-type': 'application/json'},
        'body': json.dumps(params),
    }, token)


observer.h.b.rpc = customer_rpc
if __name__ == '__main__':
    seconds = int(sys.argv[1])
    label = sys.argv[2]
    assert 30 <= seconds <= 120
    assert label in ('foreground', 'background', 'recovery', 'stopped', 'route', 'clocks')
    if label == 'stopped':
        rider = delivery.b.login(delivery.state['accounts']['physical-rider'])
        stop_status, stop = customer_rpc('fr13_tracking_context', {
            'p_order_id': delivery.state['physical_order']['oid'], 'p_enable': False}, rider)
        assert stop_status == 200 and stop.get('code') == 'STOPPED', 'Assigned rider cleanup not confirmed'
        token = delivery.b.login(delivery.state['accounts']['physical-customer'])
        status, context = customer_rpc('fr13_tracking_context', {
            'p_order_id': delivery.state['physical_order']['oid']}, token)
        result = {'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
                  'project': delivery.b.REF, 'http_status': status,
                  'code': context.get('code'), 'sharing': context.get('sharing'),
                  'latest_exposed': context.get('latest') is not None,
                  'topic_exposed': bool(context.get('topic')),
                  'rider_stop_confirmed': True,
                  'scope': 'Actual assigned-rider authenticated STOPPED response, then customer denial. Not a physical in-flight Stop-race reproduction.'}
        result['stop_confirmed'] = status == 200 and context.get('code') in ('OK', 'INELIGIBLE') and context.get('sharing') is not True and not result['latest_exposed'] and not result['topic_exposed']
        (observer.h.OUT / 'stopped.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result))
        assert result['stop_confirmed'], 'Customer sharing revocation not confirmed'
    elif label == 'clocks':
        observer.clocks()
    elif label == 'route':
        token = delivery.b.login(delivery.state['accounts']['physical-customer'])
        records = []
        for _ in range(3):
            request = urllib.request.Request(
                delivery.b.BASE + '/functions/v1/get-delivery-route', method='POST',
                data=json.dumps({'orderId': delivery.state['physical_order']['oid']}).encode(),
                headers={'apikey': delivery.b.ANON, 'Authorization': 'Bearer ' + token,
                         'Content-Type': 'application/json'})
            started = time.monotonic()
            try:
                with urllib.request.urlopen(request, timeout=40) as response:
                    status, data = response.status, json.load(response)
                    timing = response.headers.get('Server-Timing')
            except urllib.error.HTTPError as error:
                status, data, timing = error.code, json.load(error), None
            route = data.get('route') or {}
            records.append({
                'http_status': status, 'code': data.get('code'),
                'total_http_ms': round((time.monotonic() - started) * 1000, 2),
                'server_timing': timing, 'source': route.get('source'),
                'approximate': route.get('isApproximate'),
                'road_geometry': route.get('geometry') is not None,
            })
            time.sleep(1)
        result = {'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
                  'project': delivery.b.REF, 'samples': records,
                  'scope': 'Three actual authorized HTTP calls, not client rendering or a load test. Handler timings exclude outer security wrapper/network/cold start. No coordinates retained.'}
        (observer.h.OUT / 'route-timing.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result))
    else:
        observer.main(seconds, label)
