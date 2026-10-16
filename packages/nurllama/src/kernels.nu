// packages/nurllama/src/kernels.nu — the LLM decode ops as GPU kernels.
//
// Every kernel is a CHECKED kernel (packages/gpukit): it reaches device memory
// only through LD / ST (and LD16 / LD32 / LD4) over the buffers its launcher
// binds, and every index is checked against that buffer's length. A launcher
// takes the buffers themselves — GkBuf for floats, GkBBuf for a weight's GGUF
// bytes — never their addresses, so a wrong size or offset can give a wrong
// number but never a read or write outside the model's memory: every
// launcher is a plain safe function, and so is the engine that calls them.
// The same kernels run on gpukit's CPU backend.
//
// A launcher RECORDS its launch and appends it to a plan (a Vec GkLaunch);
// the engine records one evaluation's launches and replays them, giving the
// next call only the scalars that changed (its position).
//
// Layout contracts (ggml row-major, ne0 fastest):
//   weight W[out,in]  → W[r*in + c], matvec y[r] = Σc W[r*in+c]·x[c]
//   K/V cache         → cache[t*(n_kv·hd) + kh*hd + d]
//   q/k activations   → x[h*hd + d]
//
// Offsets are scalars, not views: `woff` (bytes of a quantised W, elements
// of an f32 / f16 one), `xoff` and `yoff` (elements) move a launch inside its
// buffers — a MoE expert's rows, the last position's activation — without a
// view whose start would break the alignment the word loads rely on.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

// A weight tensor on the device, in its GGUF form: `gt` the ggml type and
// `q` its bytes (the quantised blocks — or, for the float types, the f32 /
// f16 elements' bytes), and for the float types the same memory as f32
// (`f`, gt 0) or halves (`h`, gt 1). Q8_0 is held in the SPLIT row layout
// lk_q8_repack produces.
: LkW { i gt GkBBuf q GkBuf f GkHBuf h }

@ lk_w_none → LkW { ^ @ LkW { -1 ( gk_bbuf_none ) ( gk_buf_none GK_F32 ) ( gk_hbuf_none ) } }

@ lk_w_ok LkW w → b { ^ >= . w gt 0 }

// Record `body` over `c`, append it to `plan`. F (and why, on stderr — a
// refused kernel is a bug in this file) when it is refused.
@ __lk_rec GpuKit kit inout GkCall c s name s body i nblocks i block inout ( Vec GkLaunch ) plan → b {
    : GkLaunch l ( gk_record_dev kit c name body nblocks block )
    ? ( gk_launch_ok l ) {} {
        ( nurl_eprint `nurllama: kernel ` ) ( nurl_eprint name ) ( nurl_eprint `: ` )
        ( nurl_eprintln ( gk_checked_error c ) )
        ^ F
    }
    ( vec_push [GkLaunch] plan l )
    ^ T
}

// Replay `plan`, in order. F on a device error.
@ lk_run ( Vec GkLaunch ) plan → b {
    : ~ b r T
    : ~ i j 0
    ~ & r < j ( vec_len [GkLaunch] plan ) {
        = r ( gk_replay ( vec_at [GkLaunch] plan j ) )
        = j + j 1
    }
    ^ r
}

// Give scalar `name` of the plan's launch `at` the value `x`.
@ lk_set inout ( Vec GkLaunch ) plan i at s name i x → b {
    ^ ( vec_apply [GkLaunch b] plan at F \ inout GkLaunch l → b { ^ ( gk_launch_set_i64 l name x ) } )
}

@ __lk_cat3 s a s b s c → String {
    : ~ String o ( string_from a )
    ( string_push_str o b ) ( string_push_str o c )
    ^ o
}

// ── matvec: y[yoff + b·rows + r] = Σc W[r, c] · x[xoff + b·cols + c] ──

// One thread per output: the portable f32 matvec.
@ __lk_mv_body → s {
    ^ `if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long w0 = woff + r * cols;
    long long x0 = xoff + b * cols;
    float acc = 0.0f;
    for (long long c = 0; c < cols; c++) { acc += LD(W, w0 + c) * LD(x, x0 + c); }
    ST(y, yoff + b * rows + r, acc);
}`
}

// The f16 one: W bound as halves, read exactly as floats.
@ __lk_mv_f16_body → s { ^ ( __lk_mv_body ) }

// One WARP per output row (CUDA): the 32 lanes stride through the row
// together, so each warp's loads are one contiguous span, and a shuffle
// reduction folds the lane partials. `INNER` walks lane's share of row r
// for position b into `acc`.
@ __lk_warp s inner → String {
    ^ ( __lk_cat3 `long long warp = gid >> 5;
long long lane = gid & 31;
long long b = warp / rows;
long long r = warp % rows;
float acc = 0.0f;
if (warp < rows * batch) {
    long long x0 = xoff + b * cols;
` inner `
}
for (int off = 16; off > 0; off >>= 1) { acc += SHFL_DOWN(acc, off); }
if (warp < rows * batch && lane == 0) { ST(y, yoff + b * rows + r, acc); }` )
}

@ __lk_mv_f32_w → String {
    ^ ( __lk_warp `    long long w0 = woff + r * cols;
    for (long long c = lane; c < cols; c += 32) { acc += LD(W, w0 + c) * LD(x, x0 + c); }` )
}

// Batch-reuse matvecs: one thread per output ROW, looping over the batch
// positions in register tiles, so each weight element is read from DRAM
// once per 32-position tile instead of once per position. The per-output
// summation order is the scalar kernels', so results are bit-exact.
@ __lk_mv_f32_b → s {
    ^ `LOCAL_F(acc, 32);
if (gid < rows) {
    long long r = gid;
    long long w0 = woff + r * cols;
    for (long long b0 = 0; b0 < batch; b0 += 32) {
        long long bn = batch - b0;
        if (bn > 32) { bn = 32; }
        for (long long t = 0; t < bn; t++) { ST(acc, t, 0.0f); }
        for (long long c = 0; c < cols; c++) {
            float wv = LD(W, w0 + c);
            for (long long t = 0; t < bn; t++) { ST(acc, t, LD(acc, t) + wv * LD(x, xoff + (b0 + t) * cols + c)); }
        }
        for (long long t = 0; t < bn; t++) { ST(y, yoff + (b0 + t) * rows + r, LD(acc, t)); }
    }
}`
}

// ── Q8_0, in the SPLIT row layout (lk_q8_repack) ─────────────────────
//
// A row of nb blocks is [nb f16 scales][nb × 32 int8 quants], nb·34 bytes:
// with an even nb the quant region is 4-byte aligned, so a block is eight
// 32-bit words of quants against eight float4s of x — 16 loads instead of
// 64, and the accumulation keeps the byte-at-a-time left fold, so the
// result is the same bit for bit. Odd nb (tiny test models) reads bytes.

// `sub` += the block's 32 quants (words from byte QB) · x (from XB).
@ __lk_q8_dot s qb s xb → String {
    : ~ String o ( string_from `UNROLL for (int k8 = 0; k8 < 8; k8++) {
                unsigned int qq = LD32(W, ` )
    ( string_push_str o qb )
    ( string_push_str o ` + k8 * 4);
                float xa = 0.0f;
                float xc = 0.0f;
                float xe = 0.0f;
                float xg = 0.0f;
                LD4(x, ` )
    ( string_push_str o xb )
    ( string_push_str o ` + k8 * 4, xa, xc, xe, xg);
                sub += (float)(signed char)(qq) * xa;
                sub += (float)(signed char)(qq >> 8) * xc;
                sub += (float)(signed char)(qq >> 16) * xe;
                sub += (float)(signed char)(qq >> 24) * xg;
            }` )
    ^ o
}

// The byte form of the same dot, for odd nb.
@ __lk_q8_dotb s qb s xb → String {
    : ~ String o ( string_from `for (int j = 0; j < 32; j++) { sub += (float)(signed char)LD(W, ` )
    ( string_push_str o qb ) ( string_push_str o ` + j) * LD(x, ` ) ( string_push_str o xb ) ( string_push_str o ` + j); }` )
    ^ o
}

// The block loop of one row against one x row: `LANE0`/`STEP` 0/1 for a
// thread's own walk, lane/32 for a warp's.
@ __lk_q8_row s from s step → String {
    : ~ String o ( string_from `    long long nb = cols / 32;
    long long w0 = woff + r * nb * 34;
    long long q0 = w0 + nb * 2;
    if ((nb & 1) == 0) {
        for (long long blk = ` )
    ( string_push_str o from ) ( string_push_str o `; blk < nb; blk += ` ) ( string_push_str o step ) ( string_push_str o `) {
            float d = F16(LD16(W, w0 + blk * 2));
            float sub = 0.0f;
            ` )
    ( string_push_str o ( string_data ( __lk_q8_dot `q0 + blk * 32` `x0 + blk * 32` ) ) )
    ( string_push_str o `
            acc += d * sub;
        }
    } else {
        for (long long blk = ` )
    ( string_push_str o from ) ( string_push_str o `; blk < nb; blk += ` ) ( string_push_str o step ) ( string_push_str o `) {
            float d = F16(LD16(W, w0 + blk * 2));
            float sub = 0.0f;
            ` )
    ( string_push_str o ( string_data ( __lk_q8_dotb `q0 + blk * 32` `x0 + blk * 32` ) ) )
    ( string_push_str o `
            acc += d * sub;
        }
    }` )
    ^ o
}

@ __lk_mv_q8_0 → String {
    ^ ( __lk_cat3 `if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    float acc = 0.0f;
` ( string_data ( __lk_q8_row `0` `1` ) ) `
    ST(y, yoff + b * rows + r, acc);
}` )
}

@ __lk_mv_q8_0_w → String { ^ ( __lk_warp ( string_data ( __lk_q8_row `lane` `32` ) ) ) }

// The host's (CPU backend) single-position q8_0 matvec. Four blocks at a
// time: their 128 products in one loop the host compiler vectorises (no
// sum in it, so the products are the same floats however many it takes at
// once), then four sums, each in its element order, added to the row's
// total in block order — the bits of one element at a time on a backend
// that does not fuse a multiply into an add (the CPU backend; a GPU fuses
// and takes the warp kernels). A host adds one float a cycle on one port
// and converts bytes on the same one, so the element-at-a-time loop is
// bound by that port, not by its loads.
@ __lk_mv_q8_0_h → String {
    ^ ( string_from `LOCAL_F(pr, 128);
if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    long long nb = cols / 32;
    long long w0 = woff + r * nb * 34;
    long long q0 = w0 + nb * 2;
    float acc = 0.0f;
    long long blk = 0;
    for (; blk + 4 <= nb; blk += 4) {
        WIN(wq, W, q0 + blk * 32, 128);
        WIN(xw, x, x0 + blk * 32, 128);
        if (LEN(wq) == 128 && LEN(xw) == 128) {
            for (int j = 0; j < 128; j++) { ST(pr, j, (float)(signed char)LD(wq, j) * LD(xw, j)); }
        }
        float s0 = 0.0f;
        float s1 = 0.0f;
        float s2 = 0.0f;
        float s3 = 0.0f;
        for (int j = 0; j < 32; j++) {
            s0 += LD(pr, j);
            s1 += LD(pr, 32 + j);
            s2 += LD(pr, 64 + j);
            s3 += LD(pr, 96 + j);
        }
        acc += F16(LD16(W, w0 + blk * 2)) * s0;
        acc += F16(LD16(W, w0 + blk * 2 + 2)) * s1;
        acc += F16(LD16(W, w0 + blk * 2 + 4)) * s2;
        acc += F16(LD16(W, w0 + blk * 2 + 6)) * s3;
    }
    for (; blk < nb; blk++) {
        WIN(we, W, q0 + blk * 32, 32);
        WIN(xe, x, x0 + blk * 32, 32);
        float sv = 0.0f;
        for (int j = 0; j < LEN(we) && j < LEN(xe); j++) { sv += (float)(signed char)LD(we, j) * LD(xe, j); }
        acc += F16(LD16(W, w0 + blk * 2)) * sv;
    }
    ST(y, yoff + b * rows + r, acc);
}` )
}

// The batch-reuse form: a thread per row walks every batch position. The
// host's (the CPU backend): the row's block converted once, then a 2-D
// window — the block's 32 columns down the batch's rows — read position by
// position, each sum in its element order (the bits of the GPU's form). A
// host adds one float a cycle on one port; the compiler vectorises this
// loop ACROSS positions (a sum a lane, every one still in order), which
// needs the 32 products written out: given a loop, it vectorises that loop
// instead (its products, the sum still one at a time).
@ __lk_mv_q8_0_bh → String {
    : ~ String o ( string_from `LOCAL_F(acc, 32);
LOCAL_F(qf, 32);
if (gid < rows) {
    long long r = gid;
    long long nb = cols / 32;
    long long w0 = woff + r * nb * 34;
    long long q0 = w0 + nb * 2;
    for (long long b0 = 0; b0 < batch; b0 += 32) {
        long long bn = batch - b0;
        if (bn > 32) { bn = 32; }
        for (int t = 0; t < 32; t++) { ST(acc, t, 0.0f); }
        for (long long blk = 0; blk < nb; blk++) {
            float d = F16(LD16(W, w0 + blk * 2));
            WIN(wq, W, q0 + blk * 32, 32);
            if (LEN(wq) == 32) {
                for (int j = 0; j < 32; j++) { ST(qf, j, (float)(signed char)LD(wq, j)); }
            }
            WIN2(xb, x, xoff + b0 * cols + blk * 32, bn, cols, 32);
            if (COLS(xb) == 32) {
                for (int t = 0; t < ROWS(xb); t++) {
                    float sub = 0.0f;
` )
    : ~ i c 0
    ~ < c 32 {
        ( string_push_str o `                    sub += LD(qf, ` ) ( string_push_int o c ) ( string_push_str o `) * LD2(xb, t, ` ) ( string_push_int o c ) ( string_push_str o `);
` )
        = c + c 1
    }
    ( string_push_str o `                    ST(acc, t, LD(acc, t) + d * sub);
                }
            }
        }
        for (long long t = 0; t < bn; t++) { ST(y, yoff + (b0 + t) * rows + r, LD(acc, t)); }
    }
}` )
    ^ o
}

// The GPU's: a position at a time, the words and float4s of the warp
// kernels' dot (a GPU overlaps the rows' threads instead).
@ __lk_mv_q8_0_b → String {
    ^ ( string_from `LOCAL_F(acc, 32);
if (gid < rows) {
    long long r = gid;
    long long nb = cols / 32;
    long long w0 = woff + r * nb * 34;
    long long q0 = w0 + nb * 2;
    for (long long b0 = 0; b0 < batch; b0 += 32) {
        long long bn = batch - b0;
        if (bn > 32) { bn = 32; }
        for (long long t = 0; t < bn; t++) { ST(acc, t, 0.0f); }
        if ((nb & 1) == 0) {
            for (long long blk = 0; blk < nb; blk++) {
                float d = F16(LD16(W, w0 + blk * 2));
                for (long long t = 0; t < bn; t++) {
                    float sub = 0.0f;
                    UNROLL for (int k8 = 0; k8 < 8; k8++) {
                unsigned int qq = LD32(W, q0 + blk * 32 + k8 * 4);
                float xa = 0.0f;
                float xc = 0.0f;
                float xe = 0.0f;
                float xg = 0.0f;
                LD4(x, xoff + (b0 + t) * cols + blk * 32 + k8 * 4, xa, xc, xe, xg);
                sub += (float)(signed char)(qq) * xa;
                sub += (float)(signed char)(qq >> 8) * xc;
                sub += (float)(signed char)(qq >> 16) * xe;
                sub += (float)(signed char)(qq >> 24) * xg;
            }
                    ST(acc, t, LD(acc, t) + d * sub);
                }
            }
        } else {
            for (long long blk = 0; blk < nb; blk++) {
                float d = F16(LD16(W, w0 + blk * 2));
                for (long long t = 0; t < bn; t++) {
                    float sub = 0.0f;
                    for (int j = 0; j < 32; j++) { sub += (float)(signed char)LD(W, q0 + blk * 32 + j) * LD(x, xoff + (b0 + t) * cols + blk * 32 + j); }
                    ST(acc, t, LD(acc, t) + d * sub);
                }
            }
        }
        for (long long t = 0; t < bn; t++) { ST(y, yoff + (b0 + t) * rows + r, LD(acc, t)); }
    }
}` )
}

// ── the other quantised formats: dequantise IN the matvec ───────────
//
// The weights stay on the device in their GGUF block form — a Q4_K row is
// 4.5 bits a weight instead of 32 — and each kernel decodes a block into
// registers as it walks the row. Block layouts are ggml's, byte for byte.

// Q4_0: 18-byte blocks of 32 — f16 d, 16 bytes of nibbles.
@ __lk_q4_0_blk → s {
    ^ `            long long bp = w0 + blk * 18;
            float d = F16(LD16(W, bp));
            long long xb = x0 + blk * 32;
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(W, bp + 2 + j);
                acc += d * ((float)((q & 15) - 8)) * LD(x, xb + j);
                acc += d * ((float)((q >> 4) - 8)) * LD(x, xb + j + 16);
            }`
}

@ __lk_mv_q4_0 → String {
    ^ ( __lk_cat3 `if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    long long nb = cols / 32;
    long long w0 = woff + r * nb * 18;
    float acc = 0.0f;
    for (long long blk = 0; blk < nb; blk++) {
` ( __lk_q4_0_blk ) `
    }
    ST(y, yoff + b * rows + r, acc);
}` )
}

@ __lk_mv_q4_0_w → String {
    ^ ( __lk_warp ( string_data ( __lk_cat3 `    long long nb = cols / 32;
    long long w0 = woff + r * nb * 18;
    for (long long blk = lane; blk < nb; blk += 32) {
` ( __lk_q4_0_blk ) `
    }` ) ) )
}

// Q4_K / Q5_K: a sub-block's 6-bit scale and min, packed into 12 bytes.
@ __lk_k_scales s s → String {
    : ~ String o ( string_from `int sV = 0;
                int mV = 0;
                if (` )
    ( string_push_str o s ) ( string_push_str o ` < 4) { sV = (int)LD(W, sc + ` ) ( string_push_str o s ) ( string_push_str o `) & 63; mV = (int)LD(W, sc + ` ) ( string_push_str o s ) ( string_push_str o ` + 4) & 63; }
                else {
                    sV = ((int)LD(W, sc + ` ) ( string_push_str o s ) ( string_push_str o ` + 4) & 15) | (((int)LD(W, sc + ` ) ( string_push_str o s ) ( string_push_str o ` - 4) >> 6) << 4);
                    mV = ((int)LD(W, sc + ` ) ( string_push_str o s ) ( string_push_str o ` + 4) >> 4) | (((int)LD(W, sc + ` ) ( string_push_str o s ) ( string_push_str o `) >> 6) << 4);
                }` )
    ^ o
}

// The same, read through `kb`, a window over the whole super-block.
@ __lk_k_scales_w s s → String {
    : ~ String o ( string_from `int sV = 0;
                int mV = 0;
                if (` )
    ( string_push_str o s ) ( string_push_str o ` < 4) { sV = (int)LD(kb, 4 + ` ) ( string_push_str o s ) ( string_push_str o `) & 63; mV = (int)LD(kb, 8 + ` ) ( string_push_str o s ) ( string_push_str o `) & 63; }
                else {
                    sV = ((int)LD(kb, 8 + ` ) ( string_push_str o s ) ( string_push_str o `) & 15) | (((int)LD(kb, ` ) ( string_push_str o s ) ( string_push_str o `) >> 6) << 4);
                    mV = ((int)LD(kb, 8 + ` ) ( string_push_str o s ) ( string_push_str o `) >> 4) | (((int)LD(kb, 4 + ` ) ( string_push_str o s ) ( string_push_str o `) >> 6) << 4);
                }` )
    ^ o
}

// Q4_K: 144-byte super-block of 256 — d, dmin (f16), 12 packed 6-bit
// scale/min pairs, 128 nibble bytes. Sub-block s takes its 32 values from
// the low (even s) or high (odd s) nibbles of bytes [s/2*32 …]. Q5_K
// (176 bytes) adds 32 bytes carrying each value's 5th bit.
@ __lk_mv_qk_scalar b five → String {
    : ~ String o ( string_from `if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    long long nb = cols / 256;
    long long w0 = woff + r * nb * ` )
    ( string_push_str o ? five `176` `144` )
    ( string_push_str o `;
    float acc = 0.0f;
    for (long long blk = 0; blk < nb; blk++) {
        long long bp = w0 + blk * ` )
    ( string_push_str o ? five `176` `144` )
    ( string_push_str o `;
        float d = F16(LD16(W, bp));
        float dmin = F16(LD16(W, bp + 2));
        long long sc = bp + 4;
        long long qh = bp + 16;
        long long qs = bp + ` )
    ( string_push_str o ? five `48` `16` )
    ( string_push_str o `;
        long long xb = x0 + blk * 256;
        for (int s = 0; s < 8; s++) {
            ` )
    ( string_push_str o ( string_data ( __lk_k_scales `s` ) ) )
    ( string_push_str o `
            float d1 = d * sV;
            float m1 = dmin * mV;
            long long qb = qs + (s / 2) * 32;
            long long xs = xb + s * 32;
            int hi = s & 1;
            float sub = 0.0f;
            float msum = 0.0f;
            for (int l = 0; l < 32; l++) {
                int qv = (int)LD(W, qb + l);
                int q = hi ? (qv >> 4) : (qv & 15);
` )
    ? five {
        ( string_push_str o `                int hbit = ((int)LD(W, qh + l) >> s) & 1;
                sub += (float)(q + (hbit << 4)) * LD(x, xs + l);
` )
    } {
        ( string_push_str o `                sub += (float)q * LD(x, xs + l);
` )
    }
    ( string_push_str o `                msum += LD(x, xs + l);
            }
            acc += d1 * sub - m1 * msum;
        }
    }
    ST(y, yoff + b * rows + r, acc);
}` )
    ^ o
}

// The warp walks the row's blocks TOGETHER and the 32 lanes split each
// block's quants: lane l takes byte l of each 32-byte nibble group, so one
// warp load is 32 contiguous bytes and the matching x load 32 contiguous
// floats. Giving each lane its own block — the obvious partition — makes
// every warp load touch 32 separate cache lines.
// The warp form: the warp walks the row's blocks together and lane l takes
// byte l of every 32-byte group (one warp load = 32 contiguous bytes, the
// matching x load 32 contiguous floats). A block is a window — its
// offsets are constants and the lane, so whole-length windows leave no
// check in the block.
@ __lk_mv_qk_warp b five → String {
    : s bs ? five `176` `144`
    : ~ String o ( string_from `    long long nb = cols / 256;
    long long w0 = woff + r * nb * ` )
    ( string_push_str o bs )
    ( string_push_str o `;
    for (long long blk = 0; blk < nb; blk++) {
        long long bp = w0 + blk * ` )
    ( string_push_str o bs )
    ( string_push_str o `;
        float d = F16(LD16(W, bp));
        float dmin = F16(LD16(W, bp + 2));
        WIN(kb, W, bp, ` )
    ( string_push_str o bs )
    ( string_push_str o `);
        WIN(xw, x, x0 + blk * 256, 256);
        if (LEN(kb) == ` )
    ( string_push_str o bs )
    ( string_push_str o ` && LEN(xw) == 256) {
` )
    ? five { ( string_push_str o `        int hbits = (int)LD(kb, 16 + lane);
` ) } {}
    // the eight sub-blocks written out: every offset a constant plus the
    // lane (an offset of two loop counters keeps its check)
    : ~ i j 0
    ~ < j 4 {
        ( string_push_str o `        int q` ) ( string_push_int o j ) ( string_push_str o ` = (int)LD(kb, ` )
        ( string_push_int o + ? five 48 16 * j 32 ) ( string_push_str o ` + lane);
` )
        = j + j 1
    }
    : ~ i sb 0
    ~ < sb 8 {
        : ~ String sn ( string_new )
        ( string_push_int sn sb )
        ( string_push_str o `        {
                ` )
        ( string_push_str o ( string_data ( __lk_k_scales_w ( string_data sn ) ) ) )
        ( string_push_str o `
                float xv = LD(xw, ` ) ( string_push_int o * sb 32 ) ( string_push_str o ` + lane);
                int qq = ` )
        ( string_push_str o `q` ) ( string_push_int o / sb 2 ) ( string_push_str o ? == 1 % sb 2 ` >> 4` ` & 15` )
        ? five { ( string_push_str o ` | (((hbits >> ` ) ( string_push_int o sb ) ( string_push_str o `) & 1) << 4)` ) } {}
        ( string_push_str o `;
                acc += (d * sV) * ((float)qq * xv) - (dmin * mV) * xv;
        }
` )
        = sb + sb 1
    }
    ( string_push_str o `        }
    }` )
    ^ ( __lk_warp ( string_data o ) )
}

// Q6_K: 210-byte super-block of 256 — 128 low-nibble bytes, 64 bytes of
// upper 2 bits, 16 int8 scales, f16 d. Sixteen 16-element groups.
@ __lk_q6_k_blk → s {
    ^ `            long long bp = w0 + blk * 210;
            long long ql = bp;
            long long qh = bp + 128;
            long long sc = bp + 192;
            float d = F16(LD16(W, bp + 208));
            long long xb = x0 + blk * 256;
            for (int n = 0; n < 2; n++) {
                long long ql0 = ql + n * 64;
                long long qh0 = qh + n * 32;
                long long sc0 = sc + n * 8;
                long long xn = xb + n * 128;
                for (int l = 0; l < 32; l++) {
                    int is = l / 16;
                    int h = (int)LD(W, qh0 + l);
                    int b1 = (int)LD(W, ql0 + l);
                    int b2 = (int)LD(W, ql0 + l + 32);
                    int q1 = ((b1 & 15) | ((h & 3) << 4)) - 32;
                    int q2 = ((b2 & 15) | (((h >> 2) & 3) << 4)) - 32;
                    int q3 = ((b1 >> 4) | (((h >> 4) & 3) << 4)) - 32;
                    int q4 = ((b2 >> 4) | (((h >> 6) & 3) << 4)) - 32;
                    acc += d * (float)(signed char)LD(W, sc0 + is) * (float)q1 * LD(x, xn + l);
                    acc += d * (float)(signed char)LD(W, sc0 + is + 2) * (float)q2 * LD(x, xn + l + 32);
                    acc += d * (float)(signed char)LD(W, sc0 + is + 4) * (float)q3 * LD(x, xn + l + 64);
                    acc += d * (float)(signed char)LD(W, sc0 + is + 6) * (float)q4 * LD(x, xn + l + 96);
                }
            }`
}

@ __lk_mv_q6_k → String {
    ^ ( __lk_cat3 `if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    long long nb = cols / 256;
    long long w0 = woff + r * nb * 210;
    float acc = 0.0f;
    for (long long blk = 0; blk < nb; blk++) {
` ( __lk_q6_k_blk ) `
    }
    ST(y, yoff + b * rows + r, acc);
}` )
}

// The warp form: a lane per block, the block and its 256 x values as
// windows — every offset a constant plus the loop's counter, which bounds
// it, so no check is left in the block. (The block's quarters are written
// out: an offset of two counters, or of a counter's l / 16, keeps its
// check.)
@ __lk_mv_q6_k_w → String {
    ^ ( __lk_warp `    long long nb = cols / 256;
    long long w0 = woff + r * nb * 210;
    for (long long blk = lane; blk < nb; blk += 32) {
        long long bp = w0 + blk * 210;
        float d = F16(LD16(W, bp + 208));
        WIN(kb, W, bp, 210);
        WIN(xw, x, x0 + blk * 256, 256);
        if (LEN(kb) == 210 && LEN(xw) == 256) {
            for (int l = 0; l < 16; l++) {
                int h = (int)LD(kb, 128 + l);
                int b1 = (int)LD(kb, 0 + l);
                int b2 = (int)LD(kb, 32 + l);
                int q1 = ((b1 & 15) | ((h & 3) << 4)) - 32;
                int q2 = ((b2 & 15) | (((h >> 2) & 3) << 4)) - 32;
                int q3 = ((b1 >> 4) | (((h >> 4) & 3) << 4)) - 32;
                int q4 = ((b2 >> 4) | (((h >> 6) & 3) << 4)) - 32;
                acc += d * (float)(signed char)LD(kb, 192) * (float)q1 * LD(xw, 0 + l);
                acc += d * (float)(signed char)LD(kb, 194) * (float)q2 * LD(xw, 32 + l);
                acc += d * (float)(signed char)LD(kb, 196) * (float)q3 * LD(xw, 64 + l);
                acc += d * (float)(signed char)LD(kb, 198) * (float)q4 * LD(xw, 96 + l);
            }
            for (int l = 16; l < 32; l++) {
                int h = (int)LD(kb, 128 + l);
                int b1 = (int)LD(kb, 0 + l);
                int b2 = (int)LD(kb, 32 + l);
                int q1 = ((b1 & 15) | ((h & 3) << 4)) - 32;
                int q2 = ((b2 & 15) | (((h >> 2) & 3) << 4)) - 32;
                int q3 = ((b1 >> 4) | (((h >> 4) & 3) << 4)) - 32;
                int q4 = ((b2 >> 4) | (((h >> 6) & 3) << 4)) - 32;
                acc += d * (float)(signed char)LD(kb, 193) * (float)q1 * LD(xw, 0 + l);
                acc += d * (float)(signed char)LD(kb, 195) * (float)q2 * LD(xw, 32 + l);
                acc += d * (float)(signed char)LD(kb, 197) * (float)q3 * LD(xw, 64 + l);
                acc += d * (float)(signed char)LD(kb, 199) * (float)q4 * LD(xw, 96 + l);
            }
            for (int l = 0; l < 16; l++) {
                int h = (int)LD(kb, 160 + l);
                int b1 = (int)LD(kb, 64 + l);
                int b2 = (int)LD(kb, 96 + l);
                int q1 = ((b1 & 15) | ((h & 3) << 4)) - 32;
                int q2 = ((b2 & 15) | (((h >> 2) & 3) << 4)) - 32;
                int q3 = ((b1 >> 4) | (((h >> 4) & 3) << 4)) - 32;
                int q4 = ((b2 >> 4) | (((h >> 6) & 3) << 4)) - 32;
                acc += d * (float)(signed char)LD(kb, 200) * (float)q1 * LD(xw, 128 + l);
                acc += d * (float)(signed char)LD(kb, 202) * (float)q2 * LD(xw, 160 + l);
                acc += d * (float)(signed char)LD(kb, 204) * (float)q3 * LD(xw, 192 + l);
                acc += d * (float)(signed char)LD(kb, 206) * (float)q4 * LD(xw, 224 + l);
            }
            for (int l = 16; l < 32; l++) {
                int h = (int)LD(kb, 160 + l);
                int b1 = (int)LD(kb, 64 + l);
                int b2 = (int)LD(kb, 96 + l);
                int q1 = ((b1 & 15) | ((h & 3) << 4)) - 32;
                int q2 = ((b2 & 15) | (((h >> 2) & 3) << 4)) - 32;
                int q3 = ((b1 >> 4) | (((h >> 4) & 3) << 4)) - 32;
                int q4 = ((b2 >> 4) | (((h >> 6) & 3) << 4)) - 32;
                acc += d * (float)(signed char)LD(kb, 201) * (float)q1 * LD(xw, 128 + l);
                acc += d * (float)(signed char)LD(kb, 203) * (float)q2 * LD(xw, 160 + l);
                acc += d * (float)(signed char)LD(kb, 205) * (float)q3 * LD(xw, 192 + l);
                acc += d * (float)(signed char)LD(kb, 207) * (float)q4 * LD(xw, 224 + l);
            }
        }
    }` )
}

// Q5_0 (22-byte blocks: f16 d, 32 fifth bits, 16 nibble bytes) and Q5_1
// (24 bytes: d and a min m). The fifth bits are a 32-bit word at an even,
// not always 4-aligned, offset: two 16-bit loads.
@ __lk_mv_q5 b one → String {
    : ~ String o ( string_from `if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    long long nb = cols / 32;
    long long w0 = woff + r * nb * ` )
    ( string_push_str o ? one `24` `22` )
    ( string_push_str o `;
    float acc = 0.0f;
    for (long long blk = 0; blk < nb; blk++) {
        long long bp = w0 + blk * ` )
    ( string_push_str o ? one `24` `22` )
    ( string_push_str o `;
        float d = F16(LD16(W, bp));
` )
    ? one {
        ( string_push_str o `        float m = F16(LD16(W, bp + 2));
        unsigned int qh = LD16(W, bp + 4) | (LD16(W, bp + 6) << 16);
        long long qs = bp + 8;
` )
    } {
        ( string_push_str o `        unsigned int qh = LD16(W, bp + 2) | (LD16(W, bp + 4) << 16);
        long long qs = bp + 6;
` )
    }
    ( string_push_str o `        long long xb = x0 + blk * 32;
        float sub = 0.0f;
` )
    ? one { ( string_push_str o `        float msum = 0.0f;
` ) } {}
    ( string_push_str o `        for (int j = 0; j < 16; j++) {
            int h0 = ((qh >> j) & 1u) << 4;
            int h1 = ((qh >> (j + 16)) & 1u) << 4;
            int qv = (int)LD(W, qs + j);
` )
    ? one {
        ( string_push_str o `            sub += (float)((qv & 15) | h0) * LD(x, xb + j);
            sub += (float)((qv >> 4) | h1) * LD(x, xb + j + 16);
            msum += LD(x, xb + j) + LD(x, xb + j + 16);
        }
        acc += d * sub + m * msum;
` )
    } {
        ( string_push_str o `            sub += (float)(((qv & 15) | h0) - 16) * LD(x, xb + j);
            sub += (float)(((qv >> 4) | h1) - 16) * LD(x, xb + j + 16);
        }
        acc += d * sub;
` )
    }
    ( string_push_str o `    }
    ST(y, yoff + b * rows + r, acc);
}` )
    ^ o
}

// Warp: 32 lanes, 16 bytes of quants per block — lanes 0..15 take one
// block's bytes, lanes 16..31 the next block's: two blocks per step.
@ __lk_mv_q5_w b one → String {
    : ~ String o ( string_from `    long long nb = cols / 32;
    long long w0 = woff + r * nb * ` )
    ( string_push_str o ? one `24` `22` )
    ( string_push_str o `;
    for (long long blk = lane >> 4; blk < nb; blk += 2) {
        long long bp = w0 + blk * ` )
    ( string_push_str o ? one `24` `22` )
    ( string_push_str o `;
        int j = (int)(lane & 15);
        float d = F16(LD16(W, bp));
` )
    ? one {
        ( string_push_str o `        float m = F16(LD16(W, bp + 2));
        unsigned int qh = LD16(W, bp + 4) | (LD16(W, bp + 6) << 16);
        int q = (int)LD(W, bp + 8 + j);
` )
    } {
        ( string_push_str o `        unsigned int qh = LD16(W, bp + 2) | (LD16(W, bp + 4) << 16);
        int q = (int)LD(W, bp + 6 + j);
` )
    }
    ( string_push_str o `        long long xs = x0 + blk * 32;
        int h0 = ((qh >> j) & 1u) << 4;
        int h1 = ((qh >> (j + 16)) & 1u) << 4;
` )
    ? one {
        ( string_push_str o `        acc += (d * (float)((q & 15) | h0) + m) * LD(x, xs + j);
        acc += (d * (float)((q >> 4) | h1) + m) * LD(x, xs + j + 16);
    }` )
    } {
        ( string_push_str o `        acc += d * (float)(((q & 15) | h0) - 16) * LD(x, xs + j);
        acc += d * (float)(((q >> 4) | h1) - 16) * LD(x, xs + j + 16);
    }` )
    }
    ^ ( __lk_warp ( string_data o ) )
}

// The matvec dispatch: `w.gt` is the ggml type of W. F when the type has
// no device kernel (the caller then falls back — correctness first).
// `warp` = the CUDA warp shapes; without it, the portable kernels.
@ lk_matvec GpuKit kit b warp LkW w i woff GkBuf x i xoff GkBuf y i yoff i rows i cols i batch inout ( Vec GkLaunch ) plan → b {
    : i gt . w gt
    : ~ i which -1
    ? == gt 0 { = which 0 } {}
    ? == gt 1 { = which 5 } {}
    ? == gt 2 { = which 1 } {}
    ? == gt 8 { = which 2 } {}
    ? == gt 12 { = which 3 } {}
    ? == gt 14 { = which 4 } {}
    ? == gt 6 { = which 6 } {}
    ? == gt 7 { = which 7 } {}
    ? == gt 13 { = which 8 } {}
    ? < which 0 { ^ F } {}
    : ~ GkCall c ( gk_call_new )
    ? == which 0 { ( gk_call_dev_in c `W` . w f ) } ? == which 5 { ( gk_call_half_in c `W` . w h ) } { ( gk_call_bytes_in c `W` . w q ) }
    ( gk_call_dev_in c `x` x ) ( gk_call_dev c `y` y )
    ( gk_call_i64 c `rows` rows ) ( gk_call_i64 c `cols` cols ) ( gk_call_i64 c `batch` batch )
    ( gk_call_i64 c `woff` woff ) ( gk_call_i64 c `xoff` xoff ) ( gk_call_i64 c `yoff` yoff )
    // Batch >= 4 routing for f32 / Q8_0, from measurement at the llada2
    // shapes (RTX 4090):
    //   157184×2048: batch-reuse 4.4 ms vs warp-per-row 32 ms — a huge
    //     weight matrix busts L2, so re-reading it per position is the
    //     whole cost, and `rows` threads is already full occupancy.
    //   2048×2048 / 512×2048: warp-per-row wins — the weights FIT in L2.
    //   2048×512: cols/32 = 16 blocks < 32 lanes starves the warp
    //     kernels (110 us) — the plain scalar kernel wins (45 us).
    // The CPU backend always takes the batch-reuse kernel: the row stays
    // in cache across the batch.
    ? & >= batch 4 | == which 0 == which 2 {
        : b use_b | ! warp >= rows 16384
        : b use_sp & warp < cols 1024
        ? use_b {
            ? == which 0 {
                ? warp { ^ ( __lk_rec kit c `nl_mv_f32_b` ( __lk_mv_f32_b ) ( gk_grid rows 64 ) 64 plan ) } {}
                ^ ( __lk_rec kit c `nl_mv_f32_bh` ( __lk_mv_f32_bh ) ( gk_grid rows 64 ) 64 plan )
            } {}
            ? warp { ^ ( __lk_rec kit c `nl_mv_q8_0_b` ( string_data ( __lk_mv_q8_0_b ) ) ( gk_grid rows 64 ) 64 plan ) } {}
            ^ ( __lk_rec kit c `nl_mv_q8_0_bh` ( string_data ( __lk_mv_q8_0_bh ) ) ( gk_grid rows 64 ) 64 plan )
        } {}
        ? use_sp {
            ? == which 0 { ^ ( __lk_rec kit c `nl_mv` ( __lk_mv_body ) ( gk_grid * rows batch 64 ) 64 plan ) } {}
            ^ ( __lk_rec kit c `nl_mv_q8_0` ( string_data ( __lk_mv_q8_0 ) ) ( gk_grid * rows batch 64 ) 64 plan )
        } {}
    } {}
    // warp-per-row variants (CUDA): every type but f16
    ? & warp != which 5 {
        // 128 threads = 4 warps per block, one row each
        : i wg ( gk_grid * * rows batch 32 128 )
        ? == which 0 { ^ ( __lk_rec kit c `nl_mv_f32_w` ( string_data ( __lk_mv_f32_w ) ) wg 128 plan ) } {}
        ? == which 1 { ^ ( __lk_rec kit c `nl_mv_q4_0_w` ( string_data ( __lk_mv_q4_0_w ) ) wg 128 plan ) } {}
        ? == which 2 { ^ ( __lk_rec kit c `nl_mv_q8_0_w` ( string_data ( __lk_mv_q8_0_w ) ) wg 128 plan ) } {}
        ? == which 3 { ^ ( __lk_rec kit c `nl_mv_q4_k_w` ( string_data ( __lk_mv_qk_warp F ) ) wg 128 plan ) } {}
        ? == which 4 { ^ ( __lk_rec kit c `nl_mv_q6_k_w` ( string_data ( __lk_mv_q6_k_w ) ) wg 128 plan ) } {}
        ? == which 6 { ^ ( __lk_rec kit c `nl_mv_q5_0_w` ( string_data ( __lk_mv_q5_w F ) ) wg 128 plan ) } {}
        ? == which 7 { ^ ( __lk_rec kit c `nl_mv_q5_1_w` ( string_data ( __lk_mv_q5_w T ) ) wg 128 plan ) } {}
        ^ ( __lk_rec kit c `nl_mv_q5_k_w` ( string_data ( __lk_mv_qk_warp T ) ) wg 128 plan )
    } {}
    ? == which 0 { ^ ( __lk_rec kit c `nl_mv_h` ( __lk_mv_h ) ( gk_grid * rows batch 64 ) 64 plan ) } {}
    : i grid ( gk_grid * rows batch 64 )
    ? == which 1 { ^ ( __lk_rec kit c `nl_mv_q4_0_h` ( __lk_mv_q4_0_h ) grid 64 plan ) } {}
    // (here only the CPU backend — a GPU took a warp kernel above — but f16)
    ? == which 5 {
        ? warp { ^ ( __lk_rec kit c `nl_mv_f16` ( __lk_mv_f16_body ) grid 64 plan ) } {}
        ^ ( __lk_rec kit c `nl_mv_f16_h` ( __lk_mv_f16_h ) grid 64 plan )
    } {}
    ? == which 2 { ^ ( __lk_rec kit c `nl_mv_q8_0_h` ( string_data ( __lk_mv_q8_0_h ) ) grid 64 plan ) } {}
    ? == which 3 { ^ ( __lk_rec kit c `nl_mv_q4_k_h` ( __lk_mv_q4_k_h ) grid 64 plan ) } {}
    ? == which 4 { ^ ( __lk_rec kit c `nl_mv_q6_k_h` ( __lk_mv_q6_k_h ) grid 64 plan ) } {}
    ? == which 6 { ^ ( __lk_rec kit c `nl_mv_q5_0_h` ( __lk_mv_q5_0_h ) grid 64 plan ) } {}
    ? == which 7 { ^ ( __lk_rec kit c `nl_mv_q5_1_h` ( __lk_mv_q5_1_h ) grid 64 plan ) } {}
    ^ ( __lk_rec kit c `nl_mv_q5_k_h` ( __lk_mv_q5_k_h ) grid 64 plan )
}

// ── the CPU backend's matvecs ───────────────────────────────────────
//
// The host runs a kernel's threads one after another, adds one float a
// cycle on one port and converts integers on the same one, so the forms a
// GPU wants leave it waiting on its adder. These keep every sum in the
// order the GPU forms add in (the same bits), but compute the products —
// dequantised value times x — in loops the host compiler vectorises (no
// sum in them), through windows checked once a block, and run the sums of
// independent blocks side by side where the format sums a block on its
// own (q5_0 / q5_1 / the K-quants).

// f32 weights.
@ __lk_mv_h → s {
    ^ `LOCAL_F(pr, 64);
if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long w0 = woff + r * cols;
    long long x0 = xoff + b * cols;
    float acc = 0.0f;
    long long c = 0;
    for (; c + 64 <= cols; c += 64) {
        WIN(wc, W, w0 + c, 64);
        WIN(xc, x, x0 + c, 64);
        if (LEN(wc) == 64 && LEN(xc) == 64) {
            for (int j = 0; j < 64; j++) { ST(pr, j, LD(wc, j) * LD(xc, j)); }
        }
        for (int j = 0; j < 64; j++) { acc += LD(pr, j); }
    }
    for (; c < cols; c++) { acc += LD(W, w0 + c) * LD(x, x0 + c); }
    ST(y, yoff + b * rows + r, acc);
}`
}

// f16 weights: the host converts a half with branches (no vector form), so
// splitting the products from the sum only adds work — one loop, its
// checks folded by the windows.
@ __lk_mv_f16_h → s {
    ^ `if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long w0 = woff + r * cols;
    long long x0 = xoff + b * cols;
    WIN(wr, W, w0, cols);
    WIN(xr, x, x0, cols);
    float acc = 0.0f;
    for (int c = 0; c < LEN(wr) && c < LEN(xr); c++) { acc += LD(wr, c) * LD(xr, c); }
    ST(y, yoff + b * rows + r, acc);
}`
}

@ __lk_mv_q4_0_h → s {
    ^ `LOCAL_F(pr, 32);
if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    long long nb = cols / 32;
    long long w0 = woff + r * nb * 18;
    float acc = 0.0f;
    for (long long blk = 0; blk < nb; blk++) {
        long long bp = w0 + blk * 18;
        float d = F16(LD16(W, bp));
        WIN(qw, W, bp + 2, 16);
        WIN(xw, x, x0 + blk * 32, 32);
        if (LEN(qw) == 16 && LEN(xw) == 32) {
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(qw, j);
                ST(pr, 2 * j, d * (float)((q & 15) - 8) * LD(xw, j));
                ST(pr, 2 * j + 1, d * (float)((q >> 4) - 8) * LD(xw, j + 16));
            }
        }
        for (int k = 0; k < 32; k++) { acc += LD(pr, k); }
    }
    ST(y, yoff + b * rows + r, acc);
}`
}

@ __lk_mv_q5_0_h → s {
    ^ `LOCAL_F(pr, 128);
if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    long long nb = cols / 32;
    long long w0 = woff + r * nb * 22;
    float acc = 0.0f;
    long long blk = 0;
    for (; blk + 4 <= nb; blk += 4) {
        long long bp0 = w0 + (blk + 0) * 22;
        float d0 = F16(LD16(W, bp0));
        unsigned int qh0 = LD16(W, bp0 + 2) | (LD16(W, bp0 + 4) << 16);
        WIN(qw0, W, bp0 + 6, 16);
        WIN(xw0, x, x0 + (blk + 0) * 32, 32);
        long long bp1 = w0 + (blk + 1) * 22;
        float d1 = F16(LD16(W, bp1));
        unsigned int qh1 = LD16(W, bp1 + 2) | (LD16(W, bp1 + 4) << 16);
        WIN(qw1, W, bp1 + 6, 16);
        WIN(xw1, x, x0 + (blk + 1) * 32, 32);
        long long bp2 = w0 + (blk + 2) * 22;
        float d2 = F16(LD16(W, bp2));
        unsigned int qh2 = LD16(W, bp2 + 2) | (LD16(W, bp2 + 4) << 16);
        WIN(qw2, W, bp2 + 6, 16);
        WIN(xw2, x, x0 + (blk + 2) * 32, 32);
        long long bp3 = w0 + (blk + 3) * 22;
        float d3 = F16(LD16(W, bp3));
        unsigned int qh3 = LD16(W, bp3 + 2) | (LD16(W, bp3 + 4) << 16);
        WIN(qw3, W, bp3 + 6, 16);
        WIN(xw3, x, x0 + (blk + 3) * 32, 32);
        if (LEN(qw0) == 16 && LEN(xw0) == 32 && LEN(qw1) == 16 && LEN(xw1) == 32 && LEN(qw2) == 16 && LEN(xw2) == 32 && LEN(qw3) == 16 && LEN(xw3) == 32) {
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(qw0, j);
                int h0 = (int)((qh0 >> j) & 1u) << 4;
                int h1 = (int)((qh0 >> (j + 16)) & 1u) << 4;
                ST(pr, 0 + 2 * j, (float)(((q & 15) | h0) - 16) * LD(xw0, j));
                ST(pr, 0 + 2 * j + 1, (float)(((q >> 4) | h1) - 16) * LD(xw0, j + 16));
            }
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(qw1, j);
                int h0 = (int)((qh1 >> j) & 1u) << 4;
                int h1 = (int)((qh1 >> (j + 16)) & 1u) << 4;
                ST(pr, 32 + 2 * j, (float)(((q & 15) | h0) - 16) * LD(xw1, j));
                ST(pr, 32 + 2 * j + 1, (float)(((q >> 4) | h1) - 16) * LD(xw1, j + 16));
            }
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(qw2, j);
                int h0 = (int)((qh2 >> j) & 1u) << 4;
                int h1 = (int)((qh2 >> (j + 16)) & 1u) << 4;
                ST(pr, 64 + 2 * j, (float)(((q & 15) | h0) - 16) * LD(xw2, j));
                ST(pr, 64 + 2 * j + 1, (float)(((q >> 4) | h1) - 16) * LD(xw2, j + 16));
            }
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(qw3, j);
                int h0 = (int)((qh3 >> j) & 1u) << 4;
                int h1 = (int)((qh3 >> (j + 16)) & 1u) << 4;
                ST(pr, 96 + 2 * j, (float)(((q & 15) | h0) - 16) * LD(xw3, j));
                ST(pr, 96 + 2 * j + 1, (float)(((q >> 4) | h1) - 16) * LD(xw3, j + 16));
            }
        }
        float s0 = 0.0f;
        float s1 = 0.0f;
        float s2 = 0.0f;
        float s3 = 0.0f;
        for (int k = 0; k < 32; k++) {
            s0 += LD(pr, 0 + k);
            s1 += LD(pr, 32 + k);
            s2 += LD(pr, 64 + k);
            s3 += LD(pr, 96 + k);
        }
        acc += d0 * s0;
        acc += d1 * s1;
        acc += d2 * s2;
        acc += d3 * s3;
    }
    for (; blk < nb; blk++) {
        long long bp0 = w0 + (blk + 0) * 22;
        float d0 = F16(LD16(W, bp0));
        unsigned int qh0 = LD16(W, bp0 + 2) | (LD16(W, bp0 + 4) << 16);
        WIN(qt0, W, bp0 + 6, 16);
        WIN(xt0, x, x0 + (blk + 0) * 32, 32);
        if (LEN(qt0) == 16 && LEN(xt0) == 32) {
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(qt0, j);
                int h0 = (int)((qh0 >> j) & 1u) << 4;
                int h1 = (int)((qh0 >> (j + 16)) & 1u) << 4;
                ST(pr, 0 + 2 * j, (float)(((q & 15) | h0) - 16) * LD(xt0, j));
                ST(pr, 0 + 2 * j + 1, (float)(((q >> 4) | h1) - 16) * LD(xt0, j + 16));
            }
        }
        float s0 = 0.0f;
        for (int k = 0; k < 32; k++) {
            s0 += LD(pr, 0 + k);
        }
        acc += d0 * s0;
    }
    ST(y, yoff + b * rows + r, acc);
}`
}

@ __lk_mv_q5_1_h → s {
    ^ `LOCAL_F(pr, 128);
LOCAL_F(px, 64);
if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    long long nb = cols / 32;
    long long w0 = woff + r * nb * 24;
    float acc = 0.0f;
    long long blk = 0;
    for (; blk + 4 <= nb; blk += 4) {
        long long bp0 = w0 + (blk + 0) * 24;
        float d0 = F16(LD16(W, bp0));
        float m0 = F16(LD16(W, bp0 + 2));
        unsigned int qh0 = LD16(W, bp0 + 4) | (LD16(W, bp0 + 6) << 16);
        WIN(qw0, W, bp0 + 8, 16);
        WIN(xw0, x, x0 + (blk + 0) * 32, 32);
        long long bp1 = w0 + (blk + 1) * 24;
        float d1 = F16(LD16(W, bp1));
        float m1 = F16(LD16(W, bp1 + 2));
        unsigned int qh1 = LD16(W, bp1 + 4) | (LD16(W, bp1 + 6) << 16);
        WIN(qw1, W, bp1 + 8, 16);
        WIN(xw1, x, x0 + (blk + 1) * 32, 32);
        long long bp2 = w0 + (blk + 2) * 24;
        float d2 = F16(LD16(W, bp2));
        float m2 = F16(LD16(W, bp2 + 2));
        unsigned int qh2 = LD16(W, bp2 + 4) | (LD16(W, bp2 + 6) << 16);
        WIN(qw2, W, bp2 + 8, 16);
        WIN(xw2, x, x0 + (blk + 2) * 32, 32);
        long long bp3 = w0 + (blk + 3) * 24;
        float d3 = F16(LD16(W, bp3));
        float m3 = F16(LD16(W, bp3 + 2));
        unsigned int qh3 = LD16(W, bp3 + 4) | (LD16(W, bp3 + 6) << 16);
        WIN(qw3, W, bp3 + 8, 16);
        WIN(xw3, x, x0 + (blk + 3) * 32, 32);
        if (LEN(qw0) == 16 && LEN(xw0) == 32 && LEN(qw1) == 16 && LEN(xw1) == 32 && LEN(qw2) == 16 && LEN(xw2) == 32 && LEN(qw3) == 16 && LEN(xw3) == 32) {
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(qw0, j);
                int h0 = (int)((qh0 >> j) & 1u) << 4;
                int h1 = (int)((qh0 >> (j + 16)) & 1u) << 4;
                ST(pr, 0 + 2 * j, (float)((q & 15) | h0) * LD(xw0, j));
                ST(pr, 0 + 2 * j + 1, (float)((q >> 4) | h1) * LD(xw0, j + 16));
                ST(px, 0 + j, LD(xw0, j) + LD(xw0, j + 16));
            }
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(qw1, j);
                int h0 = (int)((qh1 >> j) & 1u) << 4;
                int h1 = (int)((qh1 >> (j + 16)) & 1u) << 4;
                ST(pr, 32 + 2 * j, (float)((q & 15) | h0) * LD(xw1, j));
                ST(pr, 32 + 2 * j + 1, (float)((q >> 4) | h1) * LD(xw1, j + 16));
                ST(px, 16 + j, LD(xw1, j) + LD(xw1, j + 16));
            }
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(qw2, j);
                int h0 = (int)((qh2 >> j) & 1u) << 4;
                int h1 = (int)((qh2 >> (j + 16)) & 1u) << 4;
                ST(pr, 64 + 2 * j, (float)((q & 15) | h0) * LD(xw2, j));
                ST(pr, 64 + 2 * j + 1, (float)((q >> 4) | h1) * LD(xw2, j + 16));
                ST(px, 32 + j, LD(xw2, j) + LD(xw2, j + 16));
            }
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(qw3, j);
                int h0 = (int)((qh3 >> j) & 1u) << 4;
                int h1 = (int)((qh3 >> (j + 16)) & 1u) << 4;
                ST(pr, 96 + 2 * j, (float)((q & 15) | h0) * LD(xw3, j));
                ST(pr, 96 + 2 * j + 1, (float)((q >> 4) | h1) * LD(xw3, j + 16));
                ST(px, 48 + j, LD(xw3, j) + LD(xw3, j + 16));
            }
        }
        float s0 = 0.0f;
        float ms0 = 0.0f;
        float s1 = 0.0f;
        float ms1 = 0.0f;
        float s2 = 0.0f;
        float ms2 = 0.0f;
        float s3 = 0.0f;
        float ms3 = 0.0f;
        for (int k = 0; k < 32; k++) {
            s0 += LD(pr, 0 + k);
            s1 += LD(pr, 32 + k);
            s2 += LD(pr, 64 + k);
            s3 += LD(pr, 96 + k);
        }
        for (int j = 0; j < 16; j++) {
            ms0 += LD(px, 0 + j);
            ms1 += LD(px, 16 + j);
            ms2 += LD(px, 32 + j);
            ms3 += LD(px, 48 + j);
        }
        acc += d0 * s0 + m0 * ms0;
        acc += d1 * s1 + m1 * ms1;
        acc += d2 * s2 + m2 * ms2;
        acc += d3 * s3 + m3 * ms3;
    }
    for (; blk < nb; blk++) {
        long long bp0 = w0 + (blk + 0) * 24;
        float d0 = F16(LD16(W, bp0));
        float m0 = F16(LD16(W, bp0 + 2));
        unsigned int qh0 = LD16(W, bp0 + 4) | (LD16(W, bp0 + 6) << 16);
        WIN(qt0, W, bp0 + 8, 16);
        WIN(xt0, x, x0 + (blk + 0) * 32, 32);
        if (LEN(qt0) == 16 && LEN(xt0) == 32) {
            for (int j = 0; j < 16; j++) {
                int q = (int)LD(qt0, j);
                int h0 = (int)((qh0 >> j) & 1u) << 4;
                int h1 = (int)((qh0 >> (j + 16)) & 1u) << 4;
                ST(pr, 0 + 2 * j, (float)((q & 15) | h0) * LD(xt0, j));
                ST(pr, 0 + 2 * j + 1, (float)((q >> 4) | h1) * LD(xt0, j + 16));
                ST(px, 0 + j, LD(xt0, j) + LD(xt0, j + 16));
            }
        }
        float s0 = 0.0f;
        float ms0 = 0.0f;
        for (int k = 0; k < 32; k++) {
            s0 += LD(pr, 0 + k);
        }
        for (int j = 0; j < 16; j++) {
            ms0 += LD(px, 0 + j);
        }
        acc += d0 * s0 + m0 * ms0;
    }
    ST(y, yoff + b * rows + r, acc);
}`
}

@ __lk_mv_q4_k_h → s {
    ^ `LOCAL_F(pr, 256);
if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    long long nb = cols / 256;
    long long w0 = woff + r * nb * 144;
    float acc = 0.0f;
    for (long long blk = 0; blk < nb; blk++) {
        long long bp = w0 + blk * 144;
        float d = F16(LD16(W, bp));
        float dmin = F16(LD16(W, bp + 2));
        WIN(kb, W, bp, 144);
        WIN(xw, x, x0 + blk * 256, 256);
        if (LEN(kb) == 144 && LEN(xw) == 256) {
            int sV0 = (int)LD(kb, 4) & 63;
            int mV0 = (int)LD(kb, 8) & 63;
            int sV1 = (int)LD(kb, 5) & 63;
            int mV1 = (int)LD(kb, 9) & 63;
            int sV2 = (int)LD(kb, 6) & 63;
            int mV2 = (int)LD(kb, 10) & 63;
            int sV3 = (int)LD(kb, 7) & 63;
            int mV3 = (int)LD(kb, 11) & 63;
            int sV4 = ((int)LD(kb, 12) & 15) | (((int)LD(kb, 4) >> 6) << 4);
            int mV4 = ((int)LD(kb, 12) >> 4) | (((int)LD(kb, 8) >> 6) << 4);
            int sV5 = ((int)LD(kb, 13) & 15) | (((int)LD(kb, 5) >> 6) << 4);
            int mV5 = ((int)LD(kb, 13) >> 4) | (((int)LD(kb, 9) >> 6) << 4);
            int sV6 = ((int)LD(kb, 14) & 15) | (((int)LD(kb, 6) >> 6) << 4);
            int mV6 = ((int)LD(kb, 14) >> 4) | (((int)LD(kb, 10) >> 6) << 4);
            int sV7 = ((int)LD(kb, 15) & 15) | (((int)LD(kb, 7) >> 6) << 4);
            int mV7 = ((int)LD(kb, 15) >> 4) | (((int)LD(kb, 11) >> 6) << 4);
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 16 + l);
                ST(pr, 0 + l, (float)(q & 15) * LD(xw, 0 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 16 + l);
                ST(pr, 32 + l, (float)(q >> 4) * LD(xw, 32 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 48 + l);
                ST(pr, 64 + l, (float)(q & 15) * LD(xw, 64 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 48 + l);
                ST(pr, 96 + l, (float)(q >> 4) * LD(xw, 96 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 80 + l);
                ST(pr, 128 + l, (float)(q & 15) * LD(xw, 128 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 80 + l);
                ST(pr, 160 + l, (float)(q >> 4) * LD(xw, 160 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 112 + l);
                ST(pr, 192 + l, (float)(q & 15) * LD(xw, 192 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 112 + l);
                ST(pr, 224 + l, (float)(q >> 4) * LD(xw, 224 + l));
            }
            float s0 = 0.0f;
            float m0 = 0.0f;
            float s1 = 0.0f;
            float m1 = 0.0f;
            float s2 = 0.0f;
            float m2 = 0.0f;
            float s3 = 0.0f;
            float m3 = 0.0f;
            float s4 = 0.0f;
            float m4 = 0.0f;
            float s5 = 0.0f;
            float m5 = 0.0f;
            float s6 = 0.0f;
            float m6 = 0.0f;
            float s7 = 0.0f;
            float m7 = 0.0f;
            for (int l = 0; l < 32; l++) {
                s0 += LD(pr, 0 + l);
                m0 += LD(xw, 0 + l);
                s1 += LD(pr, 32 + l);
                m1 += LD(xw, 32 + l);
                s2 += LD(pr, 64 + l);
                m2 += LD(xw, 64 + l);
                s3 += LD(pr, 96 + l);
                m3 += LD(xw, 96 + l);
                s4 += LD(pr, 128 + l);
                m4 += LD(xw, 128 + l);
                s5 += LD(pr, 160 + l);
                m5 += LD(xw, 160 + l);
                s6 += LD(pr, 192 + l);
                m6 += LD(xw, 192 + l);
                s7 += LD(pr, 224 + l);
                m7 += LD(xw, 224 + l);
            }
            acc += (d * sV0) * s0 - (dmin * mV0) * m0;
            acc += (d * sV1) * s1 - (dmin * mV1) * m1;
            acc += (d * sV2) * s2 - (dmin * mV2) * m2;
            acc += (d * sV3) * s3 - (dmin * mV3) * m3;
            acc += (d * sV4) * s4 - (dmin * mV4) * m4;
            acc += (d * sV5) * s5 - (dmin * mV5) * m5;
            acc += (d * sV6) * s6 - (dmin * mV6) * m6;
            acc += (d * sV7) * s7 - (dmin * mV7) * m7;
        }
    }
    ST(y, yoff + b * rows + r, acc);
}`
}

@ __lk_mv_q5_k_h → s {
    ^ `LOCAL_F(pr, 256);
if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    long long nb = cols / 256;
    long long w0 = woff + r * nb * 176;
    float acc = 0.0f;
    for (long long blk = 0; blk < nb; blk++) {
        long long bp = w0 + blk * 176;
        float d = F16(LD16(W, bp));
        float dmin = F16(LD16(W, bp + 2));
        WIN(kb, W, bp, 176);
        WIN(xw, x, x0 + blk * 256, 256);
        if (LEN(kb) == 176 && LEN(xw) == 256) {
            int sV0 = (int)LD(kb, 4) & 63;
            int mV0 = (int)LD(kb, 8) & 63;
            int sV1 = (int)LD(kb, 5) & 63;
            int mV1 = (int)LD(kb, 9) & 63;
            int sV2 = (int)LD(kb, 6) & 63;
            int mV2 = (int)LD(kb, 10) & 63;
            int sV3 = (int)LD(kb, 7) & 63;
            int mV3 = (int)LD(kb, 11) & 63;
            int sV4 = ((int)LD(kb, 12) & 15) | (((int)LD(kb, 4) >> 6) << 4);
            int mV4 = ((int)LD(kb, 12) >> 4) | (((int)LD(kb, 8) >> 6) << 4);
            int sV5 = ((int)LD(kb, 13) & 15) | (((int)LD(kb, 5) >> 6) << 4);
            int mV5 = ((int)LD(kb, 13) >> 4) | (((int)LD(kb, 9) >> 6) << 4);
            int sV6 = ((int)LD(kb, 14) & 15) | (((int)LD(kb, 6) >> 6) << 4);
            int mV6 = ((int)LD(kb, 14) >> 4) | (((int)LD(kb, 10) >> 6) << 4);
            int sV7 = ((int)LD(kb, 15) & 15) | (((int)LD(kb, 7) >> 6) << 4);
            int mV7 = ((int)LD(kb, 15) >> 4) | (((int)LD(kb, 11) >> 6) << 4);
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 48 + l);
                int hb = ((int)LD(kb, 16 + l) >> 0) & 1;
                ST(pr, 0 + l, (float)((q & 15) + (hb << 4)) * LD(xw, 0 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 48 + l);
                int hb = ((int)LD(kb, 16 + l) >> 1) & 1;
                ST(pr, 32 + l, (float)((q >> 4) + (hb << 4)) * LD(xw, 32 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 80 + l);
                int hb = ((int)LD(kb, 16 + l) >> 2) & 1;
                ST(pr, 64 + l, (float)((q & 15) + (hb << 4)) * LD(xw, 64 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 80 + l);
                int hb = ((int)LD(kb, 16 + l) >> 3) & 1;
                ST(pr, 96 + l, (float)((q >> 4) + (hb << 4)) * LD(xw, 96 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 112 + l);
                int hb = ((int)LD(kb, 16 + l) >> 4) & 1;
                ST(pr, 128 + l, (float)((q & 15) + (hb << 4)) * LD(xw, 128 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 112 + l);
                int hb = ((int)LD(kb, 16 + l) >> 5) & 1;
                ST(pr, 160 + l, (float)((q >> 4) + (hb << 4)) * LD(xw, 160 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 144 + l);
                int hb = ((int)LD(kb, 16 + l) >> 6) & 1;
                ST(pr, 192 + l, (float)((q & 15) + (hb << 4)) * LD(xw, 192 + l));
            }
            for (int l = 0; l < 32; l++) {
                int q = (int)LD(kb, 144 + l);
                int hb = ((int)LD(kb, 16 + l) >> 7) & 1;
                ST(pr, 224 + l, (float)((q >> 4) + (hb << 4)) * LD(xw, 224 + l));
            }
            float s0 = 0.0f;
            float m0 = 0.0f;
            float s1 = 0.0f;
            float m1 = 0.0f;
            float s2 = 0.0f;
            float m2 = 0.0f;
            float s3 = 0.0f;
            float m3 = 0.0f;
            float s4 = 0.0f;
            float m4 = 0.0f;
            float s5 = 0.0f;
            float m5 = 0.0f;
            float s6 = 0.0f;
            float m6 = 0.0f;
            float s7 = 0.0f;
            float m7 = 0.0f;
            for (int l = 0; l < 32; l++) {
                s0 += LD(pr, 0 + l);
                m0 += LD(xw, 0 + l);
                s1 += LD(pr, 32 + l);
                m1 += LD(xw, 32 + l);
                s2 += LD(pr, 64 + l);
                m2 += LD(xw, 64 + l);
                s3 += LD(pr, 96 + l);
                m3 += LD(xw, 96 + l);
                s4 += LD(pr, 128 + l);
                m4 += LD(xw, 128 + l);
                s5 += LD(pr, 160 + l);
                m5 += LD(xw, 160 + l);
                s6 += LD(pr, 192 + l);
                m6 += LD(xw, 192 + l);
                s7 += LD(pr, 224 + l);
                m7 += LD(xw, 224 + l);
            }
            acc += (d * sV0) * s0 - (dmin * mV0) * m0;
            acc += (d * sV1) * s1 - (dmin * mV1) * m1;
            acc += (d * sV2) * s2 - (dmin * mV2) * m2;
            acc += (d * sV3) * s3 - (dmin * mV3) * m3;
            acc += (d * sV4) * s4 - (dmin * mV4) * m4;
            acc += (d * sV5) * s5 - (dmin * mV5) * m5;
            acc += (d * sV6) * s6 - (dmin * mV6) * m6;
            acc += (d * sV7) * s7 - (dmin * mV7) * m7;
        }
    }
    ST(y, yoff + b * rows + r, acc);
}`
}

@ __lk_mv_q6_k_h → s {
    ^ `LOCAL_F(pr, 256);
if (gid < rows * batch) {
    long long b = gid / rows;
    long long r = gid % rows;
    long long x0 = xoff + b * cols;
    long long nb = cols / 256;
    long long w0 = woff + r * nb * 210;
    float acc = 0.0f;
    for (long long blk = 0; blk < nb; blk++) {
        long long bp = w0 + blk * 210;
        float d = F16(LD16(W, bp + 208));
        WIN(kb, W, bp, 210);
        WIN(xw, x, x0 + blk * 256, 256);
        if (LEN(kb) == 210 && LEN(xw) == 256) {
            for (int l = 0; l < 16; l++) {
                int h = (int)LD(kb, 128 + l);
                int b1 = (int)LD(kb, 0 + l);
                int b2 = (int)LD(kb, 32 + l);
                int q1 = ((b1 & 15) | ((h & 3) << 4)) - 32;
                int q2 = ((b2 & 15) | (((h >> 2) & 3) << 4)) - 32;
                int q3 = ((b1 >> 4) | (((h >> 4) & 3) << 4)) - 32;
                int q4 = ((b2 >> 4) | (((h >> 6) & 3) << 4)) - 32;
                ST(pr, 0 + l * 4 + 0, d * (float)(signed char)LD(kb, 192) * (float)q1 * LD(xw, 0 + l));
                ST(pr, 0 + l * 4 + 1, d * (float)(signed char)LD(kb, 194) * (float)q2 * LD(xw, 32 + l));
                ST(pr, 0 + l * 4 + 2, d * (float)(signed char)LD(kb, 196) * (float)q3 * LD(xw, 64 + l));
                ST(pr, 0 + l * 4 + 3, d * (float)(signed char)LD(kb, 198) * (float)q4 * LD(xw, 96 + l));
            }
            for (int l = 16; l < 32; l++) {
                int h = (int)LD(kb, 128 + l);
                int b1 = (int)LD(kb, 0 + l);
                int b2 = (int)LD(kb, 32 + l);
                int q1 = ((b1 & 15) | ((h & 3) << 4)) - 32;
                int q2 = ((b2 & 15) | (((h >> 2) & 3) << 4)) - 32;
                int q3 = ((b1 >> 4) | (((h >> 4) & 3) << 4)) - 32;
                int q4 = ((b2 >> 4) | (((h >> 6) & 3) << 4)) - 32;
                ST(pr, 0 + l * 4 + 0, d * (float)(signed char)LD(kb, 193) * (float)q1 * LD(xw, 0 + l));
                ST(pr, 0 + l * 4 + 1, d * (float)(signed char)LD(kb, 195) * (float)q2 * LD(xw, 32 + l));
                ST(pr, 0 + l * 4 + 2, d * (float)(signed char)LD(kb, 197) * (float)q3 * LD(xw, 64 + l));
                ST(pr, 0 + l * 4 + 3, d * (float)(signed char)LD(kb, 199) * (float)q4 * LD(xw, 96 + l));
            }
            for (int l = 0; l < 16; l++) {
                int h = (int)LD(kb, 160 + l);
                int b1 = (int)LD(kb, 64 + l);
                int b2 = (int)LD(kb, 96 + l);
                int q1 = ((b1 & 15) | ((h & 3) << 4)) - 32;
                int q2 = ((b2 & 15) | (((h >> 2) & 3) << 4)) - 32;
                int q3 = ((b1 >> 4) | (((h >> 4) & 3) << 4)) - 32;
                int q4 = ((b2 >> 4) | (((h >> 6) & 3) << 4)) - 32;
                ST(pr, 128 + l * 4 + 0, d * (float)(signed char)LD(kb, 200) * (float)q1 * LD(xw, 128 + l));
                ST(pr, 128 + l * 4 + 1, d * (float)(signed char)LD(kb, 202) * (float)q2 * LD(xw, 160 + l));
                ST(pr, 128 + l * 4 + 2, d * (float)(signed char)LD(kb, 204) * (float)q3 * LD(xw, 192 + l));
                ST(pr, 128 + l * 4 + 3, d * (float)(signed char)LD(kb, 206) * (float)q4 * LD(xw, 224 + l));
            }
            for (int l = 16; l < 32; l++) {
                int h = (int)LD(kb, 160 + l);
                int b1 = (int)LD(kb, 64 + l);
                int b2 = (int)LD(kb, 96 + l);
                int q1 = ((b1 & 15) | ((h & 3) << 4)) - 32;
                int q2 = ((b2 & 15) | (((h >> 2) & 3) << 4)) - 32;
                int q3 = ((b1 >> 4) | (((h >> 4) & 3) << 4)) - 32;
                int q4 = ((b2 >> 4) | (((h >> 6) & 3) << 4)) - 32;
                ST(pr, 128 + l * 4 + 0, d * (float)(signed char)LD(kb, 201) * (float)q1 * LD(xw, 128 + l));
                ST(pr, 128 + l * 4 + 1, d * (float)(signed char)LD(kb, 203) * (float)q2 * LD(xw, 160 + l));
                ST(pr, 128 + l * 4 + 2, d * (float)(signed char)LD(kb, 205) * (float)q3 * LD(xw, 192 + l));
                ST(pr, 128 + l * 4 + 3, d * (float)(signed char)LD(kb, 207) * (float)q4 * LD(xw, 224 + l));
            }
        }
        for (int k = 0; k < 256; k++) { acc += LD(pr, k); }
    }
    ST(y, yoff + b * rows + r, acc);
}`
}

// The batch form for f32 weights, shaped as __lk_mv_q8_0_bh: a 2-D window
// over 32 columns of the batch's rows, the 32 products and adds written
// out, so the host compiler vectorises across positions.
@ __lk_mv_f32_bh → s {
    ^ `LOCAL_F(acc, 32);
LOCAL_F(wf, 32);
if (gid < rows) {
    long long r = gid;
    long long w0 = woff + r * cols;
    for (long long b0 = 0; b0 < batch; b0 += 32) {
        long long bn = batch - b0;
        if (bn > 32) { bn = 32; }
        for (int t = 0; t < 32; t++) { ST(acc, t, 0.0f); }
        long long c0 = 0;
        for (; c0 + 32 <= cols; c0 += 32) {
            WIN(ww, W, w0 + c0, 32);
            if (LEN(ww) == 32) {
                for (int j = 0; j < 32; j++) { ST(wf, j, LD(ww, j)); }
            }
            WIN2(xb, x, xoff + b0 * cols + c0, bn, cols, 32);
            if (COLS(xb) == 32) {
                for (int t = 0; t < ROWS(xb); t++) {
                    float a = LD(acc, t);
                    a += LD(wf, 0) * LD2(xb, t, 0);
                    a += LD(wf, 1) * LD2(xb, t, 1);
                    a += LD(wf, 2) * LD2(xb, t, 2);
                    a += LD(wf, 3) * LD2(xb, t, 3);
                    a += LD(wf, 4) * LD2(xb, t, 4);
                    a += LD(wf, 5) * LD2(xb, t, 5);
                    a += LD(wf, 6) * LD2(xb, t, 6);
                    a += LD(wf, 7) * LD2(xb, t, 7);
                    a += LD(wf, 8) * LD2(xb, t, 8);
                    a += LD(wf, 9) * LD2(xb, t, 9);
                    a += LD(wf, 10) * LD2(xb, t, 10);
                    a += LD(wf, 11) * LD2(xb, t, 11);
                    a += LD(wf, 12) * LD2(xb, t, 12);
                    a += LD(wf, 13) * LD2(xb, t, 13);
                    a += LD(wf, 14) * LD2(xb, t, 14);
                    a += LD(wf, 15) * LD2(xb, t, 15);
                    a += LD(wf, 16) * LD2(xb, t, 16);
                    a += LD(wf, 17) * LD2(xb, t, 17);
                    a += LD(wf, 18) * LD2(xb, t, 18);
                    a += LD(wf, 19) * LD2(xb, t, 19);
                    a += LD(wf, 20) * LD2(xb, t, 20);
                    a += LD(wf, 21) * LD2(xb, t, 21);
                    a += LD(wf, 22) * LD2(xb, t, 22);
                    a += LD(wf, 23) * LD2(xb, t, 23);
                    a += LD(wf, 24) * LD2(xb, t, 24);
                    a += LD(wf, 25) * LD2(xb, t, 25);
                    a += LD(wf, 26) * LD2(xb, t, 26);
                    a += LD(wf, 27) * LD2(xb, t, 27);
                    a += LD(wf, 28) * LD2(xb, t, 28);
                    a += LD(wf, 29) * LD2(xb, t, 29);
                    a += LD(wf, 30) * LD2(xb, t, 30);
                    a += LD(wf, 31) * LD2(xb, t, 31);
                    ST(acc, t, a);
                }
            }
        }
        for (; c0 < cols; c0++) {
            float wv = LD(W, w0 + c0);
            for (long long t = 0; t < bn; t++) { ST(acc, t, LD(acc, t) + wv * LD(x, xoff + (b0 + t) * cols + c0)); }
        }
        for (long long t = 0; t < bn; t++) { ST(y, yoff + (b0 + t) * rows + r, LD(acc, t)); }
    }
}`
}

// ── Batched Mixture-of-Experts matvecs ──────────────────────────────
//
// The MoE FFN used to launch one batch-1 matvec per (position, expert) —
// 32 positions × 8 experts × 3 projections × 19 layers ≈ 24 000 tiny
// kernels per forward, each too small to use the GPU, with the CPU pegged
// issuing them. These do the whole layer's expert work in ONE launch per
// projection: output row `a` (an assignment; there are n_assign = count·K)
// uses expert `expid[a]`'s weights and reads its input from row `a / xk` of
// x — xk = K for the gate/up projections (whose input is the per-POSITION
// activation) and 1 for the down projection (the per-ASSIGNMENT hidden).
// The 3D expert tensor is expert-major: expert e's row r is weight row
// (e·rows + r). No atomics, no shared memory.

@ __lk_mv_exp_f32 → s {
    ^ `if (gid < rows * n_assign) {
    long long a = gid / rows;
    long long r = gid % rows;
    long long e = LD(expid, a);
    long long w0 = (e * rows + r) * cols;
    long long x0 = (a / xk) * cols;
    float acc = 0.0f;
    for (long long c = 0; c < cols; c++) { acc += LD(W, w0 + c) * LD(x, x0 + c); }
    ST(y, a * rows + r, acc);
}`
}

@ __lk_mv_exp_q8_0 → String {
    ^ ( __lk_cat3 `if (gid < rows * n_assign) {
    long long a = gid / rows;
    long long r = ( LD(expid, gid / rows) * rows ) + gid % rows;
    long long x0 = (a / xk) * cols;
    long long woff = 0;
    float acc = 0.0f;
` ( string_data ( __lk_q8_row `0` `1` ) ) `
    ST(y, a * rows + gid % rows, acc);
}` )
}

// True when the batched-expert matvec has a kernel for weight type `gt`:
// F32 (0) and Q8_0 (8) — the two the converter produces; other types fall
// back to the per-position loop in model.nu.
@ lk_experts_supported i gt → b { ^ | == gt 0 == gt 8 }

// One batched matvec over all n_assign expert assignments. F when `gt` has
// no batched kernel (caller falls back). (Two "better" shapes were measured
// SLOWER and stay deleted: warp-per-row — the shuffle beats the coalescing
// at these short rows — and expert-grouped tiles; the phase is not
// weight-bandwidth-bound.)
@ lk_matvec_experts GpuKit kit LkW w GkBuf x GkBuf y GkBuf expid i rows i cols i xk i n_assign inout ( Vec GkLaunch ) plan → b {
    ? ( lk_experts_supported . w gt ) {} { ^ F }
    : ~ GkCall c ( gk_call_new )
    ? == . w gt 0 { ( gk_call_dev_in c `W` . w f ) } { ( gk_call_bytes_in c `W` . w q ) }
    ( gk_call_dev_in c `x` x ) ( gk_call_dev c `y` y ) ( gk_call_dev_in c `expid` expid )
    ( gk_call_i64 c `rows` rows ) ( gk_call_i64 c `cols` cols ) ( gk_call_i64 c `xk` xk ) ( gk_call_i64 c `n_assign` n_assign )
    : i grid ( gk_grid * rows n_assign 64 )
    ? == . w gt 0 { ^ ( __lk_rec kit c `nl_mv_exp_f32` ( __lk_mv_exp_f32 ) grid 64 plan ) } {}
    ^ ( __lk_rec kit c `nl_mv_exp_q8_0` ( string_data ( __lk_mv_exp_q8_0 ) ) grid 64 plan )
}

// On-device MoE router: one thread per position. The sigmoid gating scores,
// the selection-only expert bias (all layers' biases in `bias`, this
// layer's at `boff`), the group-limited top-k (the best `topk_group` groups
// by their top-2 biased sums, then the best `n_used` experts inside them),
// and the assignment table — expid[pos·n_used + j] and its weight (the
// UNBIASED score, normalised and scaled) — written straight to the device.
// Per-thread arrays bound n_expert ≤ 256, n_group ≤ 64, n_used ≤ 32 (the
// LLaDA2 shapes: 256 / 8 / 8).
@ __lk_moe_route → s {
    ^ `LOCAL_F(sc, 256);
LOCAL_F(bs, 256);
LOCAL_L(allowed, 256);
LOCAL_F(gsc, 64);
LOCAL_L(gkeep, 64);
LOCAL_L(chosen, 32);
if (gid < count) {
    long long lg = gid * n_expert;
    for (long long e = 0; e < n_expert; e++) {
        float s = 1.0f / (1.0f + expf(-LD(logits, lg + e)));
        ST(sc, e, s);
        ST(bs, e, s + LD(bias, boff + e));
    }
    long long per = (n_group > 0) ? n_expert / n_group : n_expert;
    if (n_group > 1) {
        for (long long g = 0; g < n_group; g++) {
            float m1 = -1e30f;
            float m2 = -1e30f;
            for (long long k = 0; k < per; k++) {
                float v = LD(bs, g * per + k);
                if (v > m1) { m2 = m1; m1 = v; } else { if (v > m2) { m2 = v; } }
            }
            ST(gsc, g, m1 + m2);
        }
        for (long long g = 0; g < n_group; g++) { ST(gkeep, g, 0); }
        for (long long r = 0; r < topk_group; r++) {
            long long best = -1;
            float bv = -1e30f;
            for (long long g = 0; g < n_group; g++) {
                if (LD(gkeep, g) == 0 && LD(gsc, g) > bv) { bv = LD(gsc, g); best = g; }
            }
            if (best >= 0) { ST(gkeep, best, 1); }
        }
        for (long long e = 0; e < n_expert; e++) { ST(allowed, e, LD(gkeep, e / per)); }
    } else {
        for (long long e = 0; e < n_expert; e++) { ST(allowed, e, 1); }
    }
    for (long long r = 0; r < n_used; r++) {
        long long best = -1;
        float bv = -1e30f;
        for (long long e = 0; e < n_expert; e++) {
            if (LD(allowed, e) != 0) {
                long long taken = 0;
                for (long long t = 0; t < r; t++) { if (LD(chosen, t) == e) { taken = 1; } }
                if (taken == 0 && LD(bs, e) > bv) { bv = LD(bs, e); best = e; }
            }
        }
        ST(chosen, r, best);
    }
    float wsum = 0.0f;
    for (long long r = 0; r < n_used; r++) { if (LD(chosen, r) >= 0) { wsum += LD(sc, LD(chosen, r)); } }
    for (long long r = 0; r < n_used; r++) {
        long long e = LD(chosen, r);
        float w = (e >= 0) ? LD(sc, e) : 0.0f;
        if (norm != 0) { w = w / (wsum + 1e-20f); }
        w *= (float)scale;
        ST(expid, gid * n_used + r, (e >= 0) ? e : 0);
        ST(wts, gid * n_used + r, w);
    }
}`
}

@ lk_moe_route GpuKit kit GkBuf logits GkBuf bias i boff GkBuf expid GkBuf wts i n_expert i n_group i topk_group i n_used f scale i norm i count inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `logits` logits ) ( gk_call_dev_in c `bias` bias ) ( gk_call_dev c `expid` expid ) ( gk_call_dev c `wts` wts )
    ( gk_call_i64 c `boff` boff ) ( gk_call_i64 c `n_expert` n_expert ) ( gk_call_i64 c `n_group` n_group ) ( gk_call_i64 c `topk_group` topk_group )
    ( gk_call_i64 c `n_used` n_used ) ( gk_call_f64 c `scale` scale ) ( gk_call_i64 c `norm` norm ) ( gk_call_i64 c `count` count )
    ^ ( __lk_rec kit c `nl_moe_route` ( __lk_moe_route ) ( gk_grid count 64 ) 64 plan )
}

// Scatter-accumulate the experts' down-projections onto the residual:
// out[pos·dim + d] += Σ_j wts[pos·K+j] · down[(pos·K+j)·dim + d]. One thread
// per (pos, dim); a position's K assignments are contiguous, so no atomics.
@ lk_moe_scatter GpuKit kit GkBuf down GkBuf wts GkBuf out i K i dim i count inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `down` down ) ( gk_call_dev_in c `wts` wts ) ( gk_call_dev c `out` out )
    ( gk_call_i64 c `K` K ) ( gk_call_i64 c `dim` dim ) ( gk_call_i64 c `count` count )
    ^ ( __lk_rec kit c `nl_moe_scatter` `if (gid < count * dim) {
    long long pos = gid / dim;
    long long d = gid % dim;
    float acc = 0.0f;
    for (long long j = 0; j < K; j++) {
        long long a = pos * K + j;
        acc += LD(wts, a) * LD(down, a * dim + d);
    }
    ST(out, pos * dim + d, LD(out, pos * dim + d) + acc);
}` ( gk_grid * count dim 64 ) 64 plan )
}

// ── Greedy argmax + confidence, on device ──────────────────────────
//
// One position per thread (portable) or per warp (CUDA): the argmax token
// id and its softmax probability (1 / Σ exp(logit − max)), so only count·2
// small values come back instead of count·vocab. `out_id` is an i64 buffer.
// The lowest-index tie-break reproduces the serial first-max argmax.
@ lk_argmax_conf GpuKit kit b warp GkBuf logits GkBuf out_id GkBuf out_prob i vocab i count inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `logits` logits ) ( gk_call_dev c `out_id` out_id ) ( gk_call_dev c `out_prob` out_prob )
    ( gk_call_i64 c `vocab` vocab ) ( gk_call_i64 c `count` count )
    ? warp {
        ^ ( __lk_rec kit c `nl_argmax_conf_w` `long long warp = gid >> 5;
long long lane = gid & 31;
long long lg = warp * vocab;
float mx = -1e30f;
long long arg = 2147483647;
if (warp < count) {
    for (long long v = lane; v < vocab; v += 32) {
        float xv = LD(logits, lg + v);
        if (xv > mx || (xv == mx && v < arg)) { mx = xv; arg = v; }
    }
}
for (int off = 16; off > 0; off >>= 1) {
    float omx = SHFL_XOR(mx, off);
    long long oarg = SHFL_XOR(arg, off);
    if (omx > mx || (omx == mx && oarg < arg)) { mx = omx; arg = oarg; }
}
float sum = 0.0f;
if (warp < count) {
    for (long long v = lane; v < vocab; v += 32) { sum += expf(LD(logits, lg + v) - mx); }
}
for (int off = 16; off > 0; off >>= 1) { sum += SHFL_DOWN(sum, off); }
if (warp < count && lane == 0) {
    ST(out_id, warp, (arg == 2147483647) ? 0 : arg);
    ST(out_prob, warp, 1.0f / sum);
}` ( gk_grid * count 32 128 ) 128 plan )
    } {}
    ^ ( __lk_rec kit c `nl_argmax_conf` `if (gid < count) {
    long long lg = gid * vocab;
    float mx = -1e30f;
    long long arg = 0;
    for (long long v = 0; v < vocab; v++) {
        float xv = LD(logits, lg + v);
        if (xv > mx) { mx = xv; arg = v; }
    }
    float sum = 0.0f;
    for (long long v = 0; v < vocab; v++) { sum += expf(LD(logits, lg + v) - mx); }
    ST(out_id, gid, arg);
    ST(out_prob, gid, 1.0f / sum);
}` ( gk_grid count 64 ) 64 plan )
}

// ── norms, rotations, attention ─────────────────────────────────────

// RMSNorm. On a GPU every thread recomputes its row's sum of squares —
// O(n²) a row, but norms are dwarfed by the matvecs at decode shapes and
// it needs no cross-thread sync. The CPU backend runs threads one after
// another, so there a thread takes a whole row: the sum once (in the same
// order — the same bits), then the row. gemma's RMSNorm is documented as
// `x * inv * (1 + w)`, but the GGUF converter folds that +1 into the
// stored weights, so this is the plain form for every architecture. `y`
// must not be `x`: another thread would overwrite the row under the sum.
@ lk_rmsnorm GpuKit kit GkBuf x GkBuf w GkBuf y i n f eps i batch inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `x` x ) ( gk_call_dev_in c `w` w ) ( gk_call_dev c `y` y )
    ( gk_call_i64 c `n` n ) ( gk_call_f64 c `eps` eps ) ( gk_call_i64 c `batch` batch )
    ? != 0 ( nurl_str_eq ( gk_backend kit ) `cpu` ) {
        ^ ( __lk_rec kit c `nl_rmsnorm_r` `if (gid < batch) {
    WIN(xr, x, gid * n, n);
    WIN(wr, w, 0, n);
    WIN(yr, y, gid * n, n);
    float ss = 0.0f;
    for (int j = 0; j < LEN(xr); j++) { ss += LD(xr, j) * LD(xr, j); }
    float inv = rsqrtf(ss / n + (float)eps);
    for (int i = 0; i < LEN(xr) && i < LEN(wr) && i < LEN(yr); i++) { ST(yr, i, LD(xr, i) * inv * LD(wr, i)); }
}` ( gk_grid batch 64 ) 64 plan )
    } {}
    ^ ( __lk_rec kit c `nl_rmsnorm` `if (gid < n * batch) {
    long long b = gid / n;
    long long i = gid % n;
    WIN(xr, x, b * n, n);
    float ss = 0.0f;
    for (int j = 0; j < LEN(xr); j++) { ss += LD(xr, j) * LD(xr, j); }
    float inv = rsqrtf(ss / n + (float)eps);
    ST(y, b * n + i, LD(xr, i) * inv * LD(w, i));
}` ( gk_grid * n batch 256 ) 256 plan )
}

// Rotary embedding of the first `rd` dims of every head, at position pos0+b
// for batch element b. style 0 = ggml NORM (llama: adjacent pairs 2j, 2j+1),
// 1 = NEOX (qwen2, phi, …: the halves j, j + rd/2). Feeding a model the
// wrong one still runs and still produces fluent-looking garbage, which is
// why the architecture selects it rather than a heuristic.
@ lk_rope GpuKit kit GkBuf x i nh i hd i rd i pos0 f base i style i batch inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `x` x )
    ( gk_call_i64 c `nh` nh ) ( gk_call_i64 c `hd` hd ) ( gk_call_i64 c `rd` rd ) ( gk_call_i64 c `pos0` pos0 )
    ( gk_call_f64 c `base` base ) ( gk_call_i64 c `batch` batch )
    : i total * * nh / rd 2 batch
    : s pair ? == style 1 `long long v0 = base0 + h * hd + j;
    long long v1 = v0 + pairs;` `long long v0 = base0 + h * hd + 2 * j;
    long long v1 = v0 + 1;`
    : ~ String body ( string_from `long long pairs = rd / 2;
if (gid < nh * pairs * batch) {
    long long b = gid / (nh * pairs);
    long long p = gid % (nh * pairs);
    long long base0 = b * nh * hd;
    long long pos = pos0 + b;
    long long h = p / pairs;
    long long j = p % pairs;
    float theta = pos * powf((float)base, -2.0f * j / rd);
    float cs = cosf(theta);
    float sn = sinf(theta);
    ` )
    ( string_push_str body pair )
    ( string_push_str body `
    float a0 = LD(x, v0);
    float a1 = LD(x, v1);
    ST(x, v0, a0 * cs - a1 * sn);
    ST(x, v1, a0 * sn + a1 * cs);
}` )
    ^ ( __lk_rec kit c ? == style 1 `nl_rope_neox` `nl_rope` ( string_data body ) ( gk_grid total 256 ) 256 plan )
}

// Attention, two passes: one thread per (position, head, cache row) for the
// raw score, then the softmax over the row's scores and the value-weighted
// sum, a thread per (position, head, head-dim). `coop` (a backend whose
// block barrier is cheap — a GPU): a block per (position, head) shares
// the weights through shared memory; otherwise every thread walks its own
// row (the CPU backend runs a barrier's threads as fibers).
// `qscale` is the query scale (1/sqrt(head_dim) for llama; gemma states its
// own). `window` > 0 is a sliding window: a key older than `window`
// positions is not attended to (gemma3 on five layers of six). `causal` 1:
// batch element b attends its own window, npos0 + b cache rows
// (autoregressive decode); 0: every element attends the same npos0 rows
// (block diffusion). GQA: query head h reads kv head h/(nh/nkv). Appends two
// launches; npos0 is a scalar of both (lk_set).
@ lk_attn GpuKit kit b coop GkBuf q GkBuf kc GkBuf vc GkBuf out GkBuf sc i nh i nkv i hd i npos0 i batch i maxpos f qscale i window i causal inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `q` q ) ( gk_call_dev_in c `K` kc ) ( gk_call_dev c `scores` sc )
    ( gk_call_i64 c `nh` nh ) ( gk_call_i64 c `nkv` nkv ) ( gk_call_i64 c `hd` hd ) ( gk_call_i64 c `npos0` npos0 )
    ( gk_call_i64 c `batch` batch ) ( gk_call_i64 c `maxpos` maxpos ) ( gk_call_f64 c `qscale` qscale )
    ( gk_call_i64 c `window` window ) ( gk_call_i64 c `causal` causal )
    // (the CPU backend: a thread per (position, head) walks its cache rows
    // — the same dots, without a thread and its index arithmetic per row)
    : b sc_ok ? coop T ( __lk_rec kit c `nl_attn_sc_r` `if (gid < nh * batch) {
    long long h = gid % nh;
    long long b = gid / nh;
    long long npos = causal != 0 ? npos0 + b : npos0;
    long long lo = (window > 0 && npos - 1 - window > 0) ? (npos - 1 - window) : 0;
    long long hi = npos < maxpos ? npos : maxpos;
    long long kvdim = nkv * hd;
    long long kh = h / (nh / nkv);
    WIN(qr, q, b * nh * hd + h * hd, hd);
    WIN(sr, scores, gid * maxpos + lo, hi - lo);
    for (int u = 0; u < LEN(sr); u++) {
        WIN(kr, K, (lo + u) * kvdim + kh * hd, hd);
        float d = 0.0f;
        for (int j = 0; j < LEN(qr) && j < LEN(kr); j++) { d += LD(qr, j) * LD(kr, j); }
        ST(sr, u, d * (float)qscale);
    }
}` ( gk_grid * nh batch 64 ) 64 plan )
    ? sc_ok {} { ^ F }
    : b sc2 ? coop ( __lk_rec kit c `nl_attn_sc` `long long total = nh * batch * maxpos;
if (gid < total) {
    long long t = gid % maxpos;
    long long hb = gid / maxpos;
    long long h = hb % nh;
    long long b = hb / nh;
    long long npos = causal != 0 ? npos0 + b : npos0;
    long long lo = (window > 0 && npos - 1 - window > 0) ? (npos - 1 - window) : 0;
    if (t < npos && t >= lo) {
        long long kvdim = nkv * hd;
        long long kh = h / (nh / nkv);
        WIN(qr, q, b * nh * hd + h * hd, hd);
        WIN(kr, K, t * kvdim + kh * hd, hd);
        float d = 0.0f;
        for (int j = 0; j < LEN(qr) && j < LEN(kr); j++) { d += LD(qr, j) * LD(kr, j); }
        ST(scores, hb * maxpos + t, d * (float)qscale);
    }
}` ( gk_grid * * nh batch maxpos 256 ) 256 plan ) T
    ? sc2 {} { ^ F }
    : ~ GkCall c2 ( gk_call_new )
    ( gk_call_dev_in c2 `V` vc ) ( gk_call_dev_in c2 `scores` sc ) ( gk_call_dev c2 `out` out )
    ( gk_call_i64 c2 `nh` nh ) ( gk_call_i64 c2 `nkv` nkv ) ( gk_call_i64 c2 `hd` hd ) ( gk_call_i64 c2 `npos0` npos0 )
    ( gk_call_i64 c2 `batch` batch ) ( gk_call_i64 c2 `maxpos` maxpos ) ( gk_call_i64 c2 `window` window ) ( gk_call_i64 c2 `causal` causal )
    ? coop {} {
        ^ ( __lk_rec kit c2 `nl_attn_out_t` `if (gid < nh * batch * hd) {
    long long d = gid % hd;
    long long hb = gid / hd;
    long long h = hb % nh;
    long long b = hb / nh;
    long long npos = causal != 0 ? npos0 + b : npos0;
    long long lo = (window > 0 && npos - 1 - window > 0) ? (npos - 1 - window) : 0;
    long long kvdim = nkv * hd;
    long long kh = h / (nh / nkv);
    WIN(sr, scores, hb * maxpos + lo, npos - lo);
    WINS(vc, V, lo * kvdim + kh * hd + d, npos - lo, kvdim);
    float mx = -1e30f;
    for (int t = 0; t < LEN(sr); t++) { if (LD(sr, t) > mx) { mx = LD(sr, t); } }
    float sum = 0.0f;
    float acc = 0.0f;
    for (int t = 0; t < LEN(sr) && t < LEN(vc); t++) {
        float p = expf(LD(sr, t) - mx);
        sum += p;
        acc += p * LD(vc, t);
    }
    ST(out, b * nh * hd + h * hd + d, acc / sum);
}` ( gk_grid * * nh batch hd 256 ) 256 plan )
    }
    // One block of hd threads per (element, head), a thread per head dim:
    // the block's max through shared memory (a max is exact, so in any
    // order), then each weight computed once into a shared tile and summed
    // by every thread in position order — the bits of one thread looping
    // over every position, without each of hd threads recomputing every
    // weight.
    ^ ( __lk_rec kit c2 `nl_attn_out` `SHARED_F(pw, 256);
SHARED_F(red, 1024);
long long h = bid % nh;
long long b = bid / nh;
long long npos = causal != 0 ? npos0 + b : npos0;
long long lo = (window > 0 && npos - 1 - window > 0) ? (npos - 1 - window) : 0;
long long kvdim = nkv * hd;
long long kh = h / (nh / nkv);
long long s0 = bid * maxpos;
float pm = -1e30f;
for (long long t = lo + tid; t < npos; t += bdim) { float sv = LD(scores, s0 + t); if (sv > pm) { pm = sv; } }
ST(red, tid, pm);
SYNC();
float mx = -1e30f;
for (int u = 0; u < bdim; u++) { if (LD(red, u) > mx) { mx = LD(red, u); } }
float sum = 0.0f;
float acc = 0.0f;
for (long long t0 = lo; t0 < npos; t0 += 256) {
    SYNC();
    for (long long u = tid; u < 256; u += bdim) {
        if (t0 + u < npos) { ST(pw, u, expf(LD(scores, s0 + t0 + u) - mx)); }
    }
    SYNC();
    WINS(vt, V, t0 * kvdim + kh * hd + tid, npos - t0 < 256 ? npos - t0 : 256, kvdim);
    for (int u = 0; u < LEN(vt); u++) {
        float p = LD(pw, u);
        sum += p;
        acc += p * LD(vt, u);
    }
}
ST(out, b * nh * hd + h * hd + tid, acc / sum);` * nh batch hd plan )
}

// ── elementwise ─────────────────────────────────────────────────────

@ __lk_ew GpuKit kit inout GkCall c s name s body i n inout ( Vec GkLaunch ) plan → b {
    ^ ( __lk_rec kit c name body ( gk_grid n 256 ) 256 plan )
}

// y ← y + a·x — a routed expert's weighted down-projection onto the
// residual (yoff / xoff: the position's rows).
@ lk_axpy GpuKit kit GkBuf y i yoff GkBuf x i xoff f a i n inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `y` y ) ( gk_call_dev_in c `x` x ) ( gk_call_i64 c `yoff` yoff ) ( gk_call_i64 c `xoff` xoff )
    ( gk_call_f64 c `a` a ) ( gk_call_i64 c `n` n )
    ^ ( __lk_ew kit c `nl_axpy` `if (gid < n) { ST(y, yoff + gid, LD(y, yoff + gid) + (float)a * LD(x, xoff + gid)); }` n plan )
}

// SwiGLU gate: g = silu(g) · u, in place on g.
@ lk_silumul GpuKit kit GkBuf g GkBuf u i n inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `g` g ) ( gk_call_dev_in c `u` u ) ( gk_call_i64 c `n` n )
    ^ ( __lk_ew kit c `nl_silumul` `if (gid < n) { float v = LD(g, gid); ST(g, gid, (v / (1.0f + expf(-v))) * LD(u, gid)); }` n plan )
}

// GeGLU — gemma's FFN gate. The tanh approximation is what gemma was
// trained with (gelu_pytorch_tanh), so the exact erf form would be the
// wrong function here, not a more accurate one.
@ lk_gelumul GpuKit kit GkBuf g GkBuf u i n inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `g` g ) ( gk_call_dev_in c `u` u ) ( gk_call_i64 c `n` n )
    ^ ( __lk_ew kit c `nl_gelumul` `if (gid < n) {
    float v = LD(g, gid);
    float cc = 0.7978845608028654f * (v + 0.044715f * v * v * v);
    ST(g, gid, (0.5f * v * (1.0f + tanhf(cc))) * LD(u, gid));
}` n plan )
}

// x ← x · s (gemma scales the embedding row by sqrt(n_embd)).
@ lk_scale GpuKit kit GkBuf x f s i n inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `x` x ) ( gk_call_f64 c `s` s ) ( gk_call_i64 c `n` n )
    ^ ( __lk_ew kit c `nl_scale` `if (gid < n) { ST(x, gid, LD(x, gid) * (float)s); }` n plan )
}

// Residual add, in place: a += b.
@ lk_addv GpuKit kit GkBuf a GkBuf b i n inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `a` a ) ( gk_call_dev_in c `b` b ) ( gk_call_i64 c `n` n )
    ^ ( __lk_ew kit c `nl_addv` `if (gid < n) { ST(a, gid, LD(a, gid) + LD(b, gid)); }` n plan )
}

// Broadcast add: every row of a batch gets the same vector (a bias).
@ lk_addrow GpuKit kit GkBuf a GkBuf v i n i batch inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `a` a ) ( gk_call_dev_in c `v` v ) ( gk_call_i64 c `n` n ) ( gk_call_i64 c `batch` batch )
    ^ ( __lk_ew kit c `nl_addrow` `if (gid < n * batch) { ST(a, gid, LD(a, gid) + LD(v, gid % n)); }` * n batch plan )
}

// Element copy into an offset — appends k/v rows into the cache (`off`
// moves with the position: lk_set).
@ lk_copyat GpuKit kit GkBuf dst GkBuf src i off i n inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `dst` dst ) ( gk_call_dev_in c `src` src ) ( gk_call_i64 c `off` off ) ( gk_call_i64 c `n` n )
    ^ ( __lk_ew kit c `nl_copyat` `if (gid < n) { ST(dst, off + gid, LD(src, gid)); }` n plan )
}

// Repack an uploaded q8_0 tensor from ggml's interleaved 34-byte blocks
// ([d q0..q31] [d q0..q31] …) into the split per-row layout [d0 … d_{nb-1}]
// [q-block0 … q-block_{nb-1}], same nb·34-byte row stride. With an even nb
// the quant region is 4-byte aligned, which is what lets the matvecs read
// words and float4s instead of bytes (their limit is load-instruction
// count, not bandwidth). One thread per block, run once at model load.
@ lk_q8_repack GpuKit kit GkBBuf src GkBBuf dst i nb i nblk inout ( Vec GkLaunch ) plan → b {
    : ~ GkCall c ( gk_call_new )
    ( gk_call_bytes_in c `src` src ) ( gk_call_bytes c `dst` dst ) ( gk_call_i64 c `nb` nb ) ( gk_call_i64 c `nblk` nblk )
    // The CPU backend: a thread per row, the row's blocks and their two
    // destinations as 2-D windows (a block a row of each) — no check per
    // byte, and no per-thread cost per 34 bytes.
    ? != 0 ( nurl_str_eq ( gk_backend kit ) `cpu` ) {
        ^ ( __lk_rec kit c `nl_q8_repack_r` `if (gid < nblk / nb) {
    long long drow = gid * nb * 34;
    WIN2(sb, src, gid * nb * 34, nb, 34, 34);
    WIN2(dd, dst, drow, nb, 2, 2);
    WIN2(dq, dst, drow + nb * 2, nb, 32, 32);
    if (COLS(sb) == 34 && COLS(dd) == 2 && COLS(dq) == 32) {
        for (int b = 0; b < ROWS(sb) && b < ROWS(dd) && b < ROWS(dq); b++) {
            ST2(dd, b, 0, LD2(sb, b, 0));
            ST2(dd, b, 1, LD2(sb, b, 1));
            for (int j = 0; j < 32; j++) { ST2(dq, b, j, LD2(sb, b, 2 + j)); }
        }
    }
}` ( gk_grid / nblk nb 64 ) 64 plan )
    } {}
    // (the block and its two destinations as windows: a copy with no check
    // per byte)
    ^ ( __lk_rec kit c `nl_q8_repack` `if (gid < nblk) {
    long long row = gid / nb;
    long long blk = gid - row * nb;
    long long drow = row * nb * 34;
    WIN(sb, src, gid * 34, 34);
    WIN(dd, dst, drow + blk * 2, 2);
    WIN(dq, dst, drow + nb * 2 + blk * 32, 32);
    if (LEN(sb) == 34 && LEN(dd) == 2 && LEN(dq) == 32) {
        ST(dd, 0, LD(sb, 0));
        ST(dd, 1, LD(sb, 1));
        for (int j = 0; j < 32; j++) { ST(dq, j, LD(sb, 2 + j)); }
    }
}` ( gk_grid nblk 256 ) 256 plan )
}
