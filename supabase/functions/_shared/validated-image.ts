// Byte validation shared by new product media; existing accepted pipelines remain unchanged.
export class Failure extends Error { constructor(public status:number,message:string) {super(message);} }
export async function validateImage(bytes:Uint8Array,mime:string) {
 if(!bytes.length||bytes.length>5242880)throw new Failure(413,'Maximum image size is 5 MB.');
 if(!['image/png','image/jpeg'].includes(mime))throw new Failure(415,'Select a JPEG or PNG image.');
 try {
  if(mime==='image/png') {
   if(![137,80,78,71,13,10,26,10].every((v,i)=>bytes[i]===v)||bytes.length<33)throw Error();
   const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
   if(!view.getUint32(16)||!view.getUint32(20)||view.getUint32(16)>2048||view.getUint32(20)>2048)throw Error();
   const [{default:pngjs},{Buffer}]=await Promise.all([import('npm:pngjs@7.0.0'),import('node:buffer')]);
   pngjs.PNG.sync.read(Buffer.from(bytes),{checkCRC:true});
  } else {
   const {default:jpeg}=await import('npm:jpeg-js@0.4.4');
   const image=jpeg.decode(bytes,{useTArray:true,maxResolutionInMP:4,maxMemoryUsageInMB:64,tolerantDecoding:false});
   if(!image.width||!image.height||image.width>2048||image.height>2048)throw Error();
  }
 }catch(_){throw new Failure(422,'This file is not a valid JPEG or PNG image.');}
}
export const imageDigest=async(bytes:Uint8Array)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new Uint8Array(bytes)))).map(v=>v.toString(16).padStart(2,'0')).join('');
