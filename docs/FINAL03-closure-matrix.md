# Stage 0/1 closure execution matrix



Baseline `cb18c2b`, 2026-10-23 Asia/Karachi. TEST only. Prior evidence remains unchanged. Result cells are updated only after execution; source, mocked UI, real JWT/SQL, websocket and Android evidence remain distinct.



| ID / Classification | Requirement | Current Evidence | Missing Evidence | Required Fix/Test | Execution Method | Result | Acceptance Status |

|---|---|---|---|---|---|---|---|

| UI01 / TEST COVERAGE GAP | Stage0 conditional rendering and handlers | 410 templates/707 historical rows; retained widget cases | Resolved by the named evidence; limitations below | Parameterized screen/widget tests with handler request assertions; classify deferred/unreachable controls | Deterministic Flutter doubles plus retained real mutation evidence | 37 new screen/widget cases; all56 files mapped;412 templates,410 predecessor alignments,295 references,707 historical rows; conditional source and later-stage dispositions explicit | CLOSED for Stage0 audit; no412-runtime-pass claim |

| AUTH01 / CODE DEFECT | Secure logout and restoration | Normal four-role Android lifecycle | Resolved by the named evidence; limitations below | Independent cleanup, fail-closed credential handling and durable nonsecret logout fence | Fault-injection unit/widget tests; physical normal/account-switch/restart | Account-bound fail-closed storage and durable logout fence implemented;10 fault cases; final APK login/restart/logout/restart physical PASS | CLOSED |

| RT01 / HOSTED TEST | FR42 private Realtime authorization | Own-profile live/expired/revoked websocket checks | Resolved by the named evidence; limitations below | Enumerate channels/publication policies; exercise distinct live identities, denied peers and lifecycle | Actual user websocket/HTTP and narrow rollback policy checks | 53 actual row-stream records +6 chat +27 private tracking; retained12 own-profile lifecycle;10 new registry SQL probes | CLOSED |

| RT02 / CODE DEFECT | Chat cleanup/account isolation | Server RLS retained | Resolved by the named evidence; limitations below | Cancel pending work and reject stale generations; remove old channel | Deterministic controller races; actual chat RLS retained | Generation/account/channel/batch cleanup;5 deterministic race cases and6 actual hosted chat assertions PASS | CLOSED |

| MEDIA01 / HOSTED TEST | FR42/43 private media | CNIC45second real expiry; unrelated role/list denials | Resolved by the named evidence; limitations below | Real signed URL authorization; inspect immutable object policies and Edge byte validation; targeted negative tests | Existing protected fixtures; no provider sends/historical object rewrite | 60 real media assertions +6 live-claim blocked-owner rollback probes; retained real45s expiry; new RPC image guard5 PASS | CLOSED |

| LEG01 / TEST COVERAGE GAP | Reachable legacy security | 170 definition/ACL preservation; current174 function catalog | Resolved by the named evidence; limitations below | Risk-based function/RPC/Edge/REST inventory with explicit guards, validation, audit and retained tests | Source/body review and targeted real-JWT/rollback assertions | Independent REST/RPC/Edge/media/worker/SQL family review;175 definition/ACL hashes,17 table refs,9 Edge names,7 channel sites; confirmed product and cached-topic bugs fixed | CLOSED; bounded review limits explicit |

| FR42 / HOSTED TEST | Applicable operation authorization | 83 RLS tables/332 metadata rows;108 JWT checks | Resolved by the named evidence; limitations below | Map every reachable operation to exact policy and runtime evidence | Real user JWTs; metadata only for intentionally inaccessible private tables | Exact operation policies/grants preserved for83 old tables, new84th denied; resource/role matrix plus actual JWT/websocket/Storage cases | PASS for applicable active/denied scope |

| FR43 / TEST COVERAGE GAP | Trusted input validation | Retained feature/Deno/SQL validation | Resolved by the named evidence; limitations below | Validate ownership/types/bounds/state/idempotency/files; test gaps without sending providers | Focused Flutter/Deno/SQL/HTTP | Trusted legacy product-media bypass fixed; retained transactional validation/UUID/state/upload evidence; current media, chat, SQL, Deno and UI negative cases | PASS for applicable active/denied scope |

| FR44 / HOSTED TEST | Critical Admin audit | Vendor/rider/dispute/broadcast retained audits; new block audit/immutability | Resolved by the named evidence; limitations below | Reconcile active critical actions; narrow transactional audit assertions | Retained unchanged evidence plus affected hosted checks | Current actual Admin transaction/audit actor-target-action check and tamper/invalid/ordinary-user denial4; retained block/dispute/rider/broadcast audit evidence reconciled | PASS for active critical actions |

| ANDROID01 / PHYSICAL DEVICE TEST | Network interruption/recovery | Valid/blocked/revoked four-role restoration | Resolved by the named evidence; limitations below | Preserve connectivity settings, interrupt safe read, restore in finally; no critical mutations | Connected TEST phone only | Final installed APK real offline order-read failure/no false empty; original connectivity restored; actual Retry recovers confirmed orders; customer restart/logout restart PASS | CLOSED; no critical write/network duplicate induced |

| ANDROID02 / TEST COVERAGE GAP | Unavailable/corrupt secure storage | Normal cleanup retained | Resolved by the named evidence; limitations below | Inject storage/platform errors and stale/cross-account credentials | Controlled automated mocks; never label physical | 10 controlled secure-storage faults including unavailable, partial/corrupt, cross-account, stale logout fence; safe failure; never altered personal phone storage | CLOSED via permitted automated equivalent, not physical fault evidence |

| DOC01 / DOCUMENTATION GAP | Final acceptance and traceability | FINAL02 checkpoints | Resolved by the named evidence; limitations below | Append evidence and update required docs; scoped commits | Validated captured results only | Required five docs updated; signoff,56-file state map, resource-level security/legacy review and sanitized append-only FINAL03 evidence created; old FINAL01/02 retained | CLOSED after scoped commits |

| DEFER01 / LATER-STAGE FUNCTIONAL WORK | Approved A/B/C and unfinished FRs | Recorded approvals and roadmap | No later-stage implementation authorized here | Retain truthful unavailable states and explicit future owners; FR14 road/ETA remains unaccepted | Source/conditional tests, preserved feature reports | A/B/C retained. FR14 road/ETA/physical movement remains NOT FUNCTIONALLY ACCEPTED; other later-stage workflows retain owners and truthful unavailable states | DEFERRED; not a Stage0/1 acceptance blocker |

Final audit disposition: source inventory/classification is complete; named conditional and affected-handler evidence is reconciled with retained acceptance. This does not certify every possible runtime widget instance or all later-stage functionality. See FINAL03-rendered-states.md and FINAL-stage-0-1-signoff.md.

Resolved confirmed security findings: cached private tracking revocation (HIGH), legacy product media reference bypass (MEDIUM), secure logout/storage failure (MEDIUM), chat stale-room/account race (MEDIUM), metadata-derived drawer exposure (LOW). No open confirmed critical/high in the reviewed active TEST paths.
