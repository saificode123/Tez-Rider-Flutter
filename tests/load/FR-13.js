import http from 'k6/http';
import ws from 'k6/ws';
import {check} from 'k6';
import {Counter, Rate, Trend} from 'k6/metrics';
const fixture = JSON.parse(open(__ENV.FR13_LOAD_FIXTURES));
if (__ENV.FR13_LOCAL_ONLY !== 'true' || fixture.project !== 'tezrider-fr30-local' || fixture.base !== 'http://127.0.0.1:54321') throw Error('LOCAL fixtures only; never hosted load');
const vus = Number(__ENV.FR13_LOAD_VUS || 4);
if(!Number.isInteger(vus)||vus<1||vus>4)throw Error('Only small 1–4 VU LOCAL stages allowed');
export const options = {scenarios:{gps:{executor:'shared-iterations',vus,iterations:vus*2,maxDuration:'90s',gracefulStop:'5s'}}, thresholds: {
  checks: ['rate==1'], gps_delivery_ms: ['p(95)<800'], gps_unexpected_error: ['rate<0.01'],
  gps_delivery_complete: ['rate==1'], gps_duplicate_events: ['count==0'],
}};
const latency = new Trend('gps_delivery_ms');
const errors = new Rate('gps_unexpected_error');
const complete = new Rate('gps_delivery_complete');
const expected = new Counter('gps_expected_rejections');
const duplicates = new Counter('gps_duplicate_events');
const publications = new Counter('gps_publications');
const deliveries = new Counter('gps_deliveries');
const skew = new Counter('gps_clock_skew_samples');
function id() {return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {const r=Math.floor(Math.random()*16);return (c==='x'?r:(r&3)|8).toString(16);});}
function join(socket, row, token) {socket.send(JSON.stringify({topic:'realtime:'+row.topic,event:'phx_join',ref:'1',payload:{config:{private:true,broadcast:{ack:true,self:false},presence:{key:''},postgres_changes:[]},access_token:token}}));}
function send(row, value) {
  const response=http.post('http://127.0.0.1:54328/',JSON.stringify(value),{headers:{apikey:fixture.anon,Authorization:'Bearer '+row.rider,'Content-Type':'application/json'},timeout:'10s'});
  try {return response.json().code;} catch (_) {return 'UNAVAILABLE';}
}
export default function() {
  const row=fixture.records[(__VU-1)%fixture.records.length];
  let denied=false;const negative=[];
  ws.connect('ws://127.0.0.1:54321/realtime/v1/websocket?apikey='+encodeURIComponent(fixture.anon)+'&vsn=1.0.0',{},socket=>{
    socket.on('open',()=>join(socket,row,row.other));
    socket.on('message',text=>{const msg=JSON.parse(text);if(negative.length<3)negative.push({event:msg.event,status:msg.payload&&msg.payload.status,ref:msg.ref});if(msg.event==='phx_reply'&&msg.ref==='1'){denied=msg.payload.status==='error';socket.close();}});
    socket.setTimeout(()=>{if(!denied)console.warn(JSON.stringify({negative_join_timeout:true,events:negative}));socket.close();},15000);
  });
  check(denied,{'unauthorized subscriber rejected':v=>v});
  let published=0,received=0,ready=false,probed=false,ticks=0;const seen={};
  ws.connect('ws://127.0.0.1:54321/realtime/v1/websocket?apikey='+encodeURIComponent(fixture.anon)+'&vsn=1.0.0',{},socket=>{
    socket.on('open',()=>join(socket,row,row.customer));
    socket.on('message',text=>{
      const msg=JSON.parse(text);
      if(msg.event==='phx_reply'&&msg.ref==='1'){ready=msg.payload.status==='ok';return;}
      if(msg.event==='broadcast'&&msg.payload.event==='location'){
        const p=msg.payload.payload;received++;deliveries.add(1);
        if(seen[p.request_id])duplicates.add(1);else{seen[p.request_id]=true;duplicates.add(0);}
        const delay=Date.now()-Date.parse(p.received_at);
        if(Number.isFinite(delay)&&delay>=0){latency.add(delay);}else{skew.add(1);}
        check(p,{'message bound to own assignment':p=>p.order_id===row.order_id&&p.assignment_id===row.assignment_id});
      }
    });
    socket.setInterval(()=>{
      if(!ready||ticks>=4)return;
      ticks++;
      // Synthetic LOCAL coordinates only, never physical GPS evidence.
      const value={order_id:row.order_id,latitude:33.7+published*0.00001,longitude:73.05,accuracy:5,device_at:new Date().toISOString(),request_id:id()};
      const code=send(row,value);errors.add(!['PUBLISHED','RATE_LIMIT','REPLAYED'].includes(code));
      if(code==='RATE_LIMIT'||code==='REPLAYED')expected.add(1);
      if(code==='PUBLISHED'){published++;publications.add(1);}
      if(code==='PUBLISHED'&&!probed){
        probed=true;
        const retry=send(row,value);check(retry,{'retry suppressed':c=>c==='REPLAYED'});expected.add(retry==='REPLAYED'?1:0);
        const rate=send(row,{...value,request_id:id(),device_at:new Date().toISOString()});check(rate,{'excess frequency rejected':c=>c==='RATE_LIMIT'});expected.add(rate==='RATE_LIMIT'?1:0);
      }
    },2500);
    // Four fixes at2.5/5/7.5/10s, then a3s delivery drain. Never race a final
    // timer callback against socket close and misreport that as a dropped event.
    socket.setTimeout(()=>socket.close(),13000);
  });
  check(ready,{'authorized channel connected':v=>v});
  complete.add(published>0&&received===published);
  check(received,{'all accepted updates delivered once':v=>published>0&&v===published});
}
