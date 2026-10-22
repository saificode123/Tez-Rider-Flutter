import {serveSecurity, applicationFetch} from '../_shared/security-runtime.ts';
import {createHandler} from './handler.ts';
const base = Deno.env.get('SUPABASE_URL') ?? '';
if (base !== 'https://igeisilhtmglgnqvllrx.supabase.co') throw Error('Isolated TEST required');
const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const userHeaders = (jwt: string) => ({apikey: anon, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json'});
serveSecurity('shopping-assistant', createHandler({
  async authorize(jwt) {
    const r = await applicationFetch(base + '/rest/v1/rpc/fr28_account_status', {
      method: 'POST', headers: userHeaders(jwt), body: '{}', signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) return false;
    const value = await r.json();
    return value.code === 'OK' && ['customer', 'vendor', 'rider', 'admin'].includes(value.role) &&
      (value.role === 'customer' || value.verification_status === 'approved');
  },
  async claim(jwt) {
    const r = await applicationFetch(base + '/rest/v1/rpc/final1_claim_assistant', {
      method: 'POST', headers: userHeaders(jwt), body: '{}', signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) throw Error('UNAVAILABLE');
    return await r.json() === true;
  },
  async key() {
    const r = await applicationFetch(base + '/rest/v1/app_settings?setting_key=eq.groq_api_key&select=setting_value&limit=1', {
      headers: {apikey: service, Authorization: `Bearer ${service}`}, signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) throw Error('UNAVAILABLE');
    const rows = await r.json();
    return typeof rows[0]?.setting_value === 'string' && rows[0].setting_value.length > 0 ? rows[0].setting_value : null;
  },
  async recommend(key, prompt) {
    const r = await applicationFetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {'Content-Type': 'application/json', Authorization: `Bearer ${key}`},
      body: JSON.stringify({model: 'openai/gpt-oss-120b', max_completion_tokens: 1000, messages: [
        {role: 'system', content: "You are TezRider's shopping assistant. Recommend gifts, cakes, flowers and tailoring ideas. Be friendly, concise, and do not invent product availability, prices or completed actions."},
        {role: 'user', content: prompt},
      ]}), signal: AbortSignal.timeout(15000),
    });
    if (!r.ok) throw Error('UNAVAILABLE');
    const reader = r.body?.getReader(); if (!reader) throw Error('UNAVAILABLE');
    const chunks: Uint8Array[] = []; let size = 0;
    try {
      while (true) {
        const {done, value} = await reader.read(); if (done) break;
        size += value.length; if (size > 65536) throw Error('UNAVAILABLE'); chunks.push(value);
      }
    } finally { await reader.cancel(); }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const data = JSON.parse(new TextDecoder().decode(bytes));
    return data.choices?.[0]?.message?.content;
  },
}));
