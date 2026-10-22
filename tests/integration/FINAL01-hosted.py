"""Bounded real-JWT compatible gateway regression; no provider calls or cleanup."""
import importlib.util,json,sys,urllib.parse,urllib.request
from pathlib import Path
spec=importlib.util.spec_from_file_location('regression',Path(__file__).with_name('FINAL-security-hosted.py'));r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
b=r.b;OUT=b.ROOT/'.fr21-local/final01';direct=b.api
mode=sys.argv[1]if len(sys.argv)>1 else 'compatible'
assert mode in ('compatible','enforced')

def gateway(path,method='GET',body=None,token=None,admin=False,mime='application/json'):
 if not path.startswith('/rest/v1/')or admin or not token:return direct(path,method,body,token,admin,mime)
 parsed=urllib.parse.urlsplit(path)
 envelope={'method':method,'path':parsed.path[len('/rest/v1'):],'query':parsed.query,'headers':{'content-type':mime,'prefer':'return=representation'},'body':json.dumps(body)if body is not None else ''}
 return direct('/functions/v1/security-gateway','POST',envelope,token)

b.api=gateway;r.OUT=OUT/('gateway-'+mode);r.main()
accounts=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']
for role in ('customer','vendor','rider','admin'):
 token=b.login(accounts[role])
 code,value=gateway('/rest/v1/users?select=id&limit=1',token=token)
 r.check(code==200 and isinstance(value,list),role+': gateway preserves user RLS for permitted read')
 code,_=direct('/rest/v1/users?select=id&limit=1',token=token)
 r.check(code==(403 if mode=='enforced' else 200),role+': direct REST '+('requires gateway'if mode=='enforced'else 'compatibility retained before activation'))
 code,_=direct('/functions/v1/security-gateway','POST',{'method':'GET','path':'/users','query':'select=id','headers':{'x-final01-proof':'forged'},'body':''},token)
 r.check(code==400,role+': client cannot supply private proof')
 for worker in ('fr30-dispatch-push','fr32-email-worker'):
  # Extra field rejects before claim/send even for an authorized Admin push.
  code,_=direct('/functions/v1/'+worker,'POST',{'forbidden_test_field':True},token)
  r.check(code in (400,401,403,503),role+': '+worker+' rejects without provider/claim')
code,_=direct('/functions/v1/security-gateway','POST',{},'invalid')
r.check(code==401,'gateway invalid signed JWT denied')
code,_=direct('/rest/v1/rpc/fr21_order_contacts','POST',{'p_order_ids':[0]})
r.check(code in(401,403),'anonymous order contacts cannot disclose data')
(OUT/('hosted-'+mode+'.json')).write_text(json.dumps(r.checks,indent=2),encoding='utf-8')
print(json.dumps({'TEST':b.REF,'mode':mode,'total_checks':len(r.checks),'provider_calls':0,'business_mutations':0,'production_modified':False}))
