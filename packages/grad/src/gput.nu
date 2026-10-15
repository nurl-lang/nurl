// grad/gput.nu — the GPU replay engine: run a captured tape episode on the
// device, bit-exactly.
//
// The CPU tape (grad.nu) stays the semantic reference. `gput_capture` takes
// ONE recorded episode — parameters, constants, every op node up to the loss
// — and mirrors it onto the device: a value buffer and a gradient buffer per
// node, plus the stride/offset metadata each kernel needs. After capture the
// graph is STATIC (the mark/reset training loop re-records the same node
// structure every episode anyway): per minibatch the caller uploads fresh
// input rows into their const slots (`gput_set_input`), replays forward and
// backward on the device, and steps the device optimizer — nothing but the
// loss scalar needs to come back to the host.
//
// Bit-exactness discipline (the aegpu recipe, generalized per op):
//   * Every kernel reproduces the CPU implementation's floating-point
//     ROUNDING AND ORDER: accumulation chains are spelled with explicit
//     __dadd_rn/__dsub_rn/__dmul_rn/__ddiv_rn (never fused — NVRTC's default
//     fmad contraction would change results), inner products and reductions
//     run serially in the CPU's documented index order inside one thread,
//     and broadcast-reduce accumulation walks each slot's contributions in
//     the same row-major subsequence order as grad.nu's _g_acc_reduce.
//   * Optimizer scalars that need libm pow (Adam's lr_t) are computed on the
//     HOST with the same expressions opt.nu uses and shipped to the kernel.
//   * exp/log-based unaries (sigmoid, tanh, exp, log, softmax) mirror the
//     CPU FORMULAS exactly, but the device's exp()/log() are CUDA libm: on
//     the gpu package's CPU backend they are glibc and the results are
//     bit-identical; on real CUDA hardware they can differ by a few ulp.
//     Everything else — relu, +, −, ×, ÷, sqrt, matmul/bmm, sum/mean, data
//     movement, SGD/Adam — is bit-exact on BOTH backends. An MLP/AE
//     workload (relu + linear + mse + Adam) is therefore bit-exact
//     end-to-end everywhere; tests/gput_parity_test.nu pins both tiers.
//
// Coverage: every grad.nu op. Restrictions (capture poisons with a message):
// TE_F64 tapes only, and g_bmm only with both operands carrying the full
// batch (no batch broadcast).
//
// Ownership: GProg owns every device buffer; one gput_free. The tape is
// borrowed during capture and NOT needed afterwards (except as the target of
// gput_param_sync_host, which writes trained parameter values back into the
// tape's own tensors so gvar_value keeps working).

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `grad.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/tensor/src/ops.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/slice.nu`

// ── the kernels ───────────────────────────────────────────────────────
// Every kernel is a gpukit CHECKED kernel (gk_record_dev / gk_replay): it
// reaches the program's buffers only through LD / ST, which check every
// index against the buffer bound, so a launch is safe whatever sizes it is
// handed and needs no `unsafe` to vouch for them. Written once in f64; the
// metadata blocks (strides and offsets, i64) are read the same way.
@ __gp_body s name → s {
    ? != 0 ( nurl_str_eq name `fill` ) { ^ `if (gid < n) { double vv = (double)v; ST(o, gid, vv); }` } {}
    ? != 0 ( nurl_str_eq name `ew_bc` ) { ^ `if (gid < n) {
    long long nd = LD(meta, moff);
    long long rem = gid;
    long long ao = 0;
    long long bo = 0;
    for (long long d = 0; d < nd; d++) {
        long long st = LD(meta, moff + 1 + d);
        long long q = st > 0 ? rem / st : 0;
        if (st > 0) rem = rem % st;
        ao += q * LD(meta, moff + 1 + nd + d);
        bo += q * LD(meta, moff + 1 + 2 * nd + d);
    }
    double x = LD(a, ao);
    double y = LD(b, bo);
    double r;
    if (op == 2) r = __dadd_rn(x, y);
    else if (op == 3) r = __dsub_rn(x, y);
    else if (op == 4) r = __dmul_rn(x, y);
    else r = __ddiv_rn(x, y);
    ST(o, gid, r);
}` } {}
    ? != 0 ( nurl_str_eq name `scal` ) { ^ `if (gid < n) {
    double cc = (double)c;
    double x = LD(a, gid);
    double y;
    if (op == 6) y = __dsub_rn(0.0, x);
    else if (op == 7) y = __dadd_rn(x, cc);
    else if (op == 8) y = __dmul_rn(x, cc);
    else y = x > 0.0 ? x : 0.0;
    ST(o, gid, y);
}` } {}
    ? != 0 ( nurl_str_eq name `trans` ) { ^ `if (gid < n) {
    double x = LD(a, gid);
    double y;
    if (op == 10) { double e = exp(__dsub_rn(0.0, x)); y = __ddiv_rn(1.0, __dadd_rn(1.0, e)); }
    else if (op == 11) { double e2 = exp(__dmul_rn(2.0, x)); y = __ddiv_rn(__dsub_rn(e2, 1.0), __dadd_rn(e2, 1.0)); }
    else if (op == 12) y = exp(x);
    else if (op == 13) y = log(x);
    else y = sqrt(x);
    ST(o, gid, y);
}` } {}
    ? != 0 ( nurl_str_eq name `reduce` ) { ^ `if (gid == 0) {
    double acc = 0.0;
    long long k = 0;
    for (; k + 8 <= n; k += 8) {
        double x0 = LD(a, k);
        double x1 = LD(a, k + 1);
        double x2 = LD(a, k + 2);
        double x3 = LD(a, k + 3);
        double x4 = LD(a, k + 4);
        double x5 = LD(a, k + 5);
        double x6 = LD(a, k + 6);
        double x7 = LD(a, k + 7);
        acc = __dadd_rn(acc, x0);
        acc = __dadd_rn(acc, x1);
        acc = __dadd_rn(acc, x2);
        acc = __dadd_rn(acc, x3);
        acc = __dadd_rn(acc, x4);
        acc = __dadd_rn(acc, x5);
        acc = __dadd_rn(acc, x6);
        acc = __dadd_rn(acc, x7);
    }
    for (; k < n; k++) acc = __dadd_rn(acc, LD(a, k));
    if (op == 16) acc = __ddiv_rn(acc, (double)n);
    ST(o, 0, acc);
}` } {}
    ? != 0 ( nurl_str_eq name `matmul` ) { ^ `if (gid < M * N) {
    long long r = gid / N;
    long long cx = gid % N;
    double s = 0.0;
    for (long long p = 0; p < K; p++) s = __dadd_rn(s, __dmul_rn(LD(a, r * K + p), LD(b, p * N + cx)));
    ST(c, gid, s);
}` } {}
    ? != 0 ( nurl_str_eq name `bmm` ) { ^ `if (gid < B * M * N) {
    long long bb = gid / (M * N);
    long long rest = gid % (M * N);
    long long r = rest / N;
    long long cx = rest % N;
    long long ab = bb * M * K;
    long long bp = bb * K * N;
    double s = 0.0;
    for (long long p = 0; p < K; p++) s = __dadd_rn(s, __dmul_rn(LD(a, ab + r * K + p), LD(b, bp + p * N + cx)));
    ST(c, gid, s);
}` } {}
    ? != 0 ( nurl_str_eq name `transpose` ) { ^ `if (gid < M * N) { long long r = gid / N; long long cx = gid % N; ST(o, cx * M + r, LD(a, gid)); }` } {}
    ? != 0 ( nurl_str_eq name `copy` ) { ^ `if (gid < n) ST(o, gid, LD(a, gid));` } {}
    ? != 0 ( nurl_str_eq name `softmax` ) { ^ `if (gid < outer * inner) {
    long long ou = gid / inner;
    long long in2 = gid % inner;
    long long base = ou * ax * inner + in2;
    double m = LD(x, base);
    for (long long t = 1; t < ax; t++) {
        double xv = LD(x, base + t * inner);
        if (xv > m) m = xv;
    }
    double s = 0.0;
    for (long long t = 0; t < ax; t++) {
        double e = exp(__dsub_rn(LD(x, base + t * inner), m));
        ST(o, base + t * inner, e);
    }
    for (long long t = 0; t < ax; t++) s = __dadd_rn(s, LD(o, base + t * inner));
    for (long long t = 0; t < ax; t++) {
        long long ix = base + t * inner;
        ST(o, ix, __ddiv_rn(LD(o, ix), s));
    }
}` } {}
    ? != 0 ( nurl_str_eq name `slice_fwd` ) { ^ `if (gid < n) {
    long long nd = LD(meta, 0);
    long long rem = gid;
    long long ino = 0;
    for (long long d = 0; d < nd; d++) {
        long long sd = LD(meta, 1 + d);
        long long q = sd > 0 ? rem / sd : 0;
        if (sd > 0) rem = rem % sd;
        ino += (q + LD(meta, 1 + 2 * nd + d)) * LD(meta, 1 + nd + d);
    }
    ST(o, gid, LD(a, ino));
}` } {}
    ? != 0 ( nurl_str_eq name `concat_fwd` ) { ^ `if (gid < outer * ax * inner) {
    long long ou = gid / (ax * inner);
    long long t = (gid / inner) % ax;
    long long in2 = gid % inner;
    if (t < da) ST(o, gid, LD(a, (ou * da + t) * inner + in2));
    else ST(o, gid, LD(b, (ou * (ax - da) + (t - da)) * inner + in2));
}` } {}
    ? != 0 ( nurl_str_eq name `bw_accred` ) { ^ `if (gid < in_n) {
    double sg = (double)sgn;
    long long nd = LD(meta, moff);
    long long rem = gid;
    long long base = 0;
    for (long long d = 0; d < nd; d++) {
        long long st = LD(meta, moff + 1 + nd + d);
        long long ix = st > 0 ? rem / st : 0;
        if (st > 0) rem = rem % st;
        base += ix * LD(meta, moff + 1 + d);
    }
    double g0 = LD(ga, gid);
    for (long long q = 0; q < tfree; q++) {
        long long r2 = q;
        long long off = base;
        for (long long d = 0; d < nd; d++) {
            long long st = LD(meta, moff + 1 + 3 * nd + d);
            long long jx = st > 0 ? r2 / st : 0;
            if (st > 0) r2 = r2 % st;
            off += jx * LD(meta, moff + 1 + d);
        }
        g0 = __dadd_rn(g0, __dmul_rn(sg, LD(c, off)));
    }
    ST(ga, gid, g0);
}` } {}
    ? != 0 ( nurl_str_eq name `bw_unary` ) { ^ `if (gid < n) {
    double cc = (double)c;
    double gi = LD(g, gid);
    double a0 = LD(ga, gid);
    if (op == 6) a0 = __dsub_rn(a0, gi);
    else if (op == 7) a0 = __dadd_rn(a0, gi);
    else if (op == 8) a0 = __dadd_rn(a0, __dmul_rn(gi, cc));
    else if (op == 9) { if (LD(y, gid) > 0.0) a0 = __dadd_rn(a0, gi); }
    else if (op == 10) { double yj = LD(y, gid); a0 = __dadd_rn(a0, __dmul_rn(gi, __dmul_rn(yj, __dsub_rn(1.0, yj)))); }
    else if (op == 11) { double yj = LD(y, gid); a0 = __dadd_rn(a0, __dmul_rn(gi, __dsub_rn(1.0, __dmul_rn(yj, yj)))); }
    else if (op == 12) a0 = __dadd_rn(a0, __dmul_rn(gi, LD(y, gid)));
    else if (op == 13) a0 = __dadd_rn(a0, __ddiv_rn(gi, LD(x, gid)));
    else a0 = __dadd_rn(a0, __ddiv_rn(gi, __dmul_rn(2.0, LD(y, gid))));
    ST(ga, gid, a0);
}` } {}
    ? != 0 ( nurl_str_eq name `bw_reduce` ) { ^ `if (gid < an) {
    double g0 = LD(g, 0);
    if (op == 16) g0 = __ddiv_rn(g0, (double)an);
    ST(ga, gid, __dadd_rn(LD(ga, gid), g0));
}` } {}
    ? != 0 ( nurl_str_eq name `bw_mm_a` ) { ^ `if (gid < M * K) {
    long long i = gid / K;
    long long p = gid % K;
    double acc = 0.0;
    for (long long j = 0; j < N; j++) acc = __dadd_rn(acc, __dmul_rn(LD(g, i * N + j), LD(b, p * N + j)));
    ST(ga, gid, __dadd_rn(LD(ga, gid), acc));
}` } {}
    ? != 0 ( nurl_str_eq name `bw_mm_b` ) { ^ `if (gid < K * N) {
    long long p = gid / N;
    long long j = gid % N;
    double acc = 0.0;
    for (long long i = 0; i < M; i++) acc = __dadd_rn(acc, __dmul_rn(LD(a, i * K + p), LD(g, i * N + j)));
    ST(gb, gid, __dadd_rn(LD(gb, gid), acc));
}` } {}
    ? != 0 ( nurl_str_eq name `bw_bmm_a` ) { ^ `if (gid < B * M * K) {
    long long bb = gid / (M * K);
    long long rest = gid % (M * K);
    long long i = rest / K;
    long long p = rest % K;
    long long gb2 = bb * M * N;
    long long bp = bb * K * N;
    double acc = 0.0;
    for (long long j = 0; j < N; j++) acc = __dadd_rn(acc, __dmul_rn(LD(g, gb2 + i * N + j), LD(b, bp + p * N + j)));
    ST(ga, gid, __dadd_rn(LD(ga, gid), acc));
}` } {}
    ? != 0 ( nurl_str_eq name `bw_bmm_b` ) { ^ `if (gid < B * K * N) {
    long long bb = gid / (K * N);
    long long rest = gid % (K * N);
    long long p = rest / N;
    long long j = rest % N;
    long long ab = bb * M * K;
    long long gp2 = bb * M * N;
    double acc = 0.0;
    for (long long i = 0; i < M; i++) acc = __dadd_rn(acc, __dmul_rn(LD(a, ab + i * K + p), LD(g, gp2 + i * N + j)));
    ST(gbo, gid, __dadd_rn(LD(gbo, gid), acc));
}` } {}
    ? != 0 ( nurl_str_eq name `bw_transpose` ) { ^ `if (gid < M * N) { long long r = gid / N; long long cx = gid % N; ST(ga, gid, __dadd_rn(LD(ga, gid), LD(g, cx * M + r))); }` } {}
    ? != 0 ( nurl_str_eq name `bw_copy` ) { ^ `if (gid < n) ST(ga, gid, __dadd_rn(LD(ga, gid), LD(g, gid)));` } {}
    ? != 0 ( nurl_str_eq name `bw_softmax` ) { ^ `if (gid < outer * inner) {
    long long ou = gid / inner;
    long long in2 = gid % inner;
    long long base = ou * ax * inner + in2;
    double dot = 0.0;
    for (long long t = 0; t < ax; t++) { long long ix = base + t * inner; dot = __dadd_rn(dot, __dmul_rn(LD(g, ix), LD(y, ix))); }
    for (long long t = 0; t < ax; t++) { long long ix = base + t * inner; ST(ga, ix, __dadd_rn(LD(ga, ix), __dmul_rn(LD(y, ix), __dsub_rn(LD(g, ix), dot)))); }
}` } {}
    ? != 0 ( nurl_str_eq name `bw_slice` ) { ^ `if (gid < n) {
    long long nd = LD(meta, 0);
    long long rem = gid;
    long long ioff = 0;
    for (long long d = 0; d < nd; d++) {
        long long sd = LD(meta, 1 + d);
        long long q = sd > 0 ? rem / sd : 0;
        if (sd > 0) rem = rem % sd;
        ioff += (q + LD(meta, 1 + 2 * nd + d)) * LD(meta, 1 + nd + d);
    }
    ST(ga, ioff, __dadd_rn(LD(ga, ioff), LD(g, gid)));
}` } {}
    ? != 0 ( nurl_str_eq name `bw_concat` ) { ^ `if (gid < outer * ax * inner) {
    long long ou = gid / (ax * inner);
    long long t = (gid / inner) % ax;
    long long in2 = gid % inner;
    if (t < da) { long long ix = (ou * da + t) * inner + in2; ST(ga, ix, __dadd_rn(LD(ga, ix), LD(g, gid))); }
    else { long long ix = (ou * (ax - da) + (t - da)) * inner + in2; ST(gb, ix, __dadd_rn(LD(gb, ix), LD(g, gid))); }
}` } {}
    ? != 0 ( nurl_str_eq name `sqacc` ) { ^ `if (gid == 0) {
    double ss = 0.0;
    if (first == 0) ss = LD(acc, 0);
    for (long long k = 0; k < n; k++) ss = __dadd_rn(ss, __dmul_rn(LD(g, k), LD(g, k)));
    ST(acc, 0, ss);
}` } {}
    ? != 0 ( nurl_str_eq name `clipfin` ) { ^ `if (gid == 0) {
    double cl = (double)clip;
    double gn = sqrt(LD(acc, 0));
    ST(ctl, 1, (gn > cl) ? (cl / gn) : 1.0);
}` } {}
    ? != 0 ( nurl_str_eq name `opt` ) { ^ `if (gid < n) {
    double lrt = LD(ctl, 0);
    double cs = LD(ctl, 1);
    double al = (double)alpha;
    double lrr = (double)lr;
    double gk = __dadd_rn(__dmul_rn(LD(g, gid), cs), __dmul_rn(al, LD(w, gid)));
    if (kind == 0) {
        ST(w, gid, __dsub_rn(LD(w, gid), __dmul_rn(lrr, gk)));
    } else {
        double b1 = 0.9;
        double b2 = 0.999;
        double nm = __dadd_rn(__dmul_rn(b1, LD(m, gid)), __dmul_rn(__dsub_rn(1.0, b1), gk));
        double nv = __dadd_rn(__dmul_rn(b2, LD(v, gid)), __dmul_rn(__dsub_rn(1.0, b2), __dmul_rn(gk, gk)));
        ST(m, gid, nm);
        ST(v, gid, nv);
        ST(w, gid, __dsub_rn(LD(w, gid), __ddiv_rn(__dmul_rn(lrt, nm), __dadd_rn(sqrt(nv), 0.00000001))));
    }
}` } {}
    ^ ``
}

// A kernel's body for the program's dtype. f64 and mixed run it as
// written: mixed binds f32 buffers, and a load widens to double and a store
// narrows exactly as the old pointer-typed source did. Pure f32 swaps the
// element type, the round-to-nearest intrinsics and the libm calls — the
// same substitution the f32 kernel source always went through, so its
// arithmetic is unchanged.
@ _gp_body i dtype s name → String {
    ? == dtype 1 {
        : ~ String x ( _str_replace_all ( __gp_body name ) `__dadd_rn` `__fadd_rn` )
        = x ( _str_replace_all ( string_data x ) `__dsub_rn` `__fsub_rn` )
        = x ( _str_replace_all ( string_data x ) `__dmul_rn` `__fmul_rn` )
        = x ( _str_replace_all ( string_data x ) `__ddiv_rn` `__fdiv_rn` )
        = x ( _str_replace_all ( string_data x ) `exp(` `expf(` )
        = x ( _str_replace_all ( string_data x ) `log(` `logf(` )
        = x ( _str_replace_all ( string_data x ) `sqrt(` `sqrtf(` )
        = x ( _str_replace_all ( string_data x ) `(double)` `(float)` )
        = x ( _str_replace_all ( string_data x ) `double` `float` )
        ^ x
    } {}
    ^ ( string_from ( __gp_body name ) )
}

// Every simple textual replacement of `needle` with `rep` in `hay`. `needle`
// must be non-empty; used only on the fixed kernel source above.
@ _str_replace_all s hay s needle s rep → String {
    : ( Slice u ) hay_v ( slice_of_str hay )
    : ( Slice u ) nd_v ( slice_of_str needle )
    : i nl ( slice_len [u] nd_v )
    ? > nl 0 {} { ^ ( string_from hay ) }
    : String out ( string_new )
    : i hl ( slice_len [u] hay_v )
    : ~ i i2 0
    ~ < i2 hl {
        : b hit ? <= + i2 nl hl ( slice_bytes_eq ( slice_window [u] hay_v i2 nl ) nd_v ) F
        ? hit {
            ( string_push_str out rep )
            = i2 + i2 nl
        } {
            ( string_push_char out ( slice_byte hay_v i2 ) )
            = i2 + i2 1
        }
    }
    ^ out
}

// ── the captured program ─────────────────────────────────────────────

// One mirrored node. dims caches per-op host-side launch geometry:
//   binop broadcast: [offB1 offB2 offB3 offBA offBB tfreeA tfreeB]
//   matmul [M K N] · bmm [B M K N] · transpose [M N]
//   softmax/concat [outer axlen inner (da)]
: GpNode {
    i op
    i a
    i b
    f s
    i n  // value element count
    i reach  // 1 = loss ancestor (backward touches it)
    i rows  // shape[0] when the value is 2-D, else 0 (fusion analysis)
    i cols  // shape[1] when 2-D; the length when 1-D; else 0
    ( Vec i ) dims
    GkBuf val
    GkBuf grad
    GkBuf scr  // out-shaped scratch (mul/div backward)
    GkBuf meta  // i64 stride/offset blocks
}

: GProg {
    b ok
    GpuKit kit
    ( Vec GpNode ) nodes
    i loss
    GpuGraph gexec  // the CUDA graph of one fwd+bwd episode (none until captured)
    i dtype  // 0 GK_F64 (default) · 1 GK_F32 (device replay in float32)
    // The recorded launches (gk_record_dev), built on the first replay:
    // per node forward and backward, and the gradient zeroing + seed.
    ( Vec ( Vec GkLaunch ) ) frec
    ( Vec ( Vec GkLaunch ) ) brec
    ( Vec GkLaunch ) zrec
}

// A GProg is a handle on its state in an Arc (stdlib/std/arc.nu):
// every copy is the same state, and the last owner releases it.
// The state, for this package's own code.
// The element buffer dtype: f32 storage for both pure-f32 and mixed.
@ __gp_edt inout GProg pg → i { ? | == . pg dtype 1 == . pg dtype 2 { ^ GK_F32 } {} ^ GK_F64 }

// Device optimizer over a captured program's parameters — opt.nu mirrored:
// per-param L2, global-norm clip, the same runtime 1−β Adam arithmetic, the
// step counter behind the heap pointer.
: GpOpt {
    b ok
    i kind  // 0 sgd · 1 adam
    f lr
    f clip
    i t
    ( Vec i ) ids
    ( Vec f ) alphas
    ( Vec GkBuf ) m
    ( Vec GkBuf ) v
    GkBuf acc  // the clip norm's running sum of squares (1 element)
    GkBuf ctl  // [lrt, cs] the update kernels read (graph-capturable)
    ( Vec GkLaunch ) orec  // the step's launches, recorded on the first step
}

// A GpOpt is a handle on its state in an Arc (stdlib/std/arc.nu):
// every copy is the same state, and the last owner releases it.
// The state, for this package's own code.
@ _gp_nobuf → GkBuf { ^ ( gk_buf_none 0 ) }

// ── capture-time metadata builders ───────────────────────────────────

// Push `nd` entries of `v` (aligned to nd out dims, missing lead = filler).
@ _gp_push_vec ( Vec i ) dst ( Vec i ) src → v {
    : i n ( vec_len [i] src )
    : ~ i k 0
    ~ < k n { ( vec_push [i] dst ( _ti src k ) ) = k + k 1 }
}

// The acc-reduce block for one input: [nd ost dec fdim fdec], plus tfree.
// dec = row-major strides of the input's dims aligned into out dims (1 on
// broadcast dims); fdim/fdec describe the odometer over the broadcast dims.
@ _gp_accred_block ( Vec i ) meta ( Vec i ) oshape ( Vec i ) ost ( Vec i ) eff inout i tfree → v {
    : i nd ( vec_len [i] oshape )
    ( vec_push [i] meta nd )
    ( _gp_push_vec meta ost )
    // aligned input dims: out dim where the input participates, else 1
    : ( Vec i ) adim ( vec_new [i] )
    : ( Vec i ) fdim ( vec_new [i] )
    : ~ i d 0
    ~ < d nd {
        ? != ( _ti eff d ) 0 {
            ( vec_push [i] adim ( _ti oshape d ) )
            ( vec_push [i] fdim 1 )
        } {
            ( vec_push [i] adim 1 )
            ( vec_push [i] fdim ( _ti oshape d ) )
        }
        = d + d 1
    }
    : ( Vec i ) dec ( _t_strides adim )
    : ( Vec i ) fdec ( _t_strides fdim )
    ( _gp_push_vec meta dec )
    ( _gp_push_vec meta fdim )
    ( _gp_push_vec meta fdec )
    : ~ i tf 1
    = d 0
    ~ < d nd { = tf * tf ( _ti fdim d ) = d + d 1 }
    = tfree tf
}

// An ew block [nd ost xe ye].
@ _gp_ew_block ( Vec i ) meta ( Vec i ) ost ( Vec i ) xe ( Vec i ) ye → v {
    : i nd ( vec_len [i] ost )
    ( vec_push [i] meta nd )
    ( _gp_push_vec meta ost )
    ( _gp_push_vec meta xe )
    ( _gp_push_vec meta ye )
}

// ── capture ──────────────────────────────────────────────────────────

@ _gp_fail inout GProg pg s why → v {
    ? . pg ok { ( nurl_eprint `gput: capture failed: ` ) ( nurl_eprintln why ) } {}
    = . pg ok F
}

// A tensor's values in a new f32 device buffer. gk_dbuf_upload converts a
// large f32 upload on the device (a staging f64 memcpy and one cast
// kernel), which a frozen weight needs: element by element on the host, a
// 30-layer model's ~150M consts took more than 8 minutes to capture.
@ __gp_upload_f32 GpuKit kit Tensor t → GkBuf {
    : GkBuf out ( gk_dbuf_new kit ( vec_len [f] . t data ) GK_F32 )
    ? ( gk_buf_ok out ) {} { ^ ( _gp_nobuf ) }
    ? ( gk_dbuf_upload kit out . t data ) { ^ out } {}
    ^ ( _gp_nobuf )
}

// Upload a CPU tensor's data into a fresh device buffer of the given dtype.
// GK_F64 is a straight memcpy; GK_F32 converts on the device (see above).
// A LAZY const (grad_const_lazy) carries a shape and no values: allocate
// its buffer from the shape and upload nothing — the caller fills it after
// the capture via gput_set_input.
@ _gp_lazy Tensor t → b {
    ^ & == ( vec_len [f] . t data ) 0 > ( _t_prod . t shape ) 0
}

@ _gp_upload_tensor GpuKit kit Tensor t i edt → GkBuf {
    ? ( _gp_lazy t ) { ^ ( gk_dbuf_new kit ( _t_prod . t shape ) edt ) } {}
    ? == edt GK_F32 { ^ ( __gp_upload_f32 kit t ) } {}
    : i n ( vec_len [f] . t data )
    : GkBuf b ( gk_dbuf_new kit n edt )
    ? ( gk_buf_ok b ) {
        ? ( gk_dbuf_upload kit b . t data ) {} { ^ ( _gp_nobuf ) }
    } {}
    ^ b
}

// Mirror one recorded episode ([0, tape_len)) onto the device. `loss` is the
// node backward seeds from. Check gput_ok before use.
@ gput_capture GpuKit kit GTape tp GVar loss → GProg {
    ^ ( gput_capture_dt kit tp loss 0 )
}

// As gput_capture, but the DEVICE replay runs in the given element dtype
// (0 GK_F64 · 1 GK_F32). The CPU tape stays f64: an f32 program halves
// device memory and runs f32 ALUs, at float32 precision (the parity test
// bounds the gap ~1e-5 rel; it is NOT bit-equal to the tape like f64 is).
@ gput_capture_dt GpuKit kit GTape tp GVar loss i dtype → GProg {
    // (the program holds the kit too)
    : ~ GProg pg @ GProg { T ( GpuKit_share kit ) ( vec_new [GpNode] ) . loss id ( gpu_graph_none ) dtype
        ( vec_new [( Vec GkLaunch )] ) ( vec_new [( Vec GkLaunch )] ) ( vec_new [GkLaunch] ) }
    ? & ( tape_ok tp ) >= . loss id 0 {} { ( _gp_fail pg `tape is poisoned or loss invalid` ) ^ pg }
    ? ( gk_ok kit ) {} { ( _gp_fail pg `no device` ) ^ pg }
    : i nn ( tape_len tp )
    // reach = loss-ancestor set; need = requires-grad propagation (a param
    // in the ancestor cone). The backward sweep and the gradient BUFFERS
    // exist only where both hold — grad.nu's rule mirrored, and a frozen
    // 4 GB const costs no device gradient memory and no backward launch.
    : ( Vec i ) reach ( vec_new [i] )
    : ~ i k 0
    ~ < k nn { ( vec_push [i] reach 0 ) = k + k 1 }
    ? < . loss id nn { ( vec_set [i] reach . loss id 1 ) } {}
    = k . loss id
    ~ >= k 0 {
        ? == ( _ti reach k ) 1 {
            : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
            ? >= . nd a 0 { ( vec_set [i] reach . nd a 1 ) } {}
            ? >= . nd b 0 { ( vec_set [i] reach . nd b 1 ) } {}
        } {}
        = k - k 1
    }
    : ( Vec i ) needv ( vec_new [i] )
    = k 0
    ~ < k nn {
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        : ~ i nv 0
        ? == . nd op ( gop_param ) { = nv 1 } {
            ? & >= . nd a 0 == ( _ti needv . nd a ) 1 { = nv 1 } {}
            ? & >= . nd b 0 == ( _ti needv . nd b ) 1 { = nv 1 } {}
        }
        ( vec_push [i] needv nv )
        // the stored per-node flag = BW-active (reach AND need)
        ? & == ( _ti reach k ) 1 == nv 1 {} { ( vec_set [i] reach k 0 ) }
        = k + k 1
    }
    // gbuf = which nodes get a gradient BUFFER: every BW-active node, plus
    // both inputs of a BW-active concat (its fused backward kernel writes
    // both sides; an inactive side's buffer is pure workspace — gput_grad
    // still reports zeros for it, like the CPU tape)
    : ( Vec i ) gbuf ( vec_new [i] )
    = k 0
    ~ < k nn { ( vec_push [i] gbuf ( _ti reach k ) ) = k + k 1 }
    = k 0
    ~ < k nn {
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        ? & == . nd op ( gop_concat ) == ( _ti reach k ) 1 {
            ( vec_set [i] gbuf . nd a 1 )
            ( vec_set [i] gbuf . nd b 1 )
        } {}
        = k + k 1
    }
    = k 0
    ~ & < k nn . pg ok {
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        : Tensor tv ( _g_v tp k )
        ? == . tv dtype TE_F64 {} { ( _gp_fail pg `only TE_F64 tapes` ) }
        // a lazy const has a shape and no values yet — size from the shape
        : i n ? ( _gp_lazy tv ) ( _t_prod . tv shape ) ( vec_len [f] . tv data )
        : GkBuf val ( _gp_upload_tensor kit tv ( __gp_edt pg ) )
        : ~ GkBuf grad ( _gp_nobuf )
        ? == ( _ti gbuf k ) 1 { = grad ( gk_dbuf_new kit n ( __gp_edt pg ) ) } {}
        : ~ GkBuf scr ( _gp_nobuf )
        : ~ GkBuf meta ( _gp_nobuf )
        : ( Vec i ) dims ( vec_new [i] )
        ? ( gk_buf_ok val ) {} {
            // say WHICH node and how big — "device alloc failed" alone
            // cannot distinguish a real out-of-memory from a zero-sized
            // buffer, and the two want opposite fixes
            : String wm ( string_from `value buffer alloc failed: node ` )
            ( string_push_str wm ( nurl_str_int k ) )
            ( string_push_str wm ` op ` )
            ( string_push_str wm ( nurl_str_int . nd op ) )
            ( string_push_str wm ` elements ` )
            ( string_push_str wm ( nurl_str_int n ) )
            ( _gp_fail pg ( string_data wm ) )
        }
        ? == ( _ti gbuf k ) 1 {
            ? ( gk_buf_ok grad ) {} { ( _gp_fail pg `device alloc failed` ) }
        } {}
        : i op . nd op
        ? & >= op ( gop_add ) <= op ( gop_div ) {
            // binop: ew blocks B0(fwd) B1(g,b) B2(g,a) B3(g,g) + accred A/B
            : Tensor ta ( _g_v tp . nd a )
            : Tensor tb ( _g_v tp . nd b )
            : i nd2 ( vec_len [i] . tv shape )
            : ( Vec i ) ost ( _t_strides . tv shape )
            : ( Vec i ) ae ( _t_eff_strides . ta shape nd2 )
            : ( Vec i ) be ( _t_eff_strides . tb shape nd2 )
            : ( Vec i ) mv ( vec_new [i] )
            ( _gp_ew_block mv ost ae be )
            : i offB1 ( vec_len [i] mv )
            ( _gp_ew_block mv ost ost be )
            : i offB2 ( vec_len [i] mv )
            ( _gp_ew_block mv ost ost ae )
            : i offB3 ( vec_len [i] mv )
            ( _gp_ew_block mv ost ost ost )
            : i offBA ( vec_len [i] mv )
            : ~ i tfa 0
            : ~ i tfb 0
            ( _gp_accred_block mv . tv shape ost ae tfa )
            : i offBB ( vec_len [i] mv )
            ( _gp_accred_block mv . tv shape ost be tfb )
            ( vec_push [i] dims offB1 ) ( vec_push [i] dims offB2 )
            ( vec_push [i] dims offB3 ) ( vec_push [i] dims offBA )
            ( vec_push [i] dims offBB )
            ( vec_push [i] dims tfa )
            ( vec_push [i] dims tfb )
            = meta ( gk_dbuf_new kit ( vec_len [i] mv ) GK_I64 )
            ? & ( gk_buf_ok meta ) ( gk_dbuf_upload_i kit meta mv ) {} { ( _gp_fail pg `meta upload failed` ) }
            // mul/div backward materializes an out-shaped contribution
            ? | == op ( gop_mul ) == op ( gop_div ) {
                = scr ( gk_dbuf_new kit n ( __gp_edt pg ) )
                ? ( gk_buf_ok scr ) {} { ( _gp_fail pg `scratch alloc failed` ) }
            } {}
        } {}
        ? == op ( gop_matmul ) {
            : Tensor ta ( _g_v tp . nd a )
            : Tensor tb ( _g_v tp . nd b )
            ( vec_push [i] dims ( _ti . ta shape 0 ) )
            ( vec_push [i] dims ( _ti . ta shape 1 ) )
            ( vec_push [i] dims ( _ti . tb shape 1 ) )
        } {}
        ? == op ( gop_bmm ) {
            : Tensor ta ( _g_v tp . nd a )
            : Tensor tb ( _g_v tp . nd b )
            ? & == ( vec_len [i] . ta shape ) 3 == ( vec_len [i] . tb shape ) 3 {} {
                ( _gp_fail pg `bmm: only full-batch [B,m,k]x[B,k,n] on the device` )
            }
            ? . pg ok {
                ? == ( _ti . ta shape 0 ) ( _ti . tb shape 0 ) {} {
                    ( _gp_fail pg `bmm: only full-batch [B,m,k]x[B,k,n] on the device` )
                }
            } {}
            ? . pg ok {
                ( vec_push [i] dims ( _ti . ta shape 0 ) )
                ( vec_push [i] dims ( _ti . ta shape 1 ) )
                ( vec_push [i] dims ( _ti . ta shape 2 ) )
                ( vec_push [i] dims ( _ti . tb shape 2 ) )
            } {}
        } {}
        ? == op ( gop_transpose ) {
            : Tensor ta ( _g_v tp . nd a )
            ( vec_push [i] dims ( _ti . ta shape 0 ) )
            ( vec_push [i] dims ( _ti . ta shape 1 ) )
        } {}
        ? | == op ( gop_softmax ) == op ( gop_concat ) {
            : i axis # i . nd s
            : i ndim ( vec_len [i] . tv shape )
            : ~ i outer 1
            : ~ i inner 1
            : ~ i d 0
            ~ < d axis { = outer * outer ( _ti . tv shape d ) = d + d 1 }
            = d + axis 1
            ~ < d ndim { = inner * inner ( _ti . tv shape d ) = d + d 1 }
            ( vec_push [i] dims outer )
            ( vec_push [i] dims ( _ti . tv shape axis ) )
            ( vec_push [i] dims inner )
            ? == op ( gop_concat ) {
                : Tensor ta ( _g_v tp . nd a )
                ( vec_push [i] dims ( _ti . ta shape axis ) )
            } {}
        } {}
        ? == op ( gop_slice ) {
            : Tensor ta ( _g_v tp . nd a )
            : ( Vec i ) axs ?? ( vec_get [( Vec i )] . tp aux k ) { T x → x F → ( vec_new [i] ) }
            : ( Vec i ) ost ( _t_strides . tv shape )
            : ( Vec i ) ist ( _t_strides . ta shape )
            : ( Vec i ) mv ( vec_new [i] )
            ( vec_push [i] mv ( vec_len [i] . tv shape ) )
            ( _gp_push_vec mv ost )
            ( _gp_push_vec mv ist )
            ( _gp_push_vec mv axs )
            = meta ( gk_dbuf_new kit ( vec_len [i] mv ) GK_I64 )
            ? & ( gk_buf_ok meta ) ( gk_dbuf_upload_i kit meta mv ) {} { ( _gp_fail pg `meta upload failed` ) }
        } {}
        : i tnd ( vec_len [i] . tv shape )
        : ~ i trows 0
        : ~ i tcols 0
        ? == tnd 2 { = trows ( _ti . tv shape 0 ) = tcols ( _ti . tv shape 1 ) } {
            ? == tnd 1 { = tcols ( _ti . tv shape 0 ) } {}
        }
        ( vec_push [GpNode] . pg nodes @ GpNode {
            op . nd a . nd b . nd s n ( _ti reach k ) trows tcols dims val grad scr meta
        } )
        = k + k 1
    }
    ^ pg
}

@ gput_ok inout GProg pg → b {
    ^ . pg ok
}

// Let go of `pg` now rather than at the end of its owner's scope. The
// program's last owner releases every node's device buffers (back to the
// kit's pool), the captured graph and its hold on the kit.
@ gput_free sink GProg pg → v {}

@ _gp_node inout GProg pg i id → GpNode {
    ^ ?? ( vec_get [GpNode] . pg nodes id ) {
        T x → x
        F → @ GpNode { -1 -1 -1 0.0 0 0 0 0 ( vec_new [i] ) ( _gp_nobuf ) ( _gp_nobuf ) ( _gp_nobuf ) ( _gp_nobuf ) }
    }
}

// ── bulk f32 transfers ───────────────────────────────────────────────
//
// f32 transfers: gk_dbuf_upload/download stage a large one through a
// transient f64 device buffer — one memcpy plus one cast kernel — and fall
// back to the host loop when the staging buffer cannot be had (slower,
// never wrong: a mid-training step can leave too little free VRAM).

@ __gp_dl_f32 GpuKit kit GkBuf b ( Vec f ) dst → b { ^ ( gk_dbuf_download kit b dst ) }

@ __gp_ul_f32 GpuKit kit GkBuf b ( Vec f ) src → b { ^ ( gk_dbuf_upload kit b src ) }

// dtype-aware transfers: f64 buffers take gk's straight-memcpy path, big
// f32 buffers the staged cast. The 4096-element floor keeps small vectors
// (norms, biases) off the kernel-launch overhead.
@ _gp_dl GpuKit kit GkBuf b ( Vec f ) dst → b {
    ? & == ( gk_buf_dtype b ) GK_F32 > . b n 4096 { ^ ( __gp_dl_f32 kit b dst ) } {}
    ^ ( gk_dbuf_download kit b dst )
}

@ _gp_ul GpuKit kit GkBuf b ( Vec f ) src → b {
    ? & & == ( gk_buf_dtype b ) GK_F32 > . b n 4096 == ( vec_len [f] src ) . b n {
        ^ ( __gp_ul_f32 kit b src )
    } {}
    ^ ( gk_dbuf_upload kit b src )
}

// Fresh values for an input slot (a const's minibatch rows, or a param).
@ gput_set_input inout GProg pg GVar v ( Vec f ) data → b {
    ? . pg ok {} { ^ F }
    ? & >= . v id 0 < . v id ( vec_len [GpNode] . pg nodes ) {} { ^ F }
    : GpNode nd ( _gp_node pg . v id )
    ? == ( vec_len [f] data ) . nd n {} { ^ F }
    ^ ( _gp_ul . pg kit . nd val data )
}

// ── replay: forward ──────────────────────────────────────────────────

// Bind and check kernel `name` over `c`'s bindings, record the launch
// into `rs` and make it: `nb` blocks of `blk` threads. F (the program
// marked failed, with the reason) when the kernel is refused or fails.
@ _gp_go inout GProg pg inout ( Vec GkLaunch ) rs inout GkCall c s name i nb i blk → b {
    : String body ( _gp_body . pg dtype name )
    : ~ String kn ( string_from `gp_` )
    ( string_push_str kn name )
    : GkLaunch l ( gk_record_dev . pg kit c ( string_data kn ) ( string_data body ) nb blk )
    ? ( gk_launch_ok l ) {} {
        : ~ String why ( string_from `kernel ` )
        ( string_push_str why name ) ( string_push_str why `: ` ) ( string_push_str why ( gk_checked_error c ) )
        ( _gp_fail pg ( string_data why ) )
        ^ F
    }
    : b r ( gk_replay l )
    ( vec_push [GkLaunch] rs l )
    ^ r
}

// Replay recorded launches in order: F at the first that fails.
@ __gp_replay ( Vec GkLaunch ) rs → b {
    : ~ b r T
    : ~ i j 0
    ~ & r < j ( vec_len [GkLaunch] rs ) {
        = r ( gk_replay ( vec_at [GkLaunch] rs j ) )
        = j + j 1
    }
    ^ r
}

// One record list per node, forward and backward.
@ __gp_recs_size inout GProg pg → v {
    : i n ( vec_len [GpNode] . pg nodes )
    ~ < ( vec_len [( Vec GkLaunch )] . pg frec ) n { ( vec_push [( Vec GkLaunch )] . pg frec ( vec_new [GkLaunch] ) ) }
    ~ < ( vec_len [( Vec GkLaunch )] . pg brec ) n { ( vec_push [( Vec GkLaunch )] . pg brec ( vec_new [GkLaunch] ) ) }
}

// Buffer `b` filled with `v`, recorded into `rs`.
@ _gp_fill_rec inout GProg pg inout ( Vec GkLaunch ) rs GkBuf b f v → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `o` b ) ( gk_call_i64 c `n` . b n ) ( gk_call_f64 c `v` v )
    ^ ( _gp_go pg rs c `fill` ( gk_grid . b n 256 ) 256 )
}

// Buffer `b` filled with `v` (not recorded).
@ _gp_fill_buf inout GProg pg GkBuf b f v → b {
    : ~ ( Vec GkLaunch ) rs ( vec_new [GkLaunch] )
    ^ ( _gp_fill_rec pg rs b v )
}

// One forward launch for node `k`. Leaves are data — nothing to do. The
// launches are recorded the first time and replayed after it: the same
// kernels over the same buffers every episode, bound and checked once.
@ _gp_fwd_node inout GProg pg i k → b {
    ( __gp_recs_size pg )
    ? > ( vec_len [GkLaunch] ( vec_at [( Vec GkLaunch )] . pg frec k ) ) 0 {
        ^ ( __gp_replay ( vec_at [( Vec GkLaunch )] . pg frec k ) )
    } {}
    : ~ ( Vec GkLaunch ) rs ( vec_new [GkLaunch] )
    : b r ( __gp_fwd_build pg k rs )
    : b _s ( vec_set [( Vec GkLaunch )] . pg frec k rs )
    ^ r
}

@ __gp_fwd_build inout GProg pg i k inout ( Vec GkLaunch ) rs → b {
    : GpNode nd ( _gp_node pg k )
    : i op . nd op
    ? <= op ( gop_const ) { ^ T } {}
    : ~ GkCall c ( gk_call_new )
    ? & >= op ( gop_add ) <= op ( gop_div ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        ( gk_call_dev c `a` . na val ) ( gk_call_dev c `b` . nb val ) ( gk_call_dev c `o` . nd val ) ( gk_call_dev c `meta` . nd meta )
        ( gk_call_i64 c `moff` 0 ) ( gk_call_i64 c `n` . nd n ) ( gk_call_i64 c `op` op )
        ^ ( _gp_go pg rs c `ew_bc` ( gk_grid . nd n 256 ) 256 )
    } {}
    ? & >= op ( gop_neg ) <= op ( gop_relu ) {
        : GpNode na ( _gp_node pg . nd a )
        ( gk_call_dev c `a` . na val ) ( gk_call_dev c `o` . nd val )
        ( gk_call_i64 c `n` . nd n ) ( gk_call_i64 c `op` op ) ( gk_call_f64 c `c` . nd s )
        ^ ( _gp_go pg rs c `scal` ( gk_grid . nd n 256 ) 256 )
    } {}
    ? & >= op ( gop_sigmoid ) <= op ( gop_sqrt ) {
        : GpNode na ( _gp_node pg . nd a )
        ( gk_call_dev c `a` . na val ) ( gk_call_dev c `o` . nd val )
        ( gk_call_i64 c `n` . nd n ) ( gk_call_i64 c `op` op )
        ^ ( _gp_go pg rs c `trans` ( gk_grid . nd n 256 ) 256 )
    } {}
    ? | == op ( gop_sum ) == op ( gop_mean ) {
        : GpNode na ( _gp_node pg . nd a )
        ( gk_call_dev c `a` . na val ) ( gk_call_dev c `o` . nd val )
        ( gk_call_i64 c `n` . na n ) ( gk_call_i64 c `op` op )
        ^ ( _gp_go pg rs c `reduce` 1 1 )
    } {}
    ? == op ( gop_matmul ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        ( gk_call_dev c `a` . na val ) ( gk_call_dev c `b` . nb val ) ( gk_call_dev c `c` . nd val )
        ( gk_call_i64 c `M` ( _ti . nd dims 0 ) ) ( gk_call_i64 c `K` ( _ti . nd dims 1 ) ) ( gk_call_i64 c `N` ( _ti . nd dims 2 ) )
        ^ ( _gp_go pg rs c `matmul` ( gk_grid . nd n 256 ) 256 )
    } {}
    ? == op ( gop_bmm ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        ( gk_call_dev c `a` . na val ) ( gk_call_dev c `b` . nb val ) ( gk_call_dev c `c` . nd val )
        ( gk_call_i64 c `B` ( _ti . nd dims 0 ) ) ( gk_call_i64 c `M` ( _ti . nd dims 1 ) )
        ( gk_call_i64 c `K` ( _ti . nd dims 2 ) ) ( gk_call_i64 c `N` ( _ti . nd dims 3 ) )
        ^ ( _gp_go pg rs c `bmm` ( gk_grid . nd n 256 ) 256 )
    } {}
    ? == op ( gop_transpose ) {
        : GpNode na ( _gp_node pg . nd a )
        ( gk_call_dev c `a` . na val ) ( gk_call_dev c `o` . nd val )
        ( gk_call_i64 c `M` ( _ti . nd dims 0 ) ) ( gk_call_i64 c `N` ( _ti . nd dims 1 ) )
        ^ ( _gp_go pg rs c `transpose` ( gk_grid . nd n 256 ) 256 )
    } {}
    ? == op ( gop_reshape ) {
        : GpNode na ( _gp_node pg . nd a )
        ( gk_call_dev c `a` . na val ) ( gk_call_dev c `o` . nd val ) ( gk_call_i64 c `n` . nd n )
        ^ ( _gp_go pg rs c `copy` ( gk_grid . nd n 256 ) 256 )
    } {}
    ? == op ( gop_softmax ) {
        : GpNode na ( _gp_node pg . nd a )
        : i sl * ( _ti . nd dims 0 ) ( _ti . nd dims 2 )
        ( gk_call_dev c `x` . na val ) ( gk_call_dev c `o` . nd val )
        ( gk_call_i64 c `outer` ( _ti . nd dims 0 ) ) ( gk_call_i64 c `ax` ( _ti . nd dims 1 ) ) ( gk_call_i64 c `inner` ( _ti . nd dims 2 ) )
        ^ ( _gp_go pg rs c `softmax` ( gk_grid sl 256 ) 256 )
    } {}
    ? == op ( gop_slice ) {
        : GpNode na ( _gp_node pg . nd a )
        ( gk_call_dev c `a` . na val ) ( gk_call_dev c `o` . nd val ) ( gk_call_dev c `meta` . nd meta ) ( gk_call_i64 c `n` . nd n )
        ^ ( _gp_go pg rs c `slice_fwd` ( gk_grid . nd n 256 ) 256 )
    } {}
    ? == op ( gop_concat ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        ( gk_call_dev c `a` . na val ) ( gk_call_dev c `b` . nb val ) ( gk_call_dev c `o` . nd val )
        ( gk_call_i64 c `outer` ( _ti . nd dims 0 ) ) ( gk_call_i64 c `ax` ( _ti . nd dims 1 ) )
        ( gk_call_i64 c `inner` ( _ti . nd dims 2 ) ) ( gk_call_i64 c `da` ( _ti . nd dims 3 ) )
        ^ ( _gp_go pg rs c `concat_fwd` ( gk_grid . nd n 256 ) 256 )
    } {}
    ^ T
}

@ __gput_fwd_launches inout GProg pg → b {
    : i n ( vec_len [GpNode] . pg nodes )
    : ~ b r T
    : ~ i k 0
    ~ & < k n r {
        = r ( _gp_fwd_node pg k )
        = k + k 1
    }
    ^ r
}

// Recompute every non-leaf value on the device, in tape order.
@ gput_forward inout GProg pg → b {
    ? . pg ok {} { ^ F }
    ( gk_autosync F )
    : b r ( __gput_fwd_launches pg )
    ( gk_autosync T )
    ? r { ^ ( gk_sync . pg kit ) } {}
    ^ F
}

// ── replay: backward ─────────────────────────────────────────────────

// The out-shaped contribution `src` accumulated into input `dst`'s gradient
// over the broadcast axes (block at `moff`, odometer size `tfree`).
// The out-shaped contribution `src` accumulated into input `dst`'s gradient
// over the broadcast axes (block at `moff`, odometer size `tfree`).
@ _gp_accred inout GProg pg inout ( Vec GkLaunch ) rs GpNode dst GpNode nd GkBuf src i moff i tfree f sgn → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `ga` . dst grad ) ( gk_call_dev c `c` src ) ( gk_call_dev c `meta` . nd meta )
    ( gk_call_i64 c `moff` moff ) ( gk_call_i64 c `in_n` . dst n ) ( gk_call_i64 c `tfree` tfree ) ( gk_call_f64 c `sgn` sgn )
    ^ ( _gp_go pg rs c `bw_accred` ( gk_grid . dst n 256 ) 256 )
}

// g (out-shaped) ⊙ other-input → scr, via the ew block at `moff`.
@ _gp_scr_ew inout GProg pg inout ( Vec GkLaunch ) rs GpNode nd GkBuf x GkBuf y i moff i op → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `a` x ) ( gk_call_dev c `b` y ) ( gk_call_dev c `o` . nd scr ) ( gk_call_dev c `meta` . nd meta )
    ( gk_call_i64 c `moff` moff ) ( gk_call_i64 c `n` . nd n ) ( gk_call_i64 c `op` op )
    ^ ( _gp_go pg rs c `ew_bc` ( gk_grid . nd n 256 ) 256 )
}

// Node `k`'s backward launches, recorded the first time and replayed after.
@ _gp_bwd_node inout GProg pg i k → b {
    ( __gp_recs_size pg )
    ? > ( vec_len [GkLaunch] ( vec_at [( Vec GkLaunch )] . pg brec k ) ) 0 {
        ^ ( __gp_replay ( vec_at [( Vec GkLaunch )] . pg brec k ) )
    } {}
    : ~ ( Vec GkLaunch ) rs ( vec_new [GkLaunch] )
    : b r ( __gp_bwd_build pg k rs )
    : b _s ( vec_set [( Vec GkLaunch )] . pg brec k rs )
    ^ r
}

@ __gp_bwd_build inout GProg pg i k inout ( Vec GkLaunch ) rs → b {
    : GpNode nd ( _gp_node pg k )
    ? == . nd reach 1 {} { ^ T }
    : i op . nd op
    ? <= op ( gop_const ) { ^ T } {}
    : ~ b r T
    ? & >= op ( gop_add ) <= op ( gop_div ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        : i offB1 ( _ti . nd dims 0 )
        : i offB2 ( _ti . nd dims 1 )
        : i offB3 ( _ti . nd dims 2 )
        : i offBA ( _ti . nd dims 3 )
        : i offBB ( _ti . nd dims 4 )
        : i tfa ( _ti . nd dims 5 )
        : i tfb ( _ti . nd dims 6 )
        : b needa == . na reach 1
        : b needb == . nb reach 1
        ? == op ( gop_add ) {
            ? needa { = r & r ( _gp_accred pg rs na nd . nd grad offBA tfa 1.0 ) } {}
            ? needb { = r & r ( _gp_accred pg rs nb nd . nd grad offBB tfb 1.0 ) } {}
        } {}
        ? == op ( gop_sub ) {
            ? needa { = r & r ( _gp_accred pg rs na nd . nd grad offBA tfa 1.0 ) } {}
            ? needb { = r & r ( _gp_accred pg rs nb nd . nd grad offBB tfb -1.0 ) } {}
        } {}
        ? == op ( gop_mul ) {
            ? needa {
                = r & r ( _gp_scr_ew pg rs nd . nd grad . nb val offB1 ( gop_mul ) )
                = r & r ( _gp_accred pg rs na nd . nd scr offBA tfa 1.0 )
            } {}
            ? needb {
                = r & r ( _gp_scr_ew pg rs nd . nd grad . na val offB2 ( gop_mul ) )
                = r & r ( _gp_accred pg rs nb nd . nd scr offBB tfb 1.0 )
            } {}
        } {}
        ? == op ( gop_div ) {
            ? needa {
                = r & r ( _gp_scr_ew pg rs nd . nd grad . nb val offB1 ( gop_div ) )
                = r & r ( _gp_accred pg rs na nd . nd scr offBA tfa 1.0 )
            } {}
            ? needb {
                = r & r ( _gp_scr_ew pg rs nd . nd grad . nd val offB3 ( gop_mul ) )
                = r & r ( _gp_scr_ew pg rs nd . nd scr . nb val offB1 ( gop_div ) )
                = r & r ( _gp_accred pg rs nb nd . nd scr offBB tfb -1.0 )
            } {}
        } {}
        ^ r
    } {}
    : ~ GkCall c ( gk_call_new )
    ? & >= op ( gop_neg ) <= op ( gop_sqrt ) {
        : GpNode na ( _gp_node pg . nd a )
        ( gk_call_dev c `ga` . na grad ) ( gk_call_dev c `g` . nd grad ) ( gk_call_dev c `y` . nd val ) ( gk_call_dev c `x` . na val )
        ( gk_call_i64 c `n` . nd n ) ( gk_call_i64 c `op` op ) ( gk_call_f64 c `c` . nd s )
        ^ ( _gp_go pg rs c `bw_unary` ( gk_grid . nd n 256 ) 256 )
    } {}
    ? | == op ( gop_sum ) == op ( gop_mean ) {
        : GpNode na ( _gp_node pg . nd a )
        ( gk_call_dev c `ga` . na grad ) ( gk_call_dev c `g` . nd grad ) ( gk_call_i64 c `an` . na n ) ( gk_call_i64 c `op` op )
        ^ ( _gp_go pg rs c `bw_reduce` ( gk_grid . na n 256 ) 256 )
    } {}
    ? == op ( gop_matmul ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        : i M ( _ti . nd dims 0 )
        : i K ( _ti . nd dims 1 )
        : i N2 ( _ti . nd dims 2 )
        ? == . na reach 1 {
            ( gk_call_dev c `ga` . na grad ) ( gk_call_dev c `g` . nd grad ) ( gk_call_dev c `b` . nb val )
            ( gk_call_i64 c `M` M ) ( gk_call_i64 c `K` K ) ( gk_call_i64 c `N` N2 )
            = r ( _gp_go pg rs c `bw_mm_a` ( gk_grid * M K 256 ) 256 )
        } {}
        ? == . nb reach 1 {
            : ~ GkCall c2 ( gk_call_new )
            ( gk_call_dev c2 `gb` . nb grad ) ( gk_call_dev c2 `a` . na val ) ( gk_call_dev c2 `g` . nd grad )
            ( gk_call_i64 c2 `M` M ) ( gk_call_i64 c2 `K` K ) ( gk_call_i64 c2 `N` N2 )
            = r & r ( _gp_go pg rs c2 `bw_mm_b` ( gk_grid * K N2 256 ) 256 )
        } {}
        ^ r
    } {}
    ? == op ( gop_bmm ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        : i B2 ( _ti . nd dims 0 )
        : i M ( _ti . nd dims 1 )
        : i K ( _ti . nd dims 2 )
        : i N2 ( _ti . nd dims 3 )
        ? == . na reach 1 {
            ( gk_call_dev c `ga` . na grad ) ( gk_call_dev c `g` . nd grad ) ( gk_call_dev c `b` . nb val )
            ( gk_call_i64 c `B` B2 ) ( gk_call_i64 c `M` M ) ( gk_call_i64 c `K` K ) ( gk_call_i64 c `N` N2 )
            = r ( _gp_go pg rs c `bw_bmm_a` ( gk_grid * B2 * M K 256 ) 256 )
        } {}
        ? == . nb reach 1 {
            : ~ GkCall c2 ( gk_call_new )
            ( gk_call_dev c2 `gbo` . nb grad ) ( gk_call_dev c2 `a` . na val ) ( gk_call_dev c2 `g` . nd grad )
            ( gk_call_i64 c2 `B` B2 ) ( gk_call_i64 c2 `M` M ) ( gk_call_i64 c2 `K` K ) ( gk_call_i64 c2 `N` N2 )
            = r & r ( _gp_go pg rs c2 `bw_bmm_b` ( gk_grid * B2 * K N2 256 ) 256 )
        } {}
        ^ r
    } {}
    ? == op ( gop_transpose ) {
        : GpNode na ( _gp_node pg . nd a )
        : i M ( _ti . nd dims 0 )
        : i N2 ( _ti . nd dims 1 )
        ( gk_call_dev c `ga` . na grad ) ( gk_call_dev c `g` . nd grad ) ( gk_call_i64 c `M` M ) ( gk_call_i64 c `N` N2 )
        ^ ( _gp_go pg rs c `bw_transpose` ( gk_grid * M N2 256 ) 256 )
    } {}
    ? == op ( gop_reshape ) {
        : GpNode na ( _gp_node pg . nd a )
        ( gk_call_dev c `ga` . na grad ) ( gk_call_dev c `g` . nd grad ) ( gk_call_i64 c `n` . nd n )
        ^ ( _gp_go pg rs c `bw_copy` ( gk_grid . nd n 256 ) 256 )
    } {}
    ? == op ( gop_softmax ) {
        : GpNode na ( _gp_node pg . nd a )
        : i sl * ( _ti . nd dims 0 ) ( _ti . nd dims 2 )
        ( gk_call_dev c `ga` . na grad ) ( gk_call_dev c `g` . nd grad ) ( gk_call_dev c `y` . nd val )
        ( gk_call_i64 c `outer` ( _ti . nd dims 0 ) ) ( gk_call_i64 c `ax` ( _ti . nd dims 1 ) ) ( gk_call_i64 c `inner` ( _ti . nd dims 2 ) )
        ^ ( _gp_go pg rs c `bw_softmax` ( gk_grid sl 256 ) 256 )
    } {}
    ? == op ( gop_slice ) {
        : GpNode na ( _gp_node pg . nd a )
        ( gk_call_dev c `ga` . na grad ) ( gk_call_dev c `g` . nd grad ) ( gk_call_dev c `meta` . nd meta ) ( gk_call_i64 c `n` . nd n )
        ^ ( _gp_go pg rs c `bw_slice` ( gk_grid . nd n 256 ) 256 )
    } {}
    ? == op ( gop_concat ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        ( gk_call_dev c `ga` . na grad ) ( gk_call_dev c `gb` . nb grad ) ( gk_call_dev c `g` . nd grad )
        ( gk_call_i64 c `outer` ( _ti . nd dims 0 ) ) ( gk_call_i64 c `ax` ( _ti . nd dims 1 ) )
        ( gk_call_i64 c `inner` ( _ti . nd dims 2 ) ) ( gk_call_i64 c `da` ( _ti . nd dims 3 ) )
        ^ ( _gp_go pg rs c `bw_concat` ( gk_grid . nd n 256 ) 256 )
    } {}
    ^ r
}

// Zero every gradient, seed dL/d(loss) = 1, sweep the tape in reverse over
// the loss-ancestor set, then zero const-leaf gradients (grad.nu's epilogue).
// The zeroing and the seed are recorded once, like the nodes' launches.
@ __gput_bwd_launches inout GProg pg → b {
    : ~ b r T
    ? > ( vec_len [GkLaunch] . pg zrec ) 0 {
        = r ( __gp_replay . pg zrec )
    } {
        : ~ ( Vec GkLaunch ) zs ( vec_new [GkLaunch] )
        : i n ( vec_len [GpNode] . pg nodes )
        : ~ i k 0
        ~ & < k n r {
            : GpNode nd ( _gp_node pg k )
            : GkBuf gb2 . nd grad
            ? ( gk_buf_ok gb2 ) { = r ( _gp_fill_rec pg zs gb2 0.0 ) } {}
            = k + k 1
        }
        ? r {
            : GpNode lo ( _gp_node pg . pg loss )
            : GkBuf lg . lo grad
            ? ( gk_buf_ok lg ) { = r ( _gp_fill_rec pg zs lg 1.0 ) } {}
        } {}
        = . pg zrec zs
    }
    : ~ i k . pg loss
    ~ & >= k 0 r {
        = r ( _gp_bwd_node pg k )
        = k - k 1
    }
    ^ r
}

@ gput_backward inout GProg pg → b {
    ? . pg ok {} { ^ F }
    ( gk_autosync F )
    : b r ( __gput_bwd_launches pg )
    ( gk_autosync T )
    ? r { ^ ( gk_sync . pg kit ) } {}
    ^ F
}

// ── graph fusion: one episode (forward + backward) as ONE launch ────
// CUDA only; every kernel, argument value and launch order is IDENTICAL
// to the per-node path (bit-identical results) — the graph merely removes
// ~2N launch round-trips per episode. Inputs still refresh normally with
// gput_set_input (plain HtoD; the recorded kernels read the buffers).
// Returns F where graphs are unavailable (CPU backend) — callers keep
// using gput_forward/gput_backward.
@ gput_graph_capture inout GProg pg → b {
    ? . pg ok {} { ^ F }
    ? ( gpu_graph_ok . pg gexec ) { ^ T } {}
    : GpuKit kit . pg kit
    ? ( gpu_graph_begin ( gk_gpu kit ) ) {} { ^ F }
    ( gk_autosync F )
    : ~ b r ( __gput_fwd_launches pg )
    = r & r ( __gput_bwd_launches pg )
    ( gk_autosync T )
    : GpuGraph exec ( gpu_graph_end ( gk_gpu kit ) )
    ? & r ( gpu_graph_ok exec ) {
        = . pg gexec exec
        ^ T
    } {}
    ^ F
}

// Capture a whole TRAINING episode — forward + backward + the optimizer
// update — as one graph. Per episode the host then does: refresh inputs
// (gput_set_input), gpopt_prepare (one 16-byte ctl upload), and ONE
// gput_episode launch. The optimizer's per-step scalars ride the ctl
// buffer, so the captured launches never change.
@ gput_graph_capture_train inout GProg pg inout GpOpt go → b {
    ? & . pg ok . go ok {} { ^ F }
    ? ( gpu_graph_ok . pg gexec ) { ^ T } {}
    ? ( _gpopt_ensure go pg ) {} { ^ F }
    : GpuKit kit . pg kit
    ? ( gpu_graph_begin ( gk_gpu kit ) ) {} { ^ F }
    ( gk_autosync F )
    : ~ b r ( __gput_fwd_launches pg )
    = r & r ( __gput_bwd_launches pg )
    = r & r ( _gpopt_launches go pg )
    ( gk_autosync T )
    : GpuGraph exec ( gpu_graph_end ( gk_gpu kit ) )
    ? & r ( gpu_graph_ok exec ) {
        = . pg gexec exec
        ^ T
    } {}
    ^ F
}

// Run one fused episode (falls back to the per-node path without a graph).
@ gput_episode inout GProg pg → b {
    ? . pg ok {} { ^ F }
    ? ( gpu_graph_ok . pg gexec ) {
        ^ == ( gpu_graph_launch ( gk_gpu . pg kit ) . pg gexec ) 0
    } {}
    ? ( gput_forward pg ) {} { ^ F }
    ^ ( gput_backward pg )
}

// ── readback ─────────────────────────────────────────────────────────

// Download a node's value into `out` (resized by the caller to node size).
@ gput_value inout GProg pg GVar v ( Vec f ) out → b {
    ? . pg ok {} { ^ F }
    ? & >= . v id 0 < . v id ( vec_len [GpNode] . pg nodes ) {} { ^ F }
    : GpNode nd ( _gp_node pg . v id )
    ? == ( vec_len [f] out ) . nd n {} { ^ F }
    ^ ( _gp_dl . pg kit . nd val out )
}

@ gput_grad inout GProg pg GVar v ( Vec f ) out → b {
    ? . pg ok {} { ^ F }
    ? & >= . v id 0 < . v id ( vec_len [GpNode] . pg nodes ) {} { ^ F }
    : GpNode nd ( _gp_node pg . v id )
    ? == ( vec_len [f] out ) . nd n {} { ^ F }
    // no gradient flows here (const branch / not a loss ancestor): report
    // zeros, exactly like the CPU tape's grad_of
    ? == . nd reach 1 {} {
        : ~ i k 0
        ~ < k . nd n { ( vec_set [f] out k 0.0 ) = k + k 1 }
        ^ T
    }
    ^ ( _gp_dl . pg kit . nd grad out )
}

// The loss scalar (node value element 0).
@ gput_loss inout GProg pg → f {
    : GpNode nd ( _gp_node pg . pg loss )
    : ( Vec f ) o ( vec_new [f] )
    ( vec_push [f] o 0.0 )
    : b r ( gk_dbuf_download . pg kit . nd val o )
    : f v ( _tf o 0 )
    ? r { ^ v } {}
    ^ 0.0
}

// Write every parameter node's device value back into the CPU tape's own
// tensor (in place), so gvar_value reflects the trained weights.
@ gput_param_sync_host inout GProg pg GTape tp → b {
    ? . pg ok {} { ^ F }
    : i n ( vec_len [GpNode] . pg nodes )
    : ~ b r T
    : ~ i k 0
    ~ & < k n r {
        : GpNode nd ( _gp_node pg k )
        ? == . nd op ( gop_param ) {
            : Tensor tv ( _g_v tp k )
            = r ( _gp_dl . pg kit . nd val . tv data )
        } {}
        = k + k 1
    }
    ^ r
}

// ── the device optimizer ─────────────────────────────────────────────

@ gpopt_new i kind f lr → GpOpt {
    ^ @ GpOpt { T kind lr 0.0 0 ( vec_new [i] ) ( vec_new [f] ) ( vec_new [GkBuf] ) ( vec_new [GkBuf] )
        ( _gp_nobuf ) ( _gp_nobuf ) ( vec_new [GkLaunch] ) }
}

@ gpopt_sgd_new f lr → GpOpt { ^ ( gpopt_new 0 lr ) }

@ gpopt_adam_new f lr → GpOpt { ^ ( gpopt_new 1 lr ) }

// Let go of `o` now rather than at the end of its owner's scope (its
// moment and table buffers go with its last owner).
@ gpopt_free sink GpOpt o → v {}

@ gpopt_set_clip inout GpOpt o f maxn → v {
    = . o clip maxn
    ( vec_clear [GkLaunch] . o orec )  // the step's launches change
}

// ── optimizer-state access (checkpoint / resume) ─────────────────────
//
// A resumable checkpoint needs the Adam moments and the step counter, not
// just the parameter values — restarting with zero moments and t=0 warps
// the next ~100 updates (bias correction alone scales the first step 10×).
// Params are read/written through gput_value / gput_set_input; these cover
// the rest. `pi` is the gpopt_add registration index.

@ gpopt_t inout GpOpt o → i {
    ^ . o t
}

@ gpopt_set_t inout GpOpt o i t2 → v {
    = . o t t2
}

@ gpopt_count inout GpOpt o → i {
    ^ ( vec_len [i] . o ids )
}

@ __gpopt_buf inout GpOpt o b want_v i pi → GkBuf {
    ^ ?? ( vec_get [GkBuf] ? want_v . o v . o m pi ) { T x → x F → ( _gp_nobuf ) }
}

@ __gpopt_mv_dl inout GpOpt o inout GProg pg b want_v i pi ( Vec f ) out → b {
    ? & & . o ok >= pi 0 < pi ( vec_len [GkBuf] . o m ) {} { ^ F }
    : GkBuf b ( __gpopt_buf o want_v pi )
    ? & ( gk_buf_ok b ) == ( vec_len [f] out ) . b n {} { ^ F }
    ^ ( _gp_dl . pg kit b out )
}

@ __gpopt_mv_ul inout GpOpt o inout GProg pg b want_v i pi ( Vec f ) src → b {
    ? & & . o ok >= pi 0 < pi ( vec_len [GkBuf] . o m ) {} { ^ F }
    : GkBuf b ( __gpopt_buf o want_v pi )
    ? & ( gk_buf_ok b ) == ( vec_len [f] src ) . b n {} { ^ F }
    ^ ( _gp_ul . pg kit b src )
}

@ gpopt_m_download inout GpOpt o inout GProg pg i pi ( Vec f ) out → b {
    ^ ( __gpopt_mv_dl o pg F pi out )
}

@ gpopt_v_download inout GpOpt o inout GProg pg i pi ( Vec f ) out → b {
    ^ ( __gpopt_mv_dl o pg T pi out )
}

@ gpopt_m_upload inout GpOpt o inout GProg pg i pi ( Vec f ) src → b {
    ^ ( __gpopt_mv_ul o pg F pi src )
}

@ gpopt_v_upload inout GpOpt o inout GProg pg i pi ( Vec f ) src → b {
    ^ ( __gpopt_mv_ul o pg T pi src )
}

// Register one parameter (its Adam moments start at zero, on the device).
@ gpopt_add inout GpOpt o inout GProg pg GVar p f alpha → v {
    ? & . o ok >= . p id 0 {} { ^ v }
    : GpNode nd ( _gp_node pg . p id )
    : GkBuf mb ( gk_dbuf_new . pg kit . nd n ( __gp_edt pg ) )
    : GkBuf vb ( gk_dbuf_new . pg kit . nd n ( __gp_edt pg ) )
    ? & ( gk_buf_ok mb ) ( gk_buf_ok vb ) {} {
        = . o ok F
        ^ v
    }
    ? & ( _gp_fill_buf pg mb 0.0 ) ( _gp_fill_buf pg vb 0.0 ) {} { = . o ok F }
    ( vec_push [i] . o ids . p id )
    ( vec_push [f] . o alphas alpha )
    ( vec_push [GkBuf] . o m mb )
    ( vec_push [GkBuf] . o v vb )
    ( vec_clear [GkLaunch] . o orec )  // the step's launches change
}

// Ensure the ctl buffer and (with clipping) the norm accumulator exist.
// The accumulator keeps the sum's precision: f32 for a pure-f32 program,
// f64 for f64 and mixed (whose norm always summed in double).
@ _gpopt_ensure inout GpOpt o inout GProg pg → b {
    ? ( gk_buf_ok . o ctl ) {} {
        = . o ctl ( gk_dbuf_new . pg kit 2 ( __gp_edt pg ) )
        ? ( gk_buf_ok . o ctl ) {} { = . o ok F ^ F }
    }
    ? & > . o clip 0.0 ! ( gk_buf_ok . o acc ) {
        = . o acc ( gk_dbuf_new . pg kit 1 ? == . pg dtype 1 GK_F32 GK_F64 )
        ? ( gk_buf_ok . o acc ) {} { = . o ok F ^ F }
    } {}
    ^ T
}

// The HOST half of a step: advance t, compute Adam's lr_t (host pow, like
// opt.nu), and upload [lrt, 1.0] into ctl. The device half then overwrites
// ctl[1] with the clip scale when clipping is on. Graph-safe: per episode
// this is ONE 16-byte upload.
@ gpopt_prepare inout GpOpt o inout GProg pg → b {
    ? & . o ok . pg ok {} { ^ F }
    ? ( _gpopt_ensure o pg ) {} { ^ F }
    : ~ f lrt . o lr
    ? == . o kind 1 {
        = . o t + . o t 1
        : f tf # f . o t
        = lrt * . o lr / ( float_sqrt - 1.0 ( pow 0.999 tf ) ) - 1.0 ( pow 0.9 tf )
    } {}
    : ( Vec f ) cv ( vec_new [f] )
    ( vec_push [f] cv lrt )
    ( vec_push [f] cv 1.0 )
    : b up ( gk_dbuf_upload . pg kit . o ctl cv )
    ^ up
}

// The DEVICE half: (the clip scale when clipping) + one opt launch per
// backward-active parameter. Pure launches — capturable into a graph —
// recorded on the first step and replayed after it. The clip norm sums
// every active parameter's squared gradient in registration order, one
// parameter per launch into the accumulator: the order the single-thread
// kernel over a table of raw gradient addresses summed in.
@ _gpopt_launches inout GpOpt o inout GProg pg → b {
    ? > ( vec_len [GkLaunch] . o orec ) 0 { ^ ( __gp_replay . o orec ) } {}
    : ~ ( Vec GkLaunch ) rs ( vec_new [GkLaunch] )
    : ~ b r T
    : i np ( vec_len [i] . o ids )
    ? > . o clip 0.0 {
        : ~ b first T
        : ~ i pi 0
        ~ & < pi np r {
            : GpNode nd ( _gp_node pg ( _ti . o ids pi ) )
            ? == . nd reach 1 {
                : ~ GkCall c ( gk_call_new )
                ( gk_call_dev c `g` . nd grad ) ( gk_call_dev c `acc` . o acc )
                ( gk_call_i64 c `n` . nd n ) ( gk_call_i64 c `first` ? first 1 0 )
                = r ( _gp_go pg rs c `sqacc` 1 1 )
                = first F
            } {}
            = pi + pi 1
        }
        // (no active parameter: the norm of nothing is 0)
        ? & r first {
            : ~ GkCall c0 ( gk_call_new )
            ( gk_call_dev c0 `g` . o acc ) ( gk_call_dev c0 `acc` . o acc ) ( gk_call_i64 c0 `n` 0 ) ( gk_call_i64 c0 `first` 1 )
            = r ( _gp_go pg rs c0 `sqacc` 1 1 )
        } {}
        ? r {
            : ~ GkCall cf ( gk_call_new )
            ( gk_call_dev cf `acc` . o acc ) ( gk_call_dev cf `ctl` . o ctl ) ( gk_call_f64 cf `clip` . o clip )
            = r ( _gp_go pg rs cf `clipfin` 1 1 )
        } {}
    } {}
    : ~ i pi 0
    ~ & < pi np r {
        : i id ( _ti . o ids pi )
        : GpNode nd ( _gp_node pg id )
        ? == . nd reach 1 {
            : GkBuf mb ?? ( vec_get [GkBuf] . o m pi ) { T x → x F → ( _gp_nobuf ) }
            : GkBuf vb ?? ( vec_get [GkBuf] . o v pi ) { T x → x F → ( _gp_nobuf ) }
            : ~ GkCall c ( gk_call_new )
            ( gk_call_dev c `w` . nd val ) ( gk_call_dev c `g` . nd grad ) ( gk_call_dev c `m` mb ) ( gk_call_dev c `v` vb )
            ( gk_call_i64 c `n` . nd n ) ( gk_call_i64 c `kind` . o kind ) ( gk_call_dev c `ctl` . o ctl )
            ( gk_call_f64 c `alpha` ( _tf . o alphas pi ) ) ( gk_call_f64 c `lr` . o lr )
            = r ( _gp_go pg rs c `opt` ( gk_grid . nd n 256 ) 256 )
        } {}
        = pi + pi 1
    }
    = . o orec rs
    ^ r
}

// One update step from the gradients on the device — opt.nu's semantics:
// untouched params (not loss ancestors) are SKIPPED, the clip norm covers
// every registered ancestor's gradient in registration order, Adam's lr_t
// comes from host pow exactly like the CPU path.
@ gpopt_step inout GpOpt o inout GProg pg → b {
    ? ( gpopt_prepare o pg ) {} { ^ F }
    ( gk_autosync F )
    : b r ( _gpopt_launches o pg )
    ( gk_autosync T )
    ? r { ^ ( gk_sync . pg kit ) } {}
    ^ F
}
