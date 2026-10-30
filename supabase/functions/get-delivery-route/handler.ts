export type Data = Record<string, any>;
export interface Dependencies {
  authenticate(jwt: string): Promise<boolean>;
  accountBoundary?(req: Request): Promise<Response | null>;
  /** Only from this request's verified security scope, never HTTP input/cache. */
  initialActor?(jwt: string): number | null;
  context(jwt: string, order: number): Promise<Data>;
  prepare(order: number, actor: number, configured: boolean): Promise<Data>;
  finish(order: number, actor: number, lease: string, route: Data | null): Promise<Data>;
  pickupContext?(jwt: string, order: number): Promise<Data>;
  pickupPrepare?(order: number, actor: number, configured: boolean): Promise<Data>;
  pickupFinish?(order: number, actor: number, lease: string, route: Data | null): Promise<Data>;
  provider(origin: number[], destination: number[], scope: {orderId: number; actor: number; pickup: boolean}): Promise<unknown>;
  configured: boolean;
  now?: () => number;
}
const headers = {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Cache-Control': 'no-store'};
export function coordinate(v: unknown): v is number[] {
  return Array.isArray(v) && v.length === 2 && v.every(n => typeof n === 'number' && Number.isFinite(n)) && Math.abs(v[0]) <= 180 && Math.abs(v[1]) <= 90;
}
export function distance(a: number[], b: number[]): number {
  const rad = Math.PI / 180, lat = (b[1] - a[1]) * rad, lng = (b[0] - a[0]) * rad;
  const h = Math.sin(lat / 2) ** 2 + Math.cos(a[1] * rad) * Math.cos(b[1] * rad) * Math.sin(lng / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}
export function parseProvider(raw: unknown, origin: number[], destination: number[]): Data {
  const data = raw as Data, feature = data?.features?.[0], geometry = feature?.geometry;
  const summary = {distance: feature?.properties?.distance, duration: feature?.properties?.time};
  // Geoapify returns a MultiLineString, one member per leg. Only a single
  // two-waypoint leg is requested; no bridging disconnected geometry.
  const points = geometry?.type === 'MultiLineString' && geometry.coordinates?.length === 1 ? geometry.coordinates[0] : geometry?.type === 'LineString' ? geometry.coordinates : null;
  if (data?.type !== 'FeatureCollection' || !Array.isArray(points) || points.length < 2 || points.length > 20000 ||
    !points.every(coordinate) || ![summary.distance, summary.duration].every(v => typeof v === 'number' && Number.isFinite(v) && v >= 0) ||
    summary.distance > 1000000 || summary.duration > 86400 || (summary.distance > 50 && summary.duration <= 0) ||
    distance(points[0], origin) > 1000 || distance(points[points.length - 1], destination) > 1000 ||
    summary.distance + 1000 < distance(origin, destination)) throw Error('INVALID_PROVIDER');
  return {geometry: {type: 'LineString', coordinates: points}, distanceMeters: summary.distance, durationSeconds: summary.duration};
}
export function fallback(ctx: Data, now: number): Data | null {
  if (!coordinate(ctx.origin) || !coordinate(ctx.destination) || !Number.isFinite(ctx.speedKmh) || ctx.speedKmh < 5 || ctx.speedKmh > 50) return null;
  const meters = distance(ctx.origin, ctx.destination);
  if (meters > 200000) return null;
  const seconds = meters / (ctx.speedKmh / 3.6);
  return {orderId: ctx.orderId, geometry: null, distanceMeters: meters, durationSeconds: seconds,
    estimatedArrivalAt: new Date(now + seconds * 1000).toISOString(), computedAt: new Date(now).toISOString(),
    expiresAt: new Date(now + 60000).toISOString(), source: 'straight_line', isApproximate: true, isStale: false,
    distanceKind: 'straight_line', limitation: 'Approximate straight-line estimate at an assumed average speed; roads, traffic and stops are not included.',
    deviationMeters: ctx.deviationMeters, minimumSeconds: ctx.minimumSeconds};
}
export function createHandler(deps: Dependencies) {
  return async (req: Request): Promise<Response> => {
    const started = performance.now();
    const timings: string[] = [];
    async function timed<T>(name: string, work: () => Promise<T>): Promise<T> {
      const at = performance.now();
      try { return await work(); }
      finally { timings.push(`${name};dur=${Math.max(0, performance.now() - at).toFixed(2)}`); }
    }
    // Authorized success responses expose stage durations only. No locations,
    // identities, tokens, provider URLs or raw errors enter diagnostic headers.
    // Handler timing excludes the outer security wrapper/network/cold start.
    const reply = (data: Data, status = 200) => Response.json(data, {status, headers: status === 200 ? {
      ...headers, 'Server-Timing': [...timings, `handler;dur=${Math.max(0, performance.now() - started).toFixed(2)}`].join(', '),
    } : headers});
    if (req.method === 'OPTIONS') return new Response('ok', {headers});
    if (req.method !== 'POST') return await deps.accountBoundary?.(req) ?? reply({code: 'METHOD_NOT_ALLOWED'}, 405);
    const auth = req.headers.get('authorization') ?? '';
    if (!/^Bearer \S+$/.test(auth)) return reply({code: 'UNAUTHORIZED'}, 401);
    try {
      const jwt = auth.slice(7);
      // Independent live checks overlap, but no order lookup or provider work
      // starts until both complete. No authentication result is cached.
      const [authenticated, denial] = await timed('auth', () => Promise.all([
        deps.authenticate(jwt), deps.accountBoundary?.(req) ?? Promise.resolve(null),
      ]));
      if (denial) return denial;
      if (!authenticated) return reply({code: 'UNAUTHORIZED'}, 401);
      const reader = req.body?.getReader();
      if (!reader) return reply({code: 'INVALID_REQUEST'}, 400);
      let text = '', size = 0;
      const decoder = new TextDecoder();
      try {
        while (true) {
          const {done, value} = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > 256) return reply({code: 'INVALID_REQUEST'}, 400);
          text += decoder.decode(value, {stream: true});
        }
        text += decoder.decode();
      } finally { await reader.cancel(); }
      let body: Data;
      try { body = JSON.parse(text); } catch { return reply({code: 'INVALID_REQUEST'}, 400); }
      if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).some(key => !['orderId', 'target'].includes(key)) ||
        ('target' in body && body.target !== 'pickup') || !Number.isSafeInteger(body.orderId) || body.orderId < 1) return reply({code: 'INVALID_REQUEST'}, 400);
      const pickup = body.target === 'pickup';
      if (pickup && (!deps.pickupContext || !deps.pickupPrepare || !deps.pickupFinish)) return reply({code: 'UNAVAILABLE', route: null}, 503);
      const context = pickup ? deps.pickupContext! : deps.context;
      const prepare = pickup ? deps.pickupPrepare! : deps.prepare;
      const finish = pickup ? deps.pickupFinish! : deps.finish;
      const actor = deps.initialActor?.(jwt);
      // prepare independently checks current actor/order eligibility in SQL.
      // A verified request identity avoids a redundant initial context RPC;
      // final live JWT/session/order revalidation is still mandatory below.
      const access = Number.isSafeInteger(actor) && actor! > 0
        ? {code: 'OK', actor}
        : await timed('context', () => context(jwt, body.orderId));
      if (access.code !== 'OK' || !Number.isSafeInteger(access.actor)) return reply({code: 'FORBIDDEN'}, 403);
      const ctx = await timed('prepare', () => prepare(body.orderId, access.actor, deps.configured));
      if (ctx.code === 'FORBIDDEN') return reply({code: 'FORBIDDEN'}, 403);
      if (ctx.code === 'RATE_LIMIT') return reply({code: 'RATE_LIMIT'}, 429);
      if (['DESTINATION_UNCONFIRMED', 'LOCATION_UNAVAILABLE'].includes(ctx.code)) return reply({code: ctx.code, route: null});
      if (!coordinate(ctx.origin) || !coordinate(ctx.destination) || ctx.orderId !== body.orderId) return reply({code: 'UNAVAILABLE', route: null});
      const revalidate = async (): Promise<Response | null> => {
        const live = await timed('revalidate', () => context(jwt, body.orderId));
        if (live.code !== 'OK') return reply({code: 'FORBIDDEN'}, 403);
        if (!pickup) {
          if (!coordinate(live.destination)) return reply({code: 'UNAVAILABLE', route: null});
          if (live.destination[0] !== ctx.destination[0] || live.destination[1] !== ctx.destination[1]) {
            return reply({code: 'DESTINATION_CHANGED', route: null});
          }
        }
        return null;
      };
      if (ctx.code === 'COMPUTE') {
        let result: Data | null = null;
        try { result = parseProvider(await timed('provider', () => deps.provider(ctx.origin, ctx.destination, {orderId: body.orderId, actor: access.actor, pickup})), ctx.origin, ctx.destination); } catch { /* No raw provider error, URL, location or credential is logged or returned. */ }
        const saved = await timed('finish', () => finish(body.orderId, access.actor, ctx.lease, result));
        if (result && saved.code === 'OK') {
          // Recheck the caller/session after the external request as well.
          const denied = await revalidate(); if (denied) return denied;
          return reply({code: 'OK', route: {...saved.route, target: pickup ? 'pickup' : 'delivery', cacheStatus: 'fresh'}});
        }
        if (!['OK', 'RELEASED'].includes(saved.code)) return reply({code: 'UNAVAILABLE', route: null});
      }
      const denied = await revalidate(); if (denied) return denied;
      const now = (deps.now ?? Date.now)();
      if (ctx.cache) {
        const stale = ctx.code !== 'CACHE' || Date.parse(ctx.cache.expiresAt) <= now;
        return reply({code: 'OK', route: {...ctx.cache, target: pickup ? 'pickup' : 'delivery', isStale: stale, isApproximate: stale, cacheStatus: stale ? 'stale' : 'cached'}, retryAfterSeconds: ctx.minimumSeconds});
      }
      // Pickup navigation never replaces a road route with a straight line.
      const approximate = pickup ? null : fallback(ctx, now);
      return reply({code: approximate ? 'APPROXIMATE' : 'UNAVAILABLE', route: approximate, retryAfterSeconds: ctx.minimumSeconds});
    } catch { return reply({code: 'UNAVAILABLE', route: null}, 503); }
  };
}
