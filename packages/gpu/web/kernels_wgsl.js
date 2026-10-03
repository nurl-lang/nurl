// kernels_wgsl.js — the WGSL kernel set of the gpu package's WebGPU
// backend (backend 3).
//
// A NURL program on the WebGPU backend launches kernels by ENTRY NAME
// (gpu_compile passes only the name): the set here must hold exactly the
// kernels the program's executor requests, with the parameter list the
// executor marshals. For the onnx executor that set is DERIVED, not
// chosen here: rt_kernel_census (packages/onnx/src/runtime.nu) issues
// every gkd_* call the executor makes on a gpukit census kit, which
// records each kernel's entry name and its exact CUDA-C source — the same
// record kernels_static.c is generated from. packages/onnx/tests/
// wgsl_census_test.nu fails when
//   - the census holds a kernel this table lacks,
//   - an entry's `sig` is not, character for character, the parameter
//     list the census recorded for that kernel (a cell layout change),
//   - a parameter type has no row in CTYPES, or
//   - this table holds an entry the census no longer records.
// (Up to gpu 0.13.1 this table was a hand-kept copy of onnx's pre-0.7
// kernels — `gemm`, `osigmoid`, `int` cells — and every WebGPU build
// failed at run time with "no WGSL kernel named gk32_…" while every test
// stayed green.)
//
// What is hand-written is only the BODY. Everything else — storage
// bindings, the uniform struct, how each i64 argument cell is decoded —
// is generated from `sig` by the one mechanical rule below:
//
//   C parameter          WGSL                                    kind
//   const float* X       var<storage, read>       X: array<f32>  b
//   float* X             var<storage, read_write> X: array<f32>  w
//   const long long* X   var<storage, read>       X: array<i32>  q   (lo,hi word pairs: element k = X[2k], X[2k+1])
//   long long* X         var<storage, read_write> X: array<i32>  Q
//   long long n          p.n: i32   (the cell must fit in i32 — checked at launch)  I
//   int n                p.n: i32                                i
//   float a              p.a: f32                                f
//
// Buffers bind at 0..B-1 in parameter order, the uniform struct `p` at B.
// For every buffer parameter the struct also carries `p.nz_<name>`: 1
// when the argument was a real buffer, 0 when it was the null pointer
// (CUDA's `C!=0`; WebGPU has no null binding, so a 4-byte placeholder is
// bound instead). A C name that WGSL reserves gets a trailing `_` (bnorm's
// `var` is `var_`, bmm_tiled's `as` is `as_`).
//
// The body sees `idx`, the global invocation index. By default the launch
// runs the CUDA launch's thread count (grid*block) and the body maps idx
// to work exactly as the CUDA kernel does; a body that maps differently
// (several outputs per invocation, a workgroup per output) says how many
// invocations it needs in `invocations`, fed the scalar arguments by
// their C names. A body may also use workgroup memory and barriers — the
// WebGPU backend runs real workgroups of 64.

const PRE = "@compute @workgroup_size(64)\nfn main(@builtin(global_invocation_id) gid: vec3<u32>, @builtin(num_workgroups) nwg: vec3<u32>) {\n  let idx = i32(gid.y) * i32(nwg.x) * 64 + i32(gid.x);\n";

// C parameter type → kind (see the table above). One row per type the
// glue can marshal; tests/wgsl_census_test.nu (onnx) reads these keys.
export const CTYPES = { "const float*": "b", "float*": "w", "const long long*": "q", "long long*": "Q", "long long": "I", "int": "i", "float": "f" };

// WGSL keywords and reserved words (WGSL spec §15) — a C parameter name in
// this set gets a trailing `_`.
const RESERVED = new Set(("alias break case const const_assert continue continuing default diagnostic discard else enable false fn for if let loop override requires return struct switch true var while " +
  "NULL Self abstract active alignas alignof as asm asm_fragment async attribute auto await become binding_array cast catch class co_await co_return co_yield coherent column_major common compile compile_fragment concept const_cast consteval constexpr constinit crate debugger decltype delete demote demote_to_helper do dynamic_cast enum explicit export extends extern external fallthrough filter final finally friend from fxgroup get goto groupshared highp impl implements import inline instanceof interface layout lowp macro macro_rules match mediump meta mod module move mut mutable namespace new nil noexcept noinline nointerpolation non_coherent noncoherent noperspective null nullptr of operator package packoffset partition pass patch pixelfragment precise precision premerge priv protected pub public readonly ref regardless register reinterpret_cast require resource restrict self set shared sizeof smooth snorm static static_assert static_cast std subroutine super target template this thread_local throw trait try type typedef typeid typename typeof union unless unorm unsafe unsized use using varying virtual volatile wgsl where with writeonly yield " +
  "p idx gid nwg main").split(" "));

// The sentinel gpu_open probes (gpu.nu GPU_WGSL_SENTINEL): a pipeline for
// it compiling proves a WebGPU host with a working device is attached,
// without naming any real kernel — those belong to the census and change
// with it.
export const SENTINEL = "__nurl_wgsl_set";

const ERF = `fn erf_approx(x: f32) -> f32 {
  // Abramowitz & Stegun 7.1.26 (|error| < 1.5e-7) — WGSL has no erf
  let t = 1.0 / (1.0 + 0.3275911 * abs(x));
  let y = 1.0 - (((((1.061405429*t - 1.453152027)*t) + 1.421413741)*t - 0.284496736)*t + 0.254829592)*t*exp(-x*x);
  return select(-y, y, x >= 0.0);
}
`;

// a > b for two i64 values held as (lo, hi) i32 words
const I64GT = `fn i64_gt(alo: i32, ahi: i32, blo: i32, bhi: i32) -> bool {
  return ahi > bhi || (ahi == bhi && u32(alo) > u32(blo));
}
`;

// gk32_bc{mul,add,sub,div}: broadcast elementwise over <=6 dims (d*: the
// output shape, A*/B*: each operand's strides, 0 on a broadcast axis).
const bc = (op) => `if (idx >= p.n) { return; }
  var t = idx; var ai = 0; var bi = 0; var c = 0;
  c = t % p.d5; t = t / p.d5; ai = ai + c*p.A5; bi = bi + c*p.B5;
  c = t % p.d4; t = t / p.d4; ai = ai + c*p.A4; bi = bi + c*p.B4;
  c = t % p.d3; t = t / p.d3; ai = ai + c*p.A3; bi = bi + c*p.B3;
  c = t % p.d2; t = t / p.d2; ai = ai + c*p.A2; bi = bi + c*p.B2;
  c = t % p.d1; t = t / p.d1; ai = ai + c*p.A1; bi = bi + c*p.B1;
  ai = ai + t*p.A0; bi = bi + t*p.B0;
  o[idx] = a[ai] ${op} b[bi];`;

// gemm. A small result (projection heads: M·N in the hundreds, K in the
// thousands) would leave the GPU nearly idle at one invocation per
// output, so it gets a 64-lane workgroup per output element, lanes
// strided over K and tree-reduced in workgroup memory; the `invocations`
// hook and the body branch on the same uniform predicate.
const gemmInv = (p) => (p.M * p.N < 16384) ? p.M * p.N * 64 : p.M * p.N;
const gemm = (honorTransB) => `if (p.M*p.N < 16384) {
    // padding workgroups (2D-dispatch rounding) redo the last output —
    // identical value, benign write race
    let out = min(idx / 64, p.M*p.N - 1);
    let lane = idx % 64;
    let r = out / p.N; let c = out % p.N;
    var s = 0.0;
    ${honorTransB ? `if (p.transB != 0) {
      for (var k = lane; k < p.K; k = k + 64) { s = s + A[r*p.K + k] * B[c*p.K + k]; }
    } else {
      for (var k = lane; k < p.K; k = k + 64) { s = s + A[r*p.K + k] * B[k*p.N + c]; }
    }` : `for (var k = lane; k < p.K; k = k + 64) { s = s + A[r*p.K + k] * B[k*p.N + c]; }`}
    gemm_part[lane] = s;
    workgroupBarrier();
    for (var w = 32; w > 0; w = w >> 1u) {
      if (lane < w) { gemm_part[lane] = gemm_part[lane] + gemm_part[lane + w]; }
      workgroupBarrier();
    }
    if (lane == 0) {
      let bias = select(0.0, C[c], p.nz_C != 0);
      Y[out] = p.alpha*gemm_part[0] + p.beta*bias;
    }
  } else if (idx < p.M*p.N) {
    let r = idx / p.N; let c = idx % p.N;
    var acc = 0.0;
    ${honorTransB ? `if (p.transB != 0) {
      for (var k = 0; k < p.K; k = k + 1) { acc = acc + A[r*p.K + k] * B[c*p.K + k]; }
    } else {
      for (var k = 0; k < p.K; k = k + 1) { acc = acc + A[r*p.K + k] * B[k*p.N + c]; }
    }` : `for (var k = 0; k < p.K; k = k + 1) { acc = acc + A[r*p.K + k] * B[k*p.N + c]; }`}
    let bias = select(0.0, C[c], p.nz_C != 0);
    Y[idx] = p.alpha*acc + p.beta*bias;
  }`;

// One entry per kernel: `<name>: { sig: "<C parameter list>",` on ONE
// line starting in column 0 (tests/wgsl_census_test.nu reads that line).
export const K = {
__nurl_wgsl_set: { sig: "()", body: `` },

// ── matrix products ──
// gk32_gemm_tiled is what gkd_gemm launches for transB=0 on every backend
// with fixed kernel sets (its CUDA body ignores transB, and so does this).
gk32_gemm_tiled: { sig: "(const float* A, const float* B, const float* C, float* Y, long long M, long long N, long long K, float alpha, float beta, long long transB)",
  extra: "var<workgroup> gemm_part: array<f32, 64>;\n", invocations: gemmInv, body: gemm(false) },
gk32_gemm: { sig: "(const float* A, const float* B, const float* C, float* Y, long long M, long long N, long long K, float alpha, float beta, long long transB)",
  extra: "var<workgroup> gemm_part: array<f32, 64>;\n", invocations: gemmInv, body: gemm(true) },
// batched: `total` is the CUDA launch's tile count, batch*ceil(M/8)*ceil(N/32);
// here one invocation per output
gk32_bmm_tiled: { sig: "(const float* A, const float* B, float* Y, long long M, long long N, long long K, long long as, long long bs, long long total)",
  invocations: (p) => (p.total / (Math.ceil(p.M / 8) * Math.ceil(p.N / 32))) * p.M * p.N,
  body: `let nt = ((p.M + 7) / 8) * ((p.N + 31) / 32);
  let nb = p.total / nt;
  if (idx >= nb*p.M*p.N) { return; }
  let c = idx % p.N; let t = idx / p.N; let r = t % p.M; let bi = t / p.M;
  let ao = bi*p.as_ + r*p.K; let bo = bi*p.bs + c;
  var acc = 0.0;
  for (var k = 0; k < p.K; k = k + 1) { acc = acc + A[ao + k] * B[bo + k*p.N]; }
  Y[(bi*p.M + r)*p.N + c] = acc;` },

// ── convolution ──
// conv2d computes TWO output channels × FOUR consecutive ow outputs per
// invocation: the 3×3 fast paths share the overlapping input row across
// a vec4 accumulator (18 X-loads instead of 36 for stride 1), and
// constant loop bounds let the compiler unroll — the naive
// one-output-per-thread body ran at ~0.1% of a 4090's peak. Sums run
// bias, then ic, ky, kx ascending, as the CUDA kernel's do.
gk32_conv2d: { sig: "(const float* X, const float* Wt, const float* B, float* Y, long long Cin, long long H, long long W, long long Cout, long long kh, long long kw, long long OH, long long OW, long long ph, long long pw, long long sh, long long sw, long long hasB)",
  invocations: (p) => Math.ceil(p.Cout / 2) * p.OH * Math.ceil(p.OW / 4),
  body: `let nb = (p.OW + 3) / 4;
  let nc = (p.Cout + 1) / 2;
  if (idx >= nc*p.OH*nb) { return; }
  let ob = idx % nb; let oh = (idx / nb) % p.OH; let oc = (idx / (nb*p.OH)) * 2;
  let has2 = oc + 1 < p.Cout;
  let ow0 = ob * 4;
  // the oc+1 lane runs unconditionally when Cout is odd (its loads clamp
  // in-bounds under WebGPU robustness) — only the final store is guarded
  let oc1 = min(oc + 1, p.Cout - 1);
  let bias0 = select(0.0, B[oc], p.hasB != 0);
  let bias1 = select(0.0, B[oc1], p.hasB != 0);
  var acc = vec4<f32>(bias0);
  var acd = vec4<f32>(bias1);
  if (p.kh == 3 && p.kw == 3 && p.sh == 1 && p.sw == 1 && ow0 + 3 < p.OW) {
    let ih0 = oh - p.ph; let iw0 = ow0 - p.pw;
    for (var ic = 0; ic < p.Cin; ic = ic + 1) {
      let xoff = ic*p.H*p.W; let woff = ((oc*p.Cin) + ic)*9; let wof2 = woff + p.Cin*9;
      for (var r = 0; r < 3; r = r + 1) {
        let ih = ih0 + r;
        if (ih < 0 || ih >= p.H) { continue; }
        let ro = xoff + ih*p.W;
        let w0 = Wt[woff + r*3]; let w1 = Wt[woff + r*3 + 1]; let w2 = Wt[woff + r*3 + 2];
        let v0 = Wt[wof2 + r*3]; let v1 = Wt[wof2 + r*3 + 1]; let v2 = Wt[wof2 + r*3 + 2];
        let x0 = select(0.0, X[ro + iw0    ], iw0     >= 0 && iw0     < p.W);
        let x1 = select(0.0, X[ro + iw0 + 1], iw0 + 1 >= 0 && iw0 + 1 < p.W);
        let x2 = select(0.0, X[ro + iw0 + 2], iw0 + 2 >= 0 && iw0 + 2 < p.W);
        let x3 = select(0.0, X[ro + iw0 + 3], iw0 + 3 >= 0 && iw0 + 3 < p.W);
        let x4 = select(0.0, X[ro + iw0 + 4], iw0 + 4 >= 0 && iw0 + 4 < p.W);
        let x5 = select(0.0, X[ro + iw0 + 5], iw0 + 5 >= 0 && iw0 + 5 < p.W);
        let a = vec4<f32>(x0,x1,x2,x3); let b = vec4<f32>(x1,x2,x3,x4); let c = vec4<f32>(x2,x3,x4,x5);
        acc = acc + a*w0 + b*w1 + c*w2;
        acd = acd + a*v0 + b*v1 + c*v2;
      }
    }
  } else if (p.kh == 3 && p.kw == 3 && p.sh == 2 && p.sw == 2 && ow0 + 3 < p.OW) {
    let ih0 = oh*2 - p.ph; let iw0 = ow0*2 - p.pw;
    for (var ic = 0; ic < p.Cin; ic = ic + 1) {
      let xoff = ic*p.H*p.W; let woff = ((oc*p.Cin) + ic)*9; let wof2 = woff + p.Cin*9;
      for (var r = 0; r < 3; r = r + 1) {
        let ih = ih0 + r;
        if (ih < 0 || ih >= p.H) { continue; }
        let ro = xoff + ih*p.W;
        let w0 = Wt[woff + r*3]; let w1 = Wt[woff + r*3 + 1]; let w2 = Wt[woff + r*3 + 2];
        let v0 = Wt[wof2 + r*3]; let v1 = Wt[wof2 + r*3 + 1]; let v2 = Wt[wof2 + r*3 + 2];
        let x0 = select(0.0, X[ro + iw0    ], iw0     >= 0 && iw0     < p.W);
        let x1 = select(0.0, X[ro + iw0 + 1], iw0 + 1 >= 0 && iw0 + 1 < p.W);
        let x2 = select(0.0, X[ro + iw0 + 2], iw0 + 2 >= 0 && iw0 + 2 < p.W);
        let x3 = select(0.0, X[ro + iw0 + 3], iw0 + 3 >= 0 && iw0 + 3 < p.W);
        let x4 = select(0.0, X[ro + iw0 + 4], iw0 + 4 >= 0 && iw0 + 4 < p.W);
        let x5 = select(0.0, X[ro + iw0 + 5], iw0 + 5 >= 0 && iw0 + 5 < p.W);
        let x6 = select(0.0, X[ro + iw0 + 6], iw0 + 6 >= 0 && iw0 + 6 < p.W);
        let x7 = select(0.0, X[ro + iw0 + 7], iw0 + 7 >= 0 && iw0 + 7 < p.W);
        let x8 = select(0.0, X[ro + iw0 + 8], iw0 + 8 >= 0 && iw0 + 8 < p.W);
        let a = vec4<f32>(x0,x2,x4,x6); let b = vec4<f32>(x1,x3,x5,x7); let c = vec4<f32>(x2,x4,x6,x8);
        acc = acc + a*w0 + b*w1 + c*w2;
        acd = acd + a*v0 + b*v1 + c*v2;
      }
    }
  } else if (p.kh == 1 && p.kw == 1 && p.sh == 1 && p.sw == 1 && p.ph == 0 && p.pw == 0 && ow0 + 3 < p.OW) {
    let ro0 = oh*p.W + ow0;
    for (var ic = 0; ic < p.Cin; ic = ic + 1) {
      let ro = ic*p.H*p.W + ro0;
      let w = Wt[oc*p.Cin + ic]; let v = Wt[oc1*p.Cin + ic];
      let a = vec4<f32>(X[ro], X[ro+1], X[ro+2], X[ro+3]);
      acc = acc + a*w;
      acd = acd + a*v;
    }
  } else {
    for (var j = 0; j < 4; j = j + 1) {
      let ow = ow0 + j;
      if (ow >= p.OW) { break; }
      var a0 = bias0; var a1 = bias1;
      for (var ic = 0; ic < p.Cin; ic = ic + 1) {
        let xoff = ic*p.H*p.W; let woff = ((oc*p.Cin) + ic)*p.kh*p.kw; let wof2 = woff + p.Cin*p.kh*p.kw;
        for (var r = 0; r < p.kh; r = r + 1) {
          let ih = oh*p.sh - p.ph + r;
          if (ih < 0 || ih >= p.H) { continue; }
          for (var s = 0; s < p.kw; s = s + 1) {
            let iw = ow*p.sw - p.pw + s;
            if (iw < 0 || iw >= p.W) { continue; }
            let xv = X[xoff + ih*p.W + iw];
            a0 = a0 + xv * Wt[woff + r*p.kw + s];
            a1 = a1 + xv * Wt[wof2 + r*p.kw + s];
          }
        }
      }
      acc[j] = a0; acd[j] = a1;
    }
  }
  let yb = (oc*p.OH + oh)*p.OW;
  let yc = (oc1*p.OH + oh)*p.OW;
  for (var j = 0; j < 4; j = j + 1) {
    if (ow0 + j < p.OW) {
      Y[yb + ow0 + j] = acc[j];
      if (has2) { Y[yc + ow0 + j] = acd[j]; }
    }
  }` },
// dilated: the CUDA body accumulates in double; WGSL has no f64, so f32
gk32_conv2d_dil: { sig: "(const float* X, const float* Wt, const float* B, float* Y, long long Cin, long long H, long long W, long long Cout, long long kh, long long kw, long long OH, long long OW, long long ph, long long pw, long long sh, long long sw, long long dh, long long dw, long long hasB)",
  body: `if (idx >= p.Cout*p.OH*p.OW) { return; }
  let ox = idx % p.OW; let oy = (idx / p.OW) % p.OH; let oc = idx / (p.OW*p.OH);
  var acc = select(0.0, B[oc], p.hasB != 0);
  for (var ic = 0; ic < p.Cin; ic = ic + 1) {
    let xo = ic*p.H*p.W; let wo = (oc*p.Cin + ic)*p.kh*p.kw;
    for (var r = 0; r < p.kh; r = r + 1) {
      let iy = oy*p.sh - p.ph + r*p.dh;
      if (iy < 0 || iy >= p.H) { continue; }
      for (var s = 0; s < p.kw; s = s + 1) {
        let ix = ox*p.sw - p.pw + s*p.dw;
        if (ix < 0 || ix >= p.W) { continue; }
        acc = acc + X[xo + iy*p.W + ix] * Wt[wo + r*p.kw + s];
      }
    }
  }
  Y[idx] = acc;` },
// ConvTranspose with stride == kernel and no padding: each output has
// exactly one contributing tap, (ky,kx) = the output's phase
gk32_convt2d_up: { sig: "(const float* X, const float* Wt, const float* B, float* Y, long long Cin, long long H, long long W, long long Cout, long long kh, long long kw, long long OH, long long OW, long long ph, long long pw, long long sh, long long sw, long long hasB)",
  body: `if (idx >= p.Cout*p.OH*p.OW) { return; }
  let ox = idx % p.OW; let oy = (idx / p.OW) % p.OH; let oc = idx / (p.OW*p.OH);
  var acc = select(0.0, B[oc], p.hasB != 0);
  let iy = oy / p.sh; let ky = oy - iy*p.sh; let ix = ox / p.sw; let kx = ox - ix*p.sw;
  if (iy < p.H && ix < p.W) {
    for (var ic = 0; ic < p.Cin; ic = ic + 1) {
      acc = acc + X[ic*p.H*p.W + iy*p.W + ix] * Wt[(((ic*p.Cout) + oc)*p.kh + ky)*p.kw + kx];
    }
  }
  Y[(oc*p.OH + oy)*p.OW + ox] = acc;` },
gk32_convt2d: { sig: "(const float* X, const float* Wt, const float* B, float* Y, long long Cin, long long H, long long W, long long Cout, long long kh, long long kw, long long OH, long long OW, long long ph, long long pw, long long sh, long long sw, long long hasB)",
  body: `if (idx >= p.Cout*p.OH*p.OW) { return; }
  let ox = idx % p.OW; let oy = (idx / p.OW) % p.OH; let oc = idx / (p.OW*p.OH);
  var acc = select(0.0, B[oc], p.hasB != 0);
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
        acc = acc + X[xoff + iy*p.W + ix] * Wt[(((ic*p.Cout) + oc)*p.kh + ky)*p.kw + kx];
      }
    }
  }
  Y[(oc*p.OH + oy)*p.OW + ox] = acc;` },
gk32_maxpool2d: { sig: "(const float* X, float* Y, long long C, long long H, long long W, long long kh, long long kw, long long OH, long long OW, long long sh, long long sw, long long ph, long long pw)",
  body: `if (idx >= p.C*p.OH*p.OW) { return; }
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
gk32_bnorm: { sig: "(const float* X, const float* sc, const float* B, const float* mean, const float* var, float* Y, long long C, long long HW, float eps)",
  body: `if (idx >= p.C*p.HW) { return; }
  let c = idx / p.HW;
  Y[idx] = sc[c]*(X[idx] - mean[c]) / sqrt(var_[c] + p.eps) + B[c];` },

// ── activations / maps ──
gk32_relu: { sig: "(const float* in, float* o, long long n)",
  body: `if (idx < p.n) { let x = in[idx]; o[idx] = select(0.0, x, x > 0.0); }` },
gk32_sigmoid: { sig: "(const float* in, float* o, long long n)",
  body: `if (idx < p.n) { o[idx] = 1.0 / (1.0 + exp(-in[idx])); }` },
gk32_lrelu: { sig: "(const float* X, float* Y, long long n, float alpha)",
  body: `if (idx < p.n) { let v = X[idx]; Y[idx] = select(p.alpha*v, v, v >= 0.0); }` },
gk32_clip: { sig: "(const float* X, float* Y, long long n, float lo, float hi)",
  body: `if (idx < p.n) { let v = X[idx]; Y[idx] = select(select(v, p.hi, v > p.hi), p.lo, v < p.lo); }` },
gk32_erf: { sig: "(const float* in, float* o, long long n)", extra: ERF,
  body: `if (idx < p.n) { o[idx] = erf_approx(in[idx]); }` },
gk32_lnorm: { sig: "(const float* X, const float* sc, const float* bi, float* Y, long long outer, long long ax, float eps)",
  body: `if (idx >= p.outer) { return; }
  let off = idx*p.ax;
  var m = 0.0; for (var j = 0; j < p.ax; j = j + 1) { m = m + X[off + j]; } m = m / f32(p.ax);
  var v = 0.0; for (var j = 0; j < p.ax; j = j + 1) { let d = X[off + j] - m; v = v + d*d; } v = v / f32(p.ax);
  let inv = 1.0 / sqrt(v + p.eps);
  for (var j = 0; j < p.ax; j = j + 1) { Y[off + j] = (X[off + j] - m)*inv*sc[j] + bi[j]; }` },
gk32_softmaxax: { sig: "(const float* X, float* Y, long long outer, long long ax, long long inner)",
  body: `if (idx >= p.outer*p.inner) { return; }
  let io = idx / p.inner; let ii = idx % p.inner;
  let base = io*p.ax*p.inner + ii;
  var m = -1e30;
  for (var a = 0; a < p.ax; a = a + 1) { let v = X[base + a*p.inner]; if (v > m) { m = v; } }
  var s = 0.0;
  for (var a = 0; a < p.ax; a = a + 1) { s = s + exp(X[base + a*p.inner] - m); }
  for (var a = 0; a < p.ax; a = a + 1) { Y[base + a*p.inner] = exp(X[base + a*p.inner] - m) / s; }` },

// ── broadcast elementwise ──
gk32_bcmul: { sig: "(const float* a, const float* b, float* o, long long n, long long d0, long long d1, long long d2, long long d3, long long d4, long long d5, long long A0, long long A1, long long A2, long long A3, long long A4, long long A5, long long B0, long long B1, long long B2, long long B3, long long B4, long long B5)", body: bc("*") },
gk32_bcadd: { sig: "(const float* a, const float* b, float* o, long long n, long long d0, long long d1, long long d2, long long d3, long long d4, long long d5, long long A0, long long A1, long long A2, long long A3, long long A4, long long A5, long long B0, long long B1, long long B2, long long B3, long long B4, long long B5)", body: bc("+") },
gk32_bcsub: { sig: "(const float* a, const float* b, float* o, long long n, long long d0, long long d1, long long d2, long long d3, long long d4, long long d5, long long A0, long long A1, long long A2, long long A3, long long A4, long long A5, long long B0, long long B1, long long B2, long long B3, long long B4, long long B5)", body: bc("-") },
gk32_bcdiv: { sig: "(const float* a, const float* b, float* o, long long n, long long d0, long long d1, long long d2, long long d3, long long d4, long long d5, long long A0, long long A1, long long A2, long long A3, long long A4, long long A5, long long B0, long long B1, long long B2, long long B3, long long B4, long long B5)", body: bc("/") },

// ── data movement ──
gk32_sliceax: { sig: "(const float* S, float* D, long long outer, long long sz, long long inner, long long src_ax, long long soff)",
  body: `if (idx >= p.outer*p.sz*p.inner) { return; }
  let ii = idx % p.inner; let t = idx / p.inner;
  let a = t % p.sz; let o = t / p.sz;
  D[idx] = S[(o*p.src_ax + (p.soff + a))*p.inner + ii];` },
gk32_copyax: { sig: "(const float* S, float* D, long long outer, long long src_ax, long long inner, long long dst_ax, long long off)",
  body: `if (idx >= p.outer*p.src_ax*p.inner) { return; }
  let ii = idx % p.inner; let t = idx / p.inner;
  let a = t % p.src_ax; let o = t / p.src_ax;
  D[(o*p.dst_ax + (p.off + a))*p.inner + ii] = S[idx];` },
gk32_perm6: { sig: "(const float* X, float* Y, long long d0,long long d1,long long d2,long long d3,long long d4,long long d5,long long p0,long long p1,long long p2,long long p3,long long p4,long long p5)",
  body: `var D = array<i32,6>(p.d0, p.d1, p.d2, p.d3, p.d4, p.d5);
  var P = array<i32,6>(p.p0, p.p1, p.p2, p.p3, p.p4, p.p5);
  var O = array<i32,6>(0, 0, 0, 0, 0, 0);
  for (var i = 0; i < 6; i = i + 1) { O[i] = D[P[i]]; }
  let tot = O[0]*O[1]*O[2]*O[3]*O[4]*O[5];
  if (idx >= tot) { return; }
  var oc = array<i32,6>(0, 0, 0, 0, 0, 0);
  var t = idx;
  for (var i = 5; i >= 0; i = i - 1) { oc[i] = t % O[i]; t = t / O[i]; }
  var ins = array<i32,6>(0, 0, 0, 0, 0, 0);
  for (var i = 0; i < 6; i = i + 1) { ins[P[i]] = oc[i]; }
  let si = ((((ins[0]*p.d1 + ins[1])*p.d2 + ins[2])*p.d3 + ins[3])*p.d4 + ins[4])*p.d5 + ins[5];
  Y[idx] = X[si];` },
// bilinear: the CUDA body interpolates in double; WGSL has no f64, so f32
gk32_resizebilin: { sig: "(const float* X, float* Y, long long C, long long H, long long W, long long OH, long long OW, long long align)",
  body: `if (idx >= p.C*p.OH*p.OW) { return; }
  let ox = idx % p.OW; let oy = (idx / p.OW) % p.OH; let c = idx / (p.OW*p.OH);
  var fy = 0.0; var fx = 0.0;
  if (p.align != 0) {
    if (p.OH > 1) { fy = f32(oy)*f32(p.H - 1)/f32(p.OH - 1); }
    if (p.OW > 1) { fx = f32(ox)*f32(p.W - 1)/f32(p.OW - 1); }
  } else {
    fy = (f32(oy) + 0.5)*f32(p.H)/f32(p.OH) - 0.5; if (fy < 0.0) { fy = 0.0; }
    fx = (f32(ox) + 0.5)*f32(p.W)/f32(p.OW) - 0.5; if (fx < 0.0) { fx = 0.0; }
  }
  var y0 = i32(fy); if (y0 > p.H - 1) { y0 = p.H - 1; }
  let y1 = select(p.H - 1, y0 + 1, y0 + 1 < p.H);
  var x0 = i32(fx); if (x0 > p.W - 1) { x0 = p.W - 1; }
  let x1 = select(p.W - 1, x0 + 1, x0 + 1 < p.W);
  let wy = fy - f32(y0); let wx = fx - f32(x0);
  let b = c*p.H*p.W;
  let v00 = X[b + y0*p.W + x0]; let v01 = X[b + y0*p.W + x1];
  let v10 = X[b + y1*p.W + x0]; let v11 = X[b + y1*p.W + x1];
  let top = v00 + (v01 - v00)*wx; let bot = v10 + (v11 - v10)*wx;
  Y[idx] = top + (bot - top)*wy;` },
gk32_resizenn: { sig: "(const float* X, float* Y, long long C, long long H, long long W, long long OH, long long OW, long long sh, long long sw)",
  body: `if (idx >= p.C*p.OH*p.OW) { return; }
  let ox = idx % p.OW; let oy = (idx / p.OW) % p.OH; let c = idx / (p.OW*p.OH);
  Y[idx] = X[(c*p.H + oy/p.sh)*p.W + ox/p.sw];` },
gk32_expandl: { sig: "(const float* X, float* Y, long long outer, long long rep)",
  body: `if (idx < p.outer*p.rep) { Y[idx] = X[idx/p.rep]; }` },

// ── reductions / index selection ──
gk32_rl2: { sig: "(const float* X, float* Y, long long outer, long long ax)",
  body: `if (idx >= p.outer) { return; }
  let off = idx*p.ax;
  var s = 0.0; for (var a = 0; a < p.ax; a = a + 1) { s = s + X[off + a]*X[off + a]; }
  Y[idx] = sqrt(s);` },
gk32_argmax: { sig: "(const float* X, long long* Y, long long outer, long long ax)",
  body: `if (idx >= p.outer) { return; }
  let off = idx*p.ax;
  var bi = 0; var bv = X[off];
  for (var j = 1; j < p.ax; j = j + 1) { let v = X[off + j]; if (v > bv) { bv = v; bi = j; } }
  Y[2*idx] = bi; Y[2*idx + 1] = 0;` },
gki_argmax: { sig: "(const long long* X, long long* Y, long long outer, long long ax)", extra: I64GT,
  body: `if (idx >= p.outer) { return; }
  let off = idx*p.ax;
  var bi = 0; var blo = X[2*off]; var bhi = X[2*off + 1];
  for (var j = 1; j < p.ax; j = j + 1) {
    let lo = X[2*(off + j)]; let hi = X[2*(off + j) + 1];
    if (i64_gt(lo, hi, blo, bhi)) { blo = lo; bhi = hi; bi = j; }
  }
  Y[2*idx] = bi; Y[2*idx + 1] = 0;` },
// an index is an i64; one outside i32 is outside any axis — it reads 0,
// as the CUDA body does for any out-of-range index
gk32_gather: { sig: "(const float* D, const long long* ix, float* Y, long long axin, long long inner, long long nidx, long long total)",
  body: `if (idx >= p.total) { return; }
  let ii = idx % p.inner; let t = idx / p.inner;
  let g = t % p.nidx; let o = t / p.nidx;
  var x = ix[2*g]; let fits = ix[2*g + 1] == (x >> 31u);
  if (x < 0) { x = x + p.axin; }
  var v = 0.0;
  if (fits && x >= 0 && x < p.axin) { v = D[(o*p.axin + x)*p.inner + ii]; }
  Y[idx] = v;` },
gk32_eosg: { sig: "(const float* data, const long long* tok, float* Y, long long B, long long L, long long D)", extra: I64GT,
  body: `if (idx >= p.B*p.D) { return; }
  let d = idx % p.D; let b = idx / p.D;
  let t0 = b*p.L;
  var pos = 0; var mlo = tok[2*t0]; var mhi = tok[2*t0 + 1];
  for (var j = 1; j < p.L; j = j + 1) {
    let lo = tok[2*(t0 + j)]; let hi = tok[2*(t0 + j) + 1];
    if (i64_gt(lo, hi, mlo, mhi)) { mlo = lo; mhi = hi; pos = j; }
  }
  Y[idx] = data[(b*p.L + pos)*p.D + d];` },
};

// ── the glue, generated from `sig` ────────────────────────────────────

const layouts = new Map();

// [{ c, w, kind }] in parameter order: the C name, the WGSL name, the
// CTYPES kind. Throws on a parameter type the glue cannot marshal.
export function layout(name) {
  let l = layouts.get(name);
  if (l) return l;
  const k = K[name];
  if (!k) throw new Error(`no WGSL kernel named ${name}`);
  const inner = k.sig.trim().replace(/^\(/, "").replace(/\)$/, "").trim();
  l = [];
  if (inner !== "") {
    for (const part of inner.split(",")) {
      const m = /^(.*?)([A-Za-z_][A-Za-z0-9_]*)\s*$/.exec(part.trim());
      const ctype = m ? m[1].trim().replace(/\s+/g, " ").replace(/\s+\*/g, "*") : "";
      const kind = CTYPES[ctype];
      if (!m || !kind) throw new Error(`${name}: parameter "${part.trim()}" has a type the WebGPU glue cannot marshal`);
      const c = m[2];
      l.push({ c, w: RESERVED.has(c) ? c + "_" : c, kind });
    }
  }
  layouts.set(name, l);
  return l;
}

const isBuf = (kind) => kind === "b" || kind === "w" || kind === "q" || kind === "Q";

// The uniform struct's members in order: [{ w, t: "i32"|"f32", c?, buf? }]
// — every scalar parameter, then nz_<buffer> for every buffer parameter.
export function uniformLayout(name) {
  const l = layout(name);
  const u = [];
  for (const a of l) if (!isBuf(a.kind)) u.push({ w: a.w, c: a.c, t: a.kind === "f" ? "f32" : "i32" });
  for (const a of l) if (isBuf(a.kind)) u.push({ w: "nz_" + a.w, buf: a.c, t: "i32" });
  return u;
}

// The bind-group layout: [{ binding, type }] with type "read-only-storage",
// "storage" or "uniform" — the buffers in parameter order, then the
// uniform block when there is one.
export function bindLayout(name) {
  const out = [];
  for (const a of layout(name)) {
    if (isBuf(a.kind)) out.push({ binding: out.length, type: (a.kind === "w" || a.kind === "Q") ? "storage" : "read-only-storage" });
  }
  if (uniformLayout(name).length) out.push({ binding: out.length, type: "uniform" });
  return out;
}

// Full WGSL for kernel `name`.
export function buildWGSL(name) {
  const k = K[name];
  const l = layout(name);
  let src = k.extra || "";
  let b = 0;
  for (const a of l) {
    if (!isBuf(a.kind)) continue;
    const acc = (a.kind === "w" || a.kind === "Q") ? "read_write" : "read";
    const elem = (a.kind === "q" || a.kind === "Q") ? "i32" : "f32";
    src += `@group(0) @binding(${b++}) var<storage, ${acc}> ${a.w}: array<${elem}>;\n`;
  }
  const u = uniformLayout(name);
  if (u.length) {
    src += "struct Params {\n" + u.map((m) => `  ${m.w}: ${m.t},`).join("\n") + "\n};\n";
    src += `@group(0) @binding(${b}) var<uniform> p: Params;\n`;
  }
  src += PRE + k.body + "\n}\n";
  return src;
}

// Decode a launch's argument cells (BigInt64 values, parameter order) into
// the storage-buffer ids (0 = the null pointer) and the uniform block.
// Returns { ids, uniform: ArrayBuffer, scalars: {cname: number} } or
// { error } — a long long that does not fit the i32 WGSL computes in is
// refused, never truncated.
export function marshal(name, cells) {
  const l = layout(name);
  if (cells.length !== l.length) return { error: `${name}: launched with ${cells.length} arguments, its parameter list has ${l.length}` };
  const u = uniformLayout(name);
  const ub = new ArrayBuffer(Math.max(16, Math.ceil(u.length * 4 / 16) * 16));
  const ubI = new Int32Array(ub), ubF = new Float32Array(ub);
  const ids = [], scalars = {}, at = new Map();
  u.forEach((m, i) => at.set(m.buf !== undefined ? "nz_" + m.buf : m.c, i));
  for (let i = 0; i < l.length; i++) {
    const a = l[i], v = BigInt.asIntN(64, BigInt(cells[i]));
    if (isBuf(a.kind)) {
      const id = Number(v);
      ids.push(id);
      ubI[at.get("nz_" + a.c)] = id !== 0 ? 1 : 0;
    } else if (a.kind === "f") {
      const fv = new Float32Array(new Int32Array([Number(BigInt.asIntN(32, v))]).buffer)[0];
      ubF[at.get(a.c)] = fv;
      scalars[a.c] = fv;
    } else {
      if (v < -2147483648n || v > 2147483647n) return { error: `${name}: argument ${a.c} = ${v} does not fit the i32 a WGSL kernel computes in` };
      ubI[at.get(a.c)] = Number(v);
      scalars[a.c] = Number(v);
    }
  }
  return { ids, uniform: ub, scalars };
}

// Invocations for a launch: the CUDA launch's thread count `total`
// (grid*block), unless the body maps work differently and says so.
export function dispatchInvocations(name, scalars, total) {
  const k = K[name];
  return k.invocations ? k.invocations(scalars) : total;
}
