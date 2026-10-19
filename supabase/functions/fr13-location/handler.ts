export type Data = Record<string, unknown>;
export interface Dependencies {
  submit(jwt: string, value: Data): Promise<Data>;
  context(jwt: string, order: number): Promise<Data>;
  publish(topic: string, payload: Data): Promise<boolean>;
}
const headers = {
  'Content-Type': 'application/json', 'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info',
};
export function createHandler(deps: Dependencies) {
  return async (req: Request): Promise<Response> => {
    const reply = (code: string, status = 200) => new Response(JSON.stringify({code}), {status, headers});
    if (req.method === 'OPTIONS') return new Response('ok', {headers});
    if (req.method !== 'POST') return reply('METHOD_NOT_ALLOWED', 405);
    const auth = req.headers.get('Authorization') ?? '';
    if (!/^Bearer \S+$/.test(auth)) return reply('UNAUTHORIZED', 401);
    try {
      const text = await req.text();
      if (text.length > 2048) return reply('INVALID_LOCATION', 400);
      const value = JSON.parse(text);
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
      const accepted = await deps.submit(auth.slice(7), value);
      if (accepted.code !== 'ACCEPTED') return reply(typeof accepted.code === 'string' ? accepted.code : 'UNAVAILABLE');
      if (typeof accepted.topic !== 'string' || !accepted.topic.startsWith('fr13:') ||
        !accepted.payload || typeof accepted.payload !== 'object') return reply('UNAVAILABLE', 503);
      // Close the validation-to-publication window as far as the separate REST
      // service allows. A publication already in flight cannot be retracted.
      const current = await deps.context(auth.slice(7), value.order_id);
      if (current.code !== 'OK' || current.sharing !== true || current.topic !== accepted.topic) return reply('INELIGIBLE');
      if (!await deps.publish(accepted.topic, accepted.payload as Data)) return reply('PUBLISH_UNCONFIRMED', 503);
      return reply('PUBLISHED');
    } catch {
      return reply('UNAVAILABLE', 503);
    }
  };
}
