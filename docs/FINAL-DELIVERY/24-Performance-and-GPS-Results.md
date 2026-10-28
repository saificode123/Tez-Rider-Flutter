# GPS and routing qualification

2026-10-28. **FR-13/14 remain PARTIAL.**

Current source uses actual device positions. Android requests a 2500ms high-accuracy stream, zero distance filter, an ongoing delivery location foreground notification and wake lock. Client publication is throttled at 2300ms using monotonic elapsed time, accepts only fresh accurate genuine fixes, keeps at most one newest pending fix, and applies retry backoff. These are implementation settings, not measured physical cadence guarantees.

This stage fixes Stop during an outstanding enable/recovery request. Native subscriptions stop immediately. Server disable follows the pending response, including lost-response handling; restart remains busy until cleanup settles. Account changes prevent cleanup under a different account. The pre-fix regression failed; final tests/evidence are in report 23. No synthetic location or movement entered production code.

Prior measured real walk: 168.3m displacement; route geometry changed, but refresh TTL also qualified, so deviation-only causality was not established. Prior total route latency 2998.7ms **FAILS** the 800ms engineering target. These historical observations are not new-build measurements. No deviation from 800ms is newly approved.

Reproducible remaining physical plan:

1. Use a genuine assigned TEST delivery, confirmed destination and checklist, owner device consent and real GPS. Bind APK/source hashes and backend versions.
2. Observe private customer WebSocket events using `FR-13-observe.py`; retain interval/accuracy/age aggregates, not coordinates. Run stationary foreground then safe walking (never interact while driving).
3. Repeat background/screen-off, GPS interruption, >30s network loss/reconnect, resume, explicit Stop, order completion and logout. Verify stale customer state and zero sharing after consent/session/terminal changes.
4. Measure initial route/cache hit/deviation/expiry separately. Hold TTL constant during off-route test; use legitimate movement beyond the configured deviation distance. Record sample count, median/p95, provider HTTP duration, Edge stages, client render time and total interaction-to-render time. Provider/network/server/client timing must not be conflated.
5. Measure battery/device/OS coverage and provider budgets separately. No high-impact load test without approval.

## Executed final-APK measurements

APK SHA-256 `7D137F548B0E71F64A07FAF34E47D47DC29972FEB73F38EFBBAF89C1B19DDCD8`, physical Android device AESWNRBAEUPNTGJZ. Customer-owned session-bound private WebSocket; no generated fixes, lifecycle transition, raw coordinates or plaintext credentials retained in public evidence. Evidence: `MASTER-gps-performance.json` and `MASTER-gps-network.json`.

- Foreground: 13 received events in 60.2s; 12 inter-event samples; median 3.946s, nearest-rank p95 8.422s. **FAIL 2-3s cadence.**
- Background: 11 events in 60.8s; 10 intervals; median 5.422s, p95 7.218s. Same TEST process and actual location foreground service observed. **FAIL cadence; bounded background streaming observed.**
- Network recovery: 91.003s controlled offline window, default network absent, original Wi-Fi=1/mobile=0 restored, same process 19875. No Share/Retry input. Subsequent 61s feed: 10 events, median 5.218s, p95 6.891s. Recovery observed, cadence still FAIL. No source-fix speedup is claimed.
- Zero duplicate events across the three separate phases. Device timestamps also have gaps. These observations alone do not isolate native-provider scheduling from request backpressure; no exclusive cause is claimed.
- Raw device/server timestamp differences include negative values. Desktop/server midpoint estimates have 0.86-1.55s uncertainty; cross-clock latency is not accepted as synchronized latency. Monotonic intervals remain valid. Summed fix-path distance is not accepted proof of physical travel or off-route causality.
- Cleanup: assigned-rider authenticated STOPPED followed by customer INELIGIBLE/no location/no topic. Native sharing-off/Offline observed. This is not a physical in-flight Stop-race reproduction.

Three real approved-provider road requests returned HTTP200/OK with Geoapify geometry. Initial total HTTP 4265ms: provider HTTP/parse stage 753.26ms; handler 3130.55ms (approximately 2377.29ms excluding provider); remaining network/outer-security/cold-start time 1134.45ms. Two subsequent cache paths: 3047ms and 2484ms total, handler 1367.98ms and 1238.27ms, no provider stage. Outer-security/network time cannot be separated from these headers. **Total HTTP target 800ms FAIL.** Three samples are not production p95/load qualification. Client render/interaction-to-render time was not measured; an HTTP result is not end-to-end UI acceptance.

The unchanged approved provider/cache/quota/security mechanisms were retained. Further optimization or an explicitly approved measured deviation is required; no new latency or GPS-policy deviation was requested or assumed. Lock-screen/GPS interruption, battery, safe route-progression/deviation causality, multi-device/iOS and scale remain open.
