export type Data = Record<string, unknown>;
export interface Dependencies {
  submit(jwt: string, value: Data): Promise<Data>;
  /** Must revalidate sender consent/lifecycle and every live recipient before broadcast. */
  publishAuthorized(topic: string, payload: Data): Promise<boolean>;
}
const headers = {
  'Content-Type': 'application/json', 'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info',
};
export function createHandler(deps: Dependencies) {
  return async (req: Request): Promise<Response> => {
    const timings: string[] = [], started = performance.now();
    async function timed<T>(name: string, work: () => Promise<T>): Promise<T> {
      const at = performance.now();
      try { return await work(); }
      finally { timings.push(`${name};dur=${(performance.now() - at).toFixed(2)}`); }
    }
    const reply = (code: string, status = 200) => new Response(JSON.stringify({code}), {status, headers: code === 'PUBLISHED' ? {
      ...headers, 'Server-Timing': [...timings, `handler;dur=${(performance.now() - started).toFixed(2)}`].join(', '),
    } : headers});
    if (req.method === 'OPTIONS') return new Response('ok', {headers});
    if (req.method !== 'POST') return reply('METHOD_NOT_ALLOWED', 405);
    const auth = req.headers.get('Authorization') ?? '';
    if (!/^Bearer \S+$/.test(auth)) return reply('UNAUTHORIZED', 401);
    try {
      const reader = req.body?.getReader();
      if (!reader) return reply('INVALID_LOCATION', 400);
      let text = '', size = 0;
      const decoder = new TextDecoder('utf-8', {fatal: true});
      try {
        while (true) {
          const {done, value} = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > 2048) return reply('INVALID_LOCATION', 400);
          text += decoder.decode(value, {stream: true});
        }
        text += decoder.decode();
      } catch { return reply('INVALID_LOCATION', 400); }
      finally { await reader.cancel(); }
      let value;
      try { value = JSON.parse(text); } catch { return reply('INVALID_LOCATION', 400); }
      const fields = ['order_id', 'latitude', 'longitude', 'accuracy', 'device_at', 'request_id'];
      if (!value || Array.isArray(value) || typeof value !== 'object' ||
        Object.keys(value).length !== fields.length || fields.some(k => !(k in value)) ||
        !Number.isSafeInteger(value.order_id) || value.order_id <= 0 ||
        ![value.latitude, value.longitude, value.accuracy].every(v => typeof v === 'number' && Number.isFinite(v)) ||
        Math.abs(value.latitude) > 90 || Math.abs(value.longitude) > 180 || value.accuracy < 0 || value.accuracy > 100 ||
        typeof value.device_at !== 'string' || !Number.isFinite(Date.parse(value.device_at)) ||
        typeof value.request_id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value.request_id)) {
        return reply('INVALID_LOCATION', 400);
      }
      const accepted = await timed('submit', () => deps.submit(auth.slice(7), value));
      if (accepted.code !== 'ACCEPTED') return reply(typeof accepted.code === 'string' ? accepted.code : 'UNAVAILABLE');
      if (typeof accepted.topic !== 'string' || !accepted.topic.startsWith('fr13:') ||
        !accepted.payload || typeof accepted.payload !== 'object') return reply('UNAVAILABLE', 503);
      const topic = accepted.topic, payload = accepted.payload as Data;
      // The live-recipient query immediately before broadcast already checks
      // sender session, current consent/topic, lifecycle and recipient access.
      // Do not repeat tracking_context (and its request-ticket round trip) here.
      // An already in-flight publication cannot be retracted by either path.
      if (!await timed('publication', () => deps.publishAuthorized(topic, payload))) return reply('PUBLISH_UNCONFIRMED', 503);
      return reply('PUBLISHED');
    } catch {
      return reply('UNAVAILABLE', 503);
    }
  };
}
