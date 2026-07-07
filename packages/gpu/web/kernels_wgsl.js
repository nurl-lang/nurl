// WGSL translations of the onnx CUDA-C kernels (packages/onnx/src/ops.nu).
// Each entry: { sig, body }. sig is the arg order (b=ro storage, w=rw
// storage, q=int64-as-i32-pairs storage, i=i32 scalar, f=f32 scalar) —
// derived from the CUDA-C signature. The host builds bindings from sig:
// storage buffers at bindings 0..B-1 in order, one uniform struct at B.
// The body references buffers by name and scalars as p.NAME. Global
// index: `let idx = i32(gid.x);` prelude is added by the host wrapper.
const PRE = "@compute @workgroup_size(64)\nfn main(@builtin(global_invocation_id) gid: vec3<u32>, @builtin(num_workgroups) nwg: vec3<u32>) {\n  let idx = i32(gid.y) * i32(nwg.x) * 64 + i32(gid.x);\n";
const ERF = `fn erf_approx(x: f32) -> f32 {
  let t = 1.0 / (1.0 + 0.3275911 * abs(x));
  let y = 1.0 - (((((1.061405429*t - 1.453152027)*t) + 1.421413741)*t - 0.284496736)*t + 0.254829592)*t*exp(-x*x);
  return select(-y, y, x >= 0.0);
}\n`;

export const K = {
relu:      { params:[["X","b"],["Y","w"],["n","i"]],
  body:`if (idx < p.n) { let v = X[idx]; Y[idx] = select(0.0, v, v > 0.0); }` },
osigmoid:  { params:[["X","b"],["Y","w"],["n","i"]],
  body:`if (idx < p.n) { Y[idx] = 1.0 / (1.0 + exp(-X[idx])); }` },
leakyrelu: { params:[["X","b"],["Y","w"],["n","i"],["alpha","f"]],
  body:`if (idx < p.n) { let v = X[idx]; Y[idx] = select(p.alpha*v, v, v >= 0.0); }` },
clipk:     { params:[["X","b"],["Y","w"],["n","i"],["lo","f"],["hi","f"]],
  body:`if (idx < p.n) { Y[idx] = clamp(X[idx], p.lo, p.hi); }` },
expandlast:{ params:[["X","b"],["Y","w"],["outer","i"],["rep","i"]],
  body:`if (idx < p.outer*p.rep) { Y[idx] = X[idx/p.rep]; }` },
erfk:      { params:[["X","b"],["Y","w"],["n","i"]], extra: ERF,
  body:`if (idx < p.n) { Y[idx] = erf_approx(X[idx]); }` },
resize_nn: { params:[["X","b"],["Y","w"],["C","i"],["H","i"],["W","i"],["OH","i"],["OW","i"],["sh","i"],["sw","i"]],
  body:`if (idx >= p.C*p.OH*p.OW) { return; }
  let ox = idx % p.OW; let oy = (idx / p.OW) % p.OH; let c = idx / (p.OW*p.OH);
  Y[idx] = X[(c*p.H + oy/p.sh)*p.W + ox/p.sw];` },
eltwise:   { params:[["X","b"],["B","b"],["Y","w"],["n","i"],["per","i"],["op","i"],["bmode","i"]],
  body:`if (idx >= p.n) { return; }
  var b = 0.0;
  if (p.bmode == 0) { b = B[0]; }
  else if (p.bmode == 1) { b = B[idx/p.per]; }
  else if (p.bmode == 3) { b = B[idx%p.per]; }
  else { b = B[idx]; }
  let x = X[idx];
  var r = 0.0;
  if (p.op == 0) { r = x*b; } else if (p.op == 1) { r = x+b; } else if (p.op == 2) { r = x-b; } else { r = x/b; }
  Y[idx] = r;` },
gemm:      { params:[["A","b"],["B","b"],["C","b"],["Y","w"],["M","i"],["N","i"],["K","i"],["alpha","f"],["beta","f"],["transB","i"],["hasC","i"]],
  body:`if (idx < p.M*p.N) {
    let r = idx / p.N; let c = idx % p.N;
    var acc = 0.0;
    for (var k = 0; k < p.K; k = k + 1) {
      let bb = select(B[k*p.N + c], B[c*p.K + k], p.transB != 0);
      acc = acc + A[r*p.K + k] * bb;
    }
    let bias = select(0.0, C[c], p.hasC != 0);
    Y[idx] = p.alpha*acc + p.beta*bias;
  }` },
bmm:       { params:[["A","b"],["B","b"],["Y","w"],["batch","i"],["M","i"],["N","i"],["K","i"]],
  body:`if (idx >= p.batch*p.M*p.N) { return; }
  let c = idx % p.N; let t = idx / p.N; let r = t % p.M; let b = t / p.M;
  let aoff = b*p.M*p.K; let boff = b*p.K*p.N;
  var acc = 0.0;
  for (var k = 0; k < p.K; k = k + 1) { acc = acc + A[aoff + r*p.K + k] * B[boff + k*p.N + c]; }
  Y[idx] = acc;` },
conv2d:    { params:[["X","b"],["Wt","b"],["Bb","b"],["Y","w"],["Cin","i"],["H","i"],["W","i"],["Cout","i"],["kh","i"],["kw","i"],["OH","i"],["OW","i"],["ph","i"],["pw","i"],["sh","i"],["sw","i"],["hasB","i"]],
  body:`let total = p.Cout*p.OH*p.OW;
  if (idx >= total) { return; }
  let ow = idx % p.OW; let oh = (idx / p.OW) % p.OH; let oc = idx / (p.OW*p.OH);
  var acc = select(0.0, Bb[oc], p.hasB != 0);
  for (var ic = 0; ic < p.Cin; ic = ic + 1) {
    let xoff = ic*p.H*p.W; let woff = ((oc*p.Cin) + ic)*p.kh*p.kw;
    for (var r = 0; r < p.kh; r = r + 1) {
      let ih = oh*p.sh - p.ph + r;
      if (ih < 0 || ih >= p.H) { continue; }
      for (var s = 0; s < p.kw; s = s + 1) {
        let iw = ow*p.sw - p.pw + s;
        if (iw < 0 || iw >= p.W) { continue; }
        acc = acc + X[xoff + ih*p.W + iw] * Wt[woff + r*p.kw + s];
      }
    }
  }
  Y[(oc*p.OH + oh)*p.OW + ow] = acc;` },
convtranspose2d: { params:[["X","b"],["Wt","b"],["Bb","b"],["Y","w"],["Cin","i"],["H","i"],["W","i"],["Cout","i"],["kh","i"],["kw","i"],["OH","i"],["OW","i"],["ph","i"],["pw","i"],["sh","i"],["sw","i"],["hasB","i"]],
  body:`let total = p.Cout*p.OH*p.OW;
  if (idx >= total) { return; }
  let ox = idx % p.OW; let oy = (idx / p.OW) % p.OH; let oc = idx / (p.OW*p.OH);
  var acc = select(0.0, Bb[oc], p.hasB != 0);
  for (var ic = 0; ic < p.Cin; ic = ic + 1) {
    let xoff = ic*p.H*p.W;
    for (var ky = 0; ky < p.kh; ky = ky + 1) {
      let ty = oy + p.ph - ky;
      if (ty % p.sh != 0) { continue; }
      let iy = ty / p.sh;
      if (iy < 0 || iy >= p.H) { continue; }
      for (var kx = 0; kx < p.kw; kx = kx + 1) {
        let tx = ox + p.pw - kx;
        if (tx % p.sw != 0) { continue; }
        let ix = tx / p.sw;
        if (ix < 0 || ix >= p.W) { continue; }
        acc = acc + X[xoff + iy*p.W + ix] * Wt[(((ic*p.Cout)+oc)*p.kh + ky)*p.kw + kx];
      }
    }
  }
  Y[(oc*p.OH + oy)*p.OW + ox] = acc;` },
maxpool2d: { params:[["X","b"],["Y","w"],["C","i"],["H","i"],["W","i"],["kh","i"],["kw","i"],["OH","i"],["OW","i"],["sh","i"],["sw","i"],["ph","i"],["pw","i"]],
  body:`let total = p.C*p.OH*p.OW;
  if (idx >= total) { return; }
  let ow = idx % p.OW; let oh = (idx / p.OW) % p.OH; let c = idx / (p.OW*p.OH);
  let xoff = c*p.H*p.W;
  var m = -1e30;
  for (var r = 0; r < p.kh; r = r + 1) {
    let ih = oh*p.sh - p.ph + r;
    if (ih < 0 || ih >= p.H) { continue; }
    for (var s = 0; s < p.kw; s = s + 1) {
      let iw = ow*p.sw - p.pw + s;
      if (iw < 0 || iw >= p.W) { continue; }
      let v = X[xoff + ih*p.W + iw];
      if (v > m) { m = v; }
    }
  }
  Y[(c*p.OH + oh)*p.OW + ow] = m;` },
batchnorm: { params:[["X","b"],["sc","b"],["B","b"],["mean","b"],["vr","b"],["Y","w"],["C","i"],["HW","i"],["eps","f"]],
  body:`if (idx >= p.C*p.HW) { return; }
  let c = idx / p.HW;
  Y[idx] = sc[c]*(X[idx]-mean[c]) / sqrt(vr[c]+p.eps) + B[c];` },
softmax_ax:{ params:[["X","b"],["Y","w"],["outer","i"],["ax","i"],["inner","i"]],
  body:`if (idx >= p.outer*p.inner) { return; }
  let io = idx / p.inner; let ii = idx % p.inner;
  let base = io*p.ax*p.inner + ii;
  var m = -1e30;
  for (var a = 0; a < p.ax; a = a + 1) { let v = X[base + a*p.inner]; if (v > m) { m = v; } }
  var s = 0.0;
  for (var a = 0; a < p.ax; a = a + 1) { s = s + exp(X[base + a*p.inner] - m); }
  for (var a = 0; a < p.ax; a = a + 1) { Y[base + a*p.inner] = exp(X[base + a*p.inner] - m) / s; }` },
copy_ax:   { params:[["S","b"],["D","w"],["outer","i"],["src_ax","i"],["inner","i"],["dst_ax","i"],["off","i"]],
  body:`if (idx >= p.outer*p.src_ax*p.inner) { return; }
  let ii = idx % p.inner; let t = idx / p.inner;
  let a = t % p.src_ax; let o = t / p.src_ax;
  D[(o*p.dst_ax + (p.off+a))*p.inner + ii] = S[idx];` },
slice_ax:  { params:[["S","b"],["D","w"],["outer","i"],["sz","i"],["inner","i"],["src_ax","i"],["soff","i"]],
  body:`if (idx >= p.outer*p.sz*p.inner) { return; }
  let ii = idx % p.inner; let t = idx / p.inner;
  let a = t % p.sz; let o = t / p.sz;
  D[idx] = S[(o*p.src_ax + (p.soff+a))*p.inner + ii];` },
layernorm: { params:[["X","b"],["sc","b"],["bi","b"],["Y","w"],["outer","i"],["ax","i"],["eps","f"]],
  body:`if (idx >= p.outer) { return; }
  let off = idx*p.ax;
  var m = 0.0; for (var j = 0; j < p.ax; j = j + 1) { m = m + X[off+j]; } m = m / f32(p.ax);
  var v = 0.0; for (var j = 0; j < p.ax; j = j + 1) { let d = X[off+j]-m; v = v + d*d; } v = v / f32(p.ax);
  let inv = 1.0 / sqrt(v + p.eps);
  for (var j = 0; j < p.ax; j = j + 1) { Y[off+j] = (X[off+j]-m)*inv*sc[j] + bi[j]; }` },
reducel2:  { params:[["X","b"],["Y","w"],["outer","i"],["ax","i"]],
  body:`if (idx >= p.outer) { return; }
  let off = idx*p.ax;
  var s = 0.0; for (var a = 0; a < p.ax; a = a + 1) { s = s + X[off+a]*X[off+a]; }
  Y[idx] = sqrt(s);` },
perm6:     { params:[["X","b"],["Y","w"],["d0","i"],["d1","i"],["d2","i"],["d3","i"],["d4","i"],["d5","i"],["q0","i"],["q1","i"],["q2","i"],["q3","i"],["q4","i"],["q5","i"]],
  body:`var D = array<i32,6>(p.d0,p.d1,p.d2,p.d3,p.d4,p.d5);
  var P = array<i32,6>(p.q0,p.q1,p.q2,p.q3,p.q4,p.q5);
  var O = array<i32,6>(0,0,0,0,0,0);
  for (var i = 0; i < 6; i = i + 1) { O[i] = D[P[i]]; }
  let tot = O[0]*O[1]*O[2]*O[3]*O[4]*O[5];
  if (idx >= tot) { return; }
  var oc = array<i32,6>(0,0,0,0,0,0);
  var t = idx;
  for (var i = 5; i >= 0; i = i - 1) { oc[i] = t % O[i]; t = t / O[i]; }
  var ins = array<i32,6>(0,0,0,0,0,0);
  for (var i = 0; i < 6; i = i + 1) { ins[P[i]] = oc[i]; }
  let si = ((((ins[0]*p.d1 + ins[1])*p.d2 + ins[2])*p.d3 + ins[3])*p.d4 + ins[4])*p.d5 + ins[5];
  Y[idx] = X[si];` },
gather:    { params:[["D","b"],["idx_","q"],["Y","w"],["outer","i"],["axis_in","i"],["inner","i"],["nidx","i"]],
  body:`if (idx >= p.outer*p.nidx*p.inner) { return; }
  let ii = idx % p.inner; let t = idx / p.inner;
  let g = t % p.nidx; let o = t / p.nidx;
  let ix = idx_[2*g];
  Y[idx] = D[(o*p.axis_in + ix)*p.inner + ii];` },
argmaxk:   { params:[["X","b"],["Y","Q"],["outer","i"],["ax","i"]],
  body:`if (idx >= p.outer) { return; }
  let off = idx*p.ax;
  var bi = 0; var bv = X[off];
  for (var j = 1; j < p.ax; j = j + 1) { let v = X[off+j]; if (v > bv) { bv = v; bi = j; } }
  Y[2*idx] = bi; Y[2*idx+1] = 0;` },
argmaxk_i64:{ params:[["X","q"],["Y","Q"],["outer","i"],["ax","i"]],
  body:`if (idx >= p.outer) { return; }
  let off = idx*p.ax;
  var bi = 0; var bv = X[2*off];
  for (var j = 1; j < p.ax; j = j + 1) { let v = X[2*(off+j)]; if (v > bv) { bv = v; bi = j; } }
  Y[2*idx] = bi; Y[2*idx+1] = 0;` },
eos_gather:{ params:[["data","b"],["tok","q"],["Y","w"],["B","i"],["L","i"],["D","i"]],
  body:`if (idx >= p.B*p.D) { return; }
  let d = idx % p.D; let b = idx / p.D;
  let toff = b*p.L;
  var pos = 0; var mx = tok[2*toff];
  for (var j = 1; j < p.L; j = j + 1) { let v = tok[2*(toff+j)]; if (v > mx) { mx = v; pos = j; } }
  Y[idx] = data[(b*p.L + pos)*p.D + d];` },
};

// Build full WGSL from params + body.
export function buildWGSL(name) {
  const k = K[name];
  const bufs = k.params.filter(([n,t]) => t === "b" || t === "w" || t === "q" || t === "Q");
  const scalars = k.params.filter(([n,t]) => t === "i" || t === "f");
  let src = (k.extra || "");
  bufs.forEach(([n,t], i) => {
    const acc = (t === "w" || t === "Q") ? "read_write" : "read";
    const elem = (t === "q" || t === "Q") ? "i32" : "f32";
    src += `@group(0) @binding(${i}) var<storage, ${acc}> ${n}: array<${elem}>;\n`;
  });
  src += "struct Params {\n" + scalars.map(([n,t]) => `  ${n}: ${t === "f" ? "f32" : "i32"},`).join("\n") + "\n};\n";
  src += `@group(0) @binding(${bufs.length}) var<uniform> p: Params;\n`;
  src += PRE + k.body + "\n}\n";
  return src;
}
export function sig(name) { return K[name].params.map(([n,t]) => t).join(""); }
export function scalarLayout(name) { return K[name].params.filter(([n,t]) => t === "i" || t === "f"); }
