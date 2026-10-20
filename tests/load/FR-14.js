// Equivalent open-source load runner: Node.js built-ins only, no dependencies.
// Run only through FR-14-load.py; credentials come from an ignored local fixture.
const fs = require('node:fs');
const {performance} = require('node:perf_hooks');
async function main() {
  const config = JSON.parse(fs.readFileSync(process.env.FR14_LOAD_CONFIG, 'utf8'));
  if (config.base !== 'http://127.0.0.1:54330' || config.scope !== 'LOCAL only') throw Error('LOCAL only');
  const latency = [], codes = {}; let unexpected = 0, disclosures = 0, success = 0, fallback = 0, denied = 0;
  const vus = Math.min(1000, Number(process.env.FR14_VUS || 10));
  await Promise.all(Array.from({length: vus}, async (_, vu) => {
    for (let n = 0; n < 5; n++) {
      const unauthorized = n === 4;
      const started = performance.now();
      try {
        const r = await fetch(config.base, {method:'POST',headers:{Authorization:'Bearer '+(unauthorized ? config.other : config.customer),'Content-Type':'application/json'},body:JSON.stringify({orderId:config.order})});
        const data = await r.json(); latency.push(performance.now()-started);
        const code=r.status+':'+String(data.code);codes[code]=(codes[code]||0)+1;
        if (unauthorized) { if (data.route) disclosures++; else if (r.status === 403) denied++; else unexpected++; }
        else if (r.status === 200 && data.route) { success++; if (data.route.isApproximate) fallback++; }
        else if (r.status !== 429) unexpected++;
      } catch { unexpected++; }
    }
  }));
  latency.sort((a,b)=>a-b);const p95=latency[Math.max(0,Math.ceil(latency.length*.95)-1)]||Infinity;
  const stats=await(await fetch(config.base+'/stats')).json();
  const result={scope:'LOCAL Supabase HTTP with mocked provider',vus,requests:vus*5,p95Ms:p95,unexpectedErrors:unexpected,unexpectedErrorRate:unexpected/(vus*5),unauthorizedDisclosures:disclosures,authorizedSuccesses:success,denied,fallbackResponses:fallback,providerCalls:stats.providerCalls,providerMocked:true,codes};
  fs.writeFileSync(config.output,JSON.stringify(result,null,2));console.log(JSON.stringify(result));
  if(unexpected/(vus*5)>=.01||disclosures||stats.providerCalls!==1||p95>=800||success===0)process.exitCode=1;
}
main().catch(()=>{console.error('Local load runner failed; no credentials emitted');process.exitCode=1;});
