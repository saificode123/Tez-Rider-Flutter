# Owner-approved main consolidation

2026-11-06. The owner explicitly requested all branches/code on main so a partner
can use `git pull origin main`. All 18 remote feature tips (19 remote branches
including main) are ancestors of consolidated main; no historical feature was
blindly replayed or deleted. Prior main was
`9e51e9d9fca4f1e63cfbf94742fd33c1eaca9485`; consolidation fast-forwarded to
`87ebc22ed1f639a591a4578bcc49bda83006a9c7` without conflicts. A following
 documentation commit updates main-based setup and records this inventory.

Application source is identical to tested `623d1c72bac1cff5c1ea6db66eb1c8c4c79f0335`:
846 Flutter tests passed, 2 skipped; 240 server tests passed; root/clone analysis
clean; arm64 TEST APK built and installed. No new application edits were made
for consolidation. Existing acceptance failures/blockers remain in
FINAL-CUSTOMER-ACCEPTANCE.md. Historical JSON evidence describes its own earlier
snapshot; its main_merged=false field predates this owner-approved operation.

No production backend, secrets or database deployment is part of this merge.
The only repository workflow is manually dispatched Android TEST build.
Private .env and matching TEST Firebase configuration remain untracked and must
be supplied locally. A partner needs the documented Flutter/Android toolchain.

## Branch tips verified contained

| Remote feature branch | Commit |
|---|---|
| `origin/feature/FR-04-cnic-document-upload` | `fd478a42aa3634b362075a242b7cb56fbfb3fc9b` |
| `origin/feature/FR-10-order-timeout-autocancel` | `76960fadf207f17156a2124b547f6cbe47d04b1f` |
| `origin/feature/FR-13-ios-support` | `62d60eea86e195cc397ea5da0aa248aecce9c364` |
| `origin/feature/FR-13-rider-gps-streaming` | `3408790d7c556665228d4c1cca371c4018a07cea` |
| `origin/feature/FR-14-route-and-eta` | `f8bce533f20650649deef31304d235554af35735` |
| `origin/feature/FR-17-stock-tracking` | `57914e2d206d9c7695cc3ca286475edef88a8796` |
| `origin/feature/FR-20-rider-radius-expansion` | `fa29b4c184c17c30010053e527b976733e23cc97` |
| `origin/feature/FR-21-rider-online-status` | `5fe4abda0ac290e938e24056fce740789a83b95d` |
| `origin/feature/FR-25-dispute-submission` | `281c8a8ce3203ed49fdc425f72fa3b4e07e75533` |
| `origin/feature/FR-26-admin-dispute-resolution` | `aabd6cabe0b80eb4b178919cde0c81328d762350` |
| `origin/feature/FR-28-admin-block-users` | `7e809fdc2ab68c2f7e1d0f871e16a8d914ee6b35` |
| `origin/feature/FR-30-admin-broadcasts` | `fed835ffb27d7f163be33e89478a14a4af2943bf` |
| `origin/feature/FR-32-email-notifications` | `569e8c671a57982d3ed8f99dcb1c04613607a685` |
| `origin/feature/FR-33-email-delivery-otp` | `ec1c63b5a6f7ddbb7c42b794b516823ce0afe4c8` |
| `origin/feature/final-2-functional` | `9e51e9d9fca4f1e63cfbf94742fd33c1eaca9485` |
| `origin/feature/final-customer-delivery-fixes` | `87ebc22ed1f639a591a4578bcc49bda83006a9c7` |
| `origin/feature/pre-delivery-checklist` | `7cf80fefdca3a54f5fd0dc5b70e9b77b1ebe3287` |
| `origin/feature/premium-spatial-ui-redesign` | `36f08e8f04ec9eb7569b212a779f27597cfc2d3c` |
