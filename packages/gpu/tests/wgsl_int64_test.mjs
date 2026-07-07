import { K, buildWGSL, scalarLayout } from "../web/kernels_wgsl.js";
const adapter = await navigator.gpu.requestAdapter(); const device = await adapter.requestDevice();
const ST = GPUBufferUsage.STORAGE|GPUBufferUsage.COPY_SRC|GPUBufferUsage.COPY_DST, UN = GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST;
function sbuf(bytes){const b=device.createBuffer({size:Math.max(4,bytes.byteLength),usage:ST});device.queue.writeBuffer(b,0,bytes);return b;}
function packScalars(name,vals){const lay=scalarLayout(name);const ab=new ArrayBuffer(Math.max(16,Math.ceil(lay.length*4/16)*16));const iv=new Int32Array(ab),fv=new Float32Array(ab);lay.forEach(([n,t],i)=>{if(t==="f")fv[i]=vals[i];else iv[i]=vals[i];});return ab;}
// storage: array of {bytes, outWords?} ; returns Float32 or Int32 view of out
async function run(name, storages, scalarVals, outIdx, total, outIsI64){
  const pipe=device.createComputePipeline({layout:"auto",compute:{module:device.createShaderModule({code:buildWGSL(name)}),entryPoint:"main"}});
  const bufs=storages.map(sbuf);
  const uni=device.createBuffer({size:16,usage:UN});device.queue.writeBuffer(uni,0,packScalars(name,scalarVals));
  const entries=bufs.map((b,i)=>({binding:i,resource:{buffer:b}}));entries.push({binding:bufs.length,resource:{buffer:uni}});
  const bg=device.createBindGroup({layout:pipe.getBindGroupLayout(0),entries});
  const enc=device.createCommandEncoder();const pass=enc.beginComputePass();pass.setPipeline(pipe);pass.setBindGroup(0,bg);
  const groups=Math.ceil(total/64);pass.dispatchWorkgroups(Math.min(groups,65535),Math.ceil(groups/65535));pass.end();
  const sz=storages[outIdx].byteLength;const rb=device.createBuffer({size:sz,usage:GPUBufferUsage.COPY_DST|GPUBufferUsage.MAP_READ});
  enc.copyBufferToBuffer(bufs[outIdx],0,rb,0,sz);device.queue.submit([enc.finish()]);await rb.mapAsync(GPUMapMode.READ);
  const ab=rb.getMappedRange().slice(0);return outIsI64?Array.from(new BigInt64Array(ab)).map(Number):Array.from(new Float32Array(ab));
}
const i64 = arr => { const b=new BigInt64Array(arr.map(BigInt)); return new Uint8Array(b.buffer); };
const f32 = arr => new Float32Array(arr);
let pass=0,fail=0; const ck=(n,ok,d)=>{console.log(`${ok?"PASS":"FAIL"} ${n} ${d}`);ok?pass++:fail++;};
// argmaxk: outer2 ax4
{ const X=[3,1,4,1, 5,9,2,6]; 
  // simpler: X buffer f32, Y int64
  const Xb=f32(X); const Yb=new Uint8Array(2*8);
  const o=await run("argmaxk",[Xb,Yb],[2,4],1,2,true); ck("argmaxk",o[0]===2&&o[1]===1,`[${o}]`); }
// argmaxk_i64: outer2 ax4 int64 in
{ const X=[3,1,4,1, 5,9,2,6]; const Xb=new BigInt64Array(X.map(BigInt)); const Yb=new Uint8Array(2*8);
  const o=await run("argmaxk_i64",[new Uint8Array(Xb.buffer),Yb],[2,4],1,2,true); ck("argmaxk_i64",o[0]===2&&o[1]===1,`[${o}]`); }
// gather: D (outer1, axis_in3, inner2), idx=[2,0], → out (1,2,2)
{ const D=f32([10,11, 20,21, 30,31]); const idx=new BigInt64Array([2n,0n]); const Y=f32(new Array(4).fill(0));
  const o=await run("gather",[D,new Uint8Array(idx.buffer),Y],[1,3,2,2],2,4,false);
  ck("gather",JSON.stringify(o)===JSON.stringify([30,31,10,11]),`[${o}]`); }
// eos_gather: B1 L3 D2, tok=[1,5,2] → pos=1, Y=data[1,:]
{ const data=f32([0,0, 7,8, 0,0]); const tok=new BigInt64Array([1n,5n,2n]); const Y=f32([0,0]);
  const o=await run("eos_gather",[data,new Uint8Array(tok.buffer),Y],[1,3,2],2,2,false);
  ck("eos_gather",JSON.stringify(o)===JSON.stringify([7,8]),`[${o}]`); }
console.log(`\n=== ${pass} PASS · ${fail} FAIL ===`); if(fail)Deno.exit(1);
