export interface Dependencies {
  authenticate(jwt: string): Promise<boolean>;
  authority(jwt: string, order: number): Promise<{ code: string; path?: string }>;
  sign(path: string, seconds: number): Promise<string>;
  base: string;
}
const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info', 'Access-Control-Allow-Methods': 'POST,OPTIONS', 'Cache-Control': 'no-store' };
export function createHandler(d: Dependencies) {
  const reply = (code: string, status = 200, extra = {}) => Response.json({ code, ...extra }, { status, headers });
  return async (req: Request): Promise<Response> => {
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    if (req.method !== 'POST') return reply('METHOD_NOT_ALLOWED', 405);
    const jwt = req.headers.get('Authorization')?.match(/^Bearer (\S+)$/)?.[1];
    if (!jwt || jwt.length > 8192) return reply('AUTHENTICATION_REQUIRED', 401);
    try {
      if (!await d.authenticate(jwt)) return reply('AUTHENTICATION_REQUIRED', 401);
      if (Number(req.headers.get('Content-Length') ?? 0) > 100) return reply('INVALID_REQUEST', 400);
      const raw = await req.text(); if (raw.length > 100) return reply('INVALID_REQUEST', 400);
      let body; try { body = JSON.parse(raw); } catch { return reply('INVALID_REQUEST', 400); }
      if (!body || Object.keys(body).length !== 1 || !Number.isSafeInteger(body.order_id) || body.order_id < 1) return reply('INVALID_REQUEST', 400);
      const r = await d.authority(jwt, body.order_id);
      if (r.code !== 'READY') return reply('NOT_READY', 409);
      if (!r.path || !/^\d+\/\d+\/[0-9a-f-]{36}\.pdf$/.test(r.path)) return reply('UNAVAILABLE', 503);
      const signed = await d.sign(r.path, 900);
      const url = new URL(signed);
      if (url.origin !== d.base || !url.pathname.startsWith('/storage/v1/object/sign/invoices/')) return reply('UNAVAILABLE', 503);
      return reply('READY', 200, { url: signed, expires_in: 900 });
    } catch { return reply('INVOICE_ACCESS_UNCONFIRMED', 403); }
  };
}
