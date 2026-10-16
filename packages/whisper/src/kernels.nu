// packages/whisper/src/kernels.nu — the encoder/decoder kernels.
//
// Whisper is not the llama shape, and every kernel here is a place it differs:
//
//   * LAYERNORM, not RMSNorm — it subtracts the mean and it has a BIAS.
//   * GELU with the ERROR FUNCTION, not the tanh approximation. HF's
//     ACT2FN["gelu"] is the exact one; the tanh form is a different function and
//     using it would be a quiet, small, everywhere-wrong bias.
//   * CONV1D: two of them in front of the encoder (stride 1 then stride 2),
//     which is what turns 3000 spectrogram frames into 1500 encoder positions.
//   * NON-CAUSAL attention. Everything in this ecosystem so far has masked the
//     future; the whisper encoder looks at the whole 30 seconds at once, and the
//     decoder's cross-attention looks at all of it too.
//
// Every kernel is a CHECKED kernel (packages/gpukit): it reaches device memory
// only through LD(name, i) / ST(name, i, v) over the buffers its launcher binds,
// and every index is checked against that buffer's length. A launcher takes the
// buffers themselves — GkBuf, and GkHBuf for weights kept as 16-bit halves —
// never their addresses, so a wrong size or offset can give a wrong number but
// never a read or write outside the model's memory, and every launcher is a
// plain safe function. The same kernels run on gpukit's CPU backend.
//
// A launcher RECORDS its launch and appends it to a plan (a Vec GkLaunch)
// rather than making it: the model records its encoder, the cross-attention
// projections and one decoder step when it opens, and replays them — a replay
// is one driver call per kernel, with no binding and no checking. What changes
// from one decoder step to the next (the token, the position) is a scalar the
// replay is given (wk_set / wk_attn_keys).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

// A matrix weight on the device: f32 (`f`), or the checkpoint's own 16-bit
// halves (`h`). Halves are widened at the point of use — exactly, denormals
// included — so the arithmetic is f32 either way and the result is
// bit-identical; what changes is that the weight bytes crossing the memory bus
// of a memory-bound matvec are half. Exactly one of the two is there.
: WhW { GkBuf f GkHBuf h }

@ wk_w_none → WhW { ^ @ WhW { ( gk_buf_none GK_F32 ) ( gk_hbuf_none ) } }

@ wk_w_ok WhW w → b { ^ | ( gk_buf_ok . w f ) ( gk_hbuf_ok . w h ) }

@ __wk_bind_w inout GkCall c s name WhW w → v {
    ? ( gk_hbuf_ok . w h ) { ( gk_call_half_in c name . w h ) } { ( gk_call_dev_in c name . w f ) }
}

// Record `body` over `c` and append the launch to `plan`. F (and why, on
// stderr — a refused kernel is a bug in this file) when it is refused.
@ __wk_rec GpuKit kit inout GkCall c s name s body i nblocks i block inout ( Vec GkLaunch ) plan → b {
    : GkLaunch l ( gk_record_dev kit c name body nblocks block )
    ? ( gk_launch_ok l ) {} {
        ( nurl_eprint `whisper: kernel ` ) ( nurl_eprint name ) ( nurl_eprint `: ` )
        ( nurl_eprintln ( gk_checked_error c ) )
        ^ F
    }
    ( vec_push [GkLaunch] plan l )
    ^ T
}

// Replay every launch of `plan`, in order. F on a device error.
@ wk_run ( Vec GkLaunch ) plan → b {
    : ~ b r T
    : ~ i j 0
    ~ & r < j ( vec_len [GkLaunch] plan ) {
        = r ( gk_replay ( vec_at [GkLaunch] plan j ) )
        = j + j 1
    }
    ^ r
}

// Give scalar `name` of the plan's launch `at` the value `x` (a decoder
// step's position or token).
@ wk_set inout ( Vec GkLaunch ) plan i at s name i x → b {
    ^ ( vec_apply [GkLaunch b] plan at F \ inout GkLaunch l → b { ^ ( gk_launch_set_i64 l name x ) } )
}

@ __wk_set_blocks inout ( Vec GkLaunch ) plan i at i nb → b {
    ^ ( vec_apply [GkLaunch b] plan at F \ inout GkLaunch l → b { ^ ( gk_launch_set_blocks l nb ) } )
}

// The bias term of an output: `LD(bias, <idx>)`, or `0.0f` when there is
// none — whisper's k_proj has no bias, alone among its projections.
@ __wk_bias b has s idx → String {
    : ~ String o ( string_new )
    ? has { ( string_push_str o `LD(bias, ` ) ( string_push_str o idx ) ( string_push_str o `)` ) } { ( string_push_str o `0.0f` ) }
    ^ o
}

// What a kernel does with an output value `v` bound for y[<idx>]: the exact
// GELU when `gelu`, then `+ addend[<idx>]` when `add`, stored at `yoff` +
// <idx>. These are the passes that used to be kernels of their own — a
// GELU after fc1, the positional embedding after conv2 — each a full read
// and write of the activation; folded into the store they cost nothing, and
// the arithmetic is the same operations in the same order.
@ __wk_out s v s idx b gelu b add → String {
    : ~ String o ( string_from `{ float ov = ` )
    ( string_push_str o v ) ( string_push_str o `;` )
    ? gelu { ( string_push_str o ` ov = 0.5f * ov * (1.0f + erff(ov * 0.70710678118654752440f));` ) } {}
    // (__fadd_rn: the add the separate kernel made — a plain `+` after the
    // GELU's product would be contracted into one fused multiply-add,
    // rounded once instead of twice.)
    ? add { ( string_push_str o ` ov = __fadd_rn(ov, LD(addend, ` ) ( string_push_str o idx ) ( string_push_str o `));` ) } {}
    ( string_push_str o ` ST(y, yoff + ` ) ( string_push_str o idx ) ( string_push_str o `, ov); }` )
    ^ o
}

@ __wk_cat3 s a s b s c → String {
    : ~ String o ( string_from a )
    ( string_push_str o b ) ( string_push_str o c )
    ^ o
}

// `base` with the variant's suffixes: _b bias, _g GELU, _a addend.
@ __wk_name s base b hb b gelu b add → String {
    : ~ String o ( string_from base )
    ? hb { ( string_push_str o `_b` ) } {}
    ? gelu { ( string_push_str o `_g` ) } {}
    ? add { ( string_push_str o `_a` ) } {}
    ^ o
}

// ── matvec / matmul: y[batch][rows] = W[rows][cols] · x[batch][cols] + bias ──

// The portable matvec: one thread per output row. The CPU backend's kernel —
// a CPU has a real cache, and the warp shapes below are built for a GPU's.
@ __wk_mv_body b hb b gelu b add → String {
    : ~ String o ( string_from `if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = b * cols;
    long long w0 = r * cols;
    float acc = 0.0f;
    for (long long c = 0; c < cols; c++) { acc += LD(W, w0 + c) * LD(x, x0 + c); }
    ` )
    : String v ( __wk_cat3 `acc + ` ( string_data ( __wk_bias hb `r` ) ) `` )
    ( string_push_str o ( string_data ( __wk_out ( string_data v ) `b * rows + r` gelu add ) ) )
    ( string_push_str o `
}` )
    ^ o
}

// One WARP per output row: the 32 lanes stride through the row together, so
// each warp's loads are one contiguous span, and a shuffle reduction folds
// the lane partials.
@ __wk_mvw_body b hb b gelu b add → String {
    : ~ String o ( string_from `long long warp = gid >> 5;
long long lane = gid & 31;
long long b = warp / rows;
long long r = warp % rows;
float acc = 0.0f;
if (warp < rows * batch) {
    long long x0 = b * cols;
    long long w0 = r * cols;
    for (long long c = lane; c < cols; c += 32) { acc += LD(W, w0 + c) * LD(x, x0 + c); }
}
for (int off = 16; off > 0; off >>= 1) { acc += SHFL_DOWN(acc, off); }
if (warp < rows * batch && lane == 0) ` )
    : String v ( __wk_cat3 `acc + ` ( string_data ( __wk_bias hb `r` ) ) `` )
    ( string_push_str o ( string_data ( __wk_out ( string_data v ) `b * rows + r` gelu add ) ) )
    ^ o
}

// Many positions at once: the warp-per-row kernel above would re-read the
// weight matrix for every one of them. This one gives a warp a row AND EIGHT
// POSITIONS: w[c] is loaded once and multiplied into eight accumulators.
// Eight times less weight traffic, the same arithmetic. (nurllama tried the
// same trick on its DECODE path and it lost — there the batch is 1, so there
// is nothing to amortise. The regime is what decides, not the trick.)
@ __wk_mvt_body b hb b gelu b add → String {
    : ~ String o ( string_from `LOCAL_F(acc, 8);
long long warp = gid >> 5;
long long lane = gid & 31;
long long tiles = (batch + 7) / 8;
long long t = warp / rows;
long long r = warp % rows;
long long b0 = t * 8;
UNROLL for (int j = 0; j < 8; j++) { ST(acc, j, 0.0f); }
if (warp < rows * tiles) {
    long long w0 = r * cols;
    for (long long c = lane; c < cols; c += 32) {
        float wc = LD(W, w0 + c);
        UNROLL for (int j = 0; j < 8; j++) {
            if (b0 + j < batch) { ST(acc, j, LD(acc, j) + wc * LD(x, (b0 + j) * cols + c)); }
        }
    }
}
float bs = ` )
    ( string_push_str o ( string_data ( __wk_bias hb `r` ) ) )
    ( string_push_str o `;
UNROLL for (int j = 0; j < 8; j++) {
    float v = LD(acc, j);
    for (int off = 16; off > 0; off >>= 1) { v += SHFL_DOWN(v, off); }
    if (warp < rows * tiles && lane == 0 && b0 + j < batch) ` )
    ( string_push_str o ( string_data ( __wk_out `v + bs` `(b0 + j) * rows + r` gelu add ) ) )
    ( string_push_str o `
}` )
    ^ o
}

// ── The encoder is a GEMM, not a matvec ─────────────────────────────
//
// The encoder projects 1500 positions at once, and a matvec reads the whole
// weight matrix once per handful of them — memory traffic, not arithmetic, and
// it is where the encoder's time went.
//
// A 64x64 output tile held in registers, fed by 64x16 slabs of x and W staged
// through SHARED memory, reads the weight matrix once per 64 positions, and
// each of the 256 threads keeps 16 accumulators so the arithmetic is dense
// enough to hide what is left. The slab loads split a thread's index into
// (row, k) and NOT (k, row): consecutive threads must read consecutive
// ADDRESSES, and x and W are row-major in k — the other way round, the 32
// lanes of a warp each touch a different row, 32 transactions for one.
//
// The tiled GEMM over (batch × cols) · (rows × cols)ᵀ: its A slab staged by
// `aload` (a statement over gm, gk, kk, mm), W the B side.
@ __wk_gemm s aload b hb b gelu b add → String {
    : ~ String o ( string_from `SHARED_F(As, 1024);
SHARED_F(Bs, 1024);
LOCAL_F(acc, 16);
long long nbb = (batch + 63) / 64;
long long bm = bid % nbb;
long long bn = bid / nbb;
long long tx = tid & 15;
long long ty = tid >> 4;
UNROLL for (int i = 0; i < 16; i++) { ST(acc, i, 0.0f); }
for (long long k0 = 0; k0 < cols; k0 += 16) {
    UNROLL for (int L = 0; L < 4; L++) {
        long long idx = tid + L * 256;
        long long mm = idx >> 4;
        long long kk = idx & 15;
        long long gk = k0 + kk;
        long long gm = bm * 64 + mm;
        long long gn = bn * 64 + mm;
        ` )
    ( string_push_str o aload )
    ( string_push_str o `
        ST(Bs, kk * 64 + mm, (gn < rows && gk < cols) ? LD(W, gn * cols + gk) : 0.0f);
    }
    SYNC();
    UNROLL for (int kk = 0; kk < 16; kk++) {
        float a0 = LD(As, kk * 64 + ty * 4);
        float a1 = LD(As, kk * 64 + ty * 4 + 1);
        float a2 = LD(As, kk * 64 + ty * 4 + 2);
        float a3 = LD(As, kk * 64 + ty * 4 + 3);
        float b0 = LD(Bs, kk * 64 + tx * 4);
        float b1 = LD(Bs, kk * 64 + tx * 4 + 1);
        float b2 = LD(Bs, kk * 64 + tx * 4 + 2);
        float b3 = LD(Bs, kk * 64 + tx * 4 + 3);
        ST(acc, 0, LD(acc, 0) + a0 * b0); ST(acc, 1, LD(acc, 1) + a0 * b1); ST(acc, 2, LD(acc, 2) + a0 * b2); ST(acc, 3, LD(acc, 3) + a0 * b3);
        ST(acc, 4, LD(acc, 4) + a1 * b0); ST(acc, 5, LD(acc, 5) + a1 * b1); ST(acc, 6, LD(acc, 6) + a1 * b2); ST(acc, 7, LD(acc, 7) + a1 * b3);
        ST(acc, 8, LD(acc, 8) + a2 * b0); ST(acc, 9, LD(acc, 9) + a2 * b1); ST(acc, 10, LD(acc, 10) + a2 * b2); ST(acc, 11, LD(acc, 11) + a2 * b3);
        ST(acc, 12, LD(acc, 12) + a3 * b0); ST(acc, 13, LD(acc, 13) + a3 * b1); ST(acc, 14, LD(acc, 14) + a3 * b2); ST(acc, 15, LD(acc, 15) + a3 * b3);
    }
    SYNC();
}
UNROLL for (int i = 0; i < 4; i++) {
    long long gm = bm * 64 + ty * 4 + i;
    if (gm < batch) {
        UNROLL for (int j = 0; j < 4; j++) {
            long long gn = bn * 64 + tx * 4 + j;
            if (gn < rows) ` )
    : String v ( __wk_cat3 `LD(acc, i * 4 + j) + ` ( string_data ( __wk_bias hb `gn` ) ) `` )
    ( string_push_str o ( string_data ( __wk_out ( string_data v ) `gm * rows + gn` gelu add ) ) )
    ( string_push_str o `
        }
    }
}` )
    ^ o
}

// Bind a launch's output: y, its offset, the optional addend.
@ __wk_bind_out inout GkCall c GkBuf y i yoff GkBuf add → v {
    ( gk_call_dev c `y` y ) ( gk_call_i64 c `yoff` yoff )
    ? ( gk_buf_ok add ) { ( gk_call_dev_in c `addend` add ) } {}
}

// y[batch][rows] = W[rows][cols] · x[batch][cols] + bias[rows]. `bias` may be
// none (gk_buf_none). `warp` = the CUDA shapes: a 64x64-tiled GEMM for many
// positions (the encoder), a warp per row and eight positions for a few, a
// warp per row for one (the decoder); without it, the portable kernel.
@ wk_matvec GpuKit kit b warp WhW w GkBuf x GkBuf bias GkBuf y i rows i cols i batch inout ( Vec GkLaunch ) plan → b {
    ^ ( wk_matvec_ex kit warp w x bias y 0 F ( gk_buf_none GK_F32 ) rows cols batch plan )
}

// The same, its output written at y[yoff + …] (a decoder step's k and v go
// straight into their row of the KV cache), through the exact GELU when
// `gelu`, plus `add` (same shape as the output) when it is not none.
@ wk_matvec_ex GpuKit kit b warp WhW w GkBuf x GkBuf bias GkBuf y i yoff b gelu GkBuf add i rows i cols i batch inout ( Vec GkLaunch ) plan → b {
    : b hb ( gk_buf_ok bias )
    : b ha ( gk_buf_ok add )
    : ~ GkCall c ( gk_call_new )
    ( __wk_bind_w c `W` w ) ( gk_call_dev_in c `x` x )
    ? hb { ( gk_call_dev_in c `bias` bias ) } {}
    ( __wk_bind_out c y yoff add )
    ( gk_call_i64 c `rows` rows ) ( gk_call_i64 c `cols` cols ) ( gk_call_i64 c `batch` batch )
    ? warp {
        ? >= batch 64 {
            : i nb * / + batch 63 64 / + rows 63 64
            : String body ( __wk_gemm `ST(As, kk * 64 + mm, (gm < batch && gk < cols) ? LD(x, gm * cols + gk) : 0.0f);` hb gelu ha )
            ^ ( __wk_rec kit c ( string_data ( __wk_name `wh_mm` hb gelu ha ) ) ( string_data body ) nb 256 plan )
        } {}
        ? >= batch 8 {
            : i tiles / + batch 7 8
            ^ ( __wk_rec kit c ( string_data ( __wk_name `wh_mvt` hb gelu ha ) ) ( string_data ( __wk_mvt_body hb gelu ha ) ) ( gk_grid * * rows tiles 32 128 ) 128 plan )
        } {}
        ^ ( __wk_rec kit c ( string_data ( __wk_name `wh_mvw` hb gelu ha ) ) ( string_data ( __wk_mvw_body hb gelu ha ) ) ( gk_grid * * rows batch 32 128 ) 128 plan )
    } {}
    ^ ( __wk_rec kit c ( string_data ( __wk_name `wh_mv` hb gelu ha ) ) ( string_data ( __wk_mv_body hb gelu ha ) ) ( gk_grid * rows batch 128 ) 128 plan )
}

// ── LayerNorm ───────────────────────────────────────────────────────
//
// Subtract the mean, divide by the standard deviation, scale and SHIFT.
// RMSNorm does none of the mean and none of the shift, which is why a model
// trained with one cannot be run with the other. A row's mean and variance
// are computed once per ROW: the kernel this once was gave one thread one
// element and had it walk the whole row twice, 2n² reads per row — 4.9
// billion for the encoder's 1500 x 1280, as much as a feed-forward layer.
//
// Every norm but the first comes right after a residual add (x += the
// sublayer's output), so the add is done here, by the pass that reads x
// anyway: `res` given, x[j] = x[j] + res[j] is stored as the row is summed —
// the same addition the separate kernel made, one launch and one pass over
// the activation fewer.

// The row's first pass: the sum, after the residual add when there is one.
@ __wk_ln_first b res s acc → String {
    ? res { ^ ( __wk_cat3 `{ float xv = LD(x, r0 + j) + LD(res, r0 + j); ST(x, r0 + j, xv); ` acc ` += xv; }` ) } {}
    ^ ( __wk_cat3 `{ ` acc ` += LD(x, r0 + j); }` )
}

// One thread per row: the CPU backend's.
@ __wk_ln_body b res → String {
    : ~ String o ( string_from `if (gid < batch) {
    long long r0 = gid * n;
    float mean = 0.0f;
    for (long long j = 0; j < n; j++) ` )
    ( string_push_str o ( string_data ( __wk_ln_first res `mean` ) ) )
    ( string_push_str o `
    mean /= (float)n;
    float var = 0.0f;
    for (long long j = 0; j < n; j++) { float d = LD(x, r0 + j) - mean; var += d * d; }
    var /= (float)n;
    float inv = rsqrtf(var + (float)eps);
    for (long long j = 0; j < n; j++) { ST(y, r0 + j, (LD(x, r0 + j) - mean) * inv * LD(w, j) + LD(bias, j)); }
}` )
    ^ o
}

// On a GPU one thread per row is 1500 threads — a rounding error of the
// machine. One BLOCK per row: 256 threads share the row's sums through a
// shared-memory reduction, and every access is coalesced.
@ __wk_lnb_body b res → String {
    : ~ String o ( string_from `SHARED_F(red, 256);
if (bid < batch) {
    long long r0 = bid * n;
    float s = 0.0f;
    for (long long j = tid; j < n; j += 256) ` )
    ( string_push_str o ( string_data ( __wk_ln_first res `s` ) ) )
    ( string_push_str o `
    ST(red, tid, s);
    SYNC();
    for (long long off = 128; off > 0; off >>= 1) {
        if (tid < off) { ST(red, tid, LD(red, tid) + LD(red, tid + off)); }
        SYNC();
    }
    float mean = LD(red, 0) / (float)n;
    SYNC();
    float v = 0.0f;
    for (long long j = tid; j < n; j += 256) { float d = LD(x, r0 + j) - mean; v += d * d; }
    ST(red, tid, v);
    SYNC();
    for (long long off = 128; off > 0; off >>= 1) {
        if (tid < off) { ST(red, tid, LD(red, tid) + LD(red, tid + off)); }
        SYNC();
    }
    float inv = rsqrtf(LD(red, 0) / (float)n + (float)eps);
    for (long long j = tid; j < n; j += 256) { ST(y, r0 + j, (LD(x, r0 + j) - mean) * inv * LD(w, j) + LD(bias, j)); }
}` )
    ^ o
}

// y = LayerNorm(x) over rows of `n`; with `res` (not none) x += res first,
// in place.
@ wk_layernorm GpuKit kit b warp GkBuf x GkBuf res GkBuf w GkBuf bias GkBuf y i n f eps i batch inout ( Vec GkLaunch ) plan → b {
    : b hr ( gk_buf_ok res )
    : ~ GkCall c ( gk_call_new )
    ? hr { ( gk_call_dev c `x` x ) ( gk_call_dev_in c `res` res ) } { ( gk_call_dev_in c `x` x ) }
    ( gk_call_dev_in c `w` w ) ( gk_call_dev_in c `bias` bias ) ( gk_call_dev c `y` y )
    ( gk_call_i64 c `n` n ) ( gk_call_f64 c `eps` eps ) ( gk_call_i64 c `batch` batch )
    ? warp { ^ ( __wk_rec kit c ? hr `wh_lnb_r` `wh_lnb` ( string_data ( __wk_lnb_body hr ) ) batch 256 plan ) } {}
    ^ ( __wk_rec kit c ? hr `wh_ln_r` `wh_ln` ( string_data ( __wk_ln_body hr ) ) ( gk_grid batch 256 ) 256 plan )
}

// Conv1d over time, kernel 3, `pad` on both sides, `stride` between outputs,
// through the exact GELU (whisper's convs are always followed by one), plus
// `add` when it is not none. Layout: x is [T_in][C_in] (a spectrogram frame
// is contiguous), W is [C_out][C_in][3] as safetensors stores it, y is
// [T_out][C_out].
//
// On a GPU it is a GEMM: output t, channel o is row o of W (C_in·3 long, as
// stored) against the C_in·3 inputs around frame t·stride — so the tiled
// GEMM above runs it, its A slab gathered from those frames (zero past
// either end). The direct form — one thread per output walking its own
// weight row three floats apart, every warp's 32 reads in 32 different
// places — was the encoder's single slowest kernel: 40 ms of a 200 ms
// large-v3 window for the stride-2 conv, against under 1 ms as a GEMM.
// (The sum is the same terms in another order, so not the same bits.)
@ __wk_conv_body b add → String {
    : ~ String o ( string_from `long long T_out = (T_in + 2 * pad - 3) / stride + 1;
if (gid < T_out * C_out) {
    long long t = gid / C_out;
    long long o = gid % C_out;
    float acc = LD(bias, o);
    for (int k = 0; k < 3; k++) {
        long long ti = t * stride + k - pad;
        if (ti >= 0 && ti < T_in) {
            long long xi = ti * C_in;
            long long wi = o * C_in * 3 + k;
            for (long long c = 0; c < C_in; c++) { acc += LD(x, xi + c) * LD(W, wi + c * 3); }
        }
    }
    ` )
    ( string_push_str o ( string_data ( __wk_out `acc` `t * C_out + o` T add ) ) )
    ( string_push_str o `
}` )
    ^ o
}

@ wk_conv1d_gelu GpuKit kit b warp GkBuf x GkBuf w GkBuf bias GkBuf add GkBuf y i t_in i c_in i c_out i stride i pad inout ( Vec GkLaunch ) plan → b {
    : i t_out + / - + t_in * 2 pad 3 stride 1
    : b ha ( gk_buf_ok add )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x ) ( gk_call_dev_in c `W` w ) ( gk_call_dev_in c `bias` bias )
    ( __wk_bind_out c y 0 add )
    ( gk_call_i64 c `T_in` t_in ) ( gk_call_i64 c `C_in` c_in ) ( gk_call_i64 c `stride` stride ) ( gk_call_i64 c `pad` pad )
    ? warp {
        ( gk_call_i64 c `rows` c_out ) ( gk_call_i64 c `cols` * 3 c_in ) ( gk_call_i64 c `batch` t_out )
        : i nb * / + t_out 63 64 / + c_out 63 64
        : String body ( __wk_gemm `long long cc = gk / 3;
        long long ti = gm * stride + (gk - cc * 3) - pad;
        ST(As, kk * 64 + mm, (gm < batch && gk < cols && ti >= 0 && ti < T_in) ? LD(x, ti * C_in + cc) : 0.0f);` T T ha )
        ^ ( __wk_rec kit c ? ha `wh_convmm_a` `wh_convmm` ( string_data body ) nb 256 plan )
    } {}
    ( gk_call_i64 c `C_out` c_out )
    ^ ( __wk_rec kit c ? ha `wh_conv_a` `wh_conv` ( string_data ( __wk_conv_body ha ) ) ( gk_grid * t_out c_out 256 ) 256 plan )
}

// ── Attention ───────────────────────────────────────────────────────
//
// `causal` 0 = every query sees every key (the encoder, and the decoder's
// cross-attention); 1 = a query sees only keys at or before it.

// Fused, the flash-attention shape. The composed path (scores, then softmax
// and values) launches nh·nq·nkey threads that each re-read a whole query row
// and a whole key row to produce ONE score — ~23 GB of traffic per encoder
// layer of distil — and materialises an nh × 1500 × 1500 score matrix that
// exists only to be read back. Here one block owns 64 queries of one head and
// keeps them, and their 64 output accumulators, in REGISTERS (per-thread
// arrays, the loops over them unrolled); keys and values stream past in
// 64-row slabs through shared memory, read once per query tile; the softmax
// is computed online (running max and running sum, the accumulator rescaled
// when the max moves), so there is no score matrix at all. head_dim must be
// 64 — every whisper's is (384/6 … 1280/20); anything else takes the
// composed path, which is still correct.
@ __wk_attf_body → s {
    ^ `SHARED_F(Ks, 4096);
SHARED_F(Vs, 4096);
LOCAL_F(qr, 64);
LOCAL_F(acc, 64);
long long h = bid % nh;
long long qt = bid / nh;
long long i = qt * 64 + tid;
float qs = (float)qscale;
UNROLL for (int d = 0; d < 64; d++) {
    ST(qr, d, (i < nq) ? LD(q, i * nh * 64 + h * 64 + d) : 0.0f);
    ST(acc, d, 0.0f);
}
float m = -1e30f;
float l = 0.0f;
for (long long k0 = 0; k0 < nkey; k0 += 64) {
    long long nn = nkey - k0;
    if (nn > 64) { nn = 64; }
    if (nn == 64) {
        for (int idx = (int)tid; idx < 4096; idx += 64) {
            long long o = (k0 + (idx >> 6)) * nh * 64 + h * 64 + (idx & 63);
            ST(Ks, idx, LD(K, o));
            ST(Vs, idx, LD(V, o));
        }
    } else {
        for (int idx = (int)tid; idx < nn * 64; idx += 64) {
            long long o = (k0 + (idx >> 6)) * nh * 64 + h * 64 + (idx & 63);
            ST(Ks, idx, LD(K, o));
            ST(Vs, idx, LD(V, o));
        }
    }
    SYNC();
    for (int j = 0; j < 64; j++) {
        if (j < nn) {
            float s = 0.0f;
            UNROLL for (int d = 0; d < 64; d++) { s += LD(qr, d) * LD(Ks, j * 64 + d); }
            s *= qs;
            float mn = s > m ? s : m;
            float corr = expf(m - mn);
            float p = expf(s - mn);
            l = l * corr + p;
            UNROLL for (int d = 0; d < 64; d++) { ST(acc, d, LD(acc, d) * corr + p * LD(Vs, j * 64 + d)); }
            m = mn;
        }
    }
    SYNC();
}
if (i < nq) {
    UNROLL for (int d = 0; d < 64; d++) { ST(out, i * nh * 64 + h * 64 + d, LD(acc, d) / l); }
}`
}

// Fused for ONE query — the decoder, every step of it. attn_f amortises the
// key/value stream over 64 queries and a decode step has one; handing a
// query and a head to one block leaves most of the machine idle. So the keys
// are cut into chunks, one block per (query, head, chunk): thread t scores
// key kbeg+t (each key row read once, sequentially); the block then splits
// into 4 sub-blocks of 64 threads, thread d of sub-block s owning output
// element d over its own share of the chunk's keys (V rows read in one
// transaction); every sub-block keeps its own online-softmax state, they
// merge into one partial per chunk (in `part`: 64 accumulators, the max, the
// denominator), and wk_attn's second kernel merges the chunks the same way —
// rescale by exp(m - M). Merging partial softmaxes is associative, so the
// split is invisible in the answer: cross-attention 95 us to 11 on tiny.
@ __wk_attd_body → s {
    ^ `SHARED_F(qv, 64);
SHARED_F(sc, 256);
SHARED_F(pm, 4);
SHARED_F(pl, 4);
SHARED_F(pacc, 256);
long long c = bid % nchunk;
long long qh = bid / nchunk;
long long h = qh % nh;
long long i = qh / nh;
long long sb = tid >> 6;
long long d = tid & 63;
float qs = (float)qscale;
if (tid < 64) { ST(qv, tid, LD(q, i * nh * 64 + h * 64 + tid)); }
SYNC();
long long lim = causal != 0 ? i + 1 : nkey;
if (lim > nkey) { lim = nkey; }
long long kbeg = c * chunk;
long long kend = kbeg + chunk;
if (kend > lim) { kend = lim; }
float m = -1e30f;
float l = 0.0f;
float acc = 0.0f;
for (long long k0 = kbeg; k0 < kend; k0 += 256) {
    long long nn = kend - k0;
    if (nn > 256) { nn = 256; }
    float sv = -1e30f;
    if (tid < nn) {
        long long kv = (k0 + tid) * nh * 64 + h * 64;
        float a = 0.0f;
        for (int j = 0; j < 64; j++) { a += LD(qv, j) * LD(K, kv + j); }
        sv = a * qs;
    }
    ST(sc, tid, sv);
    SYNC();
    long long base = sb * 64;
    long long cnt = nn - base;
    if (cnt > 64) { cnt = 64; }
    if (cnt < 0) { cnt = 0; }
    for (long long j = 0; j < cnt; j++) {
        float sj = LD(sc, base + j);
        float mn = sj > m ? sj : m;
        float corr = expf(m - mn);
        float p = expf(sj - mn);
        l = l * corr + p;
        acc = acc * corr + p * LD(V, (k0 + base + j) * nh * 64 + h * 64 + d);
        m = mn;
    }
    SYNC();
}
ST(pacc, sb * 64 + d, acc);
if (d == 0) { ST(pm, sb, m); ST(pl, sb, l); }
SYNC();
if (tid < 64) {
    float M = -1e30f;
    for (int u = 0; u < 4; u++) { if (LD(pm, u) > M) { M = LD(pm, u); } }
    float L = 0.0f;
    float A = 0.0f;
    for (int u = 0; u < 4; u++) {
        float cf = expf(LD(pm, u) - M);
        L += LD(pl, u) * cf;
        A += LD(pacc, u * 64 + d) * cf;
    }
    long long po = bid * 66;
    ST(part, po + d, A);
    if (d == 0) { ST(part, po + 64, M); ST(part, po + 65, L); }
}`
}

// The chunks' partial softmaxes, merged: one block per (query, head), one
// thread per output element.
@ __wk_attdm_body → s {
    ^ `long long qh = bid;
long long h = qh % nh;
long long i = qh / nh;
long long d = tid;
float M = -1e30f;
for (long long c = 0; c < nchunk; c++) {
    float mc = LD(part, (qh * nchunk + c) * 66 + 64);
    if (mc > M) { M = mc; }
}
float L = 0.0f;
float A = 0.0f;
for (long long c = 0; c < nchunk; c++) {
    long long po = (qh * nchunk + c) * 66;
    float cf = expf(LD(part, po + 64) - M);
    L += LD(part, po + 65) * cf;
    A += LD(part, po + d) * cf;
}
ST(out, i * nh * 64 + h * 64 + d, A / L);`
}

// The composed path: every score, then softmax · V.
@ __wk_attsc_body → s {
    ^ `if (gid < nh * nq * nkey) {
    long long t = gid % nkey;
    long long qh = gid / nkey;
    long long h = qh % nh;
    long long i = qh / nh;
    if (causal != 0 && t > i) { ST(scores, qh * nkey + t, -1e30f); }
    else {
        long long qv = i * nh * hd + h * hd;
        long long kv = t * nh * hd + h * hd;
        float d = 0.0f;
        for (long long j = 0; j < hd; j++) { d += LD(q, qv + j) * LD(K, kv + j); }
        ST(scores, qh * nkey + t, d * (float)qscale);
    }
}`
}

@ __wk_atto_body → s {
    ^ `if (gid < nh * nq * hd) {
    long long d = gid % hd;
    long long qh = gid / hd;
    long long h = qh % nh;
    long long i = qh / nh;
    long long s0 = qh * nkey;
    float mx = -1e30f;
    for (long long t = 0; t < nkey; t++) { if (LD(scores, s0 + t) > mx) { mx = LD(scores, s0 + t); } }
    float sum = 0.0f;
    float acc = 0.0f;
    for (long long t = 0; t < nkey; t++) {
        float p = expf(LD(scores, s0 + t) - mx);
        sum += p;
        acc += p * LD(V, t * nh * hd + h * hd + d);
    }
    ST(out, i * nh * hd + h * hd + d, acc / sum);
}`
}

// Which attention runs: 0 = fused for one query, 1 = fused for many, 2 =
// composed. wk_attn and wk_attn_keys must agree on it.
@ __wk_attn_kind b warp i hd i nq i causal → i {
    ? & & warp == hd 64 < nq 64 { ^ 0 } {}
    ? & & & warp == causal 0 == hd 64 >= nq 64 { ^ 1 } {}
    ^ 2
}

// The one-query path's split: 128 keys a chunk, at most 32 chunks.
@ __wk_chunk i lim → i {
    : i nc / + lim 127 128
    ? > nc 32 { ^ / + lim 31 32 } {}
    ^ 128
}

@ __wk_nchunk i lim → i {
    : i nc / + lim 127 128
    ? < nc 1 { ^ 1 } {}
    ? > nc 32 { ^ 32 } {}
    ^ nc
}

// Attention: out[nq][nh·hd] from q[nq][nh·hd] and K, V [nkey][nh·hd]. `sc` is
// scratch — the one-query path's per-chunk partials (nh·nq·32·66 floats), or
// the composed path's score matrix (nh·nq·nkey); the fused many-query path
// needs none (it may be none then). Appends one or two launches.
@ wk_attn GpuKit kit b warp GkBuf q GkBuf k GkBuf v GkBuf sc GkBuf out i nh i hd i nq i nkey f qscale i causal inout ( Vec GkLaunch ) plan → b {
    : i kind ( __wk_attn_kind warp hd nq causal )
    ? == kind 0 {
        : i lim ? != causal 0 nkey nkey
        : i nchunk ( __wk_nchunk lim )
        : ~ GkCall c ( gk_call_new )
        ( gk_call_dev_in c `q` q ) ( gk_call_dev_in c `K` k ) ( gk_call_dev_in c `V` v ) ( gk_call_dev c `part` sc )
        ( gk_call_i64 c `nh` nh ) ( gk_call_i64 c `nq` nq ) ( gk_call_i64 c `nkey` nkey ) ( gk_call_f64 c `qscale` qscale )
        ( gk_call_i64 c `causal` causal ) ( gk_call_i64 c `chunk` ( __wk_chunk lim ) ) ( gk_call_i64 c `nchunk` nchunk )
        ? ( __wk_rec kit c `wh_attd` ( __wk_attd_body ) * * nh nq nchunk 256 plan ) {} { ^ F }
        : ~ GkCall c2 ( gk_call_new )
        ( gk_call_dev_in c2 `part` sc ) ( gk_call_dev c2 `out` out )
        ( gk_call_i64 c2 `nh` nh ) ( gk_call_i64 c2 `nchunk` nchunk )
        ^ ( __wk_rec kit c2 `wh_attdm` ( __wk_attdm_body ) * nh nq 64 plan )
    } {}
    ? == kind 1 {
        : ~ GkCall c ( gk_call_new )
        ( gk_call_dev_in c `q` q ) ( gk_call_dev_in c `K` k ) ( gk_call_dev_in c `V` v ) ( gk_call_dev c `out` out )
        ( gk_call_i64 c `nh` nh ) ( gk_call_i64 c `nq` nq ) ( gk_call_i64 c `nkey` nkey ) ( gk_call_f64 c `qscale` qscale )
        ^ ( __wk_rec kit c `wh_attf` ( __wk_attf_body ) * nh / + nq 63 64 64 plan )
    } {}
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `q` q ) ( gk_call_dev_in c `K` k ) ( gk_call_dev c `scores` sc )
    ( gk_call_i64 c `nh` nh ) ( gk_call_i64 c `hd` hd ) ( gk_call_i64 c `nq` nq ) ( gk_call_i64 c `nkey` nkey )
    ( gk_call_f64 c `qscale` qscale ) ( gk_call_i64 c `causal` causal )
    ? ( __wk_rec kit c `wh_attsc` ( __wk_attsc_body ) ( gk_grid * * nh nq nkey 256 ) 256 plan ) {} { ^ F }
    : ~ GkCall c2 ( gk_call_new )
    ( gk_call_dev_in c2 `V` v ) ( gk_call_dev_in c2 `scores` sc ) ( gk_call_dev c2 `out` out )
    ( gk_call_i64 c2 `nh` nh ) ( gk_call_i64 c2 `hd` hd ) ( gk_call_i64 c2 `nq` nq ) ( gk_call_i64 c2 `nkey` nkey )
    ^ ( __wk_rec kit c2 `wh_atto` ( __wk_atto_body ) ( gk_grid * * nh nq hd 256 ) 256 plan )
}

// The attention wk_attn recorded at plan[at] (with the same warp, hd, nq and
// causal), now over `nkey` keys — the decoder's self-attention grows by one
// key a step.
@ wk_attn_keys inout ( Vec GkLaunch ) plan i at b warp i nh i hd i nq i nkey i causal → b {
    : i kind ( __wk_attn_kind warp hd nq causal )
    ? == kind 0 {
        : i nchunk ( __wk_nchunk nkey )
        : ~ b ok ( wk_set plan at `nkey` nkey )
        = ok & ok ( wk_set plan at `chunk` ( __wk_chunk nkey ) )
        = ok & ok ( wk_set plan at `nchunk` nchunk )
        = ok & ok ( __wk_set_blocks plan at * * nh nq nchunk )
        ^ & ok ( wk_set plan + at 1 `nchunk` nchunk )
    } {}
    ? == kind 1 { ^ ( wk_set plan at `nkey` nkey ) } {}
    : ~ b ok ( wk_set plan at `nkey` nkey )
    = ok & ok ( __wk_set_blocks plan at ( gk_grid * * nh nq nkey 256 ) )
    ^ & ok ( wk_set plan + at 1 `nkey` nkey )
}

// ── small ones ──────────────────────────────────────────────────────

// a[i] += b[off + i] for i < n. `off` 0 is a plain add; the decoder adds its
// position's row of the positional embedding by offset.
@ wk_addv GpuKit kit GkBuf a GkBuf b i off i n inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `a` a ) ( gk_call_dev_in c `b` b ) ( gk_call_i64 c `off` off ) ( gk_call_i64 c `n` n )
    ^ ( __wk_rec kit c `wh_addv` `if (gid < n) { ST(a, gid, LD(a, gid) + LD(b, off + gid)); }` ( gk_grid n 256 ) 256 plan )
}

// A token's row of the embedding table plus its position's row of the
// positional embedding → the decoder's activation. The table is on the
// device (it is also the output projection — whisper ties them), so a
// token's row is a copy, not a host round-trip.
@ wk_embed GpuKit kit WhW table GkBuf pos GkBuf y i row i off i n inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( __wk_bind_w c `table` table ) ( gk_call_dev_in c `pos` pos ) ( gk_call_dev c `y` y )
    ( gk_call_i64 c `row` row ) ( gk_call_i64 c `off` off ) ( gk_call_i64 c `n` n )
    ^ ( __wk_rec kit c `wh_embed` `if (gid < n) { ST(y, gid, LD(table, row * n + gid) + LD(pos, off + gid)); }` ( gk_grid n 256 ) 256 plan )
}

// Widen 16-bit weights (f16, or bf16 — the GkHBuf says which) to f32 on the
// device: half the bytes over PCIe, and the widening happens where there are
// thousands of threads for it instead of one host loop doing 378 million
// iterations.
@ wk_cvt GpuKit kit GkHBuf src GkBuf dst i n inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_half_in c `src` src ) ( gk_call_dev c `dst` dst ) ( gk_call_i64 c `n` n )
    ^ ( __wk_rec kit c `wh_cvt` `if (gid < n) { ST(dst, gid, LD(src, gid)); }` ( gk_grid n 256 ) 256 plan )
}

// ── Greedy decoding's argmax, on the device ─────────────────────────
//
// The only thing greedy decoding wants from a step is WHICH logit is
// largest. Fetching the row to find out cost a 51865-float transfer and a
// 51865-iteration host loop — 365 us a token against a 477 us decode step.
// Reduced where it lives, the answer is one integer (out[0], an i64 buffer).
// One block of 1024 threads: each scans its stride of the row, then the
// warps fold their 32 candidates with shuffles and the 32 warp winners fold
// the same way — two shared-memory round trips, not a barrier per halving.
// Ties go to the LOWER index at every step, which is what the host scan's `>`
// gives — so the token stream is unchanged, not merely equivalent.
@ wk_argmax GpuKit kit GkBuf x i n GkBuf out inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x ) ( gk_call_dev c `out` out ) ( gk_call_i64 c `n` n )
    ^ ( __wk_rec kit c `wh_argmax` `SHARED_F(wv, 32);
SHARED_L(wi, 32);
float bv = -1e30f;
long long bi = 0;
for (long long i = tid; i < n; i += 1024) {
    float v = LD(x, i);
    if (v > bv) { bv = v; bi = i; }
}
for (int off = 16; off > 0; off >>= 1) {
    float ov = SHFL_DOWN(bv, off);
    long long oi = SHFL_DOWN(bi, off);
    if (ov > bv || (ov == bv && oi < bi)) { bv = ov; bi = oi; }
}
if ((tid & 31) == 0) { ST(wv, tid >> 5, bv); ST(wi, tid >> 5, bi); }
SYNC();
bv = LD(wv, tid & 31);
bi = LD(wi, tid & 31);
for (int off = 16; off > 0; off >>= 1) {
    float ov = SHFL_DOWN(bv, off);
    long long oi = SHFL_DOWN(bi, off);
    if (ov > bv || (ov == bv && oi < bi)) { bv = ov; bi = oi; }
}
if (tid == 0) { ST(out, 0, bi); }` 1 1024 plan )
}
