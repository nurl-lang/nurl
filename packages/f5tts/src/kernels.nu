// packages/f5tts/src/kernels.nu — the kernels a flow-matching DiT needs and
// a language model does not.
//
// The heavy arithmetic — every projection, the feed-forward, the fused
// attention — is gpukit's: its GEMM is tiled and tuned, and its attention is
// the online-softmax one that never writes a score matrix. What is here is
// what F5-TTS has and the rest of this ecosystem does not:
//
//   * ADALN-ZERO MODULATION. A DiT does not condition on time by adding a
//     vector; it derives a scale and a shift per feature from the timestep
//     and applies them to a normalised activation, and it gates the residual
//     by a third one. Fused into the LayerNorm, that is one pass over the
//     activation instead of four.
//   * INTERLEAVED ROPE while splitting heads. The projection writes
//     [n, heads*hd]; attention wants [heads, n, hd]; the rotation is a
//     per-pair 2-D rotation. All three are one kernel, so the activation is
//     read once and written once.
//   * CONV1D along the sequence — depthwise with kernel 7 inside the text
//     encoder's ConvNeXt blocks, and GROUPED with kernel 31 for the
//     convolutional position embedding. Neither exists anywhere else here.
//   * GRN, ConvNeXt-V2's global response normalisation, which normalises
//     down the SEQUENCE rather than across the features — two reductions
//     over the whole block before a single elementwise pass.
//   * MISH (x·tanh(softplus x)) and the two GELUs. Both GELUs are here on
//     purpose: the text encoder uses the exact error-function form and the
//     transformer's feed-forward uses the tanh approximation, and they are
//     different functions.
//
// Every kernel is a CHECKED kernel (gpukit's gk_run_checked_dev): it reaches
// device memory only through LD(name, i) / ST(name, i, v) over the GkBufs its
// launcher binds, and every index is checked against that buffer's length.
// A wrong size or offset can give a wrong number, never a read or write
// outside the buffers handed in — so every launcher here is a plain safe
// function. The block reductions use the subset's SHARED_F arrays and SYNC
// barriers, which run on both of gpukit's backends.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

// ── modulated layer norm ────────────────────────────────────────────
//
// y = normalise(x) * (1 + scale) + shift, with the mean and variance taken
// over the feature axis and `scale`/`shift` broadcast down the sequence. The
// variance is the two-pass one — E[x²] − mean² cancels catastrophically when
// the mean is large next to the spread, which is exactly what a residual
// stream looks like by layer twenty. One block per row; `w`/`bw` are
// `(1 + scale)`'s scale and the shift for f5_modln, ConvNeXt's learned weight
// and bias for f5_lnaff.

@ __f5k_ln_body b modulated → String {
    : ~ String o ( string_from `SHARED_F(red, 256);
if (bid < rows) {
    long long r0 = bid * d;
    float s = 0.0f;
    for (long long i = tid; i < d; i += bdim) { s += LD(x, r0 + i); }
    ST(red, tid, s);
    SYNC();
    for (long long st = bdim / 2; st > 0; st >>= 1) {
        if (tid < st) { ST(red, tid, LD(red, tid) + LD(red, tid + st)); }
        SYNC();
    }
    float mean = LD(red, 0) / (float)d;
    SYNC();
    float q = 0.0f;
    for (long long i = tid; i < d; i += bdim) { float v = LD(x, r0 + i) - mean; q += v * v; }
    ST(red, tid, q);
    SYNC();
    for (long long st = bdim / 2; st > 0; st >>= 1) {
        if (tid < st) { ST(red, tid, LD(red, tid) + LD(red, tid + st)); }
        SYNC();
    }
    float inv = 1.0f / sqrtf(LD(red, 0) / (float)d + (float)eps);
    for (long long i = tid; i < d; i += bdim) {
` )
    ? modulated {
        ( string_push_str o `        ST(y, r0 + i, (LD(x, r0 + i) - mean) * inv * (1.0f + LD(w, i)) + LD(bw, i));` )
    } {
        ( string_push_str o `        ST(y, r0 + i, (LD(x, r0 + i) - mean) * inv * LD(w, i) + LD(bw, i));` )
    }
    ( string_push_str o `
    }
}` )
    ^ o
}

@ __f5k_ln GpuKit kit s name b modulated GkBuf x GkBuf y GkBuf w GkBuf bw i rows i d f eps → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x ) ( gk_call_dev c `y` y ) ( gk_call_dev_in c `w` w ) ( gk_call_dev_in c `bw` bw )
    ( gk_call_i64 c `rows` rows ) ( gk_call_i64 c `d` d ) ( gk_call_f64 c `eps` eps )
    ^ ( gk_run_checked_dev kit c name ( string_data ( __f5k_ln_body modulated ) ) rows 256 )
}

@ f5k_modln GpuKit kit GkBuf x GkBuf y GkBuf scale GkBuf shift i rows i d f eps → b {
    ^ ( __f5k_ln kit `f5_modln` T x y scale shift rows d eps )
}

// The same norm with an ordinary learned weight and bias — ConvNeXt's.
@ f5k_lnaff GpuKit kit GkBuf x GkBuf y GkBuf w GkBuf bw i rows i d f eps → b {
    ^ ( __f5k_ln kit `f5_lnaff` F x y w bw rows d eps )
}

// One thread per element of `n`, in blocks of 256.
@ __f5k_go GpuKit kit inout GkCall c s name s body i n → b {
    ^ ( gk_run_checked_dev kit c name body ( gk_grid n 256 ) 256 )
}

// x += gate * y, the gate broadcast down the sequence. This is the adaLN-zero
// residual: at initialisation the gate is zero and the block is the identity.
@ f5k_gated_add GpuKit kit GkBuf x GkBuf y GkBuf gate i rows i d → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `x` x ) ( gk_call_dev_in c `y` y ) ( gk_call_dev_in c `gate` gate )
    ( gk_call_i64 c `rows` rows ) ( gk_call_i64 c `d` d )
    ^ ( __f5k_go kit c `f5_gated_add` `if (gid < rows * d) { ST(x, gid, LD(x, gid) + LD(gate, gid % d) * LD(y, gid)); }` * rows d )
}

// ── heads, and the rotation that goes with them ─────────────────────
//
// [batch*n, heads*hd] → [batch*heads, n, hd], with the interleaved rotary
// embedding applied when `dorope` is set. The tables hold one angle per PAIR
// of features, so cos and sin are [n, hd/2]. The source row is `stride` wide
// and the head block starts `coff` into it — so a fused q/k/v projection's
// three thirds can each be taken out in place, without a copy.
@ f5k_split_rope_s GpuKit kit GkBuf src GkBuf dst GkBuf cosd GkBuf sind i batch i n i heads i hd
i dorope i stride i coff → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `src` src ) ( gk_call_dev c `dst` dst ) ( gk_call_dev_in c `cosd` cosd ) ( gk_call_dev_in c `sind` sind )
    ( gk_call_i64 c `batch` batch ) ( gk_call_i64 c `n` n ) ( gk_call_i64 c `heads` heads ) ( gk_call_i64 c `hd` hd )
    ( gk_call_i64 c `dorope` dorope ) ( gk_call_i64 c `stride` stride ) ( gk_call_i64 c `coff` coff )
    ^ ( __f5k_go kit c `f5_split_rope_s` `long long total = batch * heads * n * hd;
if (gid < total) {
    long long e = gid % hd;
    long long t = (gid / hd) % n;
    long long bh = gid / (hd * n);
    long long h = bh % heads;
    long long bb = bh / heads;
    long long row = (bb * n + t) * stride + coff + h * hd;
    if (dorope == 0) { ST(dst, gid, LD(src, row + e)); }
    else {
        long long p = e >> 1;
        float cs = LD(cosd, t * (hd / 2) + p);
        float sn = LD(sind, t * (hd / 2) + p);
        float x0 = LD(src, row + p * 2);
        float x1 = LD(src, row + p * 2 + 1);
        ST(dst, gid, ((e & 1) == 0) ? (x0 * cs - x1 * sn) : (x1 * cs + x0 * sn));
    }
}` * * * batch heads n hd )
}

// [batch*heads, n, hd] → [batch*n, heads*hd]
@ f5k_merge GpuKit kit GkBuf src GkBuf dst i batch i n i heads i hd → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `src` src ) ( gk_call_dev c `dst` dst )
    ( gk_call_i64 c `batch` batch ) ( gk_call_i64 c `n` n ) ( gk_call_i64 c `heads` heads ) ( gk_call_i64 c `hd` hd )
    ^ ( __f5k_go kit c `f5_merge` `if (gid < batch * heads * n * hd) {
    long long e = gid % hd;
    long long t = (gid / hd) % n;
    long long bh = gid / (hd * n);
    long long h = bh % heads;
    long long bb = bh / heads;
    ST(dst, ((bb * n + t) * heads + h) * hd + e, LD(src, gid));
}` * * * batch heads n hd )
}

// ── activations ─────────────────────────────────────────────────────
//
// Two GELUs, and they are not interchangeable. nn.GELU() is the exact
// integral of the Gaussian; nn.GELU(approximate="tanh") is a different
// function that happens to be close. F5-TTS uses the exact one inside the
// text encoder's ConvNeXt blocks and the tanh one in every transformer
// feed-forward, so using either everywhere is a small, quiet, systematic
// error in half the network.

// x ← f(x) over the first `n` elements, `f` written over `v`.
@ __f5k_act GpuKit kit s name s f GkBuf x i n → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `x` x ) ( gk_call_i64 c `n` n )
    : ~ String body ( string_from `if (gid < n) { float v = LD(x, gid); ` )
    ( string_push_str body f ) ( string_push_str body ` }` )
    ^ ( __f5k_go kit c name ( string_data body ) n )
}

@ f5k_gelu_erf GpuKit kit GkBuf x i n → b {
    ^ ( __f5k_act kit `f5_gelu_erf` `ST(x, gid, v * 0.5f * (1.0f + erff(v * 0.70710678118654752f)));` x n )
}

@ f5k_gelu_tanh GpuKit kit GkBuf x i n → b {
    ^ ( __f5k_act kit `f5_gelu_tanh` `float inner = 0.79788456080286535588f * (v + 0.044715f * v * v * v);
    ST(x, gid, 0.5f * v * (1.0f + tanhf(inner)));` x n )
}

@ f5k_silu GpuKit kit GkBuf x i n → b { ^ ( __f5k_act kit `f5_silu` `ST(x, gid, v / (1.0f + expf(-v)));` x n ) }

@ f5k_mish GpuKit kit GkBuf x i n → b {
    ^ ( __f5k_act kit `f5_mish` `float sp = (v > 20.0f) ? v : log1pf(expf(v));
    ST(x, gid, v * tanhf(sp));` x n )
}

// ── convolution along the sequence ──────────────────────────────────
//
// "Same"-padded and stride 1, written against the [batch, n, channels]
// layout the rest of the forward already uses — so it needs none of the
// transposes PyTorch's channels-first Conv1d forces on its callers. One
// grouped convolution covers all three shapes this port needs: depthwise
// (groups = channels), fully connected across channels (groups = 1) and the
// position embedding's sixteen groups.
//
// The weights are permuted to [K][cin/groups][cout] — the output channel
// LAST, so that the 32 threads of a warp (which hold 32 consecutive output
// channels of the same position) read 32 consecutive floats instead of 32
// floats 1984 apart. The permutation happens once, while the weights are
// being uploaded. And each thread computes FOUR positions: the weights do
// not depend on the position, so computing four together reads each weight
// once for four multiply-adds — this kernel is bound by reading weights, not
// by the arithmetic.
@ f5k_conv1d_t4 GpuKit kit GkBuf x GkBuf y GkBuf w GkBuf bias i batch i n i cin i cout i K i pad i groups → b {
    ? & > groups 0 & == 0 % cin groups == 0 % cout groups {} { ^ F }
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x ) ( gk_call_dev c `y` y ) ( gk_call_dev_in c `w` w ) ( gk_call_dev_in c `bias` bias )
    ( gk_call_i64 c `batch` batch ) ( gk_call_i64 c `n` n ) ( gk_call_i64 c `cin` cin ) ( gk_call_i64 c `cout` cout )
    ( gk_call_i64 c `K` K ) ( gk_call_i64 c `pad` pad ) ( gk_call_i64 c `groups` groups )
    ^ ( __f5k_go kit c `f5_conv1d_t4` `long long nt = (n + 3) / 4;
if (gid < batch * nt * cout) {
    long long ch = gid % cout;
    long long t0 = ((gid / cout) % nt) * 4;
    long long bb = gid / (cout * nt);
    long long ipg = cin / groups;
    long long opg = cout / groups;
    long long gbase = (ch / opg) * ipg;
    long long xb = bb * n * cin;
    float bv = LD(bias, ch);
    float a0 = bv;
    float a1 = bv;
    float a2 = bv;
    float a3 = bv;
    for (long long k = 0; k < K; k++) {
        long long s0 = t0 + k - pad;
        long long wk = k * ipg * cout + ch;
        for (long long j = 0; j < ipg; j++) {
            float wv = LD(w, wk + j * cout);
            long long xs = xb + s0 * cin + gbase + j;
            if (s0 >= 0 && s0 < n) { a0 += wv * LD(x, xs); }
            if (s0 + 1 >= 0 && s0 + 1 < n) { a1 += wv * LD(x, xs + cin); }
            if (s0 + 2 >= 0 && s0 + 2 < n) { a2 += wv * LD(x, xs + 2 * cin); }
            if (s0 + 3 >= 0 && s0 + 3 < n) { a3 += wv * LD(x, xs + 3 * cin); }
        }
    }
    long long base = (bb * n + t0) * cout + ch;
    if (t0 < n) { ST(y, base, a0); }
    if (t0 + 1 < n) { ST(y, base + cout, a1); }
    if (t0 + 2 < n) { ST(y, base + 2 * cout, a2); }
    if (t0 + 3 < n) { ST(y, base + 3 * cout, a3); }
}` * * batch / + n 3 4 cout )
}

// ── GRN ─────────────────────────────────────────────────────────────
//
// ConvNeXt-V2's global response normalisation. Where a LayerNorm asks how one
// position compares with itself, GRN asks how one FEATURE compares with the
// others over the whole sequence: the L2 norm down the sequence axis, divided
// by the mean of those norms. Two reductions over the entire block, then one
// elementwise pass.
@ f5k_grn GpuKit kit GkBuf x GkBuf gx GkBuf meanb GkBuf gamma GkBuf beta i rows i d → b {
    : ~ GkCall c1 ( gk_call_new )
    ( gk_call_dev_in c1 `x` x ) ( gk_call_dev c1 `gx` gx ) ( gk_call_i64 c1 `rows` rows ) ( gk_call_i64 c1 `d` d )
    : ~ b r ( __f5k_go kit c1 `f5_grn_gx` `if (gid < d) {
    float s = 0.0f;
    for (long long r = 0; r < rows; r++) { float v = LD(x, r * d + gid); s += v * v; }
    ST(gx, gid, sqrtf(s));
}` d )
    ? r {} { ^ F }
    : ~ GkCall c2 ( gk_call_new )
    ( gk_call_dev_in c2 `gx` gx ) ( gk_call_dev c2 `meanb` meanb ) ( gk_call_i64 c2 `d` d )
    = r ( gk_run_checked_dev kit c2 `f5_grn_mean` `SHARED_F(red, 256);
float s = 0.0f;
for (long long i = tid; i < d; i += bdim) { s += LD(gx, i); }
ST(red, tid, s);
SYNC();
for (long long st = bdim / 2; st > 0; st >>= 1) {
    if (tid < st) { ST(red, tid, LD(red, tid) + LD(red, tid + st)); }
    SYNC();
}
if (tid == 0) { ST(meanb, 0, LD(red, 0) / (float)d); }` 1 256 )
    ? r {} { ^ F }
    : ~ GkCall c3 ( gk_call_new )
    ( gk_call_dev c3 `x` x ) ( gk_call_dev_in c3 `gx` gx ) ( gk_call_dev_in c3 `meanb` meanb )
    ( gk_call_dev_in c3 `gamma` gamma ) ( gk_call_dev_in c3 `beta` beta )
    ( gk_call_i64 c3 `rows` rows ) ( gk_call_i64 c3 `d` d )
    ^ ( __f5k_go kit c3 `f5_grn_apply` `if (gid < rows * d) {
    long long ch = gid % d;
    float nx = LD(gx, ch) / (LD(meanb, 0) + 1e-6f);
    float v = LD(x, gid);
    ST(x, gid, LD(gamma, ch) * (v * nx) + LD(beta, ch) + v);
}` * rows d )
}

// ── the odds and ends a sampler needs ───────────────────────────────

@ f5k_maskrows GpuKit kit GkBuf x GkBuf keep i rows i d → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `x` x ) ( gk_call_dev_in c `keep` keep ) ( gk_call_i64 c `rows` rows ) ( gk_call_i64 c `d` d )
    ^ ( __f5k_go kit c `f5_maskrows` `if (gid < rows * d) { ST(x, gid, LD(x, gid) * LD(keep, gid / d)); }` * rows d )
}

@ f5k_concat3 GpuKit kit GkBuf x GkBuf cond GkBuf txt GkBuf out i batch i n i mel i td → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x ) ( gk_call_dev_in c `cond` cond ) ( gk_call_dev_in c `txt` txt ) ( gk_call_dev c `out` out )
    ( gk_call_i64 c `batch` batch ) ( gk_call_i64 c `n` n ) ( gk_call_i64 c `mel` mel ) ( gk_call_i64 c `td` td )
    ^ ( __f5k_go kit c `f5_concat3` `long long wd = 2 * mel + td;
if (gid < batch * n * wd) {
    long long col = gid % wd;
    long long r = gid / wd;
    long long t = r % n;
    if (col < mel) { ST(out, gid, LD(x, t * mel + col)); }
    else if (col < 2 * mel) { ST(out, gid, LD(cond, r * mel + (col - mel))); }
    else { ST(out, gid, LD(txt, r * td + (col - 2 * mel))); }
}` * * batch n + * 2 mel td )
}

// out = pred + (pred − uncond) · cfg, the conditional half first.
@ f5k_cfg GpuKit kit GkBuf pred GkBuf out i n i d f cfg → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `pred` pred ) ( gk_call_dev c `out` out )
    ( gk_call_i64 c `n` n ) ( gk_call_i64 c `d` d ) ( gk_call_f64 c `cfg` cfg )
    ^ ( __f5k_go kit c `f5_cfg` `if (gid < n * d) {
    float g = (float)cfg;
    float p = LD(pred, gid);
    float u = LD(pred, n * d + gid);
    ST(out, gid, p + (p - u) * g);
}` * n d )
}

@ f5k_axpy GpuKit kit GkBuf y GkBuf v f alpha i n → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `y` y ) ( gk_call_dev_in c `v` v ) ( gk_call_f64 c `alpha` alpha ) ( gk_call_i64 c `n` n )
    ^ ( __f5k_go kit c `f5_axpy` `if (gid < n) { float al = (float)alpha; ST(y, gid, LD(y, gid) + al * LD(v, gid)); }` n )
}

@ f5k_addinto GpuKit kit GkBuf y GkBuf a i n → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `y` y ) ( gk_call_dev_in c `a` a ) ( gk_call_i64 c `n` n )
    ^ ( __f5k_go kit c `f5_addinto` `if (gid < n) { ST(y, gid, LD(y, gid) + LD(a, gid)); }` n )
}

@ f5k_scalecols GpuKit kit GkBuf x GkBuf g i rows i d → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `x` x ) ( gk_call_dev_in c `g` g ) ( gk_call_i64 c `rows` rows ) ( gk_call_i64 c `d` d )
    ^ ( __f5k_go kit c `f5_scalecols` `if (gid < rows * d) { ST(x, gid, LD(x, gid) * LD(g, gid % d)); }` * rows d )
}
