import { test } from "node:test";
import { Buffer } from "node:buffer";
import assert from "node:assert/strict";
import { createFcmSender, testPackage } from "./fcm.ts";
import { createPushHandler, matchesSecret } from "./handler.ts";
const job = {
  job_id: "job",
  lease: "lease",
  token: "synthetic-installation",
  broadcast_id: "12345678-1234-1234-1234-123456789abc",
};
test("worker secrets fail closed", () => {
  assert.equal(matchesSecret(null, "a".repeat(64)), false);
  assert.equal(matchesSecret("", ""), false);
  assert.equal(matchesSecret("a".repeat(64), "b".repeat(64)), false);
  assert.equal(matchesSecret("a".repeat(64), "a".repeat(64)), true);
});
test("worker authorization, lease completion, eligibility and bounded concurrency", async () => {
  let claimed = 0, sent = 0, finished = 0, active = 0, peak = 0;
  const handler = createPushHandler({
    workerKey: "a".repeat(64),
    ready: async () => {},
    authorize: async (jwt) => jwt === "admin",
    claim: async () => {
      claimed++;
      return Array.from(
        { length: 12 },
        (_, i) => ({ ...job, job_id: String(i) }),
      );
    },
    eligible: async (j) => j.job_id !== "0",
    send: async () => {
      active++;
      peak = Math.max(peak, active);
      await new Promise((r) => setTimeout(r, 2));
      active--;
      sent++;
      return { kind: "ACCEPTED", providerMessage: "projects/test/messages/id" };
    },
    finish: async (j, o) => {
      if (j.job_id === "0") assert.equal(o.kind, "SKIPPED");
      finished++;
    },
  });
  const invoke = (headers = {}, body = "{}") =>
    handler(new Request("https://test/", { method: "POST", headers, body }));
  assert.equal((await invoke()).status, 403);
  assert.equal(claimed, 0);
  assert.equal(
    (await invoke({ authorization: "Bearer admin" }, "{")).status,
    400,
  );
  assert.equal(
    (await invoke({ authorization: "Bearer admin" }, '{"recipients":[]}'))
      .status,
    400,
  );
  const response = await invoke({ "x-fr30-worker-key": "a".repeat(64) });
  const result = await response.json();
  assert.equal(result.provider_accepted, 11);
  assert.equal(result.skipped, 1);
  assert.equal(result.device_receipt_confirmed, false);
  assert.equal(finished, 12);
  assert.equal(sent, 11);
  assert.ok(peak <= 4);
  assert.ok(!JSON.stringify(result).includes(job.token));
});
test("unavailable sender never claims jobs", async () => {
  const handler = createPushHandler({
    workerKey: "a".repeat(64),
    ready: async () => {
      throw Error("missing");
    },
    authorize: async () => true,
    claim: async () => {
      throw Error("must not claim");
    },
    eligible: async () => true,
    send: async () => ({ kind: "RETRY" }),
    finish: async () => {},
  });
  assert.equal(
    (await handler(
      new Request("https://test/", {
        method: "POST",
        headers: { authorization: "Bearer admin" },
      }),
    )).status,
    503,
  );
});
test("real RSA signing with simulated OAuth and FCM responses; no message contents in payload", async () => {
  const keys = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const der = await crypto.subtle.exportKey("pkcs8", keys.privateKey);
  const account = {
    project_id: "tez-rider",
    client_email: "sender@tez-rider.iam.gserviceaccount.com",
    private_key: "-----BEGIN PRIVATE KEY-----\n" +
      Buffer.from(der).toString("base64") + "\n-----END PRIVATE KEY-----",
  };
  let oauth = 0, mode = 200;
  const request: typeof fetch = async (input, init) => {
    if (String(input) === "https://oauth2.googleapis.com/token") {
      oauth++;
      const jwt = new URLSearchParams(String(init!.body)).get("assertion")!
        .split(".");
      const claims = JSON.parse(Buffer.from(jwt[1], "base64url").toString());
      assert.equal(
        claims.scope,
        "https://www.googleapis.com/auth/firebase.messaging",
      );
      assert.equal(
        await crypto.subtle.verify(
          "RSASSA-PKCS1-v1_5",
          keys.publicKey,
          Buffer.from(jwt[2], "base64url"),
          new TextEncoder().encode(jwt[0] + "." + jwt[1]),
        ),
        true,
      );
      return Response.json({
        access_token: "synthetic-oauth",
        expires_in: 3600,
      });
    }
    assert.equal(
      String(input),
      "https://fcm.googleapis.com/v1/projects/tez-rider/messages:send",
    );
    const body = JSON.parse(String(init!.body));
    assert.equal(body.message.android.restricted_package_name, testPackage);
    assert.equal(body.message.fid, job.token);
    assert.deepEqual(body.message.data, {
      kind: "fr30_broadcast",
      broadcast_id: job.broadcast_id,
    });
    assert.equal(body.message.notification, undefined);
    return mode === 200
      ? Response.json({ name: "projects/tez-rider/messages/synthetic" })
      : Response.json({
        error: {
          details: [{
            "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
            errorCode: mode === 404 ? "UNREGISTERED" : "OTHER",
          }],
        },
      }, { status: mode });
  };
  const sender = createFcmSender(account, "tez-rider", request);
  await Promise.all([sender.ready(), sender.ready()]);
  assert.equal(oauth, 1);
  assert.equal((await sender.send(job)).kind, "ACCEPTED");
  mode = 404;
  assert.equal((await sender.send(job)).kind, "INVALID_TOKEN");
  mode = 429;
  assert.equal((await sender.send(job)).kind, "RETRY");
  mode = 400;
  assert.equal((await sender.send(job)).kind, "REJECTED");
  mode = 401;
  assert.equal((await sender.send(job)).kind, "RETRY");
  await sender.ready();
  assert.equal(oauth, 2);
  assert.throws(() => createFcmSender(account, "different-project", request));
});
