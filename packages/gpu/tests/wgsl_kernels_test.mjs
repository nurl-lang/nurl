// wgsl_kernels_test.mjs — every WGSL kernel of web/kernels_wgsl.js, run on
// a real WebGPU device THROUGH THE HOST (web/webgpu.js: wgpu_pipeline /
// wgpu_alloc / wgpu_upload / wgpu_launch with i64 argument cells in wasm
// memory, exactly as a NURL wasm module calls them), against a JS
// reference that mirrors the kernel's CUDA-C source (gpukit's builders,
// as recorded by onnx's kernel census).
//
// Environment-neutral: export default(args, log) → exit code (0 pass,
// 1 fail, 2 no WebGPU adapter). Runners: tests/webgpu_test.sh (Deno, or
// headless Chrome through tests/webgpu_chrome.mjs).
//
// Every kernel in K must have a case here — a kernel added to the set
// without one fails the run.

import { makeWebGPUHost } from "../web/webgpu.js";
import { K, SENTINEL, layout } from "../web/kernels_wgsl.js";

const rnd = (n, lo = -2, hi = 2) => Float32Array.from({ length: n }, () => lo + Math.random() * (hi - lo));
const f32 = (a) => Math.fround(a);
const ceil = (a, b) => Math.floor((a + b - 1) / b);
// the CUDA launch's thread count for `work` items: whole 256-thread blocks
const thr = (work) => ceil(work, 256) * 256;

// ── references (JS mirrors of the CUDA-C) ──
const R = {
  gemm(A, B, C, M, N, Kd, alpha, beta, transB) {
    const Y = new Float32Array(M * N);
    for (let r = 0; r < M; r++) for (let c = 0; c < N; c++) {
      let acc = 0;
      for (let k = 0; k < Kd; k++) acc += A[r * Kd + k] * (transB ? B[c * Kd + k] : B[k * N + c]);
      Y[r * N + c] = alpha * acc + beta * (C ? C[c] : 0);
    }
    return Y;
  },
  conv(X, Wt, B, Cin, H, W, Cout, kh, kw, OH, OW, ph, pw, sh, sw, hasB, dh = 1, dw = 1) {
    const Y = new Float32Array(Cout * OH * OW);
    for (let oc = 0; oc < Cout; oc++) for (let oy = 0; oy < OH; oy++) for (let ox = 0; ox < OW; ox++) {
      let acc = hasB ? B[oc] : 0;
      for (let ic = 0; ic < Cin; ic++) for (let r = 0; r < kh; r++) {
        const iy = oy * sh - ph + r * dh; if (iy < 0 || iy >= H) continue;
        for (let s = 0; s < kw; s++) {
          const ix = ox * sw - pw + s * dw; if (ix < 0 || ix >= W) continue;
          acc += X[(ic * H + iy) * W + ix] * Wt[((oc * Cin + ic) * kh + r) * kw + s];
        }
      }
      Y[(oc * OH + oy) * OW + ox] = acc;
    }
    return Y;
  },
  convt(X, Wt, B, Cin, H, W, Cout, kh, kw, OH, OW, ph, pw, sh, sw, hasB) {
    const Y = new Float32Array(Cout * OH * OW);
    for (let oc = 0; oc < Cout; oc++) for (let oy = 0; oy < OH; oy++) for (let ox = 0; ox < OW; ox++) {
      let acc = hasB ? B[oc] : 0;
      for (let ic = 0; ic < Cin; ic++) for (let ky = 0; ky < kh; ky++) {
        const ty = oy + ph - ky; if (ty % sh !== 0) continue; const iy = ty / sh; if (iy < 0 || iy >= H) continue;
        for (let kx = 0; kx < kw; kx++) {
          const tx = ox + pw - kx; if (tx % sw !== 0) continue; const ix = tx / sw; if (ix < 0 || ix >= W) continue;
          acc += X[(ic * H + iy) * W + ix] * Wt[((ic * Cout + oc) * kh + ky) * kw + kx];
        }
      }
      Y[(oc * OH + oy) * OW + ox] = acc;
    }
    return Y;
  },
  erf(x) { // double-precision reference: Maclaurin series below 2.5, erfc's continued fraction above
    const s = x < 0 ? -1 : 1; x = Math.abs(x);
    if (x < 2.5) {
      let sum = 0, term = x, n = 0;
      while (Math.abs(term) > 1e-17 * Math.max(1, Math.abs(sum))) { sum += term / (2 * n + 1); n++; term *= -x * x / n; }
      return s * 2 / Math.sqrt(Math.PI) * sum;
    }
    let f = x; for (let k = 60; k >= 1; k--) f = x + (k / 2) / f;
    return s * (1 - Math.exp(-x * x) / Math.sqrt(Math.PI) / f);
  },
};

// Each case: { name, args: [...in parameter order], total, out: [argIndex...], ref: () => [Float32Array|BigInt64Array per out] }
// A buffer argument is a Float32Array / BigInt64Array (uploaded) or null
// (the null pointer); a scalar is a number (or BigInt for a long long).
function cases() {
  const cs = [];
  const add = (c) => cs.push(c);
  // gemm_tiled — transB is ignored, as in the CUDA body; both the
  // workgroup-per-output (M*N < 16384) and thread-per-output shapes, with
  // and without the bias pointer
  for (const [M, N, Kd, withC] of [[3, 5, 70, true], [1, 7, 300, false], [130, 130, 5, true], [129, 131, 3, false]]) {
    const A = rnd(M * Kd), B = rnd(Kd * N), C = withC ? rnd(N) : null;
    add({ name: "gk32_gemm_tiled", label: `M${M} N${N} K${Kd}${withC ? "" : " C=null"}`,
      args: [A, B, C, new Float32Array(M * N), M, N, Kd, 0.75, 1.25, 0], total: thr(ceil(M, 8) * ceil(N, 32)),
      out: [3], ref: () => [R.gemm(A, B, C, M, N, Kd, 0.75, 1.25, 0)] });
  }
  for (const [M, N, Kd, tb] of [[4, 6, 33, 1], [4, 6, 33, 0], [140, 120, 4, 1]]) {
    const A = rnd(M * Kd), B = rnd(Kd * N), C = rnd(N);
    add({ name: "gk32_gemm", label: `M${M} N${N} K${Kd} transB${tb}`,
      args: [A, B, C, new Float32Array(M * N), M, N, Kd, 1, 1, tb], total: thr(M * N),
      out: [3], ref: () => [R.gemm(A, B, C, M, N, Kd, 1, 1, tb)] });
  }
  { // bmm_tiled: 3 batches of [5x7]@[7x40], A/B batch strides with padding
    const nb = 3, M = 5, N = 40, Kd = 7, as = M * Kd + 3, bs = Kd * N + 5;
    const A = rnd(nb * as), B = rnd(nb * bs);
    const Y = new Float32Array(nb * M * N);
    for (let b = 0; b < nb; b++) for (let r = 0; r < M; r++) for (let c = 0; c < N; c++) {
      let acc = 0; for (let k = 0; k < Kd; k++) acc += A[b * as + r * Kd + k] * B[b * bs + k * N + c];
      Y[(b * M + r) * N + c] = acc;
    }
    const tiles = nb * ceil(M, 8) * ceil(N, 32);
    add({ name: "gk32_bmm_tiled", args: [A, B, new Float32Array(nb * M * N), M, N, Kd, as, bs, tiles], total: thr(tiles), out: [2], ref: () => [Y] });
  }
  // conv2d: every lane of the 2-channel × 4-wide body — k3s1 with an OW
  // tail, k3s2, k1s1, a generic k5, odd Cout, no bias
  for (const [label, Cin, H, W, Cout, kh, kw, ph, pw, sh, sw, hasB] of [
    ["k3s1 OW=7 tail", 3, 6, 7, 3, 3, 3, 1, 1, 1, 1, 1],
    ["k3s2", 3, 8, 8, 2, 3, 3, 1, 1, 2, 2, 1],
    ["k1s1", 4, 6, 8, 3, 1, 1, 0, 0, 1, 1, 1],
    ["k5s1 generic, no bias", 2, 9, 9, 5, 5, 5, 2, 2, 1, 1, 0]]) {
    const OH = Math.floor((H + 2 * ph - kh) / sh) + 1, OW = Math.floor((W + 2 * pw - kw) / sw) + 1;
    const X = rnd(Cin * H * W), Wt = rnd(Cout * Cin * kh * kw), B = hasB ? rnd(Cout) : null;
    add({ name: "gk32_conv2d", label, args: [X, Wt, B, new Float32Array(Cout * OH * OW), Cin, H, W, Cout, kh, kw, OH, OW, ph, pw, sh, sw, hasB],
      total: thr(ceil(Cout, 4) * OH * ceil(OW, 4)), out: [3], ref: () => [R.conv(X, Wt, B, Cin, H, W, Cout, kh, kw, OH, OW, ph, pw, sh, sw, hasB)] });
  }
  { const Cin = 2, H = 9, W = 8, Cout = 3, kh = 3, kw = 3, ph = 2, pw = 2, sh = 1, sw = 1, dh = 2, dw = 2;
    const OH = H + 2 * ph - dh * (kh - 1), OW = W + 2 * pw - dw * (kw - 1);
    const X = rnd(Cin * H * W), Wt = rnd(Cout * Cin * kh * kw), B = rnd(Cout);
    add({ name: "gk32_conv2d_dil", args: [X, Wt, B, new Float32Array(Cout * OH * OW), Cin, H, W, Cout, kh, kw, OH, OW, ph, pw, sh, sw, dh, dw, 1],
      total: thr(Cout * OH * OW), out: [3], ref: () => [R.conv(X, Wt, B, Cin, H, W, Cout, kh, kw, OH, OW, ph, pw, sh, sw, 1, dh, dw)] }); }
  { const Cin = 3, H = 3, W = 4, Cout = 2, kh = 2, kw = 2, sh = 2, sw = 2, OH = 6, OW = 8;
    const X = rnd(Cin * H * W), Wt = rnd(Cin * Cout * kh * kw), B = rnd(Cout);
    add({ name: "gk32_convt2d_up", args: [X, Wt, B, new Float32Array(Cout * OH * OW), Cin, H, W, Cout, kh, kw, OH, OW, 0, 0, sh, sw, 1],
      total: thr(Cout * OH * OW), out: [3], ref: () => [R.convt(X, Wt, B, Cin, H, W, Cout, kh, kw, OH, OW, 0, 0, sh, sw, 1)] }); }
  { const Cin = 2, H = 3, W = 3, Cout = 2, kh = 3, kw = 3, ph = 1, pw = 1, sh = 2, sw = 2, OH = 5, OW = 5;
    const X = rnd(Cin * H * W), Wt = rnd(Cin * Cout * kh * kw), B = rnd(Cout);
    add({ name: "gk32_convt2d", args: [X, Wt, B, new Float32Array(Cout * OH * OW), Cin, H, W, Cout, kh, kw, OH, OW, ph, pw, sh, sw, 1],
      total: thr(Cout * OH * OW), out: [3], ref: () => [R.convt(X, Wt, B, Cin, H, W, Cout, kh, kw, OH, OW, ph, pw, sh, sw, 1)] }); }
  { const C = 2, H = 5, W = 5, kh = 3, kw = 3, sh = 2, sw = 2, ph = 1, pw = 1, OH = 3, OW = 3; const X = rnd(C * H * W);
    const Y = new Float32Array(C * OH * OW);
    for (let c = 0; c < C; c++) for (let oh = 0; oh < OH; oh++) for (let ow = 0; ow < OW; ow++) {
      let m = -1e30;
      for (let r = 0; r < kh; r++) { const ih = oh * sh - ph + r; if (ih < 0 || ih >= H) continue;
        for (let s = 0; s < kw; s++) { const iw = ow * sw - pw + s; if (iw < 0 || iw >= W) continue; m = Math.max(m, X[(c * H + ih) * W + iw]); } }
      Y[(c * OH + oh) * OW + ow] = m;
    }
    add({ name: "gk32_maxpool2d", args: [X, new Float32Array(C * OH * OW), C, H, W, kh, kw, OH, OW, sh, sw, ph, pw], total: thr(C * OH * OW), out: [1], ref: () => [Y] }); }
  { const C = 3, HW = 5, eps = 1e-5; const X = rnd(C * HW), sc = rnd(C), B = rnd(C), mean = rnd(C), vr = rnd(C, 0.5, 1.5);
    const Y = new Float32Array(C * HW); for (let i = 0; i < C * HW; i++) { const c = Math.floor(i / HW); Y[i] = sc[c] * (X[i] - mean[c]) / Math.sqrt(vr[c] + f32(eps)) + B[c]; }
    add({ name: "gk32_bnorm", args: [X, sc, B, mean, vr, new Float32Array(C * HW), C, HW, eps], total: thr(C * HW), out: [5], ref: () => [Y] }); }
  const unary = (name, fn, extra = [], n = 300) => {
    const X = rnd(n, -4, 4);
    add({ name, args: [X, new Float32Array(n), n, ...extra], total: thr(n), out: [1], ref: () => [Float32Array.from(X, fn)] });
  };
  unary("gk32_relu", (x) => x > 0 ? x : 0);
  unary("gk32_sigmoid", (x) => 1 / (1 + Math.exp(-x)));
  unary("gk32_lrelu", (x) => x >= 0 ? x : f32(0.1) * x, [0.1]);
  unary("gk32_clip", (x) => x < -0.5 ? -0.5 : (x > 1.5 ? 1.5 : x), [-0.5, 1.5]);
  unary("gk32_erf", (x) => R.erf(x));
  { const outer = 3, ax = 7, eps = 1e-5; const X = rnd(outer * ax), sc = rnd(ax), bi = rnd(ax); const Y = new Float32Array(outer * ax);
    for (let o = 0; o < outer; o++) { let m = 0; for (let j = 0; j < ax; j++) m += X[o * ax + j]; m /= ax;
      let v = 0; for (let j = 0; j < ax; j++) { const d = X[o * ax + j] - m; v += d * d; } v /= ax;
      const inv = 1 / Math.sqrt(v + f32(eps)); for (let j = 0; j < ax; j++) Y[o * ax + j] = (X[o * ax + j] - m) * inv * sc[j] + bi[j]; }
    add({ name: "gk32_lnorm", args: [X, sc, bi, new Float32Array(outer * ax), outer, ax, eps], total: thr(outer), out: [3], ref: () => [Y] }); }
  { const outer = 3, ax = 4, inner = 5; const X = rnd(outer * ax * inner); const Y = new Float32Array(outer * ax * inner);
    for (let io = 0; io < outer; io++) for (let ii = 0; ii < inner; ii++) { const b = io * ax * inner + ii;
      let m = -1e30; for (let a = 0; a < ax; a++) m = Math.max(m, X[b + a * inner]);
      let s = 0; for (let a = 0; a < ax; a++) s += Math.exp(X[b + a * inner] - m);
      for (let a = 0; a < ax; a++) Y[b + a * inner] = Math.exp(X[b + a * inner] - m) / s; }
    add({ name: "gk32_softmaxax", args: [X, new Float32Array(outer * ax * inner), outer, ax, inner], total: thr(outer * inner), out: [1], ref: () => [Y] }); }
  // broadcast: out [2,3,4] (as 6 dims [1,1,1,2,3,4]); a full, b broadcast over the middle axis
  for (const [name, op] of [["gk32_bcmul", (x, y) => x * y], ["gk32_bcadd", (x, y) => x + y], ["gk32_bcsub", (x, y) => x - y], ["gk32_bcdiv", (x, y) => x / y]]) {
    const d = [1, 1, 1, 2, 3, 4], As = [0, 0, 0, 12, 4, 1], Bs = [0, 0, 0, 4, 0, 1];
    const a = rnd(24), b = rnd(8, 0.5, 2); const n = 24; const Y = new Float32Array(n);
    for (let i = 0; i < n; i++) { let t = i, ai = 0, bi = 0; for (let k = 5; k >= 1; k--) { const c = t % d[k]; t = Math.floor(t / d[k]); ai += c * As[k]; bi += c * Bs[k]; } ai += t * As[0]; bi += t * Bs[0]; Y[i] = op(a[ai], b[bi]); }
    add({ name, args: [a, b, new Float32Array(n), n, ...d, ...As, ...Bs], total: thr(n), out: [2], ref: () => [Y] });
  }
  { const outer = 2, src_ax = 5, inner = 3, sz = 2, soff = 2; const S = rnd(outer * src_ax * inner); const Y = [];
    for (let o = 0; o < outer; o++) for (let a = 0; a < sz; a++) for (let ii = 0; ii < inner; ii++) Y.push(S[(o * src_ax + soff + a) * inner + ii]);
    add({ name: "gk32_sliceax", args: [S, new Float32Array(outer * sz * inner), outer, sz, inner, src_ax, soff], total: thr(outer * sz * inner), out: [1], ref: () => [Float32Array.from(Y)] }); }
  { const outer = 2, src_ax = 2, inner = 3, dst_ax = 5, off = 1; const S = rnd(outer * src_ax * inner); const D0 = rnd(outer * dst_ax * inner);
    const Y = Float32Array.from(D0); for (let o = 0; o < outer; o++) for (let a = 0; a < src_ax; a++) for (let ii = 0; ii < inner; ii++) Y[(o * dst_ax + off + a) * inner + ii] = S[(o * src_ax + a) * inner + ii];
    add({ name: "gk32_copyax", args: [S, D0, outer, src_ax, inner, dst_ax, off], total: thr(outer * src_ax * inner), out: [1], ref: () => [Y] }); }
  { const d = [1, 2, 1, 3, 1, 4], P = [0, 5, 2, 1, 4, 3]; const X = rnd(24);
    const O = P.map((q) => d[q]); const tot = O.reduce((x, y) => x * y, 1); const Y = new Float32Array(tot);
    for (let idx = 0; idx < tot; idx++) { const oc = []; let t = idx; for (let i = 5; i >= 0; i--) { oc[i] = t % O[i]; t = Math.floor(t / O[i]); }
      const inn = []; for (let i = 0; i < 6; i++) inn[P[i]] = oc[i];
      Y[idx] = X[((((inn[0] * d[1] + inn[1]) * d[2] + inn[2]) * d[3] + inn[3]) * d[4] + inn[4]) * d[5] + inn[5]]; }
    add({ name: "gk32_perm6", args: [X, new Float32Array(tot), ...d, ...P], total: thr(tot), out: [1], ref: () => [Y] }); }
  for (const align of [0, 1]) {
    const C = 2, H = 3, W = 4, OH = 7, OW = 5; const X = rnd(C * H * W); const Y = new Float32Array(C * OH * OW);
    for (let idx = 0; idx < C * OH * OW; idx++) { const ox = idx % OW, oy = Math.floor(idx / OW) % OH, c = Math.floor(idx / (OW * OH));
      let fy, fx; if (align) { fy = OH > 1 ? oy * (H - 1) / (OH - 1) : 0; fx = OW > 1 ? ox * (W - 1) / (OW - 1) : 0; }
      else { fy = (oy + 0.5) * H / OH - 0.5; if (fy < 0) fy = 0; fx = (ox + 0.5) * W / OW - 0.5; if (fx < 0) fx = 0; }
      let y0 = Math.trunc(fy); if (y0 > H - 1) y0 = H - 1; const y1 = y0 + 1 < H ? y0 + 1 : H - 1;
      let x0 = Math.trunc(fx); if (x0 > W - 1) x0 = W - 1; const x1 = x0 + 1 < W ? x0 + 1 : W - 1;
      const wy = fy - y0, wx = fx - x0, p = c * H * W;
      const top = X[p + y0 * W + x0] + (X[p + y0 * W + x1] - X[p + y0 * W + x0]) * wx, bot = X[p + y1 * W + x0] + (X[p + y1 * W + x1] - X[p + y1 * W + x0]) * wx;
      Y[idx] = top + (bot - top) * wy; }
    add({ name: "gk32_resizebilin", label: `align${align}`, args: [X, new Float32Array(C * OH * OW), C, H, W, OH, OW, align], total: thr(C * OH * OW), out: [1], ref: () => [Y] });
  }
  { const C = 2, H = 2, W = 3, sh = 2, sw = 3, OH = 4, OW = 9; const X = rnd(C * H * W); const Y = new Float32Array(C * OH * OW);
    for (let idx = 0; idx < C * OH * OW; idx++) { const ox = idx % OW, oy = Math.floor(idx / OW) % OH, c = Math.floor(idx / (OW * OH)); Y[idx] = X[(c * H + Math.floor(oy / sh)) * W + Math.floor(ox / sw)]; }
    add({ name: "gk32_resizenn", args: [X, new Float32Array(C * OH * OW), C, H, W, OH, OW, sh, sw], total: thr(C * OH * OW), out: [1], ref: () => [Y] }); }
  { const outer = 5, rep = 3; const X = rnd(outer); const Y = new Float32Array(outer * rep); for (let i = 0; i < outer * rep; i++) Y[i] = X[Math.floor(i / rep)];
    add({ name: "gk32_expandl", args: [X, new Float32Array(outer * rep), outer, rep], total: thr(outer * rep), out: [1], ref: () => [Y] }); }
  { const outer = 4, ax = 6; const X = rnd(outer * ax); const Y = new Float32Array(outer);
    for (let o = 0; o < outer; o++) { let s = 0; for (let a = 0; a < ax; a++) s += X[o * ax + a] ** 2; Y[o] = Math.sqrt(s); }
    add({ name: "gk32_rl2", args: [X, new Float32Array(outer), outer, ax], total: thr(outer), out: [1], ref: () => [Y] }); }
  { const outer = 3, ax = 5; const X = rnd(outer * ax); const Y = new BigInt64Array(outer);
    for (let o = 0; o < outer; o++) { let bi = 0; for (let j = 1; j < ax; j++) if (X[o * ax + j] > X[o * ax + bi]) bi = j; Y[o] = BigInt(bi); }
    add({ name: "gk32_argmax", args: [X, new BigInt64Array(outer).fill(-7n), outer, ax], total: thr(outer), out: [1], ref: () => [Y] }); }
  { // i64 values that only the high word tells apart (and negatives)
    const X = BigInt64Array.from([5n, 1n << 33n, (1n << 33n) + 1n, -3n, 7n, -1n << 40n, 2n, 3n, 9n, -9n]); const outer = 2, ax = 5;
    const Y = new BigInt64Array(outer);
    for (let o = 0; o < outer; o++) { let bi = 0; for (let j = 1; j < ax; j++) if (X[o * ax + j] > X[o * ax + bi]) bi = j; Y[o] = BigInt(bi); }
    add({ name: "gki_argmax", args: [X, new BigInt64Array(outer), outer, ax], total: thr(outer), out: [1], ref: () => [Y] }); }
  { // gather: a negative index, an out-of-range one, one beyond i32
    const outer = 2, axin = 4, inner = 3; const D = rnd(outer * axin * inner); const ix = BigInt64Array.from([2n, -1n, 4n, 1n << 35n, 0n]); const nidx = ix.length;
    const total = outer * nidx * inner; const Y = new Float32Array(total);
    for (let i = 0; i < total; i++) { const ii = i % inner, t = Math.floor(i / inner), g = t % nidx, o = Math.floor(t / nidx);
      let x = ix[g]; if (x < 0n) x += BigInt(axin); Y[i] = (x >= 0n && x < BigInt(axin)) ? D[(o * axin + Number(x)) * inner + ii] : 0; }
    add({ name: "gk32_gather", args: [D, ix, new Float32Array(total), axin, inner, nidx, total], total: thr(total), out: [2], ref: () => [Y] }); }
  { const B = 2, L = 4, Dd = 3; const data = rnd(B * L * Dd); const tok = BigInt64Array.from([5n, 49407n, 2n, 0n, 1n << 34n, 3n, (1n << 34n) + 2n, 1n]);
    const Y = new Float32Array(B * Dd);
    for (let i = 0; i < B * Dd; i++) { const d = i % Dd, b = Math.floor(i / Dd); let pos = 0; for (let j = 1; j < L; j++) if (tok[b * L + j] > tok[b * L + pos]) pos = j; Y[i] = data[(b * L + pos) * Dd + d]; }
    add({ name: "gk32_eosg", args: [data, tok, new Float32Array(B * Dd), B, L, Dd], total: thr(B * Dd), out: [2], ref: () => [Y] }); }
  return cs;
}

export default async function run(args, log = console.log) {
  const host = await makeWebGPUHost();
  if (!host.ok) { log("no WebGPU adapter"); return 2; }
  log(`adapter: ${host.describe()}${host.isFallback ? " (software)" : ""}`);
  const memory = new WebAssembly.Memory({ initial: 256 });
  host.bind({ exports: { memory } });
  const H = host.imports;
  const u8 = () => new Uint8Array(memory.buffer);
  const dv = () => new DataView(memory.buffer);
  let pass = 0, fail = 0;
  const ok = (cond, what) => { log(`${cond ? "PASS" : "FAIL"} ${what}`); cond ? pass++ : fail++; };

  // the sentinel gpu_open probes
  u8().set(new TextEncoder().encode(SENTINEL + "\0"), 64);
  ok(H.wgpu_pipeline(64) > 0n, `sentinel ${SENTINEL} compiles`);

  const all = cases();
  const covered = new Set(all.map((c) => c.name));
  for (const name of Object.keys(K)) if (name !== SENTINEL && !covered.has(name)) ok(false, `${name}: no test case`);

  for (const c of all) {
    const tag = c.name + (c.label ? ` [${c.label}]` : "");
    u8().set(new TextEncoder().encode(c.name + "\0"), 64);
    const pid = H.wgpu_pipeline(64);
    if (pid <= 0n) { ok(false, `${tag}: no pipeline`); continue; }
    const l = layout(c.name);
    if (l.length !== c.args.length) { ok(false, `${tag}: case has ${c.args.length} args, kernel ${l.length}`); continue; }
    // upload buffers through a staging area, write the argument cells
    const ids = [];
    let at = 4096;
    for (let i = 0; i < l.length; i++) {
      const a = c.args[i];
      if (a && a.buffer) {
        const id = H.wgpu_alloc(BigInt(a.byteLength));
        u8().set(new Uint8Array(a.buffer, a.byteOffset, a.byteLength), at);
        H.wgpu_upload(id, BigInt(at), BigInt(a.byteLength));
        ids[i] = id;
      } else ids[i] = 0n;
    }
    const cells = 1024;
    for (let i = 0; i < l.length; i++) {
      const a = c.args[i], k = l[i].kind;
      let v;
      if (k === "b" || k === "w" || k === "q" || k === "Q") v = ids[i];
      else if (k === "f") v = BigInt(new Int32Array(new Float32Array([a]).buffer)[0]);
      else v = BigInt(a);
      dv().setBigInt64(cells + i * 8, v, true);
    }
    const r = H.wgpu_launch(pid, BigInt(c.total), BigInt(cells), BigInt(l.length));
    if (r !== 0n) { ok(false, `${tag}: launch returned ${r}`); continue; }
    const refs = c.ref();
    let worst = 0, bad = false;
    for (let j = 0; j < c.out.length; j++) {
      const oi = c.out[j], want = refs[j];
      const got = await host.readBuffer(ids[oi], c.args[oi].byteLength);
      if (want instanceof BigInt64Array) {
        const g = new BigInt64Array(got);
        for (let e = 0; e < want.length; e++) if (g[e] !== want[e]) { bad = true; log(`   [${e}] got ${g[e]} want ${want[e]}`); break; }
      } else {
        const g = new Float32Array(got);
        for (let e = 0; e < want.length; e++) {
          const d = Math.abs(g[e] - want[e]) / Math.max(1, Math.abs(want[e]));
          if (!(d <= 2e-5)) { if (!bad) log(`   [${e}] got ${g[e]} want ${want[e]}`); bad = true; }
          worst = Math.max(worst, d || 0);
        }
      }
    }
    for (const id of ids) if (id) H.wgpu_free(id);
    ok(!bad, `${tag}  max rel err ${worst.toExponential(1)}`);
  }

  { // a long long that does not fit the i32 WGSL computes in is refused
    u8().set(new TextEncoder().encode("gk32_relu\0"), 64);
    const pid = H.wgpu_pipeline(64);
    const x = H.wgpu_alloc(16n), y = H.wgpu_alloc(16n);
    dv().setBigInt64(1024, x, true); dv().setBigInt64(1032, y, true); dv().setBigInt64(1040, 1n << 40n, true);
    const prev = console.error; console.error = () => {};
    const r = H.wgpu_launch(pid, 256n, 1024n, 3n);
    console.error = prev;
    ok(r === -3n, "a long long beyond i32 is refused, not truncated");
    H.wgpu_free(x); H.wgpu_free(y);
  }
  log(`\n=== ${pass} PASS · ${fail} FAIL ===`);
  return fail ? 1 : 0;
}

// Deno: `deno run --unstable-webgpu --allow-all tests/wgsl_kernels_test.mjs`
if (typeof Deno !== "undefined" && import.meta.main) Deno.exit(await run([]));
