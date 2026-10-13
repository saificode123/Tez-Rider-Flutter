const base = Deno.env.get("SUPABASE_URL") ?? "";
const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const localLoadTest = Deno.env.get("FR04_LOCAL_LOAD_TEST") === "true"
  && (base === "http://kong:8000" || base === "http://127.0.0.1:54321" || base === "http://localhost:54321");
const publicBase = localLoadTest ? "http://127.0.0.1:54321" : base;
const bucket = "rider-cnic";
const maxFile = 5 * 1024 * 1024;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-region",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
class Failure extends Error {
  constructor(public status: number, message: string) { super(message); }
}
function reply(status: number, value: unknown, timings?: Record<string, number>): Response {
  return new Response(JSON.stringify(value), { status, headers: {
    ...cors, "Content-Type": "application/json", "Cache-Control": "no-store",
    ...(timings ? { "Server-Timing": Object.entries(timings)
      .map(([name, duration]) => `${name};dur=${duration.toFixed(1)}`).join(", ") } : {}),
  } });
}
async function api(path: string, token: string, method = "GET", body?: unknown): Promise<any> {
  const key = token === service ? service : anon;
  const result = await fetch(base + path, { method,
    headers: { apikey: key, Authorization: "Bearer " + token, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000) });
  const data = await result.json();
  if (!result.ok) {
    const code = data.code;
    if (code === "42501") throw new Failure(403, "You are not authorized for this CNIC operation.");
    if (code === "PT409") throw new Failure(409, "Another upload is in progress. Retry the same submission.");
    if (code === "22023") throw new Failure(422, "The document or submission is missing or invalid.");
    throw new Failure(result.status >= 500 ? 503 : 400, "The CNIC operation could not be confirmed. Retry.");
  }
  return data;
}
async function readJson(req: Request): Promise<any> {
  if (!req.body) throw new Failure(400, "A request body is required.");
  const reader = req.body.getReader(); const parts: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.length;
      if (size > 7 * 1024 * 1024) { await reader.cancel(); throw new Failure(413, "Maximum image size is 5 MB."); }
      parts.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const part of parts) { bytes.set(part, offset); offset += part.length; }
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch (error) {
    if (error instanceof Failure) throw error;
    throw new Failure(400, "Invalid request body.");
  } finally { reader.releaseLock(); }
}
async function validateImage(bytes: Uint8Array, mime: string): Promise<string> {
  if (!bytes.length || bytes.length > maxFile) throw new Failure(413, "Maximum image size is 5 MB.");
  if (mime !== "image/jpeg" && mime !== "image/png") throw new Failure(415, "Select a JPEG or PNG image.");
  try {
    if (mime === "image/png") {
      const signature = [137, 80, 78, 71, 13, 10, 26, 10];
      if (!signature.every((b, i) => bytes[i] === b) || bytes.length < 33) throw Error();
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      const width = view.getUint32(16); const height = view.getUint32(20);
      if (!width || !height || width > 2048 || height > 2048) throw Error();
      // Decode and check CRC/inflate structure; magic bytes alone are insufficient.
      const [{ default: pngjs }, { Buffer }] = await Promise.all([
        import("npm:pngjs@7.0.0"), import("node:buffer"),
      ]);
      pngjs.PNG.sync.read(Buffer.from(bytes), { checkCRC: true });
      return "png";
    }
    if (bytes[0] !== 255 || bytes[1] !== 216 || bytes[2] !== 255) throw Error();
    const { default: jpeg } = await import("npm:jpeg-js@0.4.4");
    const decoded = jpeg.decode(bytes, { useTArray: true, maxResolutionInMP: 4,
      maxMemoryUsageInMB: 64, tolerantDecoding: false });
    if (!decoded.width || !decoded.height || decoded.width > 2048 || decoded.height > 2048) throw Error();
    return "jpg";
  } catch (_) { throw new Failure(422, "The file is not a valid supported image. Select another JPEG or PNG."); }
}

async function authenticatedIdentity(token: string): Promise<any> {
  const auth = await fetch(base + "/auth/v1/user", { headers: { apikey: anon, Authorization: "Bearer " + token },
    signal: AbortSignal.timeout(10000) });
  if (!auth.ok) throw new Failure(401, "Your session expired. Sign in again.");
  const identity = await auth.json();
  if (!identity.email_confirmed_at) throw new Failure(403, "Verify your email first.");
  return identity;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Use POST." });
  try {
    if ((base !== "https://igeisilhtmglgnqvllrx.supabase.co" && !localLoadTest) || !anon || !service)
      throw new Failure(503, "Dedicated TEST configuration is required.");
    const match = /^Bearer (\S+)$/.exec(req.headers.get("Authorization") ?? "");
    if (!match) throw new Failure(401, "Sign in before submitting or viewing a CNIC document.");
    const token = match[1];
    const input = await readJson(req);
    if (input.action === "view") {
      const started = performance.now();
      const timings: Record<string, number> = {};
      async function measured<T>(name: string, operation: () => Promise<T>): Promise<T> {
        const start = performance.now();
        try { return await operation(); }
        finally { timings[name] = performance.now() - start; }
      }
      if (input.user_id !== undefined && !/^\d+$/.test(String(input.user_id))) throw new Failure(400, "Invalid rider identity.");
      // Independent read-only checks run together. Both must succeed before signing.
      // The database RPC independently authenticates and authorizes this same JWT.
      const [, authority] = await Promise.all([
        measured("auth", () => authenticatedIdentity(token)),
        measured("authority", () => api("/rest/v1/rpc/fr04_document_authority", token, "POST", {
          p_user_id: input.user_id === undefined ? null : input.user_id,
        })),
      ]);
      const signed = await measured("signing", () => api("/storage/v1/object/sign/" + bucket + "/" + authority.path,
        service, "POST", { expiresIn: 900 }));
      const url = signed.signedURL ?? signed.signedUrl;
      if (typeof url !== "string") throw new Failure(503, "Document viewing is temporarily unavailable.");
      timings.handler = performance.now() - started;
      // Numeric stage durations only: no identity, token, document path or link.
      return reply(200, { url: publicBase + "/storage/v1" + url, expires_in: 900 }, timings);
    }
    if (input.action !== "upload") throw new Failure(400, "Unknown CNIC operation.");
    const identity = await authenticatedIdentity(token);
    // The client cannot choose an owner, bucket, path, expiry, or approval status.
    if (typeof input.cnic !== "string" || !/^([0-9]{13}|[0-9]{5}-[0-9]{7}-[0-9])$/.test(input.cnic))
      throw new Failure(422, "Enter a valid 13-digit CNIC number.");
    if (typeof input.request_id !== "string" || !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(input.request_id))
      throw new Failure(400, "Invalid submission identifier.");
    if (typeof input.image_base64 !== "string" || input.image_base64.length > Math.ceil(maxFile / 3) * 4)
      throw new Failure(413, "Maximum image size is 5 MB.");
    let bytes: Uint8Array;
    try { bytes = Uint8Array.from(atob(input.image_base64), (c) => c.charCodeAt(0)); }
    catch (_) { throw new Failure(422, "Invalid image encoding."); }
    const extension = await validateImage(bytes, input.mime_type);
    const digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)))
      .map((b) => b.toString(16).padStart(2, "0")).join("");
    const lease = await api("/rest/v1/rpc/fr04_begin_upload", service, "POST", {
      p_auth_uid: identity.id, p_request_id: input.request_id, p_digest: digest,
      p_extension: extension, p_cnic: input.cnic,
    });
    if (!lease.complete) {
      const upload = await fetch(base + "/storage/v1/object/" + bucket + "/" + lease.path, {
        method: "POST", headers: { apikey: service, Authorization: "Bearer " + service,
          "Content-Type": input.mime_type, "x-upsert": "true", "cache-control": "0" },
        body: bytes, signal: AbortSignal.timeout(30000),
      });
      if (!upload.ok) throw new Failure(503, "Upload was not confirmed. Retry this submission.");
      await api("/rest/v1/rpc/fr04_finish_upload", service, "POST", {
        p_auth_uid: identity.id, p_request_id: input.request_id, p_path: lease.path,
      });
    }
    return reply(200, { submission_status: "submitted", path: lease.path });
  } catch (error) {
    // Never log CNIC, request bodies, image bytes, credentials, or signed URLs.
    if (error instanceof Failure) return reply(error.status, { error: error.message });
    return reply(503, { error: "The document operation was not confirmed. Please retry." });
  }
});
