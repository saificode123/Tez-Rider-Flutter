import type { PushJob, PushOutcome } from "./fcm.ts";
export interface PushDependencies {
  workerKey: string;
  ready(): Promise<unknown>;
  authorize(jwt: string): Promise<boolean>;
  claim(): Promise<PushJob[]>;
  eligible(job: PushJob): Promise<boolean>;
  send(job: PushJob): Promise<PushOutcome>;
  finish(
    job: PushJob,
    outcome: PushOutcome | { kind: "SKIPPED" },
  ): Promise<void>;
}
export function matchesSecret(
  actual: string | null,
  expected: string,
): boolean {
  if (!actual || expected.length < 32 || actual.length !== expected.length) {
    return false;
  }
  let different = 0;
  for (let i = 0; i < expected.length; i++) {
    different |= actual.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return different === 0;
}
export function createPushHandler(deps: PushDependencies) {
  const headers = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization,apikey,content-type,x-fr30-worker-key",
    "Cache-Control": "no-store",
  };
  const result = (body: unknown, status = 200) =>
    Response.json(body, { status, headers });
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers });
    }
    if (req.method !== "POST") {
      return result({ code: "METHOD_NOT_ALLOWED" }, 405);
    }
    try {
      const bearer = /^Bearer ([^\s]+)$/.exec(
        req.headers.get("Authorization") ?? "",
      )?.[1];
      if (
        !matchesSecret(req.headers.get("x-fr30-worker-key"), deps.workerKey) &&
        (!bearer || !await deps.authorize(bearer))
      ) return result({ code: "FORBIDDEN" }, 403);
      const text = await req.text();
      if (text.length > 2048) return result({ code: "INVALID_INPUT" }, 400);
      let body: unknown;
      try {
        body = text ? JSON.parse(text) : {};
      } catch {
        return result({ code: "INVALID_INPUT" }, 400);
      }
      if (
        !body || typeof body !== "object" || Array.isArray(body) ||
        Object.keys(body).some((k) => k !== "source")
      ) return result({ code: "INVALID_INPUT" }, 400);
      await deps.ready(); // Do not claim jobs if credentials are absent/invalid.
      const jobs = await deps.claim();
      if (jobs.length > 50) throw Error("Worker batch exceeded");
      const counts = {
        claimed: jobs.length,
        provider_accepted: 0,
        retry: 0,
        skipped: 0,
        failed: 0,
      };
      let next = 0;
      await Promise.all(
        Array.from({ length: Math.min(4, jobs.length) }, async () => {
          while (next < jobs.length) {
            const job = jobs[next++];
            const outcome = await deps.eligible(job)
              ? await deps.send(job)
              : { kind: "SKIPPED" } as const;
            await deps.finish(job, outcome);
            if (outcome.kind === "ACCEPTED") counts.provider_accepted++;
            else if (outcome.kind === "RETRY") counts.retry++;
            else if (outcome.kind === "SKIPPED") counts.skipped++;
            else counts.failed++;
          }
        }),
      );
      return result({
        code: "PROCESSED",
        ...counts,
        device_receipt_confirmed: false,
      });
    } catch {
      return result({ code: "PUSH_RETRY_PENDING" }, 503);
    }
  };
}
