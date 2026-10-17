import { createHandler, type Dependencies } from './handler.ts';
function ok(v: unknown): asserts v { if (!v) throw Error('Assertion failed'); }
const base = 'https://igeisilhtmglgnqvllrx.supabase.co';
function fixture() {
  const calls = { signed: 0, seconds: 0 };
  const d: Dependencies = {
    base, authenticate: (jwt) => Promise.resolve(jwt === 'owner-token'),
    authority: (_jwt, order) => order === 123 ? Promise.resolve({ code: 'READY', path: '10/123/00000000-0000-4000-8000-000000000001.pdf' }) : Promise.reject(Error('Forbidden')),
    sign: (path, seconds) => { calls.signed++; calls.seconds = seconds; return Promise.resolve(`${base}/storage/v1/object/sign/invoices/${path}?token=synthetic`); },
  };
  const req = (order = 123, jwt = 'owner-token') => new Request(`${base}/functions/v1/fr32-invoice-url`, { method: 'POST', headers: { Authorization: `Bearer ${jwt}` }, body: JSON.stringify({ order_id: order }) });
  return { calls, d, req };
}
Deno.test('invoice URL: verified owner signs for exactly900s server-side', async () => {
  const f = fixture(); const r = await createHandler(f.d)(f.req()); const data = await r.json();
  ok(r.status === 200 && data.expires_in === 900 && f.calls.seconds === 900);
});
Deno.test('invoice URL: another order forbidden before privileged signing', async () => {
  const f = fixture(); ok((await createHandler(f.d)(f.req(124))).status === 403); ok(!f.calls.signed);
});
Deno.test('invoice URL: unauthenticated rejected', async () => {
  const f = fixture(); ok((await createHandler(f.d)(f.req(123, 'wrong'))).status === 401); ok(!f.calls.signed);
});
Deno.test('invoice URL: not ready accurately reported', async () => {
  const f = fixture(); f.d.authority = () => Promise.resolve({ code: 'NOT_READY' });
  ok((await createHandler(f.d)(f.req())).status === 409); ok(!f.calls.signed);
});
Deno.test('invoice URL: signing response cannot redirect to external host', async () => {
  const f = fixture(); f.d.sign = () => Promise.resolve('https://example.test/collect');
  ok((await createHandler(f.d)(f.req())).status === 503);
});
