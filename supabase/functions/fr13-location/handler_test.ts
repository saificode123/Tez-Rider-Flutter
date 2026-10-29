import {createHandler, type Data, type Dependencies} from './handler.ts';
import {publishToLiveSessions} from './publication.ts';
const value = {order_id: 1, latitude: 33.7, longitude: 73.05, accuracy: 5, device_at: new Date().toISOString(), request_id: '00000000-0000-4000-8000-000000000001'};
function assert(ok: boolean) {if (!ok) throw Error('FR13 handler assertion failed');}
function fixture(submitCode = 'ACCEPTED', contextCode = 'OK', published = true) {
  let sends = 0, calls = 0;
  const deps: Dependencies = {
    submit: async () => {calls++; return {code: submitCode, topic: 'fr13:1:1:session', payload: value};},
    publishAuthorized: async () => {if(contextCode !== 'OK') return false;sends++;return published;},
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
  const f = fixture('ACCEPTED', 'INELIGIBLE');assert((await (await f.run(request())).json()).code === 'PUBLISH_UNCONFIRMED');assert(f.sends() === 0);
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
Deno.test('oversized streaming body is cancelled before buffering the remainder', async () => {
  let pulled = 0, cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) { pulled++; controller.enqueue(new Uint8Array(1024)); },
    cancel() { cancelled = true; },
  });
  const f = fixture();
  const response = await f.run(new Request('http://localhost/fr13-location', {
    method: 'POST', headers: {Authorization: 'Bearer synthetic-local-test'}, body: stream,
  }));
  assert(response.status === 400 && (await response.json()).code === 'INVALID_LOCATION');
  assert(f.calls() === 0 && cancelled && pulled <= 4);
});
Deno.test('malformed JSON and invalid UTF-8 are validation errors, not server failures', async () => {
  for (const body of ['{broken', new Uint8Array([0xff, 0xfe])]) {
    const f = fixture();
    const response = await f.run(new Request('http://localhost/fr13-location', {
      method: 'POST', headers: {Authorization: 'Bearer synthetic-local-test'}, body,
    }));
    assert(response.status === 400 && (await response.json()).code === 'INVALID_LOCATION');
    assert(f.calls() === 0);
  }
});
Deno.test('changed channel after validation cannot publish stale session', async () => {
  let broadcasts = 0, lookups = 0;
  const fetcher: typeof fetch = async (input) => {
    if (String(input).endsWith('/rpc/fr13_live_topics')) {
      lookups++;
      // The database returns no destinations after Stop, changed consent topic,
      // revoked sender session or ended assignment. Never cache this result.
      return Response.json([]);
    }
    broadcasts++;
    return Response.json({});
  };
  const f = createHandler({
    submit: async () => ({code: 'ACCEPTED', topic: 'fr13:1:1:old', payload: value}),
    publishAuthorized: (topic, payload) => publishToLiveSessions(fetcher, 'https://test.invalid', 'synthetic-service', topic, payload),
  });
  const response = await f(request());
  assert(response.status === 503 && (await response.json()).code === 'PUBLISH_UNCONFIRMED');
  assert(lookups === 1 && broadcasts === 0);
});
Deno.test('publication timing exposes stages without location or credentials', async () => {
  const response = await fixture().run(request());
  const timing = response.headers.get('server-timing') ?? '';
  assert(/^submit;dur=[\d.]+, publication;dur=[\d.]+, handler;dur=[\d.]+$/.test(timing));
  assert((await response.text()) === '{"code":"PUBLISHED"}');
});
