export function createSupportContactHandler(read: () => Promise<unknown>) {
  const headers = { "Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=60" };
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
    if (request.method !== "GET") return Response.json({ code: "METHOD_NOT_ALLOWED" }, { status: 405, headers });
    if (new URL(request.url).search) return Response.json({ code: "INVALID_INPUT" }, { status: 400, headers });
    try {
      const email = await read();
      if (typeof email !== "string" || email.length > 254 || !/^[^@\s\x00-\x1f\x7f]+@[^@\s\x00-\x1f\x7f]+\.[^@\s\x00-\x1f\x7f]+$/.test(email)) throw Error("UNAVAILABLE");
      return Response.json({ code: "OK", email }, { headers });
    } catch {
      return Response.json({ code: "SUPPORT_CONTACT_UNAVAILABLE" }, { status: 503, headers: { ...headers, "Cache-Control": "no-store" } });
    }
  };
}
