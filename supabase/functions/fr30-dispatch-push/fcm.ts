export const testPackage = "com.example.flutter_application_1.fr21test";
export type PushJob = {
  job_id: string;
  lease: string;
  token: string;
  broadcast_id: string;
};
export type PushOutcome = {
  kind: "ACCEPTED" | "RETRY" | "INVALID_TOKEN" | "REJECTED";
  providerMessage?: string;
};
type Account = {
  project_id: string;
  client_email: string;
  private_key: string;
};
const encode = (value: Uint8Array) =>
  btoa(String.fromCharCode(...value)).replaceAll("+", "-").replaceAll("/", "_")
    .replaceAll("=", "");
const json64 = (value: unknown) =>
  encode(new TextEncoder().encode(JSON.stringify(value)));

export function createFcmSender(
  account: Account,
  project: string,
  request: typeof fetch = fetch,
  now = () => Date.now(),
) {
  if (
    !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(project) ||
    account.project_id !== project ||
    !account.client_email?.endsWith(".gserviceaccount.com") ||
    !account.private_key?.includes("BEGIN PRIVATE KEY")
  ) throw Error("Invalid server Firebase configuration");
  let cached: { value: string; expires: number } | undefined,
    inflight: Promise<string> | undefined;
  let key: Promise<CryptoKey> | undefined;
  async function access(): Promise<string> {
    if (cached && cached.expires > now() + 60000) return cached.value;
    if (inflight) return inflight;
    inflight = (async () => {
      const pem = account.private_key.replace(/-----[^-]+-----|\s/g, "");
      key ??= crypto.subtle.importKey(
        "pkcs8",
        Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["sign"],
      );
      const time = Math.floor(now() / 1000);
      const unsigned = json64({ alg: "RS256", typ: "JWT" }) + "." +
        json64({
          iss: account.client_email,
          scope: "https://www.googleapis.com/auth/firebase.messaging",
          aud: "https://oauth2.googleapis.com/token",
          iat: time,
          exp: time + 3600,
        });
      const signature = await crypto.subtle.sign(
        "RSASSA-PKCS1-v1_5",
        await key,
        new TextEncoder().encode(unsigned),
      );
      const response = await request("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
          assertion: unsigned + "." + encode(new Uint8Array(signature)),
        }),
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok) {
        throw Error("Firebase server authorization unavailable");
      }
      const body = await response.json();
      if (
        typeof body.access_token !== "string" ||
        !Number.isFinite(body.expires_in) || body.expires_in < 120
      ) throw Error("Invalid OAuth response");
      cached = {
        value: body.access_token,
        expires: now() + Math.min(body.expires_in, 3600) * 1000,
      };
      return cached.value;
    })();
    try {
      return await inflight;
    } finally {
      inflight = undefined;
    }
  }
  return {
    ready: access,
    async send(job: PushJob): Promise<PushOutcome> {
      try {
        // FID registration API, Android TEST restriction, and no confidential content.
        const response = await request(
          "https://fcm.googleapis.com/v1/projects/" +
            encodeURIComponent(project) + "/messages:send",
          {
            method: "POST",
            headers: {
              Authorization: "Bearer " + await access(),
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              message: {
                fid: job.token,
                data: {
                  kind: "fr30_broadcast",
                  broadcast_id: job.broadcast_id,
                },
                android: {
                  priority: "HIGH",
                  ttl: "3600s",
                  restricted_package_name: testPackage,
                },
              },
            }),
            signal: AbortSignal.timeout(8000),
          },
        );
        const body = await response.json().catch(() => ({}));
        if (response.ok) {
          if (
            typeof body.name !== "string" ||
            !body.name.startsWith("projects/" + project + "/messages/") ||
            body.name.length > 300
          ) return { kind: "RETRY" };
          return { kind: "ACCEPTED", providerMessage: body.name };
        }
        if (response.status === 401) {
          cached = undefined;
          return { kind: "RETRY" };
        }
        const codes = (body.error?.details ?? []).filter((
          d: Record<string, unknown>,
        ) =>
          d["@type"] === "type.googleapis.com/google.firebase.fcm.v1.FcmError"
        ).map((d: Record<string, unknown>) => d.errorCode);
        if (
          codes.some((c: string) =>
            ["UNREGISTERED", "SENDER_ID_MISMATCH"].includes(c)
          )
        ) return { kind: "INVALID_TOKEN" };
        if (
          [408, 429, 500, 502, 503, 504].includes(response.status) ||
          response.status === 403
        ) return { kind: "RETRY" };
        return { kind: "REJECTED" };
      } catch {
        return { kind: "RETRY" };
      }
    },
  };
}
