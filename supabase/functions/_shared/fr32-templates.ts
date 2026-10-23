export const emailTypes = [
  'order_confirmation', 'paid_invoice', 'vendor_approved', 'vendor_rejected',
  'rider_approved', 'rider_rejected', 'rider_cnic_verified', 'account_blocked', 'account_unblocked',
] as const;
export type EmailType = typeof emailTypes[number];
export function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
}
export function template(type: EmailType, order: string, manualCash = false): { subject: string; text: string; html: string } {
  if (!emailTypes.includes(type)) throw Error('UNSUPPORTED_EMAIL_TYPE');
  if (!/^[A-Za-z0-9# _-]{1,80}$/.test(order)) throw Error('INVALID_ENTITY_REFERENCE');
  const content: Record<EmailType, [string, string]> = {
    order_confirmation: ['Order confirmation', `Your Order #${order} has been confirmed.`],
    paid_invoice: manualCash ? ['Your COD cash receipt', `A manual cash receipt was recorded for Order #${order}. Your itemized receipt is attached. The app did not transfer funds.`]
      : ['Your paid invoice', `Your invoice for Order #${order} is attached.`],
    vendor_approved: ['Account approved', 'Your account has been approved.'],
    vendor_rejected: ['Account review', 'Account not approved. Contact support.'],
    rider_approved: ['Account approved', 'Your account has been approved.'],
    rider_rejected: ['Account review', 'Account not approved. Contact support.'],
    rider_cnic_verified: ['Rider verification approved', 'Your CNIC has been verified. Start accepting jobs.'],
    account_blocked: ['Account blocked', 'Your account has been blocked. Contact support for assistance.'],
    account_unblocked: ['Account unblocked', 'Your account has been unblocked. You can sign in again.'],
  };
  const [subject, text] = content[type];
  return {
    subject: `TezRider TEST — ${subject}`, text,
    html: '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>' +
      '<body style="margin:0;padding:24px;background:#f8f7ff;font-family:Arial,sans-serif;color:#1a1340">' +
      '<main style="max-width:560px;margin:auto;background:white;padding:24px;border-top:4px solid #1b5e20">' +
      '<h1 style="color:#1b5e20;font-size:22px">TezRider TEST</h1><p>' + escapeHtml(text) + '</p></main></body></html>',
  };
}
