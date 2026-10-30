import {createHandler, parseProvider, fallback, coordinate, distance, type Data, type Dependencies} from './handler.ts';
function equal(a: unknown, b: unknown) { if (JSON.stringify(a) !== JSON.stringify(b)) throw Error(`Expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`); }
const origin = [73.05, 33.7], destination = [73.06, 33.71];
function response() { return {type: 'FeatureCollection', features: [{geometry: {type: 'MultiLineString', coordinates: [[origin, destination]]}, properties: {distance: 1600, time: 240}}]}; }
function harness(change: Partial<Dependencies> = {}) {
  const calls = {provider: 0, prepare: 0, finish: 0};
  const deps: Dependencies = {
    configured: true, now: () => Date.parse('2026-10-19T12:00:00Z'),
    authenticate: async jwt => jwt === 'valid', context: async () => ({code: 'OK', actor: 42, destination}),
    prepare: async () => { calls.prepare++; return {code: 'COMPUTE', orderId: 1, origin, destination, lease: 'lease', speedKmh: 20, minimumSeconds: 60}; },
    finish: async (_order, _actor, _lease, route) => { calls.finish++; return route ? {code: 'OK', route} : {code: 'RELEASED'}; },
    provider: async () => { calls.provider++; return response(); }, ...change,
  };
  const handler = createHandler(deps);
  const run = async (body: unknown = {orderId: 1}, token = 'valid') => {
    const res = await handler(new Request('http://localhost/route', {method: 'POST', headers: {Authorization: 'Bearer ' + token}, body: JSON.stringify(body)}));
    return {status: res.status, data: await res.json()};
  };
  return {run, calls, handler};
}
Deno.test('JWT rejected before routing', async () => { const h = harness(); equal((await h.run(undefined, 'forged')).status, 401); equal(h.calls.prepare, 0); });
Deno.test('destination amendment during provider work suppresses the old geometry', async () => {
  const h = harness({initialActor: () => 42, context: async () => ({code:'OK',actor:42,destination:[73.07,33.72]})});
  const result = await h.run();
  equal(result.data, {code:'DESTINATION_CHANGED',route:null});
  equal(h.calls.finish, 1);
});
Deno.test('destination amendment during cache read suppresses the old geometry', async () => {
  const h = harness({initialActor: () => 42,
    prepare: async () => ({code:'CACHE',orderId:1,origin,destination,cache:{geometry:{type:'LineString',coordinates:[origin,destination]}}}),
    context: async () => ({code:'OK',actor:42,destination:[73.07,33.72]})});
  equal((await h.run()).data,{code:'DESTINATION_CHANGED',route:null});
  equal(h.calls.provider,0);
});
Deno.test('missing final destination metadata fails closed without geometry', async () => {
  const h = harness({initialActor: () => 42,context: async () => ({code:'OK',actor:42})});
  equal((await h.run()).data,{code:'UNAVAILABLE',route:null});
});
Deno.test('live auth and account checks overlap without starting order work early', async () => {
  let release!: (value: boolean) => void, boundaryStarted = false, contexts = 0;
  const authenticated = new Promise<boolean>(resolve => { release = resolve; });
  const h = harness({authenticate: () => authenticated,
    accountBoundary: async () => { boundaryStarted = true; return null; },
    context: async () => { contexts++; return {code: 'OK', actor: 42, destination}; }});
  const pending = h.run();
  await Promise.resolve(); equal(boundaryStarted, true); equal(contexts, 0); equal(h.calls.prepare, 0);
  release(true); equal((await pending).status, 200);
});
Deno.test('blocked account denial wins and never starts coordinate lookup', async () => {
  let contexts = 0;
  const h = harness({accountBoundary: async () => Response.json({code: 'FR28_ACCOUNT_BLOCKED'}, {status: 403}),
    context: async () => { contexts++; return {code: 'OK', actor: 42, destination}; }});
  equal((await h.run()).status, 403); equal(contexts, 0); equal(h.calls.prepare, 0);
});
Deno.test('unavailable account check fails closed without routing', async () => {
  const h = harness({accountBoundary: async () => { throw Error('account service unavailable'); }});
  equal((await h.run()).status, 503); equal(h.calls.prepare, 0);
});
Deno.test('ownership authorization precedes trusted coordinate lookup', async () => { const h = harness({context: async () => ({code: 'FORBIDDEN'})}); equal((await h.run()).status, 403); equal(h.calls.provider, 0); });
for (const body of [{orderId: 1, destination}, {orderId: -1}, {orderId: 1.5}, {}, null, []]) {
  Deno.test('strict input ' + JSON.stringify(body), async () => { equal((await harness().run(body)).status, 400); });
}
Deno.test('server coordinates exclusively passed to provider', async () => { let actual: unknown; const h = harness({provider: async (a, b, scope) => { actual = [a, b, scope]; return response(); }}); equal((await h.run()).data.code, 'OK'); equal(actual, [origin, destination, {orderId: 1, actor: 42, pickup: false}]); equal(h.calls.finish, 1); });
for (const code of ['DESTINATION_UNCONFIRMED', 'LOCATION_UNAVAILABLE']) {
  Deno.test(code + ' returns no route', async () => { const h = harness({prepare: async () => ({code})}); equal((await h.run()).data.route, null); equal(h.calls.provider, 0); });
}
for (const code of ['QUOTA', 'BUSY', 'THROTTLED', 'NOT_CONFIGURED']) {
  Deno.test(code + ' prevents HTTP and returns labeled approximation', async () => { const h = harness({prepare: async () => ({code, orderId: 1, origin, destination, speedKmh: 20})}); const r = await h.run(); equal(r.data.route.isApproximate, true); equal(r.data.route.geometry, null); equal(h.calls.provider, 0); });
}
Deno.test('cache hit avoids provider and labels cached geometry', async () => { const h = harness({prepare: async () => ({code: 'CACHE', orderId: 1, origin, destination, cache: {source: 'geoapify', expiresAt: '2026-10-19T12:05:00Z'}})}); const result = await h.run(); equal(result.data.route.isStale, false); equal(result.data.route.cacheStatus, 'cached'); equal(h.calls.provider, 0); });
Deno.test('new road geometry is labeled fresh after final live authorization', async () => {
  const h = harness(); const result = await h.run(); equal(result.data.route.cacheStatus, 'fresh'); equal(h.calls.provider, 1);
});
Deno.test('pickup request uses separate authorized prepare/finish and revalidation', async () => {
  let contexts=0, prepares=0, finishes=0;
  const h=harness({context:async()=>{throw Error('Delivery context must not be used');},
    pickupContext:async()=>{contexts++;return {code:'OK',actor:42};},
    pickupPrepare:async()=>{prepares++;return {code:'COMPUTE',orderId:1,origin,destination,lease:'pickup'};},
    pickupFinish:async(_o,_a,_l,route)=>{finishes++;return {code:'OK',route};}});
  const result=await h.run({orderId:1,target:'pickup'});
  equal(result.status,200);equal(result.data.route.target,'pickup');equal(contexts,2);equal(prepares,1);equal(finishes,1);
  equal(h.calls.prepare,0);equal(h.calls.finish,0);
});
Deno.test('pickup authorization denial never calls provider or delivery prepare', async()=>{
  const h=harness({pickupContext:async()=>({code:'FORBIDDEN'}),pickupPrepare:async()=>{throw Error('Must not prepare');},pickupFinish:async()=>({code:'UNAVAILABLE'})});
  equal((await h.run({orderId:1,target:'pickup'})).status,403);equal(h.calls.provider,0);equal(h.calls.prepare,0);
});
Deno.test('pickup phase ending during provider request suppresses geometry',async()=>{
  let context=0;
  const h=harness({pickupContext:async()=>++context===1?{code:'OK',actor:42}:{code:'FORBIDDEN'},
    pickupPrepare:async()=>({code:'COMPUTE',orderId:1,origin,destination,lease:'pickup'}),pickupFinish:async(_o,_a,_l,route)=>({code:'OK',route})});
  const result=await h.run({orderId:1,target:'pickup'});equal(result.status,403);equal(result.data.route,undefined);
});
Deno.test('pickup provider failure never substitutes straight-line navigation',async()=>{
  const h=harness({provider:async()=>{throw Error('offline');},pickupContext:async()=>({code:'OK',actor:42}),
    pickupPrepare:async()=>({code:'COMPUTE',orderId:1,origin,destination,lease:'pickup'}),pickupFinish:async()=>({code:'RELEASED'})});
  const result=await h.run({orderId:1,target:'pickup'});equal(result.data.route,null);equal(result.data.code,'UNAVAILABLE');
});
Deno.test('unknown navigation targets are rejected before any route preparation',async()=>{
  for(const target of ['delivery','other',null,4]){
    const h=harness();equal((await h.run({orderId:1,target})).status,400);equal(h.calls.prepare,0);
  }
  const h=harness();equal((await h.run(5)).status,400);
});
Deno.test('old geometry is labeled stale without another provider request', async () => {
  const h = harness({prepare: async () => ({code: 'QUOTA', orderId: 1, origin, destination, cache: {expiresAt: '2026-10-19T11:00:00Z'}})});
  equal((await h.run()).data.route.cacheStatus, 'stale'); equal(h.calls.provider, 0);
});
Deno.test('verified request actor avoids duplicate initial RPC and still revalidates', async () => {
  let contexts = 0, actor: unknown;
  const h = harness({initialActor: () => 42,
    context: async () => { contexts++; return {code: 'OK', actor: 42, destination}; },
    prepare: async (_order, currentActor) => {actor = currentActor; return {code: 'CACHE', orderId: 1, origin, destination,
      cache: {source: 'geoapify', expiresAt: '2026-10-19T12:05:00Z'}}; }});
  equal((await h.run()).data.route.isStale, false);
  equal(contexts, 1); equal(actor, 42); equal(h.calls.provider, 0);
});
Deno.test('verified actor never bypasses SQL ownership or final session revocation', async () => {
  const forbidden = harness({initialActor: () => 42, prepare: async () => ({code: 'FORBIDDEN'})});
  equal((await forbidden.run()).status, 403); equal(forbidden.calls.provider, 0);
  const revoked = harness({initialActor: () => 42, context: async () => ({code: 'FORBIDDEN'})});
  equal((await revoked.run()).status, 403);
});
Deno.test('missing or invalid verified identity falls back to live context', async () => {
  for (const actor of [null, -1, NaN, 1.5]) {
    let contexts = 0;
    const h = harness({initialActor: () => actor, context: async () => {contexts++; return {code: 'FORBIDDEN'};}});
    equal((await h.run()).status, 403); equal(contexts, 1); equal(h.calls.provider, 0);
  }
});
Deno.test('expired cache is labeled stale', async () => { const h = harness({prepare: async () => ({code: 'QUOTA', orderId: 1, origin, destination, cache: {expiresAt: '2026-10-19T11:00:00Z'}})}); equal((await h.run()).data.route.isStale, true); });
for (const error of ['429', '500', 'timeout', 'secret=DO_NOT_DISCLOSE']) {
  Deno.test('provider failure ' + error + ' releases lease and redacts error', async () => { const h = harness({provider: async () => { throw Error(error); }}); const r = await h.run(); equal(r.data.code, 'APPROXIMATE'); equal(h.calls.finish, 1); equal(JSON.stringify(r).includes(error), false); });
}
Deno.test('invalid geometry rejects provider result', () => { const v = response(); v.features[0].geometry.coordinates[0][0] = [181, 33]; let failed = false; try { parseProvider(v, origin, destination); } catch { failed = true; } equal(failed, true); });
Deno.test('duration is seconds and geometry retains longitude first', () => { const v = parseProvider(response(), origin, destination); equal(v.durationSeconds, 240); equal(v.geometry.coordinates[0], origin); });
Deno.test('finite and range validation', () => { for (const v of [[Infinity, 1], [1, NaN], [73, 91], null]) equal(coordinate(v), false); });
Deno.test('fallback ETA uses calculation clock without fake road geometry', () => { const r = fallback({orderId: 1, origin, destination, speedKmh: 20}, 0)!; equal(r.geometry, null); equal(Date.parse(r.estimatedArrivalAt), Math.floor(r.durationSeconds * 1000)); equal(r.distanceMeters, distance(origin, destination)); });
Deno.test('meaningless fallback unavailable', () => { equal(fallback({origin, destination: [0, 0], speedKmh: 20}, 0), null); });
Deno.test('oversized request bounded before JSON parse', async () => { const h = harness(); equal((await h.run({orderId: 1, padding: 'x'.repeat(1024)})).status, 400); equal(h.calls.prepare, 0); });
Deno.test('disconnected multipart road geometry is not bridged', () => { const v=response();v.features[0].geometry.coordinates.push([destination,origin]);let failed=false;try{parseProvider(v,origin,destination);}catch{failed=true;}equal(failed,true); });
Deno.test('invalid provider duration rejected', () => { for(const time of [-1,NaN,Infinity]) {const v=response();v.features[0].properties.time=time;let failed=false;try{parseProvider(v,origin,destination);}catch{failed=true;}equal(failed,true);} });
Deno.test('end-of-delivery race does not disclose computed route', async () => { const h = harness({finish: async () => ({code: 'UNAVAILABLE'})}); equal((await h.run()).data.route, null); });
Deno.test('blocked/session change after HTTP suppresses route', async () => { let count = 0; const h = harness({context: async () => ++count === 1 ? {code: 'OK', actor: 42, destination} : {code: 'FORBIDDEN'}}); equal((await h.run()).status, 403); });
Deno.test('SQL lease semantics mock: concurrent HTTP calls single provider invocation', async () => {
  let leased = false, providers = 0;
  const h = harness({prepare: async () => { const code = leased ? 'BUSY' : 'COMPUTE'; leased = true; return {code, orderId: 1, origin, destination, speedKmh: 20, lease: 'lease'}; },
    provider: async () => { providers++; await new Promise(r => setTimeout(r, 10)); return response(); }});
  await Promise.all(Array.from({length: 25}, () => h.run())); equal(providers, 1);
});
Deno.test('authorized routing exposes bounded stage timings without private values', async () => {
  const h = harness();
  const response = await h.handler(new Request('http://localhost/route', {
    method: 'POST', headers: {Authorization: 'Bearer valid'}, body: '{"orderId":1}',
  }));
  equal(response.status, 200);
  const timing = response.headers.get('Server-Timing')!;
  const parts = timing.split(', ');
  equal(parts.map(part => part.split(';')[0]), ['auth', 'context', 'prepare', 'provider', 'finish', 'revalidate', 'handler']);
  equal(parts.every(part => /^[a-z]+;dur=\d+\.\d{2}$/.test(part)), true);
  for (const secret of ['Bearer valid', 'actor', 'lease', 'origin', 'destination']) equal(timing.includes(secret), false);
});
Deno.test('cache timing omits provider work and denied calls omit diagnostic details', async () => {
  const h = harness({prepare: async () => ({code: 'CACHE', orderId: 1, origin, destination, cache: {source: 'geoapify', expiresAt: '2026-10-19T12:05:00Z'}})});
  const request = (token: string) => new Request('http://localhost/route', {
    method: 'POST', headers: {Authorization: 'Bearer ' + token}, body: '{"orderId":1}',
  });
  const hit = await h.handler(request('valid'));
  equal(hit.headers.get('Server-Timing')!.includes('provider;'), false);
  equal(h.calls.provider, 0);
  const denial = await h.handler(request('forged'));
  equal(denial.status, 401);
  equal(denial.headers.get('Server-Timing'), null);
});
Deno.test('provider failure timings do not disclose raw exception', async () => {
  const h = harness({provider: async () => { throw Error('apiKey=PRIVATE_VALUE'); }});
  const response = await h.handler(new Request('http://localhost/route', {
    method: 'POST', headers: {Authorization: 'Bearer valid'}, body: '{"orderId":1}',
  }));
  equal(response.status, 200);
  equal(response.headers.get('Server-Timing')!.includes('provider;dur='), true);
  equal(JSON.stringify([...response.headers]).includes('PRIVATE_VALUE'), false);
  equal((await response.json()).code, 'APPROXIMATE');
});
