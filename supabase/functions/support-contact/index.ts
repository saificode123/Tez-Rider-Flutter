import { serveSecurity, applicationFetch } from "../_shared/security-runtime.ts";
import { createSupportContactHandler } from "./handler.ts";
const base = Deno.env.get("SUPABASE_URL") ?? "";
if (base !== "https://igeisilhtmglgnqvllrx.supabase.co") throw Error("Isolated TEST required");
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
let cached: string | undefined, expires = 0;
let pending: Promise<unknown> | undefined;
async function read(): Promise<unknown> {
  if (cached && Date.now() < expires) return cached;
  if (pending) return pending;
  pending = (async () => {
    // Fixed public contact projection only; no client-selected setting or user data.
    const result = await applicationFetch(base + "/rest/v1/app_settings?setting_key=eq.support_email&select=setting_value&limit=1", {
      headers: { apikey: service, Authorization: "Bearer " + service }, signal: AbortSignal.timeout(8000),
    });
    if (!result.ok) throw Error("UNAVAILABLE");
    const rows = await result.json();
    const value = rows?.[0]?.setting_value;
    if (typeof value !== "string") throw Error("UNAVAILABLE");
    cached = value; expires = Date.now() + 60000; return value;
  })();
  try { return await pending; } finally { pending = undefined; }
}
// Deliberately public GET: blocked/signed-out people may read only this contact.
serveSecurity("support-contact", createSupportContactHandler(read));
