import {publishToLiveSessions} from './publication.ts';
function assert(value: unknown) { if (!value) throw Error('Publication assertion failed'); }
const base = 'https://igeisilhtmglgnqvllrx.supabase.co';
Deno.test('fresh recipients only: trusted publication never sends the old shared topic', async () => {
  const calls: {path: string; body: Record<string, unknown>}[] = [];
  const fetcher: typeof fetch = async (url, init) => {
    calls.push({path: String(url), body: JSON.parse(String(init?.body))});
    return Response.json(calls.length === 1 ? ['fr13:delivery:live-session'] : {});
  };
  assert(await publishToLiveSessions(fetcher, base, 'unit-service', 'fr13:delivery:sender', {latitude: 1}));
  const messages = calls[1].body.messages as Record<string, unknown>[];
  assert(messages.length === 1 && messages[0].topic === 'fr13:delivery:live-session' && messages[0].private === true);
  assert(calls[0].body.p_sender_topic === 'fr13:delivery:sender');
});
Deno.test('revoked or empty destination list sends nothing and cannot claim publication', async () => {
  let calls = 0;
  const fetcher: typeof fetch = async () => { calls++; return Response.json([]); };
  assert(!await publishToLiveSessions(fetcher, base, 'unit-service', 'fr13:sender', {}));
  assert(calls === 1);
});
Deno.test('recipient authorization failure does not fall back to shared broadcast', async () => {
  let calls = 0;
  const fetcher: typeof fetch = async () => { calls++; return new Response('', {status: 403}); };
  assert(!await publishToLiveSessions(fetcher, base, 'unit-service', 'fr13:sender', {})); assert(calls === 1);
});
Deno.test('malformed recipients cannot create arbitrary public channels', async () => {
  let calls = 0;
  const fetcher: typeof fetch = async () => { calls++; return Response.json(['other-channel']); };
  assert(!await publishToLiveSessions(fetcher, base, 'unit-service', 'fr13:sender', {})); assert(calls === 1);
});
Deno.test('bounded batches preserve every live destination and fail on unconfirmed delivery', async () => {
  let calls = 0; const sizes: number[] = [];
  const fetcher: typeof fetch = async (_, init) => {
    calls++;
    if (calls === 1) return Response.json(Array.from({length: 21}, (_, i) => 'fr13:session:' + i));
    sizes.push(JSON.parse(String(init?.body)).messages.length);
    return new Response('', {status: calls === 4 ? 503 : 200});
  };
  assert(!await publishToLiveSessions(fetcher, base, 'unit-service', 'fr13:sender', {}));
  assert(sizes.join(',') === '10,10,1');
});
