import http from 'k6/http';
import { check, sleep } from 'k6';
import encoding from 'k6/encoding';

// Private fixture JSON stays outside Git: {anon_key, admin_token, rider_id}.
// Full load requires a local Supabase stack with the reviewed schema/function.
// Local Edge runtime must explicitly set FR04_LOCAL_LOAD_TEST=true; cloud
// runtime leaves it absent. Local synthetic Auth confirmation must be automatic.
const base = (__ENV.FR04_URL || '').replace(/\/$/, '');
const local = /^http:\/\/(127\.0\.0\.1|localhost):54321$/.test(base);
const smoke = __ENV.FR04_HOSTED_SMOKE === 'true';
if (!local && !(smoke && base === 'https://igeisilhtmglgnqvllrx.supabase.co')) {
  throw new Error('Only local full load or a two-user dedicated TEST read smoke is permitted.');
}
const credentials = JSON.parse(open(__ENV.FR04_FIXTURE_FILE));
const smokeIterations = Number(__ENV.FR04_SMOKE_ITERATIONS || 8);
if (smoke && ![8, 40].includes(smokeIterations)) {
  throw new Error('Hosted read smoke is bounded to 8 or 40 iterations with two users.');
}
const sample = local ? encoding.b64encode(open(__ENV.FR04_SYNTHETIC_IMAGE, 'b')) : null;
export const options = {
  ...(smoke ? { vus: 2, iterations: smokeIterations } : {
    stages: [{duration:'1m',target:100},{duration:'2m',target:500},
      {duration:'2m',target:1000},{duration:'3m',target:1000},{duration:'1m',target:0}],
  }),
  thresholds: {http_req_duration:['p(95)<800'],
    'http_req_duration{endpoint:approval_queue}':['p(95)<800'],
    'http_req_duration{endpoint:signed_url}':['p(95)<800'],
    http_req_failed:['rate<0.01'],checks:['rate>0.99']},
};
function call(path, body, token, endpoint) {
  const headers = {apikey:credentials.anon_key,Authorization:`Bearer ${token || credentials.anon_key}`,
    'Content-Type':'application/json'};
  if (path.startsWith('/functions/') && __ENV.FR04_EDGE_REGION) headers['x-region']=__ENV.FR04_EDGE_REGION;
  const r = http.post(base + path, JSON.stringify(body), {
    headers, tags:{endpoint},timeout:'15s',
  });
  check(r, {[endpoint + ' confirmed']: response => response.status >= 200 && response.status < 300});
  if (__ENV.FR04_DIAGNOSTICS === 'true') {
    const timing = r.headers['Server-Timing'] || '';
    const stages = {};
    for (const part of timing.split(',')) {
      const match = /^\s*(auth|authority|signing|handler);dur=([0-9.]+)\s*$/.exec(part);
      if (match) stages[match[1]] = Number(match[2]);
    }
    console.log(JSON.stringify({endpoint,status:r.status,vu:__VU,iteration:__ITER,
      duration_ms:r.timings.duration,waiting_ms:r.timings.waiting,
      blocked_ms:r.timings.blocked,tls_ms:r.timings.tls_handshaking,
      region:r.headers['X-Sb-Edge-Region'] || null,server_ms:stages}));
  }
  return r;
}
export default function () {
  call('/rest/v1/rpc/fr04_admin_riders',{p_limit:30},credentials.admin_token,'approval_queue');
  call('/functions/v1/fr04-cnic',{action:'view',user_id:credentials.rider_id},credentials.admin_token,'signed_url');
  if (local && !smoke) {
    const email = `fr04-load-${__ENV.FR04_RUN_ID}-${__VU}-${__ITER}@example.test`;
    const password = __ENV.FR04_SYNTHETIC_PASSWORD;
    if (!password || !__ENV.FR04_RUN_ID) throw new Error('Unique run ID and synthetic password required.');
    const auth = call('/auth/v1/signup',{email,password,data:{role:'rider',name:'FR04 load synthetic'}},null,'signup');
    if (auth.status < 300 && auth.status >= 200 && auth.json('access_token')) {
      const token = auth.json('access_token');
      call('/rest/v1/users',{email,name:'FR04 load synthetic',role:'rider',verification_status:'pending'},token,'rider_profile');
      // Unique RFC4122 v4 UUID per request; retry tests use the hosted suite instead.
      const id = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c => {
        const r=Math.floor(Math.random()*16);return (c==='x'?r:(r&3)|8).toString(16);
      });
      call('/functions/v1/fr04-cnic',{action:'upload',request_id:id,cnic:'3200012345671',
        mime_type:'image/png',image_base64:sample},token,'upload');
    }
  }
  sleep(1);
}
