import {createHandler, type Dependencies} from './handler.ts';
function ok(v: unknown): asserts v { if (!v) throw Error('Assertion failed'); }
function setup(overrides: Partial<Dependencies> = {}) {
  const calls = {keys: 0, providers: 0, claims: 0};
  const deps: Dependencies = {
    authorize: async () => true,
    claim: async () => { calls.claims++; return true; },
    key: async () => { calls.keys++; return 'synthetic-private-provider-credential'; },
    recommend: async () => { calls.providers++; return 'A confirmed server reply'; },
    ...overrides,
  };
  return {run: createHandler(deps), calls};
}
const request = (body: unknown, authorization = 'Bearer synthetic-user-session') => new Request('https://example.test', {
  method: 'POST', headers: {Authorization: authorization}, body: JSON.stringify(body),
});
for (const body of [null, [], {}, {prompt: 1}, {prompt: ''}, {prompt: ' '.repeat(20)},
  {prompt: 'x'.repeat(2001)}, {prompt: 'question', actor: 'admin'}, {prompt: '\u0000'}]) {
  Deno.test('invalid prompt rejected before credentials: ' + JSON.stringify(body).slice(0, 35), async () => {
    const {run, calls} = setup(); const response = await run(request(body));
    ok(response.status === 400); ok(calls.keys === 0 && calls.providers === 0);
  });
}
Deno.test('anonymous never reaches credentials', async () => {
  const {run, calls} = setup(); const r = await run(request({prompt: 'Question'}, ''));
  ok(r.status === 401 && calls.keys === 0 && calls.providers === 0);
});
Deno.test('invalid blocked pending or revoked identity never reaches credentials', async () => {
  const {run, calls} = setup({authorize: async () => false});
  ok((await run(request({prompt: 'Question'}))).status === 403);
  ok(calls.keys === 0 && calls.claims === 0 && calls.providers === 0);
});
Deno.test('chunked body bounded without Content-Length', async () => {
  const {run, calls} = setup();
  const r = await run(new Request('https://example.test', {
    method: 'POST', headers: {Authorization: 'Bearer synthetic'}, body: 'x'.repeat(10001),
  }));
  ok(r.status === 413 && calls.keys === 0);
});
Deno.test('malformed JSON is a private400', async () => {
  const {run} = setup(); const r = await run(new Request('https://example.test', {
    method: 'POST', headers: {Authorization: 'Bearer synthetic'}, body: '{invalid',
  })); ok(r.status === 400);
});
Deno.test('rate denial never calls provider/key', async () => {
  const {run, calls} = setup({claim: async () => false});
  ok((await run(request({prompt: 'Question'}))).status === 429);
  ok(calls.keys === 0 && calls.providers === 0);
});
Deno.test('unconfigured server returns503 without simulated content', async () => {
  const {run, calls} = setup({key: async () => null});
  const r = await run(request({prompt: 'Question'}));
  ok(r.status === 503 && calls.providers === 0);
  ok((await r.json()).code === 'UNAVAILABLE');
});
Deno.test('blocked between key load and provider call denied', async () => {
  let count = 0; const {run, calls} = setup({authorize: async () => ++count === 1});
  ok((await run(request({prompt: 'Question'}))).status === 403);
  ok(calls.keys === 1 && calls.providers === 0);
});
Deno.test('provider failure response contains no credentials or provider body', async () => {
  const {run} = setup({recommend: async () => { throw Error('synthetic-private-provider-credential'); }});
  const r = await run(request({prompt: 'Question'}));
  ok(r.status === 503 && await r.text() === '{"code":"UNAVAILABLE"}');
});
Deno.test('provider echo of key rejected rather than disclosed', async () => {
  const {run} = setup({recommend: async (key) => key});
  const r = await run(request({prompt: 'Question'}));
  ok(r.status === 503 && await r.text() === '{"code":"UNAVAILABLE"}');
});
Deno.test('valid Unicode boundary authenticated reply, no credential field', async () => {
  const {run, calls} = setup(); const r = await run(request({prompt: '🎁'.repeat(2000)}));
  const value = await r.json();
  ok(r.status === 200 && value.code === 'OK' && value.text === 'A confirmed server reply');
  ok(Object.keys(value).length === 2 && calls.keys === 1 && calls.providers === 1);
});
Deno.test('GET and OPTIONS do not access credentials', async () => {
  const {run, calls} = setup();
  ok((await run(new Request('https://example.test'))).status === 405);
  ok((await run(new Request('https://example.test', {method: 'OPTIONS'}))).status === 200);
  ok(calls.keys === 0);
});
