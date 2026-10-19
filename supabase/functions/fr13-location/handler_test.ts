import {createHandler, type Data, type Dependencies} from './handler.ts';
const value = {order_id: 1, latitude: 33.7, longitude: 73.05, accuracy: 5, device_at: new Date().toISOString(), request_id: '00000000-0000-4000-8000-000000000001'};
function assert(ok: boolean) {if (!ok) throw Error('FR13 handler assertion failed');}
function fixture(submitCode = 'ACCEPTED', contextCode = 'OK', published = true) {
  let sends = 0, calls = 0;
  const deps: Dependencies = {
    submit: async () => {calls++; return {code: submitCode, topic: 'fr13:1:1:session', payload: value};},
    context: async () => ({code: contextCode, sharing: true, topic: 'fr13:1:1:session'}),
    publish: async () => {sends++;return published;},
  };
  return {run: createHandler(deps), sends: () => sends, calls: () => calls};
}
function request(body: unknown = value, auth = 'Bearer synthetic-local-test'): Request {
  return new Request('http://localhost/fr13-location', {method: 'POST', headers: {Authorization: auth}, body: JSON.stringify(body)});
}
for (const code of ['FORBIDDEN', 'INELIGIBLE', 'SHARING_STOPPED', 'STALE_FIX', 'RATE_LIMIT', 'REPLAYED']) {
  Deno.test(code + ' never publishes', async () => {
    const f = fixture(code);const result = await (await f.run(request())).json();
    assert(result.code === code && f.sends() === 0);
  });
}
Deno.test('accepted update publishes once after lifecycle recheck', async () => {
  const f = fixture();assert((await (await f.run(request())).json()).code === 'PUBLISHED');assert(f.sends() === 1);
});
Deno.test('ended assignment between validation and publish is denied', async () => {
  const f = fixture('ACCEPTED', 'INELIGIBLE');assert((await (await f.run(request())).json()).code === 'INELIGIBLE');assert(f.sends() === 0);
});
Deno.test('broadcast transport failure is never success', async () => {
  const f = fixture('ACCEPTED', 'OK', false);const r = await f.run(request());assert(r.status === 503 && (await r.json()).code === 'PUBLISH_UNCONFIRMED');
});
Deno.test('anonymous request cannot reach RPC', async () => {
  const f = fixture();assert((await f.run(request(value, ''))).status === 401);assert(f.calls() === 0);
});
Deno.test('malformed/nonfinite/poor/oversized payload cannot reach RPC', async () => {
  const bad: unknown[] = [null, [], {}, {...value, latitude: 91}, {...value, longitude: -181}, {...value, accuracy: -1}, {...value, accuracy: 101}, {...value, latitude: null}, {...value, device_at: 'invalid'}, {...value, request_id: 'invalid'}, {...value, topic: 'victim'}, {...value, extra: 'x'.repeat(3000)}];
  for (const body of bad) {const f = fixture();assert((await f.run(request(body))).status === 400);assert(f.calls() === 0);}
});
Deno.test('changed channel after validation cannot publish stale session', async () => {
  let sends = 0;const f = createHandler({submit: async () => ({code: 'ACCEPTED', topic: 'fr13:1:1:old', payload: value}),context: async () => ({code: 'OK', sharing: true, topic: 'fr13:1:1:new'}),publish: async () => {sends++;return true;}});
  assert((await (await f(request())).json()).code === 'INELIGIBLE' && sends === 0);
});
