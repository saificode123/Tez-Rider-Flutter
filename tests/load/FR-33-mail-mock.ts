// Local-only SMTP acceptance stub. Never opens an outbound network connection.
let accepted=0;
Deno.serve({hostname:'127.0.0.1',port:8789},async req=>{
 if(req.method!=='POST'||new URL(req.url).pathname!=='/send')return new Response(null,{status:404});
 const body=await req.json();
 if(!body.to?.[0]?.email?.endsWith('@example.test')||typeof body.textContent!=='string')return new Response(null,{status:400});
 accepted++;return Response.json({messageId:'FR33-LOCAL-MOCK-'+accepted},{status:201});
});
