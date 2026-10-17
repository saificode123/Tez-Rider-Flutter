import { createHandler, type Dependencies, type Job } from './handler.ts';
import { digest, retryAfter, sendBrevo } from '../_shared/fr32-brevo.ts';
import { emailTypes, escapeHtml, template } from '../_shared/fr32-templates.ts';
import { invoicePdf, type InvoiceSnapshot, money, validateInvoice } from '../_shared/fr32-invoice.ts';
import { PDFDocument } from 'npm:pdf-lib@1.17.1';

function ok(v: unknown, message = 'Assertion failed'): asserts v { if (!v) throw Error(message); }
const secret = 'synthetic-worker-key-'.repeat(3);
export const sample: InvoiceSnapshot = {
  invoice_id: '00000000-0000-4000-8000-000000000001', invoice_number: 'TR-000000000123', order_id: 123,
  customer_id: 10, customer: 'FR32 Synthetic Customer', currency: 'PKR', paid_at: '2026-10-16T12:00:00.000Z',
  payment_reference: 'SYNTHETIC-CAPTURE-123', payment_status: 'PAID',
  subtotal_cents: '24000', delivery_cents: '20000', total_cents: '44000',
  items: [
    { product: 'Rice box', vendor: 'Vendor A', vendor_id: 20, quantity: 2, unit_cents: '8000', line_cents: '16000' },
    { product: 'Water', vendor: 'Vendor B', vendor_id: 21, quantity: 1, unit_cents: '8000', line_cents: '8000' },
  ],
};
const job: Job = { id: crypto.randomUUID(), lease: crypto.randomUUID(), type: 'order_confirmation', entity_id: '123', recipient: 'original@example.test', provider_key: crypto.randomUUID(), test_approved: true };
function fixture(jobs: Job[] = [structuredClone(job)]) {
  const calls = { claims: 0, begins: 0, sends: [] as string[], finishes: [] as unknown[], pdfs: 0 };
  const d: Dependencies = {
    workerSecret: secret, sender: 'sender@example.test', testRecipient: 'approved@example.test',
    claim: () => { calls.claims++; return Promise.resolve(jobs); },
    pdf: () => { calls.pdfs++; return Promise.resolve(new TextEncoder().encode('%PDF-fixture')); },
    begin: () => { calls.begins++; return Promise.resolve('SEND'); },
    send: (wire) => { calls.sends.push(wire); return Promise.resolve({ outcome: 'sent', provider: 'synthetic-provider-id' }); },
    finish: (_j, result) => { calls.finishes.push(result); return Promise.resolve(); },
  };
  const request = (key = secret) => new Request('https://example.test/worker', { method: 'POST', headers: { 'x-fr32-worker-key': key }, body: '{}' });
  return { d, calls, request };
}
Deno.test('worker: success redirects only approved TEST inbox', async () => {
  const f = fixture(); const r = await createHandler(f.d)(f.request());
  ok(r.status === 200 && f.calls.sends.length === 1);
  const wire = JSON.parse(f.calls.sends[0]);
  ok(wire.to[0].email === 'approved@example.test' && !f.calls.sends[0].includes('original@example.test'));
  ok(wire.headers.idempotencyKey === job.provider_key && wire.textContent && wire.htmlContent);
});
for (const value of ['', 'wrong-key']) Deno.test(`worker: unauthorized key length${value.length} rejected before claim`, async () => {
  const f = fixture(); ok((await createHandler(f.d)(f.request(value))).status === 401); ok(f.calls.claims === 0);
});
Deno.test('worker: unconfigured secret fails closed', async () => {
  const f = fixture(); f.d.workerSecret = ''; ok((await createHandler(f.d)(f.request())).status === 503); ok(f.calls.claims === 0);
});
Deno.test('worker: skipped TEST batch consumes no send/quota', async () => {
  const f = fixture([]); ok((await createHandler(f.d)(f.request())).status === 200); ok(!f.calls.begins && !f.calls.sends.length);
});
Deno.test('worker: no verified recipient fails before quota', async () => {
  const f = fixture([{ ...job, recipient: null }]); await createHandler(f.d)(f.request());
  ok(!f.calls.begins && !f.calls.sends.length); ok(JSON.stringify(f.calls.finishes).includes('VERIFIED_RECIPIENT_UNAVAILABLE'));
});
Deno.test('worker: shared quota exhaustion prevents HTTP send', async () => {
  const f = fixture(); f.d.begin = () => Promise.resolve('QUOTA_EXCEEDED');
  await createHandler(f.d)(f.request()); ok(!f.calls.sends.length);
});
Deno.test('worker: uncertain finalize does not schedule blind retry', async () => {
  const f = fixture(); f.d.finish = () => Promise.reject(Error('SECRET api-key original@example.test'));
  const r = await createHandler(f.d)(f.request()); const body = await r.text();
  ok(r.status === 503 && f.calls.sends.length === 1 && f.calls.finishes.length === 0);
  ok(!/SECRET|api-key|@/.test(body));
});
Deno.test('worker: invalid batch is bounded', async () => {
  const f = fixture([job, job, job]); ok((await createHandler(f.d)(f.request())).status === 503); ok(!f.calls.begins);
});
Deno.test('worker: paid invoice attachment is mandatory and exact SRDS wording', async () => {
  const f = fixture([{ ...job, type: 'paid_invoice', invoice: sample, invoice_metadata: { id: sample.invoice_id, path: '10/123/a.pdf', status: 'pending', sha256: null, bytes: null } }]);
  await createHandler(f.d)(f.request()); const wire = JSON.parse(f.calls.sends[0]);
  ok(f.calls.pdfs === 1 && wire.attachment[0].name === sample.invoice_number + '.pdf');
  ok(atob(wire.attachment[0].content).startsWith('%PDF-'));
  ok(wire.textContent === 'Your invoice for Order #123 is attached.');
});
Deno.test('worker: invalid invoice source never sends bare invoice email', async () => {
  const f = fixture([{ ...job, type: 'paid_invoice' }]); await createHandler(f.d)(f.request());
  ok(!f.calls.pdfs && !f.calls.begins && !f.calls.sends.length);
});
Deno.test('worker: invoice PDF available even when TEST email is suppressed', async () => {
  const f = fixture([{ ...job, type: 'paid_invoice', test_approved: false, invoice: sample, invoice_metadata: { id: sample.invoice_id, path: '10/123/a.pdf', status: 'pending', sha256: null, bytes: null } }]);
  await createHandler(f.d)(f.request());
  ok(f.calls.pdfs === 1 && !f.calls.begins && !f.calls.sends.length);
  ok(JSON.stringify(f.calls.finishes).includes('skipped_test'));
});
Deno.test('worker: transient PDF storage error never consumes quota', async () => {
  const f = fixture([{ ...job, type: 'paid_invoice', invoice: sample, invoice_metadata: { id: sample.invoice_id, path: '10/123/a.pdf', status: 'pending', sha256: null, bytes: null } }]);
  f.d.pdf = () => Promise.reject(Error('private Storage access token'));
  await createHandler(f.d)(f.request()); ok(!f.calls.begins && !f.calls.sends.length);
  ok(JSON.stringify(f.calls.finishes) === '[{"outcome":"prepare_retry","error":"PREPARATION_UNCONFIRMED"}]');
});
for (const [status, code, expected] of [
  [201, '', 'sent'], [429, '', 'retry'], [500, '', 'uncertain_retry'], [408, '', 'uncertain_retry'],
  [400, 'invalid_parameter', 'failed'], [401, '', 'failed'], [400, 'duplicate_parameter', 'delivery_unknown'], [400, 'not_enough_credits', 'retry'],
] as const) Deno.test(`Brevo: ${status}/${code || 'response'} -> ${expected}`, async () => {
  const transport = (() => Promise.resolve(Response.json({ messageId: 'synthetic-provider', code, message: 'secret@never-log.test' }, { status, headers: { 'Retry-After': '120' } }))) as typeof fetch;
  const result = await sendBrevo('{}', 'private-synthetic-key', transport);
  ok(result.outcome === expected); if (status === 429) ok(result.retrySeconds === 120);
  ok(!JSON.stringify(result).includes('secret@'));
});
Deno.test('Brevo: network timeout records uncertainty and redacts error', async () => {
  const result = await sendBrevo('{}', 'private', (() => Promise.reject(Error('private recipient@example.test'))) as typeof fetch);
  ok(result.outcome === 'uncertain_retry' && !JSON.stringify(result).includes('private'));
});
Deno.test('Brevo: success without message ID is uncertain', async () => {
  ok((await sendBrevo('{}', 'private', (() => Promise.resolve(Response.json({}, { status: 201 }))) as typeof fetch)).outcome === 'uncertain_retry');
});
Deno.test('Brevo: Retry-After validation and bounds', () => {
  ok(retryAfter('nonsense') === undefined && retryAfter('0') === 30 && retryAfter('9999999') === 86400);
  ok(retryAfter('Fri, 16 Oct 2026 12:02:00 GMT', Date.parse(sample.paid_at)) === 120);
});
Deno.test('templates: all required events plain+HTML, no tracking/PII/OTP', () => {
  for (const type of emailTypes) {
    const t = template(type, '123'); ok(t.text.length && t.html.includes(escapeHtml(t.text)));
    ok(!/<img|cnic number|\botp\b/i.test(t.html));
  }
  ok(template('vendor_approved', '123').text === 'Your account has been approved.');
  ok(template('rider_cnic_verified', '123').text === 'Your CNIC has been verified. Start accepting jobs.');
  ok(escapeHtml('<script>"x"&\'') === '&lt;script&gt;&quot;x&quot;&amp;&#39;');
});
Deno.test('invoice: integer cents, no floating financial rounding', () => {
  ok(money('44000') === '440.00' && money('100000000000001') === '1000000000000.01');
  validateInvoice(sample);
});
Deno.test('invoice: unpaid COD and altered totals rejected', () => {
  for (const s of [{ ...sample, payment_status: 'pending' }, { ...sample, total_cents: '1' }, { ...sample, delivery_cents: '-1' }]) {
    let rejected = false; try { validateInvoice(s); } catch { rejected = true; } ok(rejected);
  }
});
Deno.test('invoice: actual pdf-lib runtime, valid PDF pages, deterministic repeat bytes', async () => {
  const a = await invoicePdf(sample), b = await invoicePdf(sample);
  ok(new TextDecoder().decode(a.subarray(0, 5)) === '%PDF-');
  const document = await PDFDocument.load(a); ok(document.getPageCount() === 1);
  ok(document.getTitle() === 'Invoice TR-000000000123'); ok(await digest(a) === await digest(b));
  await Deno.writeFile('.fr21-local/fr32/invoice-sample.pdf', a);
});
Deno.test('invoice: Arabic Unicode identity and multipage rendering', async () => {
  const s = { ...sample, customer: 'محمد علی', items: Array.from({ length: 30 }, (_, i) => ({ ...sample.items[0], product: 'چاول', vendor: 'دکان', vendor_id: 20 + i % 2 })) , subtotal_cents: '480000', total_cents: '500000' };
  const bytes = await invoicePdf(s); ok((await PDFDocument.load(bytes)).getPageCount() >= 2);
  await Deno.writeFile('.fr21-local/fr32/invoice-unicode.pdf', bytes);
});
