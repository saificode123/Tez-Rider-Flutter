import { PDFDocument, PDFFont, rgb } from 'npm:pdf-lib@1.17.1';
import * as fontkit from 'npm:fontkit@2.0.4';

export interface InvoiceItem {
  product: string; vendor: string; vendor_id: number; quantity: number;
  unit_cents: string; line_cents: string;
}
export interface InvoiceSnapshot {
  invoice_id: string; invoice_number: string; order_id: number; customer_id: number; customer: string;
  paid_at: string; payment_reference: string; payment_status: string; currency: 'PKR';
  subtotal_cents: string; delivery_cents: string; total_cents: string; items: InvoiceItem[];
  cash_event_id?: number; cash_actor_role?: 'admin' | 'rider';
}
export function cents(value: string): bigint {
  if (typeof value !== 'string' || !/^\d{1,15}$/.test(value)) throw Error('INVOICE_INVALID_MONEY');
  return BigInt(value);
}
export function money(value: string): string {
  const n = cents(value);
  return `${n / 100n}.${(n % 100n).toString().padStart(2, '0')}`;
}
function text(value: string): string {
  if (typeof value !== 'string' || !value.trim() || value.length > 300 || /[\x00-\x1f\x7f]/.test(value)) throw Error('INVOICE_INVALID_TEXT');
  return value;
}
export function validateInvoice(s: InvoiceSnapshot): void {
  if (!s || !Number.isSafeInteger(s.order_id) || !Number.isSafeInteger(s.customer_id) || s.currency !== 'PKR' ||
    !/^TR-\d{1,20}$/.test(s.invoice_number) || !Number.isFinite(Date.parse(s.paid_at)) ||
    !['PAID', 'SUCCESS', 'COMPLETED', 'SUCCEEDED', 'CASH_RECORDED'].includes(s.payment_status) ||
    !Array.isArray(s.items) || s.items.length < 1 || s.items.length > 100) throw Error('INVOICE_SOURCE_REVIEW_REQUIRED');
  text(s.customer); text(s.payment_reference);
  if (s.payment_status === 'CASH_RECORDED' && (!Number.isSafeInteger(s.cash_event_id) || s.cash_event_id! <= 0 ||
    !['admin', 'rider'].includes(s.cash_actor_role ?? '') || s.payment_reference !== `COD-CASH-${s.cash_event_id}`)) {
    throw Error('INVOICE_SOURCE_REVIEW_REQUIRED');
  }
  let sum = 0n;
  for (const i of s.items) {
    text(i.product); text(i.vendor);
    if (!Number.isSafeInteger(i.quantity) || i.quantity < 1 || !Number.isSafeInteger(i.vendor_id)) throw Error('INVOICE_INVALID_ITEM');
    if (cents(i.unit_cents) * BigInt(i.quantity) !== cents(i.line_cents)) throw Error('INVOICE_LINE_MISMATCH');
    sum += cents(i.line_cents);
  }
  if (sum !== cents(s.subtotal_cents) || sum + cents(s.delivery_cents) !== cents(s.total_cents) || cents(s.total_cents) <= 0n) throw Error('INVOICE_TOTAL_MISMATCH');
}
let fontBytes: Promise<[Uint8Array, Uint8Array]> | undefined;
export async function invoicePdf(s: InvoiceSnapshot): Promise<Uint8Array> {
  validateInvoice(s);
  fontBytes ??= Promise.all([
    Deno.readFile(new URL('./fr32-fonts/NotoSans-Regular.ttf', import.meta.url)),
    Deno.readFile(new URL('./fr32-fonts/NotoNaskhArabic-Regular.ttf', import.meta.url)),
  ]);
  const doc = await PDFDocument.create();
  doc.registerFontkit(fontkit);
  const [latinBytes, arabicBytes] = await fontBytes;
  // Full embedding uses fontkit2's supported API; the older pdf-lib fork's
  // subset stream/shaper relies on __proto__, disabled by secure Deno runtimes.
  const latin = await doc.embedFont(latinBytes, { subset: false });
  const arabic = await doc.embedFont(arabicBytes, { subset: false });
  const date = new Date(s.paid_at);
  doc.setTitle(`Invoice ${s.invoice_number}`); doc.setAuthor('TezRider');
  doc.setCreationDate(date); doc.setModificationDate(date);
  let page = doc.addPage([595.28, 841.89]);
  let y = 790;
  const pick = (value: string): PDFFont => /\p{Script=Arabic}/u.test(value) ? arabic : latin;
  const ensure = (height = 24) => { if (y < 58 + height) { page = doc.addPage([595.28, 841.89]); y = 790; } };
  function draw(value: string, x = 44, size = 10, width = 507, color = rgb(0.1, 0.08, 0.2)): void {
    const font = pick(value), supported = new Set(font.getCharacterSet());
    if (Array.from(value).some((c) => !supported.has(c.codePointAt(0)!))) throw Error('INVOICE_UNSUPPORTED_GLYPH');
    // Character-based wrapping also handles long references without spaces.
    let line = '';
    for (const char of value) {
      if (font.widthOfTextAtSize(line + char, size) > width && line) {
        ensure(18); page.drawText(line, { x, y, size, font, color }); y -= 17; line = '';
      }
      line += char;
    }
    if (line) { ensure(18); page.drawText(line, { x, y, size, font, color }); y -= 17; }
  }
  draw('TezRider', 44, 22, 507, rgb(0.1, 0.37, 0.13)); y -= 8;
  const manualCash = s.payment_status === 'CASH_RECORDED';
  draw(`${manualCash ? 'COD CASH RECEIPT' : 'PAID INVOICE'} ${s.invoice_number}`, 44, 14);
  draw(`Order #${s.order_id}  |  Date ${date.toISOString().slice(0, 10)} (UTC)`);
  draw(`Customer #${s.customer_id}`); draw(s.customer); y -= 12;
  const groups = new Map<number, InvoiceItem[]>();
  for (const item of s.items) groups.set(item.vendor_id, [...(groups.get(item.vendor_id) ?? []), item]);
  for (const [vendorId, items] of groups) {
    ensure(90); draw(`Vendor #${vendorId}`, 44, 11); draw(items[0].vendor);
    const headerY = y;
    draw('Item', 44, 9); y = headerY; draw('Qty', 326, 9); y = headerY;
    draw('Unit PKR', 375, 9); y = headerY; draw('Total PKR', 469, 9);
    for (const item of items) {
      ensure(Math.ceil(pick(item.product).widthOfTextAtSize(item.product, 9) / 250) * 17 + 40); const top = y;
      draw(item.product, 44, 9, 265); const bottom = y;
      y = top; draw(String(item.quantity), 326, 9, 40);
      y = top; draw(money(item.unit_cents), 375, 9, 79);
      y = top; draw(money(item.line_cents), 469, 9, 85);
      y = Math.min(y, bottom) - 7;
    }
    y -= 12;
  }
  ensure(160);
  draw(`Items subtotal: PKR ${money(s.subtotal_cents)}`, 285, 10, 266);
  draw(`Shared delivery fee: PKR ${money(s.delivery_cents)}`, 285, 10, 266);
  draw(`${manualCash ? 'Cash recorded' : 'Total paid'}: PKR ${money(s.total_cents)}`, 285, 12, 266); y -= 12;
  if (manualCash) {
    draw(`Manual cash acknowledgement recorded by an authorized ${s.cash_actor_role}.`);
    draw('The app did not perform a payment-provider transfer.');
  }
  draw(`Payment status: ${s.payment_status}`); draw('Payment reference:'); draw(s.payment_reference);
  const pages = doc.getPages();
  pages.forEach((p, i) => p.drawText(`TezRider | ${s.invoice_number} | Page ${i + 1}/${pages.length}`, { x: 44, y: 30, size: 8, font: latin, color: rgb(0.4, 0.4, 0.4) }));
  const bytes = await doc.save({ useObjectStreams: false });
  if (bytes.length > 5242880) throw Error('INVOICE_ATTACHMENT_TOO_LARGE');
  return bytes;
}
