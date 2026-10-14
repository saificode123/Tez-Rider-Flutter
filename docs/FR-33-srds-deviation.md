# FR-33 approved SMS-to-email substitution

The user explicitly approved email instead of the SRDS SMS delivery OTP for FR-33. Reliable mandatory SMS delivery would conflict with the project's zero-cost policy. This substitution does not change S-04's three-failure rule, server authorization, required messages, atomic delivery proof, audit or notification requirements.

An assigned approved rider requests the code after arrival. Only the order customer's confirmed canonical email is resolved server-side. Flutter receives no plaintext code. TEST additionally restricts actual sends to the recipient in the ignored private configuration. The HMAC key is generated in Supabase Vault, never supplied to Flutter; existing FR-04 keys were preserved.

Brevo Free permits 300 emails/day, without rollover. Five emails per order means at most 60 orders/day if every order uses all five issuances; at most 300 with one each, less when other account mail or failed/ambiguous reservations consume budget. The server conservatively budgets 300 UTC-day issuance reservations. Provider quota clocks and other account usage can differ; provider errors remain visible. Budgeting does not guarantee quota availability or receipt. API acceptance is distinct from inbox delivery: mail can be delayed, filtered into spam, or queued beyond the code's ten-minute validity. The rider must wait for the customer's received email or explicitly request a fresh code after the cooldown; no offline delivery bypass exists.

Actual configured sender was found active in the provider API. Own-domain DNS authentication was NOT VERIFIED; an active sender is not proof of SPF/DKIM/DMARC. A free mailbox domain cannot be authenticated as an owned domain. Sender/domain configuration and spam placement remain operational responsibilities.

Official sources checked during implementation:
- [Brevo Free limits](https://help.brevo.com/hc/en-us/articles/208580669-FAQs-What-are-the-limits-of-the-Free-plan)
- [Brevo API limits](https://developers.brevo.com/docs/api-limits): general transactional email endpoint 1,000 requests/second, separate from daily credits.
- [Sender verification](https://help.brevo.com/hc/en-us/articles/208836149-Create-a-new-sender-From-name-and-From-email)
- [Supabase pricing](https://supabase.com/pricing): Free 500 MB DB, shared resources, 200 peak Realtime connections, 2 million Realtime messages/month.
- [Edge pricing](https://supabase.com/docs/guides/functions/pricing): 500,000 Free invocations/month.
- [Edge limits](https://supabase.com/docs/guides/functions/limits): 256 MB memory, two-second CPU allowance, 150-second Free wall/idle limit.

1,000 simultaneous distinct real-email deliveries are not supported by this free configuration: the 300/day reservation budget rejects excess requests before sending; Free Realtime also allows only 200 peak connections. Unverified throughput is not a guarantee. The free mitigation is budget enforcement, per-rider throttling, idempotent retries and explicit capacity/error states, rather than a paid upgrade or unlimited queue.
