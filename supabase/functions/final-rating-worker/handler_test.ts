import { createRatingHandler, type RatingDependencies } from './handler.ts';
const key = 'f'.repeat(64);
function fixture(overrides: Partial<RatingDependencies> = {}) {
  const calls: string[] = [];
  const handler = createRatingHandler({
    workerKey: key,
    evaluate: async daily => { calls.push(daily ? 'daily' : 'retry'); return {code: 'OK', operations: []}; },
    synchronize: async () => { calls.push('sync'); return {code: 'OK'}; }, ...overrides,
  });
  return {calls, handler};
}
function request(body = '{"source":"daily"}', secret: string | null = key, method = 'POST') {
  return new Request('https://fixture.invalid/worker', {method, headers: secret ? {'x-final-rating-worker-key': secret} : {}, ...(method === 'POST' ? {body} : {})});
}
function assert(value: unknown) { if (!value) throw Error('Assertion failed'); }
Deno.test('worker rejects missing, incorrect and unset private keys without evaluating', async () => {
  for (const secret of [null, 'x'.repeat(64), key.slice(1)]) {
    const f = fixture(); assert((await f.handler(request(undefined, secret))).status === 403); assert(f.calls.length === 0);
  }
  const f = fixture({workerKey: ''}); assert((await f.handler(request())).status === 403);
});
Deno.test('worker rejects other methods', async () => {
  const f = fixture(); assert((await f.handler(request(undefined, key, 'GET'))).status === 405); assert(!f.calls.length);
});
Deno.test('worker rejects invalid, unrecognized and oversized bodies', async () => {
  for (const body of ['broken', '{}', 'null', '[]', '{"source":"other"}', '{"source":"daily","target":5}']) {
    const f = fixture(); assert((await f.handler(request(body))).status === 400); assert(!f.calls.length);
  }
  const f = fixture(); assert((await f.handler(request(' '.repeat(257)))).status === 413); assert(!f.calls.length);
});
Deno.test('daily and retry requests pass distinct population-evaluation flags', async () => {
  const f = fixture(); assert((await f.handler(request())).status === 200);
  assert((await f.handler(request('{"source":"retry"}'))).status === 200);
  assert(f.calls.join(',') === 'daily,retry');
});
Deno.test('worker does not claim successful synchronization on partial Auth failure', async () => {
  const f = fixture({evaluate: async () => ({code: 'OK', operations: [{operation_id: 'fixture', target_id: 1}]}), synchronize: async () => ({code: 'AUTH_SYNC_PENDING'})});
  const r = await f.handler(request()); assert(r.status === 202); const b = await r.json(); assert(b.synced === 0 && b.pending === 1);
});
Deno.test('worker counts only confirmed or already applied synchronization', async () => {
  const f = fixture({evaluate: async () => ({code: 'OK', operations: [{operation_id: 'fixture', target_id: 1}]}), synchronize: async () => ({code: 'ALREADY_APPLIED'})});
  const r = await f.handler(request()); assert(r.status === 200); const b = await r.json(); assert(b.synced === 1 && b.pending === 0);
});
Deno.test('missing policy Admin and server failures fail visibly', async () => {
  const f = fixture({evaluate: async () => ({code: 'POLICY_ADMIN_REQUIRED', operations: []})});
  assert((await f.handler(request())).status === 503);
  const failed = fixture({evaluate: async () => { throw Error('fixture'); }}); assert((await failed.handler(request())).status === 503);
});
Deno.test('oversized server batches fail closed before Auth work', async () => {
  const f = fixture({evaluate: async () => ({code: 'OK', operations: Array.from({length:21}, () => ({operation_id:'fixture',target_id:1}))})});
  assert((await f.handler(request())).status === 503); assert(!f.calls.length);
});
