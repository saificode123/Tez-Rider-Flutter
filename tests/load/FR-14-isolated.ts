// Permissionless diagnostic only: all external dependencies are mocked.
// This is NOT an Auth/RLS/database, hosted Edge, quota or comparable load test.
import {createHandler, fallback, type Dependencies, type Data} from '../../supabase/functions/get-delivery-route/handler.ts';

const origin = [73.05, 33.7], destination = [73.06, 33.71]; // Synthetic only.
const now = Date.parse('2026-10-20T12:00:00Z');
function summary(values: number[]) {
  const ordered = [...values].sort((a, b) => a - b);
  const at = (p: number) => ordered[Math.ceil(ordered.length * p) - 1];
  return {count: ordered.length, p50Ms: at(.5), p95Ms: at(.95), p99Ms: at(.99)};
}
const reports = [];
for (const scenario of ['cache', 'fallback', 'provider_failure', 'authorization_denial']) {
  const times: Record<string, number[]> = {};
  let providerCalls = 0;
  async function measure<T>(name: string, work: () => Promise<T>): Promise<T> {
    const start = performance.now();
    try { return await work(); }
    finally { (times[name] ??= []).push(performance.now() - start); }
  }
  const context: Data = {orderId: 1, origin, destination, speedKmh: 20, minimumSeconds: 60};
  const deps: Dependencies = {
    configured: true, now: () => now,
    authenticate: token => measure('mockAuth', async () => token === 'mock-valid'),
    accountBoundary: () => measure('mockAccountBoundary', async () => null),
    context: () => measure('mockAuthorization', async () => ({code: scenario === 'authorization_denial' ? 'FORBIDDEN' : 'OK', actor: 42})),
    prepare: () => measure('mockCacheLookup', async () => ({...context,
      code: scenario === 'cache' ? 'CACHE' : scenario === 'provider_failure' ? 'COMPUTE' : 'THROTTLED',
      lease: 'mock-only',
      ...(scenario === 'cache' ? {cache: {source: 'geoapify', geometry: {type: 'LineString', coordinates: [origin, destination]}, distanceMeters: 1600, durationSeconds: 240, expiresAt: new Date(now + 240000).toISOString()}} : {}),
    })),
    finish: () => measure('mockFinish', async () => ({code: 'RELEASED'})),
    provider: () => measure('mockProvider', async () => {
      providerCalls++;
      await new Promise(resolve => setTimeout(resolve, 10));
      throw Error('Mock provider failure');
    }),
  };
  const handler = createHandler(deps), totals: number[] = [];
  for (let i = 0; i < 20; i++) {
    const start = performance.now();
    const response = await handler(new Request('http://localhost/mock-only', {method: 'POST', headers: {Authorization: 'Bearer mock-valid'}, body: JSON.stringify({orderId: 1})}));
    const data = await response.json();
    totals.push(performance.now() - start);
    const denied = scenario === 'authorization_denial';
    if (response.status !== (denied ? 403 : 200) || (denied ? data.route != null : !data.route) ||
      (!denied && scenario !== 'cache' && (data.route.geometry !== null || !data.route.isApproximate))) throw Error('Diagnostic contract failed');
  }
  if (providerCalls !== (scenario === 'provider_failure' ? 20 : 0)) throw Error('Unexpected mock provider count');
  reports.push({scenario, firstRequestMs: totals[0], total: summary(totals), subsequent: summary(totals.slice(1)),
    dependencies: Object.fromEntries(Object.entries(times).map(([name, values]) => [name, summary(values)])), mockProviderCalls: providerCalls});
}
const fallbackTimes: number[] = [];
for (let i = 0; i < 100; i++) {
  const start = performance.now();
  if (!fallback({orderId: 1, origin, destination, speedKmh: 20}, now)) throw Error('Fallback unavailable');
  fallbackTimes.push(performance.now() - start);
}
console.log(JSON.stringify({scope: 'IN-PROCESS MOCKS ONLY; NOT COMPARABLE TO SUPABASE LOAD', realProviderCalls: 0,
  realAuthRlsDatabaseMeasured: false, hostedColdStartMeasured: false, securityAcceptanceEstablished: false,
  reports, fallbackMath: summary(fallbackTimes)}));
