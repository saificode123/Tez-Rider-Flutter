"""Admit only the owner's single order confirmation; never claim inbox receipt."""
import datetime as dt
import importlib.util
import json
from pathlib import Path
import urllib.request
import urllib.error
import uuid

def load(name, file):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

h=load('confirmation_accounts','FR-14-hosted.py');b=h.b

def read(path):
    code,data=b.api(path,admin=True)
    assert code==200,'Confirmation precondition read unconfirmed'
    return data

def main():
    b.target()
    file=b.PRIVATE/'accept-single-delivery.dpapi'
    state=json.loads(b.crypt(file.read_bytes(),True))
    oid=state['order_id'];assert isinstance(oid,int) and state['customer_id']==159 and state['product_id']==224 and state['message_limits']['order_confirmation']==1
    owner=h.state['accounts']['physical-customer']
    auth=read('/auth/v1/admin/users/'+str(uuid.UUID(owner['auth_id'])))
    config={}
    for line in(b.ROOT/'supabase/functions/.env.test.local').read_text().splitlines():
        key,sep,value=line.partition('=')
        if sep and key.strip()=='BREVO_TEST_RECIPIENT':config[key.strip()]=value.strip().strip('\"\'')
    assert auth.get('email_confirmed_at') and config['BREVO_TEST_RECIPIENT'].lower()==auth['email'].lower()==owner['email'].lower()
    order=read('/rest/v1/orders?id=eq.'+str(oid)+'&user_id=eq.159&select=id,amount,payment_method,order_status')
    assert len(order)==1 and order[0]['amount']==470 and order[0]['payment_method']=='COD'and order[0]['order_status']not in('cancelled',)
    jobs=read('/rest/v1/email_outbox?entity_type=eq.order&entity_id=eq.'+str(oid)+'&email_type=eq.order_confirmation&select=id,status,test_approved,recipient_user_id,attempts,provider_message_id')
    assert len(jobs)==1 and jobs[0]['recipient_user_id']==159
    job=jobs[0];jid=str(uuid.UUID(job['id']))
    assert state.get('confirmation_approval_job_id')in(None,jid)
    approved=read('/rest/v1/email_outbox?test_approved=eq.true&status=in.(pending,deferred,sending)&select=id')
    assert all(row['id']==jid for row in approved),'Unrelated approved sendable job; do not run batch worker'
    state['confirmation_approval_job_id']=jid
    temporary=file.with_suffix('.dpapi.tmp');temporary.write_bytes(b.crypt(json.dumps(state).encode()));temporary.replace(file)
    if not job['test_approved']:
        assert job['status']in('pending','skipped_test','deferred') and job['attempts']==0
        code,result=b.rpc('fr32_test_allow_email',{'p_ids':[jid]},admin=True)
        assert code==200,'Single confirmation admission unconfirmed; inspect before retry'
    # One worker invocation only. Scheduler/provider idempotency retains the same job.
    worker_status=None
    if job['status']!='sent'and not state.get('confirmation_worker_invoked_at'):
        state['confirmation_worker_invoked_at']=dt.datetime.now(dt.timezone.utc).isoformat()
        temporary.write_bytes(b.crypt(json.dumps(state).encode()));temporary.replace(file)
        key=b.crypt((b.PRIVATE/'fr32-worker.bin').read_bytes(),True).decode()
        request=urllib.request.Request(b.BASE+'/functions/v1/fr32-email-worker',data=b'{}',headers={'Content-Type':'application/json','x-fr32-worker-key':key},method='POST')
        try:
            with urllib.request.urlopen(request,timeout=55)as response:worker_status=response.status;response.read()
        except urllib.error.HTTPError as error:worker_status=error.code
        except TimeoutError:worker_status='UNCONFIRMED; inspect same job, no resend'
    current=read('/rest/v1/email_outbox?id=eq.'+jid+'&select=status,test_approved,attempts,provider_message_id,sent_at')[0]
    result={'project':b.REF,'utc':dt.datetime.now(dt.timezone.utc).isoformat(),'order_id':oid,'email_type':'order_confirmation','job_id':jid,
        'status':current['status'],'approved':current['test_approved'],'attempts':current['attempts'],'provider_accepted':bool(current['provider_message_id'])and current['status']=='sent',
        'sent_at':current['sent_at'],'worker_status':worker_status,'inbox_receipt_confirmed':False,'other_jobs_approved':False,'scope':'Exactly one existing order confirmation job to verified configured owner TEST inbox. No OTP or invoice sent by this action. Provider acceptance is not inbox receipt.'}
    (b.ROOT/'docs/evidence/AUTH-order-confirmation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result))

if __name__=='__main__':main()
