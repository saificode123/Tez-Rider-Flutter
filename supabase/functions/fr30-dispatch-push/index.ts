import { createFcmSender, type PushJob, type PushOutcome } from "./fcm.ts";
import { createPushHandler } from "./handler.ts";
const base = Deno.env.get("SUPABASE_URL") ?? "";
if (base !== "https://igeisilhtmglgnqvllrx.supabase.co") {
  throw Error("Android push is authorized only on isolated TEST");
}
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const project = Deno.env.get("FR30_FIREBASE_PROJECT_ID") ?? "tez-rider-fe12b";
const workerKey = Deno.env.get("FR30_PUSH_WORKER_KEY") ?? "";
let sender: ReturnType<typeof createFcmSender> | undefined;
try {
  const raw = Deno.env.get("FR30_FIREBASE_SERVICE_ACCOUNT");
  if (raw) sender = createFcmSender(JSON.parse(raw), project);
} catch { /* Fail closed, never log credentials. */ }
async function rpc(name: string, body: unknown) {
  const response = await fetch(base + "/rest/v1/rpc/" + name, {
    method: "POST",
    headers: {
      apikey: service,
      Authorization: "Bearer " + service,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) throw Error("Worker database operation unconfirmed");
  return await response.json();
}
const handler = createPushHandler({
  workerKey,
  async ready() {
    if (!sender || !service || !anon) throw Error("Push not configured");
    await sender.ready();
  },
  async authorize(jwt) {
    const headers = { apikey: anon, Authorization: "Bearer " + jwt };
    const user = await fetch(base + "/auth/v1/user", {
      headers,
      signal: AbortSignal.timeout(8000),
    });
    if (!user.ok) return false;
    const status = await fetch(base + "/rest/v1/rpc/fr28_account_status", {
      method: "POST",
      headers: { ...headers, "Content-Type": "application/json" },
      body: "{}",
      signal: AbortSignal.timeout(8000),
    });
    if (!status.ok) return false;
    const account = await status.json();
    return account.code === "OK" && account.role === "admin" &&
      account.verification_status === "approved";
  },
  claim: () => rpc("fr30_claim_push", { p_limit: 50 }),
  eligible: (job: PushJob) =>
    rpc("fr30_push_eligible", { p_job: job.job_id, p_lease: job.lease }),
  send: (job: PushJob) => sender!.send(job),
  async finish(job: PushJob, outcome: PushOutcome | { kind: "SKIPPED" }) {
    const result = await rpc("fr30_finish_push", {
      p_job: job.job_id,
      p_lease: job.lease,
      p_outcome: outcome.kind,
      p_provider_message: "providerMessage" in outcome
        ? outcome.providerMessage
        : null,
    });
    if (
      result.code !== "RECORDED" && result.code !== "STALE_LEASE"
    ) throw Error("Push outcome unconfirmed");
  },
});
let active = 0;
Deno.serve(async (req) => {
  if (active >= 2) {
    return Response.json({ code: "BUSY" }, {
      status: 429,
      headers: { "Retry-After": "30", "Cache-Control": "no-store" },
    });
  }
  active++;
  try {
    return await handler(req);
  } finally {
    active--;
  }
});
