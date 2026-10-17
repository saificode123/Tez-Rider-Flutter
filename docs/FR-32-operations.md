# FR-32 operations (TEST)

Target: `igeisilhtmglgnqvllrx` only. Production has not been accessed.
Migration: `202610160003_fr32_email_outbox.sql`. See progress/acceptance for actual deployment status.

## Delivery and invoices

Business transactions insert one intent per stable event identity. Required enqueue failures abort the business transaction; provider failures occur after commit. Account transitions have fresh UUIDs; FR28 mail follows confirmed SYNCED operations, not the earlier fail-closed flag. A valid approved CNIC produces one combined approval/verification email. Registration verification remains Supabase Auth.

The protected worker claims at most2 due rows using SKIP LOCKED and2-minute leases. It prepares/persists private PDFs before shared quota admission and HTTP. Preparation failures back off; ten preparations/five provider attempts are bounded. A pre-send crashed lease is recoverable. An expired lease after send began is quarantined as delivery_unknown. Provider201 with an ID means provider acceptance, not inbox receipt.

Confirmed rejections429 retry using validated Retry-After; permanent4xx fail. Network/5xx may be uncertain: the same immutable message and body `headers.idempotencyKey` are retried only within a conservative10-minute window. Changed message hashes and duplicate_parameter require reconciliation. Enqueue is deduplicated; exactly-once external delivery is not promised.

For delivery_unknown, inspect the provider message ID and the provider transactional log privately. Record confirmed evidence before any privileged recovery. Do not reset attempts, replace the provider key or blindly requeue an uncertain message after the window. Absence of an API response is not evidence of nondelivery.

Uncollected/pending COD gets an order confirmation and no paid invoice. A trusted server record of successful full collection can issue an invoice. No COD collection workflow or gateway is added. One shared-order invoice uses immutable item price snapshots and the shared delivery fee once. Discounts/taxes are absent from the accepted checkout and are not invented. Missing/reconciling source data fails visibly with SOURCE_REVIEW_REQUIRED. Synthetic capture tests do not verify a bank capture.

PDFs use pdf-lib1.17.1, fontkit2.0.4 and licensed Noto fonts. Unsupported glyphs fail explicitly, without substituting identity text. Full fonts are embedded because the legacy subset/shaper fork fails secure Deno defaults. Sample size409751bytes; actual size varies. Private5MiB bucket; deterministic object paths; create-only uploads; hash/length checks; repeat attempts reuse the PDF. No public URL or expiring URL is persisted. Owner/admin signing returns900-second URLs through fr32-invoice-url. Existing Order History opens them without requiring email receipt.

## Shared quota and TEST controls

User approved temporary rolling26-hour admission on2026-10-16 because the provider email-credit reset timezone could not be verified. Total300 logical delivery reservations per rolling window;90 reserved for OTP; FR32 can consume at most210, OTP can use the remaining total. Configuration is server-private. Reservations serialize on one row; retries of the same provider-idempotent message reuse admission. Failed/unknown sends conservatively retain reservations. Legacy FR33 UTC accounting remains an additional guard; HMAC/nonce, rate limits, ownership and expiry are unchanged. Prior OTP usage is conservatively bootstrapped, not reset.

Provider-day mode exists but must not be enabled until a verified timezone is supplied. SQL timezone-boundary tests use an explicitly synthetic timezone, not a statement about Brevo.

Every FR32 send redirects to BREVO_TEST_RECIPIENT. New jobs are unapproved by default. Noninvoice jobs become skipped_test without HTTP/quota use; invoice jobs can prepare the private PDF then skip email. Only service-only fr32_test_allow_email can approve at most30 known job IDs, and cannot automatically resend previously attempted jobs. FR33 retains its original recipient allowlist and OTP flow.

Planned scheduler: one `fr32-email-worker` job every2minutes, calling private dispatch; key in Vault `fr32_email_worker_key`, matching Edge secret FR32_EMAIL_WORKER_KEY. Secret generated256-bit, never tracked. Existing jobs1 FR30 and4 FR10 must compare unchanged before/after activation. See deployment evidence for the actual FR32 job ID. Unauthorized calls fail before claiming.

## Safe operational queries

Run only through an authorized TEST SQL connection; these omit addresses, payloads and credentials.

```sql
select status,email_type,count(*)as jobs,min(created_at)as oldest
from public.email_outbox group by status,email_type order by status,email_type;
-- pending, failed, deferred and delivery_unknown queues:
select id,email_type,status,attempts,next_attempt_at,last_error
from public.email_outbox where status in('pending','failed','deferred','delivery_unknown')
order by priority,next_attempt_at,id limit100;
select email_type,sum(attempts)as attempts,count(*)filter(where status='sent')as provider_accepted
from public.email_outbox group by email_type;
select kind,sum(units)as active_reservations,min(expires_at)as next_release
from fr32_private.quota_reservations where expires_at>clock_timestamp()group by kind;
select quota_mode,daily_budget,otp_reserve,provider_timezone,dispatch_enabled
from fr32_private.configuration;
-- Preparation failures (including unsupported glyphs) may live on the outbox
-- while the immutable invoice is still pending; inspect both records.
select i.id,i.order_id,i.payment_id,i.status,i.failure_code,
 e.status as email_status,e.last_error as preparation_or_send_error
from public.invoices i left join public.email_outbox e
 on e.dedupe_key='invoice:'||i.payment_id
where i.status<>'ready' or e.status in('failed','delivery_unknown')
order by i.created_at limit100;
select jobid,jobname,schedule,active from cron.job where jobname in('fr32-email-worker','fr10-order-timeout','fr30-android-push');
select jobid,status,start_time,end_time from cron.job_run_details
where jobid in(select jobid from cron.job where jobname='fr32-email-worker')order by start_time desc limit20;
select id,provider_message_id from public.email_outbox where status in('sent','delivery_unknown')order by created_at desc limit20;
select bucket_id,count(*)as objects,sum((metadata->>'size')::bigint)as bytes
from storage.objects where bucket_id='invoices'group by bucket_id;
```

Inspect fr32-email-worker/fr32-invoice-url logs in TEST Edge Functions, and aggregate cron history above. Do not dump Vault, scheduler headers, signed URLs, recipient lists or PDF contents into logs. pg_net response history is transport evidence, not proof that an email reached an inbox. Invoice failure metadata and outbox failure codes remain visible to authorized operations even without a new dashboard.

No automatic deletion of financial history is introduced. Monitor queue oldest age, failure counts and Storage usage. Archive eligible operational records only under an approved retention policy; preserve invoice/payment/audit history. Production requires separate review, credentials, quota policy and deployment authorization; the TEST-only runtime guards deliberately reject a production URL.

## Verified free-tier limits (official sources checked2026-10-16)

- [Brevo pricing](https://help.brevo.com/hc/en-us/articles/208589409-About-Brevo-s-pricing-plans):300emails/day; [Free FAQ](https://help.brevo.com/hc/en-us/articles/208580669-FAQs-What-are-the-limits-of-the-Free-plan):unused credits do not roll over. Hosted account preflight confirmed free/sendLimit300 and an active sender.
- [Brevo API limits](https://developers.brevo.com/docs/api-limits):general Free SMTP POST send-email1000requests/s; daily credits, not worker throughput, constrain this application first. No rate-limit entitlement is assumed beyond the documented/account-specific limits.
- [Attachments](https://help.brevo.com/hc/en-us/articles/4402811730962-Add-an-attachment-to-a-transactional-email):API total20MB including email/attachments; [send API](https://developers.brevo.com/reference/send-transac-email):base64 content plus filename. Our5MiB cap stays below this, including base64 overhead.
- [Brevo idempotency](https://developers.brevo.com/docs/heterogenous-versions-batch-emails):current guide30-minute TTL and duplicate_parameter; [historical changelog](https://developers.brevo.com/changelog/2021/11/10) said15minutes. Conservative recovery is10minutes; no provider reset timezone was established.
- [Edge limits](https://supabase.com/docs/guides/functions/limits):256MB, Free150s wall time, CPU limit applies separately. [Invocations](https://supabase.com/docs/guides/functions/pricing):500000/month Free. A2-minute schedule is21600 invocations per30days before manual calls; existing jobs also consume invocations.
- [Storage](https://supabase.com/docs/guides/storage/pricing):1GB Free; [upload cap](https://supabase.com/docs/guides/storage/uploads/file-limits):Free global maximum50MB, our bucket5MiB. Other application objects share the quota.
- [Cron](https://supabase.com/docs/guides/cron) uses pg_cron; [pg_net](https://supabase.com/docs/guides/database/extensions/pg_net) supports asynchronous calls. Both were found in hosted TEST preflight. [Static files](https://supabase.com/changelog/32815-add-static-files-to-edge-functions) bundle the invoice fonts; hosted runtime was verified by actual private PDF generation, rendering and device access in isolated TEST.
- [Default Auth SMTP](https://supabase.com/docs/guides/auth/auth-smtp):team-member recipients only and2messages/hour, not a general production mail service. TEST public settings show email enabled/autoconfirm false; they do not expose the actual SMTP host/rate configuration, so default transport is not asserted. Auth SMTP was not changed. If custom Auth SMTP uses this same Brevo account outside the shared admission layer, its usage must be accounted for before production activation.
- [pdf-lib](https://pdf-lib.js.org/) and [fontkit](https://github.com/foliojs/fontkit) are open-source; Noto license accompanies the bundled fonts.

Assumption: with exactly one confirmation and one invoice per paid order and no account-action traffic,210FR32 slots allow105such orders per rolling26hours. Real capacity is lower with retries/reservations and other events. At the sample PDF size, invoice history eventually fills the1GB shared Storage allowance; this is not unlimited production capacity. Free mitigation: retain the asynchronous queue, prioritize OTP, monitor backlog/Storage, batch bounded processing and arrange an approved offline archive before limits are reached. Do not silently discard mail or financial history. No paid service is introduced.
