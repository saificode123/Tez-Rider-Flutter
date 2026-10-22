import { AsyncLocalStorage } from 'node:async_hooks';
export type SecurityContext = { code: string; jwt: string; auth_id?: string; session_id?: string; profile_id?: number; role?: string; verification_status?: string; session_expires_at?: string; retry_after?: number };
const scope = new AsyncLocalStorage<SecurityContext>();
export const currentSecurityContext = () => scope.getStore();
const TEST = 'https://igeisilhtmglgnqvllrx.supabase.co';
export function failureClass(status: number): string | null {
  if (status === 401) return 'authentication';
  if (status === 403) return 'authorization';
  if (status >= 500) return 'server';
  return null; // Validation and business-rule rejections are handled, not unhandled errors.
}
export function mediaTtl(deadline: string, requested = 900, now = Date.now()): number {
  const seconds = Math.min(requested, 900, Math.floor((Date.parse(deadline) - now) / 1000));
  if (!Number.isFinite(seconds) || seconds < 1) throw Error('SESSION_EXPIRED');
  return seconds;
}
export function sessionMediaTtl(requested = 900): number {
  const deadline = scope.getStore()?.session_expires_at;
  if (!deadline) throw Error('SESSION_UNCONFIRMED');
  return mediaTtl(deadline, requested);
}
export function boundaryResponse(value: SecurityContext): Response {
  const status = value.code === 'RATE_LIMITED' ? 429 : value.code === 'FR28_ACCOUNT_BLOCKED' ? 403 : 401;
  return Response.json({code: value.code}, {status, headers: {
    'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*',
    ...(status === 429 ? {'Retry-After': String(value.retry_after ?? 60)} : {}),
  }});
}
export async function authorizeRequest(jwt: string, base: string, anon: string): Promise<SecurityContext> {
  const response = await fetch(base + '/rest/v1/rpc/final01_authorize_request', {
    method: 'POST', headers: {apikey: anon, Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json'}, body: '{}', signal: AbortSignal.timeout(10000),
  });
  if (response.status === 401) return {code: 'FR28_SESSION_REVOKED', jwt};
  if (response.status === 403) {
    const denied = await response.json();
    return {code: denied?.message === 'FR28_ACCOUNT_BLOCKED' ? 'FR28_ACCOUNT_BLOCKED' : 'FR28_SESSION_REVOKED', jwt};
  }
  if (!response.ok) throw Error('AUTHORIZATION_UNAVAILABLE');
  const value = await response.json();
  if (!value || !['OK', 'FR28_ACCOUNT_BLOCKED', 'FR28_SESSION_REVOKED', 'RATE_LIMITED'].includes(value.code)) throw Error('AUTHORIZATION_UNCONFIRMED');
  if (value.code === 'OK' && (typeof value.auth_id !== 'string' || typeof value.session_id !== 'string' || typeof value.session_expires_at !== 'string')) throw Error('AUTHORIZATION_UNCONFIRMED');
  return {...value, jwt};
}
async function serviceRpc(name: string, body: unknown): Promise<unknown> {
  const base = Deno.env.get('SUPABASE_URL') ?? '';
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (base !== TEST || !service) throw Error('TEST_SERVER_REQUIRED');
  const r = await fetch(base + '/rest/v1/rpc/' + name, {method: 'POST', headers: {apikey: service, Authorization: 'Bearer ' + service, 'Content-Type': 'application/json'}, body: JSON.stringify(body), signal: AbortSignal.timeout(5000)});
  if (!r.ok) throw Error('SERVER_OPERATION_UNCONFIRMED');
  return await r.json();
}
export async function recordFailure(endpoint: string, status: number, actor?: string): Promise<void> {
  const kind = failureClass(status); if (!kind) return;
  try {
    await serviceRpc('final01_record_failure', {p_actor: actor ?? null, p_endpoint: endpoint, p_kind: kind});
  } catch {
    // Safe provider-log fallback. No body, path, token, identifier or exception.
    console.error('SECURITY_AUDIT_UNCONFIRMED', endpoint, kind);
  }
}
export async function requestTicket(context: SecurityContext, method: string, path: string): Promise<string> {
  const value = await serviceRpc('final01_request_ticket', {p_actor: context.auth_id, p_session: context.session_id, p_method: method, p_path: path});
  if (typeof value !== 'string') throw Error('TICKET_UNCONFIRMED');
  return value;
}
// User-context backend requests retain the user's JWT/RLS. Service requests stay
// server-only. No recursive proxy call or client-readable capability is needed.
export async function applicationFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const request = new Request(input, init);
  const base = Deno.env.get('SUPABASE_URL') ?? '';
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const jwt = request.headers.get('Authorization')?.match(/^Bearer (\S+)$/)?.[1];
  if (base === TEST && request.url.startsWith(base + '/rest/v1/') && jwt && jwt !== service && jwt !== anon) {
    const context = scope.getStore()?.jwt === jwt ? scope.getStore()! : await authorizeRequest(jwt, base, anon);
    if (context.code !== 'OK') return boundaryResponse(context);
    const path = new URL(request.url).pathname.slice('/rest/v1'.length);
    request.headers.set('x-final01-proof', await requestTicket(context, request.method, path));
    const response = await fetch(request);
    await recordFailure('rest', response.status, context.auth_id);
    return response;
  }
  return fetch(request);
}
export function securityHandler(endpoint: string, handler: Deno.ServeHandler): Deno.ServeHandler {
  return async (req, info) => {
    let context: SecurityContext | undefined;
    try {
      const base = Deno.env.get('SUPABASE_URL') ?? '';
      const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
      const jwt = req.headers.get('Authorization')?.match(/^Bearer (\S+)$/)?.[1];
      // Trusted workers preserve their own worker-secret/service authorization.
      const worker = ['fr32-email-worker', 'fr30-dispatch-push'].includes(endpoint);
      if (base === TEST && req.method === 'POST' && !worker && jwt !== service) {
        if (!jwt || jwt.length > 8192) {
          await recordFailure(endpoint, 401);
          return Response.json({code: 'AUTHENTICATION_REQUIRED'}, {status: 401, headers: {'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store'}});
        }
        context = await authorizeRequest(jwt, base, Deno.env.get('SUPABASE_ANON_KEY') ?? '');
        if (context.code !== 'OK') {
          const response = boundaryResponse(context); await recordFailure(endpoint, response.status, context.auth_id); return response;
        }
      } else if (base === TEST && req.method === 'POST' && worker && jwt && jwt !== service) {
        // An authenticated Admin dispatch still shares the request budget.
        // Custom worker secrets are validated by the existing worker handler.
        if (jwt.split('.').length === 3) {
          context = await authorizeRequest(jwt, base, Deno.env.get('SUPABASE_ANON_KEY') ?? '');
          if (context.code !== 'OK') return boundaryResponse(context);
        }
      }
      const response = context ? await scope.run(context, () => handler(req, info)) : await handler(req, info);
      await recordFailure(endpoint, response.status, context?.auth_id);
      return response;
    } catch {
      await recordFailure(endpoint, 500, context?.auth_id);
      return Response.json({code: 'UNAVAILABLE'}, {status: 500, headers: {'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store'}});
    }
  };
}
export function serveSecurity(endpoint: string, optionsOrHandler: (Deno.ServeOptions & Deno.ServeTcpOptions) | Deno.ServeHandler, maybeHandler?: Deno.ServeHandler) {
  const handler = typeof optionsOrHandler === 'function' ? optionsOrHandler : maybeHandler!;
  const wrapped = securityHandler(endpoint, handler);
  return typeof optionsOrHandler === 'function' ? Deno.serve(wrapped) : Deno.serve(optionsOrHandler, wrapped);
}
