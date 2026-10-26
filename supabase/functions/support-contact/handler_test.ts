import { createSupportContactHandler } from "./handler.ts";
function check(value: unknown) { if (!value) throw Error("Assertion failed"); }
Deno.test("public configured contact works without sign-in and exposes only email", async () => {
  const r = await createSupportContactHandler(async () => "support@example.test")(new Request("https://example.test"));
  check(r.status === 200); const value = await r.json(); check(value.email === "support@example.test" && Object.keys(value).length === 2);
});
for (const value of [null, "", "private\nheader@example.test", "not-email"]) Deno.test("invalid or missing contact fails closed: " + String(value), async () => {
  const r = await createSupportContactHandler(async () => value)(new Request("https://example.test")); check(r.status === 503);
});
Deno.test("caller cannot select another setting or write through public endpoint", async () => {
  let calls = 0; const handler = createSupportContactHandler(async () => { calls++; return "support@example.test"; });
  check((await handler(new Request("https://example.test?setting=groq_api_key"))).status === 400);
  check((await handler(new Request("https://example.test", { method: "POST", body: "{}" }))).status === 405); check(calls === 0);
});
Deno.test("backend failure reveals no server detail", async () => {
  const r = await createSupportContactHandler(async () => { throw Error("private provider credential"); })(new Request("https://example.test"));
  check(r.status === 503 && !(await r.text()).includes("private"));
});
