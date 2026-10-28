# Full SRDS compliance - current completion stage

2026-10-28, Asia/Karachi. **NOT READY FOR PRODUCTION.**

Baseline verified: branch `feature/final-2-functional`, HEAD `294f289914a1cd1a4eb998cf766e97942b9bb2c9`, clean working tree before this stage; existing GitHub origin preserved.

The 45-page SRDS PDF is available. Its functional clauses were extracted directly with pypdf. The original Word requirements document is unavailable. The owner supplied the FR gap-list text in chat; report 20 distinguishes it from direct inspection of FR.docx.

`python tests/integration/MASTER-compliance.py` validates all 137 unique inherited rows and generates `docs/evidence/MASTER-compliance.json`. Every row records description, Flutter/backend implementation, test/evidence references, environment, actual result and acceptance status. It fails on a changed row count, duplicate ID or unexpected baseline counts. This is an executable inventory check, not an end-to-end acceptance runner.

Retained classifications: 76 bounded historical TEST passes, 17 approved deviations, 43 PARTIAL, 1 BLOCKED. **Zero whole requirements have been newly promoted to PASS in this stage.** Individual regression passes do not close physical, platform, capacity or production gates. Historical evidence remains bound to its original source/artifact.

Priority implementation: location Stop now waits for a pending server enable response before revoking sharing, while immediately stopping device collection and preventing restart. The same ordering protects presence-recovery enable requests. Regression covers initial start, recovery, lost enable response and account change. No GPS fix, movement, delivery, payment or earning is synthesized.

Device-discovered login correction: the language selector could scroll above the visible screen. It is now pinned above the scrolling form, including with keyboard/large text. English and Urdu were visually verified on the final installed TEST APK; Urdu persisted through a cold restart. Entered credentials survive language switching in the widget regression. Implementation commit: `cd3f9ac`.

See 23 for execution, 24 for GPS/performance limits, 25 for release gates, and 26 for handover. All unaccepted clauses remain open in the machine-readable matrix and report 15.
