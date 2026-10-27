type Data = Record<string, unknown>;
export type Turn = {role: 'user' | 'assistant'; content: string};
export interface Dependencies {
  authorize(jwt: string): Promise<boolean>;
  claim(jwt: string): Promise<boolean>;
  key(): Promise<string | null>;
  context?(jwt: string, prompt: string, history: Turn[]): Promise<unknown>;
  recommend(key: string, prompt: string, history: Turn[], context: unknown): Promise<string>;
}
const headers = {
  'Content-Type': 'application/json', 'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info',
};
export function createHandler(deps: Dependencies) {
  return async (req: Request): Promise<Response> => {
    const reply = (body: Data, status: number) => new Response(JSON.stringify(body), {
      status, headers: {...headers, ...(status === 429 ? {'Retry-After': '60'} : {})},
    });
    if (req.method === 'OPTIONS') return new Response('ok', {headers});
    if (req.method !== 'POST') return reply({code: 'METHOD_NOT_ALLOWED'}, 405);
    const auth = req.headers.get('Authorization') ?? '';
    if (!/^Bearer \S+$/.test(auth)) return reply({code: 'UNAUTHORIZED'}, 401);
    try {
      const reader = req.body?.getReader();
      if (!reader) return reply({code: 'INVALID_REQUEST'}, 400);
      const chunks: Uint8Array[] = []; let size = 0;
      try {
        while (true) {
          const {done, value} = await reader.read(); if (done) break;
          size += value.length;
          if (size > 24000) return reply({code: 'INVALID_REQUEST'}, 413);
          chunks.push(value);
        }
      } finally { await reader.cancel(); }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      let value: Data;
      try { value = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes)); }
      catch { return reply({code: 'INVALID_REQUEST'}, 400); }
      if (!value || Array.isArray(value) || typeof value !== 'object' ||
          Object.keys(value).some(k => !['prompt', 'history'].includes(k)) || typeof value.prompt !== 'string' ||
          [...value.prompt.trim()].length < 1 || [...value.prompt.trim()].length > 2000 ||
          /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value.prompt)) {
        return reply({code: 'INVALID_REQUEST'}, 400);
      }
      const history = value.history ?? [];
      if (!Array.isArray(history) || history.length > 6 || history.some((t) =>
        !t || typeof t !== 'object' || Object.keys(t).length !== 2 ||
        !['user', 'assistant'].includes(t.role) || typeof t.content !== 'string' ||
        !t.content.trim() || [...t.content].length > 1000 ||
        /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(t.content))) {
        return reply({code: 'INVALID_REQUEST'}, 400);
      }
      const jwt = auth.slice(7);
      if (!await deps.authorize(jwt)) return reply({code: 'FORBIDDEN'}, 403);
      if (!await deps.claim(jwt)) return reply({code: 'RATE_LIMITED'}, 429);
      const key = await deps.key();
      if (!key) return reply({code: 'UNAVAILABLE'}, 503);
      if (!await deps.authorize(jwt)) return reply({code: 'FORBIDDEN'}, 403);
      const context = deps.context ? await deps.context(jwt, value.prompt.trim(), history) : null;
      const text = await deps.recommend(key, value.prompt.trim(), history, context);
      if (typeof text !== 'string' || !text.trim() || text.length > 16000 || text.includes(key)) {
        return reply({code: 'UNAVAILABLE'}, 503);
      }
      if (!await deps.authorize(jwt)) return reply({code: 'FORBIDDEN'}, 403);
      return reply({code: 'OK', text}, 200);
    } catch {
      return reply({code: 'UNAVAILABLE'}, 503);
    }
  };
}
