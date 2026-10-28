# Smart Assistant evaluation

Status: targeted quality repair verified; exhaustive acceptance remains PARTIAL.

## Architecture and consent

Existing Groq model openai/gpt-oss-120b and server-held credential retained. Owner explicitly approved minimal order ID/status/dates and public product names/prices/stock to the existing provider, then separately approved up to six recent chat messages. No new paid service. Existing app limit remains 10 requests/minute; provider free quota and availability are external limits, not an unlimited service guarantee.

Caller JWT and existing ownership-checked RPCs supply data. No service-role read of private orders. At most five recent owned orders and twenty visible catalogue products are projected, with explicit sample limits. No address, phone, CNIC, customer name, private media or provider credentials are selected. Conversation content can contain what users type, as explicitly approved. Missing/denied reads never become fabricated stock/order state. A final account-access check suppresses a response after revocation.

## Measured defects and corrections

Initial 12-case live run: 7 PASS, 5 FAIL under bounded semantic review. Failures: physical receipt promise, INR symbol instead of PKR, unrelated essay, ungrounded refund-record statement, invented navigation control. A second full run fixed those broad defects but exposed Urdu payment/OTP conflation and a section-heading-as-button instruction. Targeted reruns corrected language/navigation. A receipt promise recurred: added a deterministic output check for that known failure and wrong currency, one provider correction attempt, and visible unavailable failure if still invalid. No static chatbot replacement or fabricated successful operation.

Plain-text normalization removes bold/heading syntax for the existing Text widget. Urdu suggestions/errors, responsive message title and explicit send busy state were added. History is bounded and screen-local; cross-account in-flight results are discarded.

## Results

- Latest reviewed sample for each of 12 case types: PASS across successive runs. This is not 12 fresh samples on the final version. Only affected cases were rerun after corrections.
- Cases: English/Urdu payment, actual catalogue sample, absent product, recent owned orders, invalid order, ambiguity, unsupported request, private-data injection, refund uncertainty, navigation, follow-up.
- 35 Deno tests PASS: validation, history-role injection, bounded payload, rate limit, provider failure, credential echo rejection, revocation, ownership-RPC use, projection, Unicode, catalogue failure, formatting and factual-output guards.
- Flutter conversation tests pass within the 46-case focused suite. A separate 45-case notification/location suite also passes.
- Deno entrypoint check PASS. Deployed only shopping-assistant to TEST; no schema or production change.
- Live requests generally took about 3–8 seconds. No lower-latency or production availability guarantee.

Evidence: ../evidence/REPAIR-assistant-evaluation.json records failures, responses, targeted reruns and final source hashes. Reproducible harness: tests/integration/REPAIR-assistant-eval.py. Synthetic TEST records were read; they are not fabricated app responses. Existing catalogue fixture names remain unchanged.

## Limits

Catalogue lookup currently supplies a bounded first-page sample, not semantic full-catalogue search. Store hours and refund state are unavailable. Assistant cannot perform operations. Unauthorized ownership and network/provider-failure behavior are covered by local tests, not a new hosted negative-order ownership journey or induced provider outage. More adversarial and repeated evaluations remain necessary; model outputs can still be wrong outside measured checks.

Read-only hosted grounding check: sampled order status and product name/price/confirmed stock matched actual caller-authorized RPC responses; invalid order was denied. See ../evidence/REPAIR-assistant-grounding.json.
