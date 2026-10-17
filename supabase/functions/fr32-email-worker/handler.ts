import { digest, type Outcome } from '../_shared/fr32-brevo.ts';
import { type EmailType, template } from '../_shared/fr32-templates.ts';
import type { InvoiceSnapshot } from '../_shared/fr32-invoice.ts';

export interface Job {
  id: string; lease: string; type: EmailType; entity_id: string; recipient: string | null;
  provider_key: string; test_approved: boolean; invoice?: InvoiceSnapshot; invoice_metadata?: { id: string; path: string; status: string; sha256: string | null; bytes: number | null };
}
export interface Dependencies {
  workerSecret: string; sender: string; testRecipient: string;
  claim(): Promise<Job[]>;
  pdf(job: Job): Promise<Uint8Array>;
  begin(job: Job, fingerprint: string): Promise<string>;
  send(body: string): Promise<Outcome>;
  finish(job: Job, outcome: Outcome | { outcome: 'prepare_retry' | 'skipped_test'; error: string }): Promise<void>;
}
function reply(code: string, status = 200, extra = {}): Response {
  return Response.json({ code, ...extra }, { status, headers: { 'Cache-Control': 'no-store' } });
}
const email = (s: string): boolean => s.length <= 254 && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s);
async function equal(a: string, b: string): Promise<boolean> {
  const x = await digest(a), y = await digest(b);
  let diff = 0; for (let i = 0; i < x.length; i++) diff |= x.charCodeAt(i) ^ y.charCodeAt(i);
  return diff === 0;
}
function base64(bytes: Uint8Array): string {
  let binary = ''; for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(binary);
}
export function createHandler(d: Dependencies): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method !== 'POST') return reply('METHOD_NOT_ALLOWED', 405);
    if (d.workerSecret.length < 32) return reply('WORKER_NOT_CONFIGURED', 503);
    const key = req.headers.get('x-fr32-worker-key') ?? '';
    if (key.length > 256 || !await equal(key, d.workerSecret)) return reply('UNAUTHORIZED', 401);
    if (Number(req.headers.get('content-length') ?? 0) > 64) return reply('INVALID_REQUEST', 400);
    if (!email(d.sender) || !email(d.testRecipient)) return reply('EMAIL_NOT_CONFIGURED', 503);
    let jobs: Job[];
    try { jobs = await d.claim(); } catch { return reply('CLAIM_UNCONFIRMED', 503); }
    if (!Array.isArray(jobs) || jobs.length > 2) return reply('INVALID_BATCH', 503);
    let processed = 0, unconfirmed = 0;
    await Promise.all(jobs.map(async (job) => {
      let began = false;
      try {
        const invoice = job.type === 'paid_invoice';
        if (invoice && (!job.invoice || !job.invoice_metadata || job.invoice_metadata.status === 'failed')) {
          await d.finish(job, { outcome: 'failed', error: 'INVOICE_SOURCE_REVIEW_REQUIRED' }); processed++; return;
        }
        const copy = template(job.type, invoice ? String(job.invoice!.order_id) : job.entity_id);
        const attachment = invoice ? await d.pdf(job) : null;
        if (attachment && (attachment.length > 5242880 || new TextDecoder().decode(attachment.subarray(0, 5)) !== '%PDF-')) throw Error('INVOICE_INVALID_PDF');
        // Invoice access must work even when TEST email delivery is not approved.
        if (!job.test_approved) {
          await d.finish(job, { outcome: 'skipped_test', error: 'TEST_DELIVERY_NOT_APPROVED' }); processed++; return;
        }
        if (!job.recipient || !email(job.recipient)) {
          await d.finish(job, { outcome: 'failed', error: 'VERIFIED_RECIPIENT_UNAVAILABLE' }); processed++; return;
        }
        // Original identity stays in PostgreSQL; only the approved TEST inbox leaves the server.
        const wire = JSON.stringify({
          sender: { name: 'TezRider TEST', email: d.sender }, to: [{ email: d.testRecipient }],
          subject: copy.subject, textContent: copy.text, htmlContent: copy.html,
          headers: { idempotencyKey: job.provider_key },
          ...(attachment ? { attachment: [{ name: `${job.invoice!.invoice_number}.pdf`, content: base64(attachment) }] } : {}),
        });
        const code = await d.begin(job, await digest(wire));
        if (code !== 'SEND') { processed++; return; }
        began = true;
        await d.finish(job, await d.send(wire)); processed++;
      } catch (error) {
        // A finalization failure after HTTP cannot safely change to an ordinary retry.
        if (began) { unconfirmed++; return; }
        const safe = error instanceof Error && /^INVOICE_[A-Z_]{1,65}$/.test(error.message) ? error.message : 'PREPARATION_UNCONFIRMED';
        try {
          await d.finish(job, { outcome: safe === 'PREPARATION_UNCONFIRMED' ? 'prepare_retry' : 'failed', error: safe }); processed++;
        } catch { unconfirmed++; }
      }
    }));
    return reply(unconfirmed ? 'FINALIZATION_UNCONFIRMED' : 'PROCESSED', unconfirmed ? 503 : 200, { processed, unconfirmed });
  };
}
