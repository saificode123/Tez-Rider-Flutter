import { createHandler, type Job } from './handler.ts';
import { digest, sendBrevo } from '../_shared/fr32-brevo.ts';
import { invoicePdf } from '../_shared/fr32-invoice.ts';

const base = Deno.env.get('SUPABASE_URL') ?? '';
const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const headers = { apikey: service, Authorization: `Bearer ${service}` };
function target(): void {
  if (base !== 'https://igeisilhtmglgnqvllrx.supabase.co' || !service) throw Error('TEST_CONFIGURATION_REQUIRED');
}
async function rpc(name: string, body: unknown): Promise<unknown> {
  target();
  const r = await fetch(`${base}/rest/v1/rpc/${name}`, { method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(12000) });
  if (!r.ok) throw Error('DATABASE_UNCONFIRMED'); return await r.json();
}
function objectUrl(job: Job): string {
  const path = job.invoice_metadata!.path;
  if (!/^\d+\/\d+\/[0-9a-f-]{36}\.pdf$/.test(path)) throw Error('INVOICE_INVALID_PATH');
  return `${base}/storage/v1/object/invoices/${path}`;
}
async function download(url: string): Promise<Uint8Array | null> {
  const r = await fetch(url, { headers, signal: AbortSignal.timeout(12000) });
  if (r.status === 404) return null;
  // Storage commonly returns400 for a missing object. Recognize only its safe code.
  if (r.status === 400) {
    const error = await r.json(); if (error.statusCode === '404' || error.error === 'not_found') return null;
  }
  if (!r.ok || Number(r.headers.get('content-length') ?? 0) > 5242880) throw Error('STORAGE_UNCONFIRMED');
  const bytes = new Uint8Array(await r.arrayBuffer());
  if (bytes.length > 5242880 || new TextDecoder().decode(bytes.subarray(0, 5)) !== '%PDF-') throw Error('INVOICE_INVALID_PDF');
  return bytes;
}
async function pdf(job: Job): Promise<Uint8Array> {
  target(); const url = objectUrl(job), meta = job.invoice_metadata!;
  let bytes = await download(url);
  if (!bytes) {
    if (meta.status === 'ready') throw Error('INVOICE_READY_OBJECT_MISSING');
    bytes = await invoicePdf(job.invoice!);
    const r = await fetch(url, { method: 'POST', headers: { ...headers, 'Content-Type': 'application/pdf', 'x-upsert': 'false' }, body: new Uint8Array(bytes), signal: AbortSignal.timeout(12000) });
    if (!r.ok) {
      if (![400, 409].includes(r.status)) throw Error('STORAGE_UNCONFIRMED');
      // A crashed upload may already exist. Never overwrite invoice history.
      const existing = await download(url); if (!existing) throw Error('STORAGE_UNCONFIRMED');
      if (await digest(bytes) !== await digest(existing)) throw Error('INVOICE_IMMUTABLE_OBJECT_MISMATCH');
      bytes = existing;
    }
  }
  const sha = await digest(bytes);
  if (meta.status === 'ready' && (meta.sha256 !== sha || meta.bytes !== bytes.length)) throw Error('INVOICE_IMMUTABLE_OBJECT_MISMATCH');
  const result = await rpc('fr32_register_invoice_pdf', { p_job: job.id, p_lease: job.lease, p_sha256: sha, p_bytes: bytes.length }) as { code: string };
  if (result.code !== 'READY') throw Error('DATABASE_UNCONFIRMED');
  return bytes;
}
Deno.serve(async (req) => {
  try {
    return await createHandler({
      workerSecret: Deno.env.get('FR32_EMAIL_WORKER_KEY') ?? '', sender: Deno.env.get('BREVO_SENDER_EMAIL') ?? '', testRecipient: Deno.env.get('BREVO_TEST_RECIPIENT') ?? '',
      claim: async () => await rpc('fr32_claim_email', { p_limit: 2 }) as Job[], pdf,
      begin: async (j, fingerprint) => (await rpc('fr32_begin_email', { p_id: j.id, p_lease: j.lease, p_fingerprint: fingerprint }) as { code: string }).code,
      send: (wire) => sendBrevo(wire, Deno.env.get('BREVO_API_KEY') ?? ''),
      finish: async (j, result) => {
        const r = await rpc('fr32_finish_email', { p_id: j.id, p_lease: j.lease, p_outcome: result.outcome, p_provider: 'provider' in result ? result.provider ?? null : null, p_retry_seconds: 'retrySeconds' in result ? result.retrySeconds ?? null : null, p_error: result.error ?? null }) as { code: string };
        if (r.code !== 'RECORDED') throw Error('DATABASE_UNCONFIRMED');
      },
    })(req);
  } catch { return Response.json({ code: 'UNAVAILABLE' }, { status: 503, headers: { 'Cache-Control': 'no-store' } }); }
});
