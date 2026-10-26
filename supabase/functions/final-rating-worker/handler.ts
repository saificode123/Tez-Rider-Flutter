import { matchesSecret } from '../fr30-dispatch-push/handler.ts';
export interface RatingOperation { operation_id: string; target_id: number }
export interface RatingDependencies {
  workerKey: string;
  evaluate(daily: boolean): Promise<{code: string; operations: RatingOperation[]}>;
  synchronize(operation: RatingOperation): Promise<{code: string}>;
}
export function createRatingHandler(deps: RatingDependencies) {
  const reply = (status: number, body: unknown) => Response.json(body, {status, headers: {'Cache-Control': 'no-store'}});
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'POST') return reply(405, {code: 'METHOD_NOT_ALLOWED'});
    if (!matchesSecret(req.headers.get('x-final-rating-worker-key'), deps.workerKey)) return reply(403, {code: 'FORBIDDEN'});
    try {
      // Bound the stream, rather than trusting Content-Length or buffering an
      // arbitrarily large authenticated request before checking its size.
      const reader = req.body?.getReader();
      if (!reader) return reply(400, {code: 'INVALID_INPUT'});
      const chunks: Uint8Array[] = []; let size = 0;
      try {
        while (true) {
          const {done, value} = await reader.read(); if (done) break;
          size += value.length;
          if (size > 256) { await reader.cancel(); return reply(413, {code: 'INVALID_INPUT'}); }
          chunks.push(value);
        }
      } finally { reader.releaseLock(); }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      let body: {source?: unknown};
      try { body = JSON.parse(new TextDecoder().decode(bytes)); } catch { return reply(400, {code: 'INVALID_INPUT'}); }
      if (!body || Array.isArray(body) || Object.keys(body).some(k => k !== 'source') || !['daily','retry'].includes(body.source as string)) {
        return reply(400, {code: 'INVALID_INPUT'});
      }
      const result = await deps.evaluate(body.source === 'daily');
      if (!['OK','BUSY','DISABLED'].includes(result.code)) return reply(503, {code: result.code});
      if (!Array.isArray(result.operations) || result.operations.length > 20) throw Error('Invalid worker batch');
      let synced = 0, pending = 0;
      for (const operation of result.operations) {
        const outcome = await deps.synchronize(operation);
        if (['OK','ALREADY_APPLIED'].includes(outcome.code)) synced++; else pending++;
      }
      return reply(pending ? 202 : 200, {code: result.code, synced, pending});
    } catch { return reply(503, {code: 'OPERATION_UNCONFIRMED'}); }
  };
}
