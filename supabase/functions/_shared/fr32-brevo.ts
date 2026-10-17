// No provider response text, recipient, API key or invoice data leaves this boundary.
export type Outcome = {
  outcome: 'sent' | 'retry' | 'uncertain_retry' | 'failed' | 'delivery_unknown';
  provider?: string; retrySeconds?: number; error?: string;
};
export function retryAfter(value: string | null, now = Date.now()): number | undefined {
  if (!value) return;
  const seconds = /^\d+$/.test(value) ? Number(value) : (Date.parse(value) - now) / 1000;
  return Number.isFinite(seconds) && seconds >= 0 ? Math.min(86400, Math.max(30, Math.ceil(seconds))) : undefined;
}
export async function sendBrevo(body: string, key: string, transport: typeof fetch = fetch): Promise<Outcome> {
  try {
    const response = await transport('https://api.brevo.com/v3/smtp/email', {
      method: 'POST', headers: { 'api-key': key, 'Content-Type': 'application/json', Accept: 'application/json' },
      body, signal: AbortSignal.timeout(20000),
    });
    if (response.status === 201) {
      const data = await response.json();
      if (typeof data.messageId === 'string' && /^[^\r\n]{1,200}$/.test(data.messageId)) {
        return { outcome: 'sent', provider: data.messageId };
      }
      return { outcome: 'uncertain_retry', error: 'PROVIDER_RECEIPT_MISSING' };
    }
    if (response.status >= 500 || response.status === 408) return { outcome: 'uncertain_retry', error: 'PROVIDER_UNCERTAIN' };
    if (response.status === 429) return { outcome: 'retry', retrySeconds: retryAfter(response.headers.get('retry-after')), error: 'PROVIDER_RATE_LIMIT' };
    let code: string | undefined;
    try { code = (await response.json()).code; } catch { /* untrusted response ignored */ }
    if (code === 'duplicate_parameter') return { outcome: 'delivery_unknown', error: 'PROVIDER_DUPLICATE_REQUIRES_RECONCILIATION' };
    if (code === 'not_enough_credits' || code === 'insufficient_credits') {
      return { outcome: 'retry', retrySeconds: 3600, error: 'PROVIDER_CREDITS_EXHAUSTED' };
    }
    return { outcome: 'failed', error: 'PROVIDER_PERMANENT_REJECTION' };
  } catch {
    return { outcome: 'uncertain_retry', error: 'NETWORK_UNCERTAIN' };
  }
}
export async function digest(bytes: Uint8Array | string): Promise<string> {
  const data = typeof bytes === 'string' ? new TextEncoder().encode(bytes) : bytes;
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new Uint8Array(data))), (v) => v.toString(16).padStart(2, '0')).join('');
}
