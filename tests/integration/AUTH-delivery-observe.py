"""Bounded Customer-authorized observation of the one genuine TEST delivery."""
import datetime as dt
import importlib.util
import json
from pathlib import Path
import statistics
import sys
import time
import urllib.request
import urllib.error

spec=importlib.util.spec_from_file_location('auth_delivery_observer',Path(__file__).with_name('MASTER-gps-observe.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
b=m.delivery.b

def main(mode, prefix='AUTH-delivery-'):
    assert prefix in ('AUTH-delivery-', 'MAP-')
    assert mode in('gps','route','travel','stopped')
    b.target()
    state=json.loads(b.crypt((b.PRIVATE/'accept-single-delivery.dpapi').read_bytes(),True))
    owner=json.loads(b.crypt((b.PRIVATE/'rider-auth-verification.dpapi').read_bytes(),True))
    oid=state['order_id'];assert oid==3180 and state['customer_id']==159 and state['product_id']==224
    customer=m.delivery.state['accounts']['physical-customer']
    assert customer['profile_id']==159 and customer['auth_id']!=owner['auth_id']
    code,orders=b.api('/rest/v1/orders?id=eq.'+str(oid)+'&select=user_id,rider_id,order_status',admin=True)
    assert code==200 and len(orders)==1 and orders[0]['user_id']==159 and orders[0]['rider_id']==999 and orders[0]['order_status']=='on_the_way'
    # In-memory observer binding only; preserve old physical-order checkpoints.
    m.observer.h.state['physical_order_id']=oid
    out=b.ROOT/('.fr21-local/auth-gps'if prefix=='AUTH-delivery-'else'.fr21-local/map-gps');out.mkdir(parents=True,exist_ok=True)
    m.observer.h.OUT=out
    if mode=='stopped':
        token=b.login(customer)
        code,context=m.customer_rpc('fr13_tracking_context',{'p_order_id':oid},token)
        stopped=code==200 and context.get('code')in('OK','INELIGIBLE')and context.get('sharing')is not True and context.get('latest')is None and not context.get('topic')
        result={'project':b.REF,'order_id':oid,'utc':dt.datetime.now(dt.timezone.utc).isoformat(),'http_status':code,'code':context.get('code'),'sharing':context.get('sharing'),'latest_exposed':context.get('latest')is not None,'topic_exposed':bool(context.get('topic')),'stop_confirmed':stopped,'scope':'Actual owner-instructed normal Rider Stop sharing control followed by fresh owning-Customer context inspection. No Rider password login, lifecycle transition or coordinates retained.'}
        assert stopped,'Customer sharing revocation not confirmed'
    elif mode in('gps','travel'):
        seconds=120 if mode=='travel'else 60
        label='travel'if mode=='travel'else'foreground'
        m.observer.main(seconds,label)
        result=json.loads((out/('physical-observer-'+label+'.json')).read_text())
        intervals=result['device_intervals_seconds']
        result.update(project=b.REF,order_id=oid,artifact_sha256=json.loads((b.ROOT/'build/delivery/test/build-evidence.json').read_text(encoding='utf-8-sig'))['sha256'],
            device_interval_p50_seconds=statistics.median(intervals)if intervals else None,
            device_interval_p95_seconds=sorted(intervals)[max(0,int(len(intervals)*.95+.999)-1)]if intervals else None,
            strict_2_to_3_second_intervals_pass=bool(intervals)and all(2<=x<=3 for x in intervals),
            scope=str(seconds)+'-second real physical TEST delivery broadcast observation under owning Customer authorization. No coordinates or credentials persisted. Interval distribution alone does not prove physical arrival, handover, background/recovery or full travel qualification.')
    else:
        token=b.login(customer);samples=[]
        for _ in range(3):
            request=urllib.request.Request(b.BASE+'/functions/v1/get-delivery-route',method='POST',data=json.dumps({'orderId':oid}).encode(),headers={'apikey':b.ANON,'Authorization':'Bearer '+token,'Content-Type':'application/json'})
            started=time.monotonic()
            try:
                with urllib.request.urlopen(request,timeout=40)as response:status=response.status;data=json.load(response)
            except urllib.error.HTTPError as error:status=error.code;data=json.load(error)
            route=data.get('route')or{}
            samples.append({'http_status':status,'code':data.get('code'),'request_ms':round((time.monotonic()-started)*1000,2),'source':route.get('source'),'road_geometry':route.get('geometry')is not None,'is_approximate':route.get('isApproximate'),'cache_status':route.get('cacheStatus'),'target':route.get('target')})
            time.sleep(1)
        result={'project':b.REF,'order_id':oid,'utc':dt.datetime.now(dt.timezone.utc).isoformat(),'samples':samples,'strict_800ms_all_samples_pass':all(s['http_status']==200 and s['request_ms']<=800 for s in samples),'scope':'Three real owning-Customer authorized route calls on the genuine delivery. No coordinates or geometry persisted. No load or rendering qualification.'}
    (b.ROOT/'docs/evidence'/(prefix+mode+'.json')).write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'mode':mode,'order_id':oid,'evidence_saved':True,'result':{key:value for key,value in result.items()if key.startswith('strict_')or key in('events','device_interval_p50_seconds','device_interval_p95_seconds','samples')}}))

if __name__=='__main__':main(sys.argv[1])
