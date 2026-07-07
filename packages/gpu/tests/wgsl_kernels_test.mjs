import { K, buildWGSL, scalarLayout, dispatchInvocations } from "../web/kernels_wgsl.js";
const adapter = navigator.gpu && await navigator.gpu.requestAdapter();
if (!adapter) { console.log('no WebGPU adapter'); Deno.exit(2); }
const device = await adapter.requestDevice();
const ST = GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST;
const UN = GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST;
const sbuf = d => { const b = device.createBuffer({size:Math.max(4,d.byteLength),usage:ST}); device.queue.writeBuffer(b,0,d); return b; };
function packScalars(name, vals) {
  const lay = scalarLayout(name);
  const ab = new ArrayBuffer(Math.max(16, Math.ceil(lay.length*4/16)*16));
  const iv = new Int32Array(ab), fv = new Float32Array(ab);
  lay.forEach(([n,t],i) => { if (t==="f") fv[i]=vals[i]; else iv[i]=vals[i]; });
  return ab;
}
// run: storageArrays (Float32Array|Int32Array), scalarVals (in param order), outIdx, total
async function run(name, storageArrays, scalarVals, outIdx, total) {
  const wgsl = buildWGSL(name);
  let mod, pipe;
  try {
    mod = device.createShaderModule({ code: wgsl });
    pipe = device.createComputePipeline({ layout:"auto", compute:{ module:mod, entryPoint:"main" } });
  } catch(e) { return { err: "compile: " + e.message }; }
  const bufs = storageArrays.map(sbuf);
  const uni = device.createBuffer({size:Math.max(16,packScalars(name,scalarVals).byteLength),usage:UN});
  device.queue.writeBuffer(uni, 0, packScalars(name, scalarVals));
  const entries = bufs.map((b,i)=>({binding:i,resource:{buffer:b}}));
  entries.push({binding:bufs.length,resource:{buffer:uni}});
  const bg = device.createBindGroup({layout:pipe.getBindGroupLayout(0),entries});
  const enc = device.createCommandEncoder();
  const pass = enc.beginComputePass(); pass.setPipeline(pipe); pass.setBindGroup(0,bg);
  const groups = Math.ceil(dispatchInvocations(name, scalarVals, total)/64); const gx = Math.min(groups,65535), gy = Math.ceil(groups/65535);
  pass.dispatchWorkgroups(gx, gy); pass.end();
  const outLen = storageArrays[outIdx].length;
  const rb = device.createBuffer({size:outLen*4,usage:GPUBufferUsage.COPY_DST|GPUBufferUsage.MAP_READ});
  enc.copyBufferToBuffer(bufs[outIdx],0,rb,0,outLen*4);
  device.queue.submit([enc.finish()]);
  await rb.mapAsync(GPUMapMode.READ);
  return { out: Array.from(new Float32Array(rb.getMappedRange().slice(0))) };
}
const md = (a,b) => { let m=0; for(let i=0;i<a.length;i++) m=Math.max(m,Math.abs(a[i]-b[i])); return m; };
const rnd = n => Float32Array.from({length:n}, () => (Math.random()*4-2));
let pass=0, fail=0;
async function check(name, storage, scalars, outIdx, total, ref) {
  const r = await run(name, storage, scalars, outIdx, total);
  if (r.err) { console.log(`FAIL ${name}: ${r.err}`); fail++; return; }
  const d = md(r.out, ref);
  const ok = d < 1e-3;
  console.log(`${ok?"PASS":"FAIL"} ${name} maxdiff=${d.toExponential(2)}`);
  ok ? pass++ : fail++;
}

// ── references (JS mirrors of the CUDA-C) ──
{ const X=rnd(20); const ref=[...X].map(v=>v>0?v:0); await check("relu",[X,new Float32Array(20)],[20],1,20,ref); }
{ const X=rnd(20); const ref=[...X].map(v=>1/(1+Math.exp(-v))); await check("osigmoid",[X,new Float32Array(20)],[20],1,20,ref); }
{ const X=rnd(20); const a=0.1; const ref=[...X].map(v=>v>=0?v:a*v); await check("leakyrelu",[X,new Float32Array(20)],[20,a],1,20,ref); }
{ const X=rnd(20); const ref=[...X].map(v=>Math.min(1,Math.max(-0.5,v))); await check("clipk",[X,new Float32Array(20)],[20,-0.5,1],1,20,ref); }
{ const X=rnd(5); const ref=[]; for(let o=0;o<5;o++)for(let r=0;r<3;r++)ref.push(X[o]); await check("expandlast",[X,new Float32Array(15)],[5,3],1,15,ref); }
{ const erf=x=>{const s=x<0?-1:1;x=Math.abs(x);const t=1/(1+0.3275911*x);const y=1-((((1.061405429*t-1.453152027)*t+1.421413741)*t-0.284496736)*t+0.254829592)*t*Math.exp(-x*x);return s*y;};
  const X=rnd(20); const ref=[...X].map(erf); await check("erfk",[X,new Float32Array(20)],[20],1,20,ref); }
{ // resize_nn C1 H2 W2 → 4x4 (sh=sw=2)
  const C=1,H=2,W=2,OH=4,OW=4,sh=2,sw=2; const X=rnd(C*H*W); const ref=[];
  for(let c=0;c<C;c++)for(let oy=0;oy<OH;oy++)for(let ox=0;ox<OW;ox++)ref.push(X[(c*H+(oy>>1))*W+(ox>>1)]);
  await check("resize_nn",[X,new Float32Array(C*OH*OW)],[C,H,W,OH,OW,sh,sw],1,C*OH*OW,ref); }
{ // eltwise full mul
  const n=16; const X=rnd(n),B=rnd(n); const ref=[...X].map((x,i)=>x*B[i]);
  await check("eltwise",[X,B,new Float32Array(n)],[n,1,0,2],2,n,ref); }
{ // eltwise per-channel add (bmode1)
  const n=12,per=4; const X=rnd(n),B=rnd(3); const ref=[...X].map((x,i)=>x+B[Math.floor(i/per)]);
  await check("eltwise",[X,B,new Float32Array(n)],[n,per,1,1],2,n,ref); }
{ // gemm 3x4 @ 4x2
  const M=3,N=2,K=4; const A=rnd(M*K),B=rnd(K*N); const ref=[];
  for(let r=0;r<M;r++)for(let c=0;c<N;c++){let s=0;for(let k=0;k<K;k++)s+=A[r*K+k]*B[k*N+c];ref.push(s);}
  await check("gemm",[A,B,new Float32Array([0]),new Float32Array(M*N)],[M,N,K,1,0,0,0],3,M*N,ref); }
{ // bmm 2 x (2x3 @ 3x2)
  const batch=2,M=2,N=2,Kd=3; const A=rnd(batch*M*Kd),B=rnd(batch*Kd*N); const ref=[];
  for(let b=0;b<batch;b++)for(let r=0;r<M;r++)for(let c=0;c<N;c++){let s=0;for(let k=0;k<Kd;k++)s+=A[b*M*Kd+r*Kd+k]*B[b*Kd*N+k*N+c];ref.push(s);}
  await check("bmm",[A,B,new Float32Array(batch*M*N)],[batch,M,N,Kd],2,batch*M*N,ref); }
{ // conv2d 2ch 4x4, 3 filters 3x3, stride1 pad1
  const Cin=2,H=4,W=4,Cout=3,kh=3,kw=3,ph=1,pw=1,sh=1,sw=1,OH=4,OW=4;
  const X=rnd(Cin*H*W),Wt=rnd(Cout*Cin*kh*kw),Bb=rnd(Cout); const ref=[];
  for(let oc=0;oc<Cout;oc++)for(let oh=0;oh<OH;oh++)for(let ow=0;ow<OW;ow++){let acc=Bb[oc];
    for(let ic=0;ic<Cin;ic++)for(let r=0;r<kh;r++){let ih=oh*sh-ph+r;if(ih<0||ih>=H)continue;
      for(let s=0;s<kw;s++){let iw=ow*sw-pw+s;if(iw<0||iw>=W)continue;acc+=X[(ic*H+ih)*W+iw]*Wt[((oc*Cin+ic)*kh+r)*kw+s];}}
    ref.push(acc);}
  await check("conv2d",[X,Wt,Bb,new Float32Array(Cout*OH*OW)],[Cin,H,W,Cout,kh,kw,OH,OW,ph,pw,sh,sw,1],3,Cout*OH*OW,ref); }
// conv2d again for every specialized path in the 4-outputs-per-thread
// kernel: k3s1 fast lane with OW not a multiple of 4 (tail lane), k3s2
// fast lane, k1s1 lane, and a k5 shape that must take the generic lane.
{ const convRef=(X,Wt,Bb,Cin,H,W,Cout,kh,kw,OH,OW,ph,pw,sh,sw)=>{const ref=[];
    for(let oc=0;oc<Cout;oc++)for(let oh=0;oh<OH;oh++)for(let ow=0;ow<OW;ow++){let acc=Bb[oc];
      for(let ic=0;ic<Cin;ic++)for(let r=0;r<kh;r++){let ih=oh*sh-ph+r;if(ih<0||ih>=H)continue;
        for(let s=0;s<kw;s++){let iw=ow*sw-pw+s;if(iw<0||iw>=W)continue;acc+=X[(ic*H+ih)*W+iw]*Wt[((oc*Cin+ic)*kh+r)*kw+s];}}
      ref.push(acc);}
    return ref;};
  const cases=[
    ["conv k3s1 OW=7 tail", 3,6,7, 2, 3,3, 1,1, 1,1],
    ["conv k3s2",           3,8,8, 2, 3,3, 1,1, 2,2],
    ["conv k1s1",           4,6,8, 3, 1,1, 0,0, 1,1],
    ["conv k5s1 generic",   2,9,9, 2, 5,5, 2,2, 1,1],
  ];
  for (const [label,Cin,H,W,Cout,kh,kw,ph,pw,sh,sw] of cases) {
    const OH=Math.floor((H+2*ph-kh)/sh)+1, OW=Math.floor((W+2*pw-kw)/sw)+1;
    const X=rnd(Cin*H*W),Wt=rnd(Cout*Cin*kh*kw),Bb=rnd(Cout);
    const ref=convRef(X,Wt,Bb,Cin,H,W,Cout,kh,kw,OH,OW,ph,pw,sh,sw);
    console.log(`  · ${label}`);
    await check("conv2d",[X,Wt,Bb,new Float32Array(Cout*OH*OW)],[Cin,H,W,Cout,kh,kw,OH,OW,ph,pw,sh,sw,1],3,Cout*OH*OW,ref);
  } }
{ // convtranspose2d 2ch 3x3, 2 out, 2x2 kernel stride2 pad0 → 6x6
  const Cin=2,H=3,W=3,Cout=2,kh=2,kw=2,sh=2,sw=2,ph=0,pw=0,OH=6,OW=6;
  const X=rnd(Cin*H*W),Wt=rnd(Cin*Cout*kh*kw),Bb=rnd(Cout); const ref=[];
  for(let oc=0;oc<Cout;oc++)for(let oy=0;oy<OH;oy++)for(let ox=0;ox<OW;ox++){let acc=Bb[oc];
    for(let ic=0;ic<Cin;ic++)for(let ky=0;ky<kh;ky++){let ty=oy+ph-ky;if(ty%sh!=0)continue;let iy=ty/sh;if(iy<0||iy>=H)continue;
      for(let kx=0;kx<kw;kx++){let tx=ox+pw-kx;if(tx%sw!=0)continue;let ix=tx/sw;if(ix<0||ix>=W)continue;
        acc+=X[(ic*H+iy)*W+ix]*Wt[(((ic*Cout)+oc)*kh+ky)*kw+kx];}}
    ref.push(acc);}
  await check("convtranspose2d",[X,Wt,Bb,new Float32Array(Cout*OH*OW)],[Cin,H,W,Cout,kh,kw,OH,OW,ph,pw,sh,sw,1],3,Cout*OH*OW,ref); }
{ // maxpool2d 1ch 4x4, 2x2 stride2
  const C=1,H=4,W=4,kh=2,kw=2,OH=2,OW=2,sh=2,sw=2,ph=0,pw=0; const X=rnd(C*H*W); const ref=[];
  for(let c=0;c<C;c++)for(let oh=0;oh<OH;oh++)for(let ow=0;ow<OW;ow++){let m=-1e30;
    for(let r=0;r<kh;r++){let ih=oh*sh-ph+r;if(ih<0||ih>=H)continue;for(let s=0;s<kw;s++){let iw=ow*sw-pw+s;if(iw<0||iw>=W)continue;let v=X[(c*H+ih)*W+iw];if(v>m)m=v;}}
    ref.push(m);}
  await check("maxpool2d",[X,new Float32Array(C*OH*OW)],[C,H,W,kh,kw,OH,OW,sh,sw,ph,pw],1,C*OH*OW,ref); }
{ // batchnorm C3 HW4
  const C=3,HW=4,eps=1e-5; const X=rnd(C*HW),sc=rnd(C),B=rnd(C),mean=rnd(C),vr=Float32Array.from({length:C},()=>Math.random()+0.5);
  const ref=[]; for(let i=0;i<C*HW;i++){let c=Math.floor(i/HW);ref.push(sc[c]*(X[i]-mean[c])/Math.sqrt(vr[c]+eps)+B[c]);}
  await check("batchnorm",[X,sc,B,mean,vr,new Float32Array(C*HW)],[C,HW,eps],5,C*HW,ref); }
{ // softmax over ax=4 inner=2 outer=3
  const outer=3,ax=4,inner=2; const X=rnd(outer*ax*inner); const ref=new Array(outer*ax*inner);
  for(let io=0;io<outer;io++)for(let ii=0;ii<inner;ii++){let base=io*ax*inner+ii;let m=-1e30;for(let a=0;a<ax;a++)m=Math.max(m,X[base+a*inner]);let s=0;for(let a=0;a<ax;a++)s+=Math.exp(X[base+a*inner]-m);for(let a=0;a<ax;a++)ref[base+a*inner]=Math.exp(X[base+a*inner]-m)/s;}
  await check("softmax_ax",[X,new Float32Array(outer*ax*inner)],[outer,ax,inner],1,outer*inner,ref); }
{ // layernorm outer3 ax5
  const outer=3,ax=5,eps=1e-5; const X=rnd(outer*ax),sc=rnd(ax),bi=rnd(ax); const ref=new Array(outer*ax);
  for(let o=0;o<outer;o++){let off=o*ax;let m=0;for(let j=0;j<ax;j++)m+=X[off+j];m/=ax;let v=0;for(let j=0;j<ax;j++){let d=X[off+j]-m;v+=d*d;}v/=ax;let inv=1/Math.sqrt(v+eps);for(let j=0;j<ax;j++)ref[off+j]=(X[off+j]-m)*inv*sc[j]+bi[j];}
  await check("layernorm",[X,sc,bi,new Float32Array(outer*ax)],[outer,ax,eps],3,outer,ref); }
{ // reducel2 outer3 ax4
  const outer=3,ax=4; const X=rnd(outer*ax); const ref=[]; for(let o=0;o<outer;o++){let s=0;for(let a=0;a<ax;a++)s+=X[o*ax+a]**2;ref.push(Math.sqrt(s));}
  await check("reducel2",[X,new Float32Array(outer)],[outer,ax],1,outer,ref); }
{ // slice_ax outer2 src_ax5 inner2, sz3 soff1
  const outer=2,src_ax=5,inner=2,sz=3,soff=1; const X=rnd(outer*src_ax*inner); const ref=[];
  for(let o=0;o<outer;o++)for(let a=0;a<sz;a++)for(let ii=0;ii<inner;ii++)ref.push(X[(o*src_ax+(soff+a))*inner+ii]);
  await check("slice_ax",[X,new Float32Array(outer*sz*inner)],[outer,sz,inner,src_ax,soff],1,outer*sz*inner,ref); }
{ // copy_ax: src (outer2, src_ax2, inner2) into dst (outer2, dst_ax5, inner2) at off1
  const outer=2,src_ax=2,inner=2,dst_ax=5,off=1; const S=rnd(outer*src_ax*inner); const D=new Float32Array(outer*dst_ax*inner);
  const ref=new Array(outer*dst_ax*inner).fill(0);
  for(let o=0;o<outer;o++)for(let a=0;a<src_ax;a++)for(let ii=0;ii<inner;ii++)ref[(o*dst_ax+(off+a))*inner+ii]=S[(o*src_ax+a)*inner+ii];
  await check("copy_ax",[S,D],[outer,src_ax,inner,dst_ax,off],1,outer*src_ax*inner,ref); }
{ // perm6: transpose a [2,3] as [1,1,1,1,2,3] perm swapping last two → [1,1,1,1,3,2]
  const d=[1,1,1,1,2,3]; const perm=[0,1,2,3,5,4]; const X=rnd(6);
  const O=perm.map(pi=>d[pi]); const tot=O.reduce((a,b)=>a*b,1); const ref=new Array(tot);
  for(let idx=0;idx<tot;idx++){let oc=new Array(6);let t=idx;for(let i=5;i>=0;i--){oc[i]=t%O[i];t=Math.floor(t/O[i]);}let inn=new Array(6);for(let i=0;i<6;i++)inn[perm[i]]=oc[i];let si=((((inn[0]*d[1]+inn[1])*d[2]+inn[2])*d[3]+inn[3])*d[4]+inn[4])*d[5]+inn[5];ref[idx]=X[si];}
  await check("perm6",[X,new Float32Array(tot)],[...d,...perm],1,tot,ref); }

console.log(`\n=== ${pass} PASS · ${fail} FAIL ===`);
if (fail) Deno.exit(1);
