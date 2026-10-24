import {Failure, validateImage, imageDigest} from './validated-image.ts';
import pngjs from 'npm:pngjs@7.0.0';
import jpeg from 'npm:jpeg-js@0.4.4';
import {Buffer} from 'node:buffer';
const assert=(value:unknown)=>{if(!value)throw Error('Assertion failed');};
async function rejects(bytes:Uint8Array,mime:string,status:number){try{await validateImage(bytes,mime);}catch(error){assert(error instanceof Failure&&error.status===status);return;}throw Error('Invalid file accepted');}
const png=()=>new Uint8Array(pngjs.PNG.sync.write({width:1,height:1,data:Buffer.from([0,128,0,255])}));
Deno.test('valid decoded PNG accepted',async()=>{await validateImage(png(),'image/png');});
Deno.test('valid decoded JPEG accepted',async()=>{const bytes=jpeg.encode({width:1,height:1,data:new Uint8Array([0,128,0,255])},80).data;await validateImage(bytes,'image/jpeg');});
Deno.test('empty and oversize contents rejected',async()=>{await rejects(new Uint8Array(),'image/png',413);await rejects(new Uint8Array(5242881),'image/png',413);});
Deno.test('claimed HTML and SVG MIME rejected',async()=>{await rejects(new TextEncoder().encode('<script>bad</script>'),'text/html',415);await rejects(new TextEncoder().encode('<svg/>'),'image/svg+xml',415);});
Deno.test('forged PNG MIME cannot hide HTML contents',async()=>{await rejects(new TextEncoder().encode('<script>bad</script>'),'image/png',422);});
Deno.test('PNG CRC corruption rejected',async()=>{const bytes=png();bytes[45]^=255;await rejects(bytes,'image/png',422);});
Deno.test('oversize PNG dimensions rejected before decoding allocation',async()=>{const bytes=png();new DataView(bytes.buffer).setUint32(16,2049);await rejects(bytes,'image/png',422);});
Deno.test('zero PNG dimensions rejected',async()=>{const bytes=png();new DataView(bytes.buffer).setUint32(20,0);await rejects(bytes,'image/png',422);});
Deno.test('truncated JPEG and PNG rejected',async()=>{await rejects(new Uint8Array([255,216,255]),'image/jpeg',422);await rejects(png().subarray(0,30),'image/png',422);});
Deno.test('digest reflects exact bytes and is stable across retries',async()=>{const bytes=png();const hash=await imageDigest(bytes);assert(/^[a-f0-9]{64}$/.test(hash));assert(hash===await imageDigest(new Uint8Array(bytes)));bytes[45]^=1;assert(hash!==await imageDigest(bytes));});
