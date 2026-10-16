// gpukit/devops.nu — the NN operator family over device-resident GkBufs.
//
// These are the kernels a CNN / transformer forward pass needs beyond the
// arithmetic core in dev.nu: gemm, conv/pool, normalisation, activation,
// axis softmax, axis data movement (concat/slice/permute/resize/expand),
// reductions and argmax/index selection. The kernel bodies are lifted from
// packages/onnx's original f32 operator set and generalised over the
// element type, keeping the arithmetic ORDER identical — so the GK_F32
// instantiation is bit-for-bit the kernels the onnx/objdet/yoloe models
// were verified with, and GK_F64 gets the same operators in double.
//
// Conventions:
//   - every wrapper validates buffers, dtypes and sizes and fails closed
//     (returns F) — a wrong shape never reaches the device;
//   - layout metadata is explicit (NCHW dims, axis views (outer,ax,inner));
//     batch N is assumed 1 for the conv family, group 1;
//   - arithmetic ops require a float dtype; pure data movement
//     (copy/slice/permute/resize/expand) accepts GK_I64 too;
//   - index outputs (argmax) are GK_I64.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `dev.nu`

// The counter type of a loop to `n`: an int when n — plus a stride of up
// to 65536 past it, as a loop striding by the block takes — fits one (the
// compiler unrolls an int loop further, and a window's check folds
// against it), else a long long. A counter that could wrap is never an int.
@ __gkd_ctr i n → s { ? <= n 2147418112 { ^ `int` } {} ^ `long long` }

// `x` as the element type's C scalar: a checked kernel's f64 scalar,
// cast to float for an f32 op exactly as a float parameter was.
@ __gkd_scal i dtype s nm → String {
    : ~ String o ( string_from `((` )
    ( string_push_str o ( _gk_tname dtype ) ) ( string_push_str o `)` ) ( string_push_str o nm ) ( string_push_str o `)` )
    ^ o
}

// One thread per element of `total`, in blocks of 256.
@ __gkd_run GpuKit kit inout GkCall c String kname String body i total → b {
    ^ ( gk_run_checked_dev kit c ( string_data kname ) ( string_data body ) ( gk_grid total 256 ) 256 )
}

// (the same, the body made by `mk` only the first time `tag` is seen:
// see gk_run_checked_dev_tagged)
@ __gkd_run_t GpuKit kit inout GkCall c String kname String tag ( @ String ) mk i total → b {
    ^ ( gk_run_checked_dev_tagged kit c ( string_data kname ) ( string_data tag ) mk ( gk_grid total 256 ) 256 )
}

@ __gkd_name i dtype → String { ^ ( string_from ( _gk_pfx dtype ) ) }

// Float-math suffix: expf/sqrtf/erff on f32, exp/sqrt/erf on f64.
@ __gkd_sfx i dtype → s { ? == dtype GK_F32 { ^ `f` } {} ^ `` }

// The -1e30 "effectively -inf" literal in the buffer's element type.
@ __gkd_neg i dtype → s { ? == dtype GK_F32 { ^ `-1e30f` } {} ^ `-1e30` }

@ __gkd_isfloat GkBuf x → b { ^ & ( gk_buf_ok x ) != . x dtype GK_I64 }

// ── Gemm: Y[M×N] = alpha·A[M×K]·B(ᵀ) + beta·bias ─────────────────────
// bias is broadcast over rows; pass hasb 0 to skip it (c is ignored).

@ gkd_gemm GpuKit kit GkBuf y GkBuf a GkBuf b GkBuf c i hasb i m i n i k f alpha f beta i transb → b {
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok a ) ( gk_buf_ok b ) {} { ^ F }
    ? & == . y dtype . a dtype == . a dtype . b dtype {} { ^ F }
    ? & & > m 0 > n 0 > k 0 {} { ^ F }
    ? & & == . a n ( _gk_p2 m k ) == . b n ( _gk_p2 k n ) == . y n ( _gk_p2 m n ) {} { ^ F }
    ? != hasb 0 {
        ? & & ( gk_buf_ok c ) == . c dtype . y dtype >= . c n n {} { ^ F }
    } {}
    : s tn ( _gk_tname . y dtype )
    // CPU with B already [K,N] (transb=0): one output per thread with a
    // scalar accumulator walks a COLUMN of B and gives the vectoriser
    // nothing — the same shape problem _gk_tile_body was written for.
    // Bit-identical to the per-element kernel: the sum still runs
    // t = 0..K ascending, only the visit order over outputs changes.
    //
    // transb=1 deliberately stays on the per-element kernel. Staging a
    // transpose at CALL time to reach the tiled body was measured and is
    // a LOSS: the transpose is a full memory round trip over a cold weight
    // used once, and a model came out 2.4x slower. Callers that want the tiled path
    // transpose their weights ONCE, at load.
    //
    // On the CUDA backend the shared-memory tile (_gkd_smem_cbody) wins on
    // anything big enough to fill one: a 64x64 tile with K >= 16. Below
    // that — the M=1 GEMVs a camera/pose head runs — the per-element
    // kernel is the better shape, since a 64-row tile would be 63/64
    // wasted, so the threshold is on M and N, not on a FLOP count.
    : b on_cpu ( nurl_str_eq ( gk_backend kit ) `cpu` )
    : b tiled & on_cpu == transb 0
    : b on_cuda ( nurl_str_eq ( gk_backend kit ) `cuda` )
    : b smem & & & on_cuda >= m 16 >= n 32 >= k 16
    // The 128x64 tile with an 8x4 register block (see _gkd_smem_cbody):
    // double the arithmetic intensity per shared read, but half the
    // blocks — so only where M is deep enough that ceil(M/128)*ceil(N/64)
    // still covers a big card's SMs. A batched or long-sequence encoder
    // forward lives here; the ~800-row single forwards the 64x64 tile
    // was sized for do not, and keep it.
    : b big & & smem >= m 512 >= * ( _gkd_ceil m 128 ) ( _gkd_ceil n 64 ) 128
    // Too few rows for a tile — a pose head's [1,K]x[K,N]. The
    // per-element kernel runs those as M*N threads, which for a 2048-wide
    // projection is eight blocks on a 128-SM card: 94% of the machine
    // idle while eight blocks each walk a 2048-long dot product. One
    // BLOCK per output instead: its 256 threads stage the two operand
    // chunks coalesced into shared memory, and the dot product itself
    // stays a single ascending sum in one thread, which is what keeps it
    // bit-identical. The chains of different outputs overlap, so the
    // depth of one no longer sets the time.
    : b gemv & & on_cuda ! smem >= k 128
    : i dt . y dtype
    : b tb != transb 0
    : String kname ( __gkd_name dt )
    ( string_push_str kname ? smem
    ? big
    ? tb `gemm_smem2_t` `gemm_smem2`
    ? tb `gemm_smem_t` `gemm_smem`
    ? gemv `gemv` ? tiled `gemm_tiled` `gemm` )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `A` a y ) ( _gkd_in cl `B` b y )
    // (a bias either way — the first operand standing in for an absent
    // one — read only when hasB says so)
    ? != hasb 0 { ( _gkd_in cl `Cb` c y ) } { ( _gkd_in cl `Cb` a y ) }
    ( gk_call_dev cl `Y` y )
    ( gk_call_i64 cl `M` m ) ( gk_call_i64 cl `N` n ) ( gk_call_i64 cl `K` k )
    ( gk_call_f64 cl `alpha` alpha ) ( gk_call_f64 cl `beta` beta ) ( gk_call_i64 cl `hasB` hasb )
    // (the transpose is in the body: the GEMV's and the per-element
    // kernel's names do not carry it, so the tag does)
    : String tag ( string_from ? tb `t` `n` )
    // The smem body maps ONE BLOCK to a 64x64 (or 128x64) tile, so its
    // launch is a block count, not a thread count.
    ? smem {
        : i nb ? big
        { * ( _gkd_ceil m 128 ) ( _gkd_ceil n 64 ) }
        { * ( _gkd_ceil m GKD_BM ) ( _gkd_ceil n GKD_BN ) }
        ^ ( gk_run_checked_dev_tagged kit cl ( string_data kname ) ( string_data tag ) \ → String { ^ ( _gkd_smem_cbody tn dt tb F big ) } nb 256 )
    } {}
    // one block per output element, not one thread
    ? gemv { ^ ( gk_run_checked_dev_tagged kit cl ( string_data kname ) ( string_data tag ) \ → String { ^ ( _gkd_gemv_cbody tn dt tb ) } * m n 256 ) } {}
    : i total ? tiled * ( _gkd_ceil m GKD_RT ) ( _gkd_ceil n GKD_CT ) * m n
    ^ ( gk_run_checked_dev_tagged kit cl ( string_data kname ) ( string_data tag ) \ → String { ^ ? tiled ( _gk_tile_body tn dt F T ) ( _gkd_elem_cbody tn dt tb T F F ) } ( gk_grid total 256 ) 256 )
}

// ── 2-D convolution, NCHW, batch 1, group 1 ──────────────────────────
// X[Cin,H,W] * W[Cout,Cin,kh,kw] (+ bias[Cout] when hasb) → Y[Cout,OH,OW].
// Out-of-range taps are skipped (zero padding); ph/pw are the begin pads.

// conv2d's CUDA body: the shape in the source (see gkd_conv2d).
@ __gkd_conv2d_cuda s tn s lc i hasb i cin i h i wd i cout i kh i kw i oh i ow i ph i pw i sh i sw → String {
    // Sixteen outputs per thread: four along the output row, four output
    // channels deep — the weight fetched once for the four, four
    // independent chains. The input row a tap row needs (the four
    // outputs' taps overlap: 3*sw + kw values) is loaded once into a
    // local and every tap reads it from there.
    //
    // The twelve dimensions go in as constants, so the tap loops unroll
    // and every tap reads a fixed slot (each geometry compiles once; the
    // on-disk cache makes that once per machine), and the kernel is built
    // for its buffers' exact lengths. The input is a 3-D window (Cin
    // planes of H rows of W), the weights another (Cout of Cin of kh*kw):
    // each index is checked against its own extent — the channel against
    // its loop, the row against the padding test, the column against the
    // row's — so no load carries a check.
    //
    // Each output still sums ic, then r, then s, ascending, over exactly
    // the taps it summed before — bit-identical.
    : i nx + * 3 sw kw
    : b rowl <= nx 16
    : b one & == kh 1 == kw 1
    // (32-bit counters where they fit: NVRTC keeps a 64-bit one in two
    // registers)
    : s ict ( __gkd_ctr cin )
    : s ity ( __gkd_ctr + + * oh sh kh h )
    : ~ String body ( string_new )
    ( string_push_str body lc ) ( string_push_str body `acc, 16);
` )
    ( string_push_str body lc )
    ? rowl {
        ( string_push_str body `xr, ` ) ( string_push_int body nx ) ( string_push_str body `);
` )
    } { ( string_push_str body `xv, 4);
` ) }
    ? one {
        ? rowl { ( string_push_str body lc ) ( string_push_str body `xv, 4);
` ) } {}
        ( string_push_str body lc ) ( string_push_str body `xu, 4);
` )
    } {}
    : ~ ( Vec String ) dn ( vec_new [String] )
    ( vec_push [String] dn ( string_from `Cin` ) ) ( vec_push [String] dn ( string_from `H` ) ) ( vec_push [String] dn ( string_from `W` ) )
    ( vec_push [String] dn ( string_from `Cout` ) ) ( vec_push [String] dn ( string_from `kh` ) ) ( vec_push [String] dn ( string_from `kw` ) )
    ( vec_push [String] dn ( string_from `OH` ) ) ( vec_push [String] dn ( string_from `OW` ) ) ( vec_push [String] dn ( string_from `ph` ) )
    ( vec_push [String] dn ( string_from `pw` ) ) ( vec_push [String] dn ( string_from `sh` ) ) ( vec_push [String] dn ( string_from `sw` ) )
    : ~ ( Vec i ) dv ( vec_new [i] )
    ( vec_push [i] dv cin ) ( vec_push [i] dv h ) ( vec_push [i] dv wd ) ( vec_push [i] dv cout ) ( vec_push [i] dv kh ) ( vec_push [i] dv kw )
    ( vec_push [i] dv oh ) ( vec_push [i] dv ow ) ( vec_push [i] dv ph ) ( vec_push [i] dv pw ) ( vec_push [i] dv sh ) ( vec_push [i] dv sw )
    : ~ i q 0
    ~ < q 12 {
        ( string_push_str body `const long long ` ) ( string_push_str body ( string_data ( vec_at [String] dn q ) ) ) ( string_push_str body ` = ` )
        ( string_push_int body ( vec_at [i] dv q ) ) ( string_push_str body `;
` )
        = q + q 1
    }
    ( string_push_str body `long long nwb = (OW + 3) / 4, ncb = (Cout + 3) / 4;
if (gid < ncb * OH * nwb) {
    long long wb = gid % nwb, oh = (gid / nwb) % OH, ocb = gid / (nwb * OH);
    long long ow0 = wb * 4, oc0 = ocb * 4;
    for (int c = 0; c < 4; c++) {
        ` ) ( string_push_str body tn )
    ( string_push_str body ? != hasb 0 ` b0 = (oc0 + c < Cout) ? LD(B, oc0 + c) : 0;` ` b0 = 0;` )
    ( string_push_str body `
        for (int t = 0; t < 4; t++) { ST(acc, c * 4 + t, b0); }
    }
    long long j0 = ow0 * sw - pw;
    WIN3(xa, X, 0, Cin, H * W, H, W, W);
    WIN3(wa, Wt, 0, Cout, Cin * kh * kw, Cin, kh * kw, kh * kw);
    if (PLANES(xa) == Cin && ROWS(xa) == H && COLS(xa) == W && PLANES(wa) == Cout && ROWS(wa) == Cin && COLS(wa) == kh * kw) {
` )
    ? one {
        // 1x1: two input channels a step, both rows loaded before either
        // is used (twice the loads in flight; each output still sums
        // its channels in order)
        ( string_push_str body `        long long ih = oh * sh - ph;
        if (ih >= 0 && ih < H) {
            ` ) ( string_push_str body ict ) ( string_push_str body ` ic = 0;
            if (j0 >= 0 && j0 + 3 * sw < W) {
                for (; ic + 1 < Cin; ic += 2) {
                    for (int t = 0; t < 4; t++) { ST(xv, t, LD3(xa, ic, ih, j0 + t * sw)); ST(xu, t, LD3(xa, ic + 1, ih, j0 + t * sw)); }
                    for (int c = 0; c < 4; c++) {
                        if (oc0 + c < Cout) {
                            ` ) ( string_push_str body tn ) ( string_push_str body ` wv = LD3(wa, oc0 + c, ic, 0);
                            ` ) ( string_push_str body tn ) ( string_push_str body ` wu = LD3(wa, oc0 + c, ic + 1, 0);
                            for (int t = 0; t < 4; t++) { ST(acc, c * 4 + t, LD(acc, c * 4 + t) + LD(xv, t) * wv); }
                            for (int t = 0; t < 4; t++) { ST(acc, c * 4 + t, LD(acc, c * 4 + t) + LD(xu, t) * wu); }
                        }
                    }
                }
            }
            for (; ic < Cin; ++ic) {
                for (int t = 0; t < 4; t++) { long long iw = j0 + t * sw; ST(xv, t, (iw >= 0 && iw < W) ? LD3(xa, ic, ih, iw) : 0); }
                for (int c = 0; c < 4; c++) {
                    if (oc0 + c < Cout) {
                        ` ) ( string_push_str body tn ) ( string_push_str body ` wv = LD3(wa, oc0 + c, ic, 0);
                        for (int t = 0; t < 4; t++) { ST(acc, c * 4 + t, LD(acc, c * 4 + t) + LD(xv, t) * wv); }
                    }
                }
            }
        }
    }
` )
    } {
        ( string_push_str body `        for (` ) ( string_push_str body ict ) ( string_push_str body ` ic = 0; ic < Cin; ++ic) {
            for (` ) ( string_push_str body ity ) ( string_push_str body ` r = 0; r < kh; ++r) {
                ` ) ( string_push_str body ity ) ( string_push_str body ` ih = (` ) ( string_push_str body ity ) ( string_push_str body `)(oh * sh - ph + r);
                if (ih < 0 || ih >= H) { continue; }
` )
        ? rowl {
            ( string_push_str body `                if (j0 >= 0 && j0 + ` ) ( string_push_int body - nx 1 ) ( string_push_str body ` < W) {
                    for (int j = 0; j < ` ) ( string_push_int body nx ) ( string_push_str body `; j++) { ST(xr, j, LD3(xa, ic, ih, j0 + j)); }
                } else {
                    for (int j = 0; j < ` ) ( string_push_int body nx ) ( string_push_str body `; j++) { long long iw = j0 + j; ST(xr, j, (iw >= 0 && iw < W) ? LD3(xa, ic, ih, iw) : 0); }
                }
                for (int s = 0; s < kw; s++) {
` )
        } {
            ( string_push_str body `                for (long long s = 0; s < kw; s++) {
                    long long i0 = j0 + s;
                    if (i0 >= 0 && i0 + 3 * sw < W) {
                        for (int t = 0; t < 4; t++) { ST(xv, t, LD3(xa, ic, ih, i0 + t * sw)); }
                    } else {
                        for (int t = 0; t < 4; t++) { long long iw = i0 + t * sw; ST(xv, t, (iw >= 0 && iw < W) ? LD3(xa, ic, ih, iw) : 0); }
                    }
` )
        }
        ( string_push_str body `                    for (int c = 0; c < 4; c++) {
                        if (oc0 + c < Cout) {
                            ` ) ( string_push_str body tn ) ( string_push_str body ` wv = LD3(wa, oc0 + c, ic, r * kw + s);
                            for (int t = 0; t < 4; t++) { ST(acc, c * 4 + t, LD(acc, c * 4 + t) + LD(` ) ( string_push_str body ? rowl `xr, s + t * sw` `xv, t` ) ( string_push_str body `) * wv); }
                        }
                    }
                }
            }
        }
    }
` )
    }
    ( string_push_str body `    for (int c = 0; c < 4; c++) {
        long long oc = oc0 + c;
        if (oc < Cout) {
            WIN(yr, Y, (oc * OH + oh) * OW + ow0, OW - ow0 < 4 ? OW - ow0 : 4);
            if (LEN(yr) == 4) {
                for (int t = 0; t < 4; t++) { ST(yr, t, LD(acc, c * 4 + t)); }
            } else {
                for (int t = 0; t < LEN(yr); t++) { ST(yr, t, LD(acc, c * 4 + t)); }
            }
        }
    }
}` )
    ^ body
}

@ gkd_conv2d GpuKit kit GkBuf y GkBuf x GkBuf w GkBuf bias i hasb i cin i h i wd i cout i kh i kw i oh i ow i ph i pw i sh i sw → b {
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok x ) ( gk_buf_ok w ) {} { ^ F }
    ? & == . y dtype . x dtype == . x dtype . w dtype {} { ^ F }
    ? & & & > cin 0 > h 0 > wd 0 > cout 0 {} { ^ F }
    ? & & & > kh 0 > kw 0 > oh 0 > ow 0 {} { ^ F }
    ? & > sh 0 > sw 0 {} { ^ F }
    ? & & == . x n ( _gk_p3 cin h wd ) == . w n ( _gk_p4 cout cin kh kw ) == . y n ( _gk_p3 cout oh ow ) {} { ^ F }
    ? != hasb 0 {
        ? & & ( gk_buf_ok bias ) == . bias dtype . y dtype >= . bias n cout {} { ^ F }
    } {}
    : s tn ( _gk_tname . y dtype )
    : s lc ? == . y dtype GK_F32 `LOCAL_F(` `LOCAL_D(`
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `conv2d` )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( _gkd_in cl `Wt` w y )
    : b cuda ( nurl_str_eq ( gk_backend kit ) `cuda` )
    // (the host's binds a bias either way — the input standing in for an
    // absent one — and reads it only when hasB says so: one kernel for
    // both, as the static backend links one)
    ? != hasb 0 { ( _gkd_in cl `B` bias y ) } { ? cuda {} { ( _gkd_in cl `B` x y ) } }
    ( gk_call_dev cl `Y` y )
    ? cuda {
        // (the shape is the kernel: it is the tag, and the body is made
        // once per shape)
        ( gk_call_exact cl )
        : ~ String tag ( string_with_cap 96 )
        ( string_push_int tag hasb )
        : ~ i q 0
        ~ < q 12 {
            ( string_push_char tag 44 )
            ( string_push_int tag ? == q 0 cin ? == q 1 h ? == q 2 wd ? == q 3 cout ? == q 4 kh ? == q 5 kw ? == q 6 oh ? == q 7 ow ? == q 8 ph ? == q 9 pw ? == q 10 sh sw )
            = q + q 1
        }
        ^ ( __gkd_run_t kit cl kname tag \ → String { ^ ( __gkd_conv2d_cuda tn lc hasb cin h wd cout kh kw oh ow ph pw sh sw ) } * * ( _gkd_ceil cout 4 ) oh ( _gkd_ceil ow 4 ) )
    } {}
    // The host's (the CPU and static backends): one source for every
    // shape — the static backend links one kernel, so the shape is in
    // the arguments — and a path per kind of layer, picked here and
    // passed in. Each thread owns four output channels and a run of
    // sixteen columns (fewer for a stride-2 layer, below), so a tap's work is a
    // vector multiply-add the host compiler can see: the input row's
    // span is copied once per tap row into a local, zero where it pads,
    // and every tap reads consecutive slots of it. A 1x1 layer opens its
    // windows once per thread. Anything else (a stride above 2, a tap
    // row wider than sixteen) takes the four-wide per-tap form.
    : i mode ? & & == kh 1 == kw 1 == sw 1 0 ? & == sw 1 <= kw 16 1 ? & == sw 2 <= kw 16 2 3
    // (stride 2: sixteen columns while there are few input channels to
    // share a run's overhead, else eight)
    : i tw ? < mode 2 16 ? == mode 2 ? >= cin 8 8 16 4
    ( gk_call_i64 cl `Cin` cin ) ( gk_call_i64 cl `H` h ) ( gk_call_i64 cl `W` wd ) ( gk_call_i64 cl `Cout` cout ) ( gk_call_i64 cl `kh` kh ) ( gk_call_i64 cl `kw` kw )
    ( gk_call_i64 cl `OH` oh ) ( gk_call_i64 cl `OW` ow ) ( gk_call_i64 cl `ph` ph ) ( gk_call_i64 cl `pw` pw ) ( gk_call_i64 cl `sh` sh ) ( gk_call_i64 cl `sw` sw )
    ( gk_call_i64 cl `mode` mode ) ( gk_call_i64 cl `tw` tw ) ( gk_call_i64 cl `hasB` hasb )
    ^ ( __gkd_run_t kit cl kname ( string_from `h` ) \ → String { ^ ( __gkd_conv2d_host tn lc ) } * * ( _gkd_ceil cout 4 ) oh ( _gkd_ceil ow tw ) )
}

// conv2d's host body (see gkd_conv2d): one for every shape.
@ __gkd_conv2d_host s tn s lc → String {
    : ~ String body ( string_new )
    ( string_push_str body lc ) ( string_push_str body `acc, 64);
` )
    ( string_push_str body lc ) ( string_push_str body `xp, 32);
` )
    ( string_push_str body lc ) ( string_push_str body `xe, 24);
` )
    ( string_push_str body lc ) ( string_push_str body `xo, 24);
` )
    ( string_push_str body lc ) ( string_push_str body `xv, 16);
` )
    : String t1 ( string_replace ( string_from `long long nwb = (OW + tw - 1) / tw, ncb = (Cout + 3) / 4;
if (gid < ncb * OH * nwb) {
    long long wb = gid % nwb, oh = (gid / nwb) % OH, ocb = gid / (nwb * OH);
    long long ow0 = wb * tw, oc0 = ocb * 4;
    for (int c = 0; c < 4; c++) {
        @T@ b0 = (oc0 + c < Cout) ? @BIAS@ : 0;
        for (int t = 0; t < 16; t++) { ST(acc, c * 16 + t, b0); }
    }
    long long j0 = ow0 * sw - pw;
    long long nc = Cout - oc0 < 4 ? Cout - oc0 : 4;
    WIN3(xa, X, 0, Cin, H * W, H, W, W);
    if (PLANES(xa) == Cin && ROWS(xa) == H && COLS(xa) == W) {
        if (mode == 0 && kh == 1 && kw == 1 && sw == 1) {
            // 1x1: the four channels' weights and the sixteen columns'
            // inputs are windows over every input channel, opened once
            long long ih = oh * sh - ph;
            WIN2(w1, Wt, oc0 * Cin, nc, Cin, Cin);
            if (ih >= 0 && ih < H && COLS(w1) == Cin) {
                if (j0 >= 0 && j0 + 15 < W) {
                    WIN2(x1, X, ih * W + j0, Cin, H * W, 16);
                    if (ROWS(x1) == Cin && COLS(x1) == 16) {
                        for (long long ic = 0; ic < Cin; ++ic) {
                            for (int c = 0; c < 4; c++) {
                                if (c < ROWS(w1)) {
                                    @T@ wv = LD2(w1, c, ic);
                                    for (int t = 0; t < 16; t++) { ST(acc, c * 16 + t, LD(acc, c * 16 + t) + LD2(x1, ic, t) * wv); }
                                }
                            }
                        }
                    }
                } else {
                    for (long long ic = 0; ic < Cin; ++ic) {
                        for (int t = 0; t < 16; t++) { long long iw = j0 + t; ST(xv, t, (iw >= 0 && iw < W) ? LD3(xa, ic, ih, iw) : 0); }
                        for (int c = 0; c < 4; c++) {
                            if (c < ROWS(w1)) {
                                @T@ wv = LD2(w1, c, ic);
                                for (int t = 0; t < 16; t++) { ST(acc, c * 16 + t, LD(acc, c * 16 + t) + LD(xv, t) * wv); }
                            }
                        }
                    }
                }
            }
        } else if (mode == 1 || mode == 2) {
            // The span of input columns a tap row's outputs cover, and the
            // part of it inside the row: copied once per tap row into a
            // local whose other slots keep their zeros (the padding).
            long long nx = (tw - 1) * sw + kw;
            long long jlo = j0 < 0 ? -j0 : 0;
            long long jhi = W - j0 < nx ? W - j0 : nx;
            for (long long ic = 0; ic < Cin && jlo < jhi; ++ic) {
                for (long long r = 0; r < kh; ++r) {
                    long long ih = oh * sh - ph + r;
                    if (ih < 0 || ih >= H) { continue; }
                    WIN2(wr, Wt, (oc0 * Cin + ic) * kh * kw + r * kw, nc, Cin * kh * kw, kw);
                    WIN(xs, X, (ic * H + ih) * W + j0 + jlo, jhi - jlo);
                    if (COLS(wr) != kw) { continue; }
                    if (mode == 1 && sw == 1 && kw <= 16) {
                        // unit stride: a tap reads sixteen consecutive slots
                        for (int j = 0; j < LEN(xs); j++) { ST(xp, jlo + j, LD(xs, j)); }
                        for (long long s = 0; s < kw; ++s) {
                            for (int c = 0; c < 4; c++) {
                                if (c < ROWS(wr)) {
                                    @T@ wv = LD2(wr, c, s);
                                    for (int t = 0; t < 16; t++) { ST(acc, c * 16 + t, LD(acc, c * 16 + t) + LD(xp, s + t) * wv); }
                                }
                            }
                        }
                    } else if (mode == 2 && sw == 2 && kw <= 16) {
                        // stride 2: the row as its even and odd columns, so
                        // a tap again reads consecutive slots
                        for (int j = 0; j < LEN(xs); j++) {
                            long long q = jlo + j;
                            if ((q & 1) == 0) { ST(xe, q >> 1, LD(xs, j)); } else { ST(xo, q >> 1, LD(xs, j)); }
                        }
                        for (long long s = 0; s < kw; ++s) {
                            for (int c = 0; c < 4; c++) {
                                if (c < ROWS(wr)) {
                                    @T@ wv = LD2(wr, c, s);
                                    if (tw == 8) {
                                        if ((s & 1) == 0) {
                                            for (int t = 0; t < 8; t++) { ST(acc, c * 16 + t, LD(acc, c * 16 + t) + LD(xe, (s >> 1) + t) * wv); }
                                        } else {
                                            for (int t = 0; t < 8; t++) { ST(acc, c * 16 + t, LD(acc, c * 16 + t) + LD(xo, (s >> 1) + t) * wv); }
                                        }
                                    } else {
                                        if ((s & 1) == 0) {
                                            for (int t = 0; t < 16; t++) { ST(acc, c * 16 + t, LD(acc, c * 16 + t) + LD(xe, (s >> 1) + t) * wv); }
                                        } else {
                                            for (int t = 0; t < 16; t++) { ST(acc, c * 16 + t, LD(acc, c * 16 + t) + LD(xo, (s >> 1) + t) * wv); }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            // anything else: four outputs, one tap at a time
            for (long long ic = 0; ic < Cin; ++ic) {
                for (long long r = 0; r < kh; ++r) {
                    long long ih = oh * sh - ph + r;
                    if (ih < 0 || ih >= H) { continue; }
                    WIN2(wg, Wt, (oc0 * Cin + ic) * kh * kw + r * kw, nc, Cin * kh * kw, kw);
                    if (COLS(wg) != kw) { continue; }
                    for (long long s = 0; s < kw; ++s) {
                        long long i0 = j0 + s;
                        if (i0 >= 0 && i0 + 3 * sw < W) {
                            for (int t = 0; t < 4; t++) { ST(xv, t, LD3(xa, ic, ih, i0 + t * sw)); }
                        } else {
                            for (int t = 0; t < 4; t++) { long long iw = i0 + t * sw; ST(xv, t, (iw >= 0 && iw < W) ? LD3(xa, ic, ih, iw) : 0); }
                        }
                        for (int c = 0; c < 4; c++) {
                            if (c < ROWS(wg)) {
                                @T@ wv = LD2(wg, c, s);
                                for (int t = 0; t < 4; t++) { ST(acc, c * 16 + t, LD(acc, c * 16 + t) + LD(xv, t) * wv); }
                            }
                        }
                    }
                }
            }
        }
    }
    // (an output row's outputs as a window: plain stores where all are
    // there — a check per store keeps the host compiler from holding
    // the sums in registers)
    for (int c = 0; c < 4; c++) {
        long long oc = oc0 + c;
        if (oc < Cout) {
            WIN(yr, Y, (oc * OH + oh) * OW + ow0, OW - ow0 < tw ? OW - ow0 : tw);
            if (LEN(yr) == 16) {
                for (int t = 0; t < 16; t++) { ST(yr, t, LD(acc, c * 16 + t)); }
            } else {
                for (int t = 0; t < LEN(yr); t++) { ST(yr, t, LD(acc, c * 16 + t)); }
            }
        }
    }
}` ) `@T@` tn )
    : String t2 ( string_replace t1 `@BIAS@` `(hasB != 0 ? LD(B, oc0 + c) : 0)` )
    ( string_push_str body ( string_data t2 ) )
    ^ body
}

// ── 2-D DILATED convolution, NCHW, batch 1, group 1 ──────────────────
// The atrous variant (U²-Net's RSU4F, DeepLab-family heads): tap (r, s)
// reads input row iy = oy·sh − ph + r·dh. gkd_conv2d is the dh=dw=1
// special case and keeps its specialised fast kernel; this one is a
// plain one-thread-per-output body, because dilated layers in the models
// that need them are a handful of small feature maps, not the hot path.
@ gkd_conv2d_dil GpuKit kit GkBuf y GkBuf x GkBuf w GkBuf bias i hasb i cin i h i wd i cout i kh i kw i oh i ow i ph i pw i sh i sw i dh i dw → b {
    ? & == dh 1 == dw 1 {
        ^ ( gkd_conv2d kit y x w bias hasb cin h wd cout kh kw oh ow ph pw sh sw )
    } {}
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok x ) ( gk_buf_ok w ) {} { ^ F }
    ? & == . y dtype . x dtype == . x dtype . w dtype {} { ^ F }
    ? & & & > cin 0 > h 0 > wd 0 > cout 0 {} { ^ F }
    ? & & & > kh 0 > kw 0 > oh 0 > ow 0 {} { ^ F }
    ? & & & > sh 0 > sw 0 > dh 0 > dw 0 {} { ^ F }
    ? & & == . x n ( _gk_p3 cin h wd ) == . w n ( _gk_p4 cout cin kh kw ) == . y n ( _gk_p3 cout oh ow ) {} { ^ F }
    ? != hasb 0 {
        ? & & ( gk_buf_ok bias ) == . bias dtype . y dtype >= . bias n cout {} { ^ F }
    } {}
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `conv2d_dil` )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( _gkd_in cl `Wt` w y )
    ? != hasb 0 { ( _gkd_in cl `B` bias y ) } { ( _gkd_in cl `B` x y ) }
    ( gk_call_dev cl `Y` y )
    ( gk_call_i64 cl `Cin` cin ) ( gk_call_i64 cl `H` h ) ( gk_call_i64 cl `W` wd ) ( gk_call_i64 cl `Cout` cout ) ( gk_call_i64 cl `kh` kh ) ( gk_call_i64 cl `kw` kw )
    ( gk_call_i64 cl `OH` oh ) ( gk_call_i64 cl `OW` ow ) ( gk_call_i64 cl `ph` ph ) ( gk_call_i64 cl `pw` pw ) ( gk_call_i64 cl `sh` sh ) ( gk_call_i64 cl `sw` sw )
    ( gk_call_i64 cl `dh` dh ) ( gk_call_i64 cl `dw` dw ) ( gk_call_i64 cl `hasB` hasb )
    ^ ( __gkd_run_t kit cl kname ( string_new ) \ → String { ^ ( __gkd_conv2d_dil_body tn ) } * * cout oh ow )
}

// (the input a 3-D window, the output channel's weights another — one
// each per thread, every index checked against its own extent: the
// channel against its loop, a tap's row and column against the padding
// tests)
@ __gkd_conv2d_dil_body s tn → String {
    : ~ String body ( string_from `if (gid < Cout * OH * OW) {
    long long ox = gid % OW, oy = (gid / OW) % OH, oc = gid / (OW * OH);
    double acc = hasB != 0 ? (double)LD(B, oc) : 0.0;` )
    ( string_push_str body `
    WIN3(xa, X, 0, Cin, H * W, H, W, W);
    WIN3(wk, Wt, oc * Cin * kh * kw, Cin, kh * kw, kh, kw, kw);
    if (PLANES(xa) == Cin && ROWS(xa) == H && COLS(xa) == W && PLANES(wk) == Cin && ROWS(wk) == kh && COLS(wk) == kw) {
        for (long long ic = 0; ic < Cin; ic++) {
            for (long long r = 0; r < kh; r++) {
                long long iy = oy * sh - ph + r * dh; if (iy < 0 || iy >= H) { continue; }
                for (long long s = 0; s < kw; s++) {
                    long long ix = ox * sw - pw + s * dw; if (ix < 0 || ix >= W) { continue; }
                    acc += (double)LD3(xa, ic, iy, ix) * (double)LD3(wk, ic, r, s);
                }
            }
        }
    }
    ST(Y, gid, (` ) ( string_push_str body tn ) ( string_push_str body `)acc);
}` )
    ^ body
}

// ── 2-D transposed convolution (deconv), NCHW, batch 1, group 1 ──────
// PyTorch/ONNX weight layout [Cin, Cout, kh, kw] (Cin first, unlike Conv).
// Gather form: Y[oc,oy,ox] = bias + Σ X[ic,iy,ix]·W[ic,oc,ky,kx] where
// iy = (oy + ph − ky)/sh taken only when it divides evenly and is in range.

@ gkd_convtranspose2d GpuKit kit GkBuf y GkBuf x GkBuf w GkBuf bias i hasb i cin i h i wd i cout i kh i kw i oh i ow i ph i pw i sh i sw → b {
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok x ) ( gk_buf_ok w ) {} { ^ F }
    ? & == . y dtype . x dtype == . x dtype . w dtype {} { ^ F }
    ? & & & > cin 0 > h 0 > wd 0 > cout 0 {} { ^ F }
    ? & & & > kh 0 > kw 0 > oh 0 > ow 0 {} { ^ F }
    ? & > sh 0 > sw 0 {} { ^ F }
    ? & & == . x n ( _gk_p3 cin h wd ) == . w n ( _gk_p4 cin cout kh kw ) == . y n ( _gk_p3 cout oh ow ) {} { ^ F }
    ? != hasb 0 {
        ? & & ( gk_buf_ok bias ) == . bias dtype . y dtype >= . bias n cout {} { ^ F }
    } {}
    : s tn ( _gk_tname . y dtype )
    // The stride-equals-kernel case (an exact upsample: 2x2/2, 4x4/4 —
    // what a DPT head's reassemble stage runs) has EXACTLY ONE (ky,kx)
    // contributing per output pixel, and which one is a function of the
    // output coordinate alone. The general body rediscovers that inside
    // the Cin loop with two 64-bit modulos per tap and then `continue`s
    // out of 15 of every 16 iterations; here it is two divisions before
    // the loop, and the loop is Cin long instead of Cin*kh*kw. Measured
    // on a 4090, 256->256 at 37x21 -> 148x84: 14.2 ms -> 0.35 ms.
    //
    // The sum still runs ic ascending over the same terms — the skipped
    // iterations contributed nothing — so it is bit-identical.
    //
    // Every backend takes it. The CPU and static backends pay for the
    // general body's modulos even more than a GPU does (a 64-bit idiv
    // per tap): on the static backend a YOLOE-seg forward spent 44 % of
    // its time in this kernel's general body.
    : b exact & & == ph 0 == pw 0 & == sh kh == sw kw
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname ? exact `convt2d_up` `convt2d` )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( _gkd_in cl `Wt` w y )
    ? != hasb 0 { ( _gkd_in cl `B` bias y ) } { ( _gkd_in cl `B` x y ) }
    ( gk_call_dev cl `Y` y )
    ( gk_call_i64 cl `Cin` cin ) ( gk_call_i64 cl `H` h ) ( gk_call_i64 cl `W` wd ) ( gk_call_i64 cl `Cout` cout ) ( gk_call_i64 cl `kh` kh ) ( gk_call_i64 cl `kw` kw )
    ( gk_call_i64 cl `OH` oh ) ( gk_call_i64 cl `OW` ow ) ( gk_call_i64 cl `ph` ph ) ( gk_call_i64 cl `pw` pw ) ( gk_call_i64 cl `sh` sh ) ( gk_call_i64 cl `sw` sw ) ( gk_call_i64 cl `hasB` hasb )
    : s ict ( __gkd_ctr cin )
    : b cuda ( nurl_str_eq ( gk_backend kit ) `cuda` )
    : ~ String tag ( string_from ? cuda `g` `h` )
    ( string_push_str tag ict )
    ^ ( __gkd_run_t kit cl kname tag \ → String { ^ ( __gkd_convt2d_body tn exact ict cuda ) } * * cout oh ow )
}

@ __gkd_convt2d_body s tn b exact s ict b cuda → String {
    : ~ String body ( string_from `if (gid < Cout * OH * OW) {
    long long ox = gid % OW, oy = (gid / OW) % OH, oc = gid / (OW * OH);
    ` )
    ( string_push_str body tn ) ( string_push_str body ` acc = hasB != 0 ? LD(B, oc) : 0;` )
    ? exact {
        // (the input column and the weights for this output pixel are
        // strided windows: the Cin loop's checks fold)
        ( string_push_str body `
    long long iy = oy / sh, ky = oy - iy * sh, ix = ox / sw, kx = ox - ix * sw;
    if (iy < H && ix < W) {
        WINS(xc, X, iy * W + ix, Cin, H * W);
        WINS(wc, Wt, (oc * kh + ky) * kw + kx, Cin, Cout * kh * kw);
        if (LEN(xc) == Cin && LEN(wc) == Cin) {
            for (` ) ( string_push_str body ict ) ( string_push_str body ` ic = 0; ic < Cin; ++ic) { acc += LD(xc, ic) * LD(wc, ic); }
        }
    }` )
    } ? cuda {
        // (on CUDA the loads' own clamps: the GPU hides them, and the
        // windows' bookkeeping costs it more than they save)
        ( string_push_str body `
    for (long long ic = 0; ic < Cin; ++ic) {
        long long xp = ic * H * W;
        for (long long ky = 0; ky < kh; ++ky) { long long ty = oy + ph - ky; if (ty % sh != 0) { continue; } long long iy = ty / sh; if (iy < 0 || iy >= H) { continue; }
            for (long long kx = 0; kx < kw; ++kx) { long long tx = ox + pw - kx; if (tx % sw != 0) { continue; } long long ix = tx / sw; if (ix < 0 || ix >= W) { continue; }
                acc += LD(X, xp + iy * W + ix) * LD(Wt, (((ic * Cout) + oc) * kh + ky) * kw + kx); } }
    }` )
    } {
        // (the input a 3-D window and this output channel's weights
        // another — [Cin][kh][kw], Cout*kh*kw apart — so a tap's indices
        // fold against the divisibility and range tests before it)
        ( string_push_str body `
    WIN3(xa, X, 0, Cin, H * W, H, W, W);
    WIN3(wt, Wt, oc * kh * kw, Cin, Cout * kh * kw, kh, kw, kw);
    if (PLANES(xa) == Cin && ROWS(xa) == H && COLS(xa) == W && PLANES(wt) == Cin && ROWS(wt) == kh && COLS(wt) == kw) {
        for (long long ic = 0; ic < Cin; ++ic) {
            for (long long ky = 0; ky < kh; ++ky) { long long ty = oy + ph - ky; if (ty % sh != 0) { continue; } long long iy = ty / sh; if (iy < 0 || iy >= H) { continue; }
                for (long long kx = 0; kx < kw; ++kx) { long long tx = ox + pw - kx; if (tx % sw != 0) { continue; } long long ix = tx / sw; if (ix < 0 || ix >= W) { continue; }
                    acc += LD3(xa, ic, iy, ix) * LD3(wt, ic, ky, kx); } }
        }
    }` )
    }
    ( string_push_str body `
    ST(Y, (oc * OH + oy) * OW + ox, acc);
}` )
    ^ body
}

// ── 2-D max pool, NCHW; padding taps are ignored (−inf) ──────────────

@ gkd_maxpool2d GpuKit kit GkBuf y GkBuf x i c i h i wd i kh i kw i oh i ow i sh i sw i ph i pw → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? & & & > c 0 > h 0 > wd 0 & > kh 0 > kw 0 {} { ^ F }
    ? & & & > oh 0 > ow 0 > sh 0 > sw 0 {} { ^ F }
    ? & == . x n ( _gk_p3 c h wd ) == . y n ( _gk_p3 c oh ow ) {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `maxpool2d` )
    : i dty . y dtype
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( gk_call_dev cl `Y` y )
    ( gk_call_i64 cl `C` c ) ( gk_call_i64 cl `H` h ) ( gk_call_i64 cl `W` wd ) ( gk_call_i64 cl `kh` kh ) ( gk_call_i64 cl `kw` kw )
    ( gk_call_i64 cl `OH` oh ) ( gk_call_i64 cl `OW` ow ) ( gk_call_i64 cl `sh` sh ) ( gk_call_i64 cl `sw` sw ) ( gk_call_i64 cl `ph` ph ) ( gk_call_i64 cl `pw` pw )
    ^ ( __gkd_run_t kit cl kname ( string_new ) \ → String {
        : ~ String body ( string_from `if (gid < C * OH * OW) {
    long long ow = gid % OW, oh = (gid / OW) % OH, c = gid / (OW * OH);
    long long xp = c * H * W;
    ` )
        ( string_push_str body tn ) ( string_push_str body ` m = ` ) ( string_push_str body ( __gkd_neg dty ) )
        ( string_push_str body `;
    for (long long r = 0; r < kh; ++r) { long long ih = oh * sh - ph + r; if (ih < 0 || ih >= H) { continue; }
        for (long long s = 0; s < kw; ++s) { long long iw = ow * sw - pw + s; if (iw < 0 || iw >= W) { continue; }
            ` ) ( string_push_str body tn ) ( string_push_str body ` v = LD(X, xp + ih * W + iw); if (v > m) { m = v; } } }
    ST(Y, (c * OH + oh) * OW + ow, m);
}` )
        ^ body
    } * * c oh ow )
}

// ── BatchNormalization (inference), per channel over C×HW ────────────
// Y = scale·(X−mean)/sqrt(var+eps) + B.

@ gkd_batchnorm GpuKit kit GkBuf y GkBuf x GkBuf sc GkBuf bb GkBuf mean GkBuf var i c i hw f eps → b {
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok x ) & ( gk_buf_ok sc ) ( gk_buf_ok bb ) {} { ^ F }
    ? & ( gk_buf_ok mean ) ( gk_buf_ok var ) {} { ^ F }
    ? & == . y dtype . x dtype == . x dtype . sc dtype {} { ^ F }
    ? & & == . sc dtype . bb dtype == . bb dtype . mean dtype == . mean dtype . var dtype {} { ^ F }
    ? & > c 0 > hw 0 {} { ^ F }
    ? & == . x n ( _gk_p2 c hw ) == . y n ( _gk_p2 c hw ) {} { ^ F }
    ? & & & >= . sc n c >= . bb n c >= . mean n c >= . var n c {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `bnorm` )
    : i dty . y dtype
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( _gkd_in cl `sc` sc y ) ( _gkd_in cl `B` bb y ) ( _gkd_in cl `mean` mean y ) ( _gkd_in cl `var` var y )
    ( gk_call_dev cl `Y` y ) ( gk_call_i64 cl `C` c ) ( gk_call_i64 cl `HW` hw ) ( gk_call_f64 cl `eps` eps )
    ^ ( __gkd_run_t kit cl kname ( string_new ) \ → String {
        : ~ String body ( string_from `if (gid < C * HW) { long long c = gid / HW; ST(Y, gid, LD(sc, c) * (LD(X, gid) - LD(mean, c)) / sqrt` )
        ( string_push_str body ( __gkd_sfx dty ) ) ( string_push_str body `(LD(var, c) + ` )
        ( string_push_str body ( string_data ( __gkd_scal dty `eps` ) ) ) ( string_push_str body `) + LD(B, c)); }` )
        ^ body
    } * c hw )
}

// ── LeakyRelu / Clip / Erf (elementwise with scalar params) ──────────

@ gkd_leakyrelu GpuKit kit GkBuf y GkBuf x f alpha → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? & == . y dtype . x dtype == . y n . x n {} { ^ F }
    : i n . y n
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `lrelu` )
    : i dt . y dtype
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( gk_call_dev cl `Y` y ) ( gk_call_i64 cl `n` n ) ( gk_call_f64 cl `alpha` alpha )
    ^ ( __gkd_run_t kit cl kname ( string_new ) \ → String {
        : ~ String body ( string_from `if (gid < n) { ` )
        ( string_push_str body tn ) ( string_push_str body ` v = LD(X, gid); ST(Y, gid, v >= 0 ? v : ` )
        ( string_push_str body ( string_data ( __gkd_scal dt `alpha` ) ) ) ( string_push_str body ` * v); }` )
        ^ body
    } n )
}

@ gkd_clip GpuKit kit GkBuf y GkBuf x f lo f hi → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? & == . y dtype . x dtype == . y n . x n {} { ^ F }
    : i n . y n
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `clip` )
    : String lo2 ( __gkd_scal . y dtype `lo` )
    : String hi2 ( __gkd_scal . y dtype `hi` )
    : i dty . y dtype
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( gk_call_dev cl `Y` y ) ( gk_call_i64 cl `n` n ) ( gk_call_f64 cl `lo` lo ) ( gk_call_f64 cl `hi` hi )
    ^ ( __gkd_run_t kit cl kname ( string_new ) \ → String {
        : ~ String body ( string_from `if (gid < n) { ` )
        ( string_push_str body tn ) ( string_push_str body ` v = LD(X, gid); ST(Y, gid, v < ` ) ( string_push_str body ( string_data lo2 ) )
        ( string_push_str body ` ? ` ) ( string_push_str body ( string_data lo2 ) ) ( string_push_str body ` : (v > ` ) ( string_push_str body ( string_data hi2 ) )
        ( string_push_str body ` ? ` ) ( string_push_str body ( string_data hi2 ) ) ( string_push_str body ` : v)); }` )
        ^ body
    } n )
}

@ gkd_erf GpuKit kit GkBuf y GkBuf x → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? & == . y dtype . x dtype == . y n . x n {} { ^ F }
    ? == . y dtype GK_F32 { ^ ( gkd_map kit `erf` `erff(x)` y x ) } {}
    ^ ( gkd_map kit `erf` `erf(x)` y x )
}

// ── LayerNormalization over the last axis ────────────────────────────
// Per (outer) row of `ax` elements: y = (x−mean)/sqrt(var+eps)·sc + bi.

@ gkd_layernorm GpuKit kit GkBuf y GkBuf x GkBuf sc GkBuf bi i outer i ax f eps → b {
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok x ) & ( gk_buf_ok sc ) ( gk_buf_ok bi ) {} { ^ F }
    ? & == . y dtype . x dtype == . x dtype . sc dtype {} { ^ F }
    ? == . sc dtype . bi dtype {} { ^ F }
    ? & > outer 0 > ax 0 {} { ^ F }
    ? & == . x n ( _gk_p2 outer ax ) == . y n ( _gk_p2 outer ax ) {} { ^ F }
    ? & >= . sc n ax >= . bi n ax {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : s sfx ( __gkd_sfx . y dtype )
    // One thread per row is the wrong shape on a GPU twice over: a
    // transformer normalises ~800 rows, which is three blocks on a
    // 128-SM card, and each thread then walks its own row while its
    // neighbours walk theirs — every load a separate transaction.
    //
    // A row per BLOCK fixes both: `outer` blocks fill the machine, and
    // the rewrite pass is 256 threads striding one row, i.e. coalesced.
    // The two sums stay in ONE thread, in ascending j, because that is
    // what makes them bit-identical to the per-thread kernel and to
    // every golden taken with it — a tree reduction would be faster
    // still and would change the low bits of every normalised model.
    // The serial chain is latency, not bandwidth, and with many blocks
    // resident per SM the chains overlap.
    //
    // Below `ax` ~ a few hundred the old shape is better (the row is too
    // short to amortise a block), so the choice is on ax, not on outer.
    : b on_cuda ( nurl_str_eq ( gk_backend kit ) `cuda` )
    : b rowwise & on_cuda >= ax 128
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname ? rowwise `lnormrow` `lnorm` )
    : s ct ( __gkd_ctr ax )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( _gkd_in cl `sc` sc y ) ( _gkd_in cl `bi` bi y ) ( gk_call_dev cl `Y` y )
    ( gk_call_i64 cl `outer` outer ) ( gk_call_i64 cl `ax` ax ) ( gk_call_f64 cl `eps` eps )
    : i dty . y dtype
    : String tag ( string_from ct )
    ? rowwise { ^ ( gk_run_checked_dev_tagged kit cl ( string_data kname ) ( string_data tag ) \ → String { ^ ( __gkd_lnorm_body tn sfx ct dty rowwise ) } outer 256 ) } {}
    ^ ( __gkd_run_t kit cl kname tag \ → String { ^ ( __gkd_lnorm_body tn sfx ct dty rowwise ) } outer )
}

@ __gkd_lnorm_body s tn s sfx s ct i dty b rowwise → String {
    : String ev ( __gkd_scal dty `eps` )
    : ~ String sums ( string_new )
    ( string_push_str sums tn ) ( string_push_str sums ` m = 0; for (` ) ( string_push_str sums ct ) ( string_push_str sums ` j = 0; j < LEN(p); j++) { m += LD(p, j); } m /= ax;
    ` ) ( string_push_str sums tn ) ( string_push_str sums ` v = 0; for (` ) ( string_push_str sums ct ) ( string_push_str sums ` j = 0; j < LEN(p); j++) { ` )
    ( string_push_str sums tn ) ( string_push_str sums ` d = LD(p, j) - m; v += d * d; } v /= ax;
    ` )
    : ~ String body ( string_new )
    ? rowwise {
        ( string_push_str body ? == dty GK_F32 `SHARED_F(st, 2);` `SHARED_D(st, 2);` )
        ( string_push_str body `
if (bid < outer) {
    WIN(p, X, bid * ax, ax);
    WIN(q, Y, bid * ax, ax);
    if (tid == 0) {
    ` ) ( string_push_str body ( string_data sums ) )
        ( string_push_str body `ST(st, 0, m); ST(st, 1, 1 / sqrt` ) ( string_push_str body sfx ) ( string_push_str body `(v + ` ) ( string_push_str body ( string_data ev ) ) ( string_push_str body `));
    }
    SYNC();
    ` ) ( string_push_str body tn ) ( string_push_str body ` m = LD(st, 0), inv = LD(st, 1);
    for (` ) ( string_push_str body ct ) ( string_push_str body ` j = tid; j < LEN(p) && j < LEN(q); j += bdim) { ST(q, j, (LD(p, j) - m) * inv * LD(sc, j) + LD(bi, j)); }
}` )
    } {
        // (the rewrite as one loop of one exit with every window whole —
        // a loop the host compiler vectorises, as it did the raw kernel's)
        ( string_push_str body `if (gid < outer) {
    WIN(p, X, gid * ax, ax);
    WIN(q, Y, gid * ax, ax);
    WIN(sw, sc, 0, ax);
    WIN(bw, bi, 0, ax);
    ` ) ( string_push_str body ( string_data sums ) )
        ( string_push_str body tn ) ( string_push_str body ` inv = 1 / sqrt` ) ( string_push_str body sfx ) ( string_push_str body `(v + ` ) ( string_push_str body ( string_data ev ) ) ( string_push_str body `);
    if (LEN(q) == ax && LEN(sw) == ax && LEN(bw) == ax && LEN(p) == ax) {
        for (` ) ( string_push_str body ct ) ( string_push_str body ` j = 0; j < ax; j++) { ST(q, j, (LD(p, j) - m) * inv * LD(sw, j) + LD(bw, j)); }
    }
}` )
    }
    ^ body
}

// ── Fused scaled-dot-product attention ────────────────────────────────
//
//   O[h,i,:] = softmax_j( scale * Q[h,i,:]·K[h,j,:] ) · V[h,j,:]
//
// Q is [heads, n, hd], K and V are [heads, nkv, hd], O is [heads, n, hd].
//
// The composed form — bmm, scale, softmax, bmm — has to MATERIALISE the
// [heads, n, nkv] score matrix, and that is the whole cost. For a
// streaming aggregator holding 72 frames of 783 tokens, one block's
// scores are 2.8 GB, written once by the first bmm, read and written
// four times by the softmax and read once more by the second bmm. The
// arithmetic is a rounding error next to the traffic, and the buffer
// alone bounds how long a sequence fits in memory.
//
// So the scores are never written. A block owns BQ queries, walks the
// keys in tiles, and keeps a running row maximum and denominator,
// rescaling its accumulator when the maximum moves — the online softmax
// of Milakov & Gimelshein, which is what FlashAttention and torch's own
// SDPA do. K and V are read once each; nothing of size n*nkv exists.
//
// **This is the one op in this file that is NOT bit-identical to its
// composed equivalent.** The sum over keys is blocked and rescaled
// rather than run left to right, so the low bits differ — as they do
// between torch's SDPA and its own naive path. It is the same value to
// within f32 rounding, and closer to the reference than the composed
// form is, but a golden taken with gkd_bmm + gkd_softmax_ax will not
// reproduce bit for bit.
//
// The kernel is a checked one: its tiles are shared arrays read through
// windows, the heads' rows through LD/ST on the bound buffers. It runs
// bit for bit the raw kernel it replaced, and as fast or faster.

// Shared-memory budget one attention block may take: a third of the
// 100 KB an Ada SM can carve out, so three blocks stay resident.
: i GKD_ATTN_SMEM 33792

// Whether gkd_attention will run for this head width on this backend —
// so a caller can decide, before it allocates, whether it needs the
// [heads, n, nkv] score buffer the composed fallback would want. At a
// 72-frame window of 783 tokens that buffer is 2.8 GB, and it is the
// difference between a long sequence fitting and not.
@ gkd_attention_ok GpuKit kit i hd → b {
    ? ( nurl_str_eq ( gk_backend kit ) `cuda` ) {} { ^ F }
    // The register tile is sized for exactly QT*DT = 16 accumulators per
    // thread, i.e. BQ*hd == 16*256; the call fails closed for any other
    // head width, and this predicate has to say so BEFORE a caller
    // decides it does not need the score buffer.
    ^ ( __gkd_attn_fits hd )
}

// Unmasked: every key is visible to every query.
@ gkd_attention GpuKit kit GkBuf o GkBuf q GkBuf k GkBuf v
i heads i n i nkv i hd f scale → b {
    ^ ( gkd_attention_masked kit o q k v ( gk_buf_none . o dtype ) heads n nkv hd 1 scale )
}

// With a per-key additive bias: `mask` holds (heads/hpb) rows of `nkv`
// floats, head h reading row h/hpb, and the bias is added to the score
// before the softmax — 0 keeps a key, -1e30 drops it. That is how a
// padded batch says "these positions are not there": the key never
// reaches the running maximum and contributes exactly zero to the
// denominator, so the row is the row it would have been without the
// padding. Pass a zero GkBuf (dptr 0) for `mask` to run unmasked — the
// kernel is then character-for-character the one gkd_attention has
// always generated, so nothing already compiled is invalidated.
@ gkd_attention_masked GpuKit kit GkBuf o GkBuf q GkBuf k GkBuf v GkBuf mask
i heads i n i nkv i hd i hpb f scale → b {
    ? & & ( __gkd_isfloat o ) ( gk_buf_ok q ) & ( gk_buf_ok k ) ( gk_buf_ok v ) {} { ^ F }
    ? & & == . o dtype . q dtype == . q dtype . k dtype == . k dtype . v dtype {} { ^ F }
    ? & & & > heads 0 > n 0 > nkv 0 > hd 0 {} { ^ F }
    : b masked ( gk_buf_ok mask )
    ? masked {
        ? & & > hpb 0 == % heads hpb 0 == . mask dtype . o dtype {} { ^ F }
        ? >= . mask n ( _gk_p2 / heads hpb nkv ) {} { ^ F }
    } {}
    ? & & == . q n * heads * n hd == . o n * heads * n hd
    & == . k n ( _gk_p3 heads nkv hd ) == . v n ( _gk_p3 heads nkv hd ) {} { ^ F }
    ^ ( __gkd_attn kit o q k v mask 1 heads n nkv hd hpb scale )
}

// The fused attention over a BATCH of sequences in the layout a
// transformer's linear layers actually produce: Q, K, V and O are
// [batch·n, heads·hd] — token rows, heads interleaved within the row —
// NOT the [heads, n, hd] gkd_attention wants. A caller running batch=1
// used two gkd_perm round trips per tensor per block to get in and out
// of head-major layout; a caller running a real batch would also need a
// 4-D permute whose dims gkd_perm bakes into the kernel name, i.e. an
// NVRTC compile per (batch, length) pair. This entry removes both: the
// kernel reads the interleaved layout directly (row stride heads·hd,
// head offset h·hd — the loads along `d` stay contiguous and coalesced
// exactly as before), and no permuted copy of Q/K/V/O ever exists.
//
// `mask` is one additive row of `nkv` floats PER BATCH ELEMENT
// ([batch, nkv]; 0 keeps a key, -1e30 drops it), or a zero GkBuf to run
// unmasked. Same tile, same online softmax, same accumulation order as
// gkd_attention_masked — a sequence embedded at batch b is bit-identical
// to the same sequence permuted through the head-major entry.
// gkd_attention_ok answers for this entry too (the tile constraint is
// the same).
@ gkd_attention_batch GpuKit kit GkBuf o GkBuf q GkBuf k GkBuf v GkBuf mask
i batch i heads i n i nkv i hd f scale → b {
    ? & & ( __gkd_isfloat o ) ( gk_buf_ok q ) & ( gk_buf_ok k ) ( gk_buf_ok v ) {} { ^ F }
    ? & & == . o dtype . q dtype == . q dtype . k dtype == . k dtype . v dtype {} { ^ F }
    ? & & & & > batch 0 > heads 0 > n 0 > nkv 0 > hd 0 {} { ^ F }
    : b masked ( gk_buf_ok mask )
    ? masked {
        ? & == . mask dtype . o dtype >= . mask n ( _gk_p2 batch nkv ) {} { ^ F }
    } {}
    ? & & == . q n * * * batch n heads hd == . o n * * * batch n heads hd
    & == . k n ( _gk_p4 batch nkv heads hd ) == . v n ( _gk_p4 batch nkv heads hd ) {} { ^ F }
    ^ ( __gkd_attn kit o q k v mask batch heads n nkv hd 0 scale )
}

// The key tile of a head width: what the shared-memory budget leaves
// after Qs[BQ][hd+1] once each key costs Ks, Vs rows and an S column.
// Sized for THREE resident blocks per SM, not for one block's 48 KB
// ceiling. Filling the ceiling is the obvious read of "how big a key
// tile fits", and it is the wrong one: at hd=64 it picks BK=32, which
// is 41 KB per block, and 41 KB lets only two blocks share an Ada
// SM's 100 KB — sixteen warps to hide the shared-memory latency of a
// kernel that is nothing but shared-memory traffic. A third of that
// budget picks BK=16 (29 KB, three blocks, 24 warps) and the same
// work runs measurably faster on both shapes an encoder produces:
// one 3072-token sequence 1862 -> 1689 us, sixteen 192-token ones
// 133 -> 122 us, on a 4090. The K/V tile is read once either way —
// only how much of it a block holds at a time changes.
@ __gkd_attn_bk i bq i hd i esz → i {
    : i fixed + * * bq + hd 1 esz * bq esz
    : i per * + * 2 + hd 1 bq esz
    : ~ i bk / - GKD_ATTN_SMEM fixed per
    = bk * / bk 16 16
    ? > bk 64 { = bk 64 } {}
    ? < bk 16 { = bk 16 } {}
    // (a power of two, and few enough key pairs that the score tile is
    // one pass of the block: the kernel masks its indices with both)
    ? == bk 48 { = bk 32 } {}
    ? > * / bq 4 / bk 2 256 { = bk / 2048 bq } {}
    ^ bk
}

// Both entries: `hpb` > 0 is the head-major layout (mask row h/hpb),
// 0 the batched one (`batch` sequences, mask row per sequence).
@ __gkd_attn GpuKit kit GkBuf o GkBuf q GkBuf k GkBuf v GkBuf mask
i batch i heads i n i nkv i hd i hpb f scale → b {
    // Only on CUDA: the CPU backend runs a block's threads as fibers,
    // and the composed path is the better shape there.
    ? ( nurl_str_eq ( gk_backend kit ) `cuda` ) {} { ^ F }
    // BQ is chosen so each thread owns exactly QT*DT = 16 accumulators
    // (BQ*hd / 256 threads), which is what the register tiles are sized
    // for: a head the 256 threads would not cover exactly is refused.
    ? ( __gkd_attn_fits hd ) {} { ^ F }
    : b masked ( gk_buf_ok mask )
    : b major > hpb 0
    : i esz ( gk_buf_esz o )
    : i bq ? <= hd 64 64 32
    : i bk ( __gkd_attn_bk bq hd esz )
    : i dt . o dtype
    : String kname ( __gkd_name dt )
    ( string_push_str kname ? major `attn` `attnx` )
    ( string_push_int kname hd )
    ( string_push_char kname 95 )
    ( string_push_int kname bk )
    ? masked { ( string_push_str kname `_m` ) } {}
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev_in c `Q` q )
    ( gk_call_dev_in c `K` k )
    ( gk_call_dev_in c `V` v )
    ( gk_call_dev c `O` o )
    ? masked { ( gk_call_dev_in c `M` mask ) } {}
    ( gk_call_i64 c `heads` heads )
    ( gk_call_i64 c `n` n )
    ( gk_call_i64 c `nkv` nkv )
    ? & masked major { ( gk_call_i64 c `hpb` hpb ) } {}
    ( gk_call_f64 c `scale` scale )
    : i nb * * batch heads ( _gkd_ceil n bq )
    ^ ( gk_run_checked_dev_tagged kit c ( string_data kname ) `` \ → String { ^ ( __gkd_attn_body dt bq hd bk masked major ) } nb 256 )
}

@ __gkd_attn_fits i hd → b {
    ? & > hd 0 == % hd 16 0 {} { ^ F }
    ^ == * ? <= hd 64 { 64 } { 32 } hd * 16 256
}

// The kernel: a block owns BQ queries of one head and walks the keys BK
// at a time — Q, K and V tiles in shared memory (+1 on every row so a
// column read walks distinct banks), the scaled scores into S, then the
// online softmax and the accumulator update. A thread's register tiles
// are written out: QT=4 queries by SK=2 keys of the score tile, QT=4
// queries by DT=4 channels of the output — four by four is eight shared
// reads per sixteen multiply-adds, which is what makes this arithmetic
// rather than a shared-memory queue.
//
// Every tile is read through a 2-D window, its row and column checked
// apart: the column is the loop's counter and the row a thread's own,
// masked to the tile (all the extents are powers of two), so the compiler
// sees both in range and no check is left in the loops.
@ __gkd_attn_body i dt i bq i hd i bk b masked b major → String {
    : s tn ( _gk_tname dt )
    : s sfx ( __gkd_sfx dt )
    : s neg ( __gkd_neg dt )
    : s sh ? == dt GK_F32 `SHARED_F(` `SHARED_D(`
    // (the rescale rounded on its own, as a loop over the keys leaves it:
    // with the loop unrolled the compiler would fuse it into the first
    // multiply-add, and the bits would change)
    : s mul ? == dt GK_F32 `__fmul_rn` `__dmul_rn`
    : i h1 + hd 1
    : i b1 + bk 1
    : i nk / bk 2
    : i nd / hd 4
    : ~ String b ( string_new )
    ( string_push_str b sh ) ( string_push_str b `qs, ` ) ( string_push_int b * bq h1 ) ( string_push_str b `);
` )
    ( string_push_str b sh ) ( string_push_str b `ks, ` ) ( string_push_int b * bk h1 ) ( string_push_str b `);
` )
    ( string_push_str b sh ) ( string_push_str b `vs, ` ) ( string_push_int b * bk h1 ) ( string_push_str b `);
` )
    ( string_push_str b sh ) ( string_push_str b `ss, ` ) ( string_push_int b * bq b1 ) ( string_push_str b `);
` )
    ( string_push_str b sh ) ( string_push_str b `ms, ` ) ( string_push_int b bq ) ( string_push_str b `);
` )
    ( string_push_str b sh ) ( string_push_str b `ls, ` ) ( string_push_int b bq ) ( string_push_str b `);
` )
    ( string_push_str b sh ) ( string_push_str b `cs, ` ) ( string_push_int b bq ) ( string_push_str b `);
` )
    ( __gkd_attn_tile b `qt` `qs` bq h1 hd )
    ( __gkd_attn_tile b `kt` `ks` bk h1 hd )
    ( __gkd_attn_tile b `vt` `vs` bk h1 hd )
    ( __gkd_attn_tile b `st` `ss` bq b1 bk )
    ( string_push_str b `long long nqb = (n + ` ) ( string_push_int b - bq 1 ) ( string_push_str b `) / ` ) ( string_push_int b bq )
    ( string_push_str b `;
long long hb = bid / nqb;
long long qb = (bid % nqb) * ` ) ( string_push_int b bq ) ( string_push_str b `;
` )
    // (a row of Q, K, V or O is `rs` elements from the next: the head's
    // own width head-major, the token's heads·hd interleaved)
    ? major {
        ( string_push_str b `long long h = hb;
long long rs = ` ) ( string_push_int b hd ) ( string_push_str b `;
long long qo = h * n * rs;
long long ko = h * nkv * rs;
` )
        ? masked { ( string_push_str b `long long mo = (h / hpb) * nkv;
` ) } {}
    } {
        ( string_push_str b `long long bi = hb / heads;
long long h = hb % heads;
long long rs = heads * ` ) ( string_push_int b hd ) ( string_push_str b `;
long long qo = bi * n * rs + h * ` ) ( string_push_int b hd ) ( string_push_str b `;
long long ko = bi * nkv * rs + h * ` ) ( string_push_int b hd ) ( string_push_str b `;
` )
        ? masked { ( string_push_str b `long long mo = bi * nkv;
` ) } {}
    }
    ( string_push_str b tn ) ( string_push_str b ` scl = (` ) ( string_push_str b tn ) ( string_push_str b `)scale;
for (int it = 0; it < ` ) ( string_push_int b / * bq hd 256 ) ( string_push_str b `; it++) {
    int idx = it * 256 + (int)tid;
    int i = idx / ` ) ( string_push_int b hd ) ( string_push_str b `;
    int d = idx & ` ) ( string_push_int b - hd 1 ) ( string_push_str b `;
    long long gq = qb + i;
    ST2(qt, i, d, (gq < n) ? LD(Q, qo + gq * rs + d) : 0);
}
` )
    // (thread tid owns queries ai0..ai0+3 by channels ad0..ad0+3 of the
    // output: BQ*hd/16 = 256 such blocks, one each)
    ( string_push_str b `int ai0 = (((int)tid / ` ) ( string_push_int b nd ) ( string_push_str b `) & ` ) ( string_push_int b - / bq 4 1 ) ( string_push_str b `) * 4;
int ad0 = ((int)tid & ` ) ( string_push_int b - nd 1 ) ( string_push_str b `) * 4;
` )
    : ~ i x 0
    ~ < x 16 {
        ( string_push_str b tn ) ( string_push_str b ` a` ) ( string_push_int b / x 4 ) ( string_push_int b % x 4 ) ( string_push_str b ` = 0;
` )
        = x + x 1
    }
    ( string_push_str b `if (tid < ` ) ( string_push_int b bq ) ( string_push_str b `) {
    int r = (int)tid & ` ) ( string_push_int b - bq 1 ) ( string_push_str b `;
    ST(ms, r, ` ) ( string_push_str b neg ) ( string_push_str b `);
    ST(ls, r, 0);
}
SYNC();
for (long long k0 = 0; k0 < nkv; k0 += ` ) ( string_push_int b bk ) ( string_push_str b `) {
    for (int it = 0; it < ` ) ( string_push_int b / * bk hd 256 ) ( string_push_str b `; it++) {
        int idx = it * 256 + (int)tid;
        int j = idx / ` ) ( string_push_int b hd ) ( string_push_str b `;
        int d = idx & ` ) ( string_push_int b - hd 1 ) ( string_push_str b `;
        long long gk = k0 + j;
        ST2(kt, j, d, (gk < nkv) ? LD(K, ko + gk * rs + d) : 0);
        ST2(vt, j, d, (gk < nkv) ? LD(V, ko + gk * rs + d) : 0);
    }
    SYNC();
    if (tid < ` ) ( string_push_int b * / bq 4 nk ) ( string_push_str b `) {
        int i0 = (((int)tid / ` ) ( string_push_int b nk ) ( string_push_str b `) & ` ) ( string_push_int b - / bq 4 1 ) ( string_push_str b `) * 4;
        int j0 = ((int)tid & ` ) ( string_push_int b - nk 1 ) ( string_push_str b `) * 2;
` )
    = x 0
    ~ < x 8 {
        ( string_push_str b `        ` ) ( string_push_str b tn ) ( string_push_str b ` s` ) ( string_push_int b / x 2 ) ( string_push_int b % x 2 ) ( string_push_str b ` = 0;
` )
        = x + x 1
    }
    ( string_push_str b `        UNROLL for (int d = 0; d < ` ) ( string_push_int b hd ) ( string_push_str b `; d++) {
` )
    = x 0
    ~ < x 4 {
        ( string_push_str b `            ` ) ( string_push_str b tn ) ( string_push_str b ` q` ) ( string_push_int b x ) ( string_push_str b ` = LD2(qt, i0 + ` ) ( string_push_int b x ) ( string_push_str b `, d);
` )
        = x + x 1
    }
    = x 0
    ~ < x 2 {
        ( string_push_str b `            ` ) ( string_push_str b tn ) ( string_push_str b ` kv` ) ( string_push_int b x ) ( string_push_str b ` = LD2(kt, j0 + ` ) ( string_push_int b x ) ( string_push_str b `, d);
` )
        = x + x 1
    }
    = x 0
    ~ < x 8 {
        ( string_push_str b `            s` ) ( string_push_int b / x 2 ) ( string_push_int b % x 2 ) ( string_push_str b ` += q` ) ( string_push_int b / x 2 ) ( string_push_str b ` * kv` ) ( string_push_int b % x 2 ) ( string_push_str b `;
` )
        = x + x 1
    }
    ( string_push_str b `        }
` )
    = x 0
    ~ < x 8 {
        : i qq / x 2
        : i tt % x 2
        ( string_push_str b `        ST2(st, i0 + ` ) ( string_push_int b qq ) ( string_push_str b `, j0 + ` ) ( string_push_int b tt )
        ( string_push_str b `, (k0 + j0 + ` ) ( string_push_int b tt ) ( string_push_str b ` < nkv) ? s` ) ( string_push_int b qq ) ( string_push_int b tt ) ( string_push_str b ` * scl` )
        ? masked { ( string_push_str b ` + LD(M, mo + k0 + j0 + ` ) ( string_push_int b tt ) ( string_push_str b `)` ) } {}
        ( string_push_str b ` : ` ) ( string_push_str b neg ) ( string_push_str b `);
` )
        = x + x 1
    }
    // online softmax bookkeeping, one thread per query row
    ( string_push_str b `    }
    SYNC();
    if (tid < ` ) ( string_push_int b bq ) ( string_push_str b `) {
        int r = (int)tid & ` ) ( string_push_int b - bq 1 ) ( string_push_str b `;
        ` ) ( string_push_str b tn ) ( string_push_str b ` m = LD(ms, r);
        ` ) ( string_push_str b tn ) ( string_push_str b ` l = LD(ls, r);
        ` ) ( string_push_str b tn ) ( string_push_str b ` mt = ` ) ( string_push_str b neg ) ( string_push_str b `;
        for (int j = 0; j < ` ) ( string_push_int b bk ) ( string_push_str b `; j++) { ` ) ( string_push_str b tn ) ( string_push_str b ` sv = LD2(st, r, j); if (sv > mt) { mt = sv; } }
        ` ) ( string_push_str b tn ) ( string_push_str b ` mn = (mt > m) ? mt : m;
        ` ) ( string_push_str b tn ) ( string_push_str b ` corr = exp` ) ( string_push_str b sfx ) ( string_push_str b `(m - mn);
        ` ) ( string_push_str b tn ) ( string_push_str b ` sum = 0;
        for (int j = 0; j < ` ) ( string_push_int b bk ) ( string_push_str b `; j++) { ` ) ( string_push_str b tn ) ( string_push_str b ` p = exp` ) ( string_push_str b sfx ) ( string_push_str b `(LD2(st, r, j) - mn); ST2(st, r, j, p); sum += p; }
        ST(ms, r, mn);
        ST(ls, r, l * corr + sum);
        ST(cs, r, corr);
    }
    SYNC();
` )
    // rescale what is accumulated, then add this tile's contribution
    = x 0
    ~ < x 4 {
        ( string_push_str b `    ` ) ( string_push_str b tn ) ( string_push_str b ` c` ) ( string_push_int b x ) ( string_push_str b ` = LD(cs, ai0 + ` ) ( string_push_int b x ) ( string_push_str b `);
` )
        : ~ i u 0
        ~ < u 4 {
            ( string_push_str b `    a` ) ( string_push_int b x ) ( string_push_int b u ) ( string_push_str b ` = ` ) ( string_push_str b mul ) ( string_push_str b `(a` ) ( string_push_int b x ) ( string_push_int b u ) ( string_push_str b `, c` ) ( string_push_int b x ) ( string_push_str b `);
` )
            = u + u 1
        }
        = x + x 1
    }
    ( string_push_str b `    UNROLL for (int j = 0; j < ` ) ( string_push_int b bk ) ( string_push_str b `; j++) {
` )
    = x 0
    ~ < x 4 {
        ( string_push_str b `        ` ) ( string_push_str b tn ) ( string_push_str b ` p` ) ( string_push_int b x ) ( string_push_str b ` = LD2(st, ai0 + ` ) ( string_push_int b x ) ( string_push_str b `, j);
` )
        = x + x 1
    }
    = x 0
    ~ < x 4 {
        ( string_push_str b `        ` ) ( string_push_str b tn ) ( string_push_str b ` v` ) ( string_push_int b x ) ( string_push_str b ` = LD2(vt, j, ad0 + ` ) ( string_push_int b x ) ( string_push_str b `);
` )
        = x + x 1
    }
    = x 0
    ~ < x 16 {
        ( string_push_str b `        a` ) ( string_push_int b / x 4 ) ( string_push_int b % x 4 ) ( string_push_str b ` += p` ) ( string_push_int b / x 4 ) ( string_push_str b ` * v` ) ( string_push_int b % x 4 ) ( string_push_str b `;
` )
        = x + x 1
    }
    ( string_push_str b `    }
    SYNC();
}
` )
    = x 0
    ~ < x 4 {
        ( string_push_str b `if (qb + ai0 + ` ) ( string_push_int b x ) ( string_push_str b ` < n) {
    ` ) ( string_push_str b tn ) ( string_push_str b ` li = LD(ls, ai0 + ` ) ( string_push_int b x ) ( string_push_str b `);
` )
        : ~ i u 0
        ~ < u 4 {
            ( string_push_str b `    ST(O, qo + (qb + ai0 + ` ) ( string_push_int b x ) ( string_push_str b `) * rs + ad0 + ` ) ( string_push_int b u ) ( string_push_str b `, a` ) ( string_push_int b x ) ( string_push_int b u ) ( string_push_str b ` / li);
` )
            = u + u 1
        }
        ( string_push_str b `}
` )
        = x + x 1
    }
    ^ b
}

// `WIN2(w, arr, 0, rows, stride, cols);` — a tile of shared array `arr`.
@ __gkd_attn_tile inout String b s w s arr i rows i stride i cols → v {
    ( string_push_str b `WIN2(` ) ( string_push_str b w ) ( string_push_str b `, ` ) ( string_push_str b arr ) ( string_push_str b `, 0, ` )
    ( string_push_int b rows ) ( string_push_str b `, ` ) ( string_push_int b stride ) ( string_push_str b `, ` ) ( string_push_int b cols ) ( string_push_str b `);
` )
}

// ── Softmax along an interior axis, viewed as (outer, ax, inner) ─────
// For each (outer, inner) pair the `ax` elements at stride `inner` form
// one distribution. Numerically stable (max-subtracted).

@ gkd_softmax_ax GpuKit kit GkBuf y GkBuf x i outer i ax i inner → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? & & > outer 0 > ax 0 > inner 0 {} { ^ F }
    ? & == . x n ( _gk_p3 outer ax inner ) == . y n ( _gk_p3 outer ax inner ) {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : s sfx ( __gkd_sfx . y dtype )
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `softmaxax` )
    : s ct ( __gkd_ctr ax )
    : i dty . y dtype
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( gk_call_dev cl `Y` y ) ( gk_call_i64 cl `outer` outer ) ( gk_call_i64 cl `ax` ax ) ( gk_call_i64 cl `inner` inner )
    ^ ( __gkd_run_t kit cl kname ( string_from ct ) \ → String {
        : ~ String body ( string_from `if (gid < outer * inner) {
    long long io = gid / inner, ii = gid % inner;
    long long base = io * ax * inner + ii;
    WINS(xc, X, base, ax, inner);
    WINS(yc, Y, base, ax, inner);
    ` )
        ( string_push_str body tn ) ( string_push_str body ` m = ` ) ( string_push_str body ( __gkd_neg dty ) )
        ( string_push_str body `;
    for (` ) ( string_push_str body ct ) ( string_push_str body ` a = 0; a < LEN(xc); a++) { ` ) ( string_push_str body tn )
        ( string_push_str body ` v = LD(xc, a); if (v > m) { m = v; } }
    ` ) ( string_push_str body tn ) ( string_push_str body ` s = 0;
    for (` ) ( string_push_str body ct ) ( string_push_str body ` a = 0; a < LEN(xc); a++) { s += exp` ) ( string_push_str body sfx )
        ( string_push_str body `(LD(xc, a) - m); }
    for (` ) ( string_push_str body ct ) ( string_push_str body ` a = 0; a < LEN(xc) && a < LEN(yc); a++) { ST(yc, a, exp` ) ( string_push_str body sfx )
        ( string_push_str body `(LD(xc, a) - m) / s); }
}` )
        ^ body
    } * outer inner )
}

// ── Axis data movement (any element type) ────────────────────────────

// Copy `src` into a concat output along an axis viewed as (outer, src_ax,
// inner); the slot starts at `off` in the output's axis of size dst_ax.
@ gkd_copy_ax GpuKit kit GkBuf dst GkBuf src i outer i src_ax i inner i dst_ax i off → b {
    ? & ( gk_buf_ok dst ) ( gk_buf_ok src ) {} { ^ F }
    ? == . dst dtype . src dtype {} { ^ F }
    ? & & > outer 0 > src_ax 0 > inner 0 {} { ^ F }
    ? & >= off 0 <= + off src_ax dst_ax {} { ^ F }
    ? & == . src n ( _gk_p3 outer src_ax inner ) == . dst n ( _gk_p3 outer dst_ax inner ) {} { ^ F }
    : String kname ( __gkd_name . dst dtype )
    ( string_push_str kname `copyax` )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `S` src dst ) ( gk_call_dev cl `D` dst )
    ( gk_call_i64 cl `outer` outer ) ( gk_call_i64 cl `src_ax` src_ax ) ( gk_call_i64 cl `inner` inner ) ( gk_call_i64 cl `dst_ax` dst_ax ) ( gk_call_i64 cl `off` off )
    ^ ( __gkd_run_t kit cl kname ( string_new ) \ → String {
        : String body ( string_from `if (gid < outer * src_ax * inner) {
    long long ii = gid % inner; long long t = gid / inner;
    long long a = t % src_ax; long long o = t / src_ax;
    ST(D, (o * dst_ax + (off + a)) * inner + ii, LD(S, gid));
}` )
        ^ body
    } * * outer src_ax inner )
}

// Extract a contiguous axis slice into a fresh tensor: viewing src as
// (outer, src_ax, inner), dst[o,a,i] = src[o, soff+a, i] for a in [0,sz).
@ gkd_slice_ax GpuKit kit GkBuf dst GkBuf src i outer i sz i inner i src_ax i soff → b {
    ? & ( gk_buf_ok dst ) ( gk_buf_ok src ) {} { ^ F }
    ? == . dst dtype . src dtype {} { ^ F }
    ? & & > outer 0 > sz 0 > inner 0 {} { ^ F }
    ? & >= soff 0 <= + soff sz src_ax {} { ^ F }
    ? & == . src n ( _gk_p3 outer src_ax inner ) == . dst n ( _gk_p3 outer sz inner ) {} { ^ F }
    : String kname ( __gkd_name . dst dtype )
    ( string_push_str kname `sliceax` )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `S` src dst ) ( gk_call_dev cl `D` dst )
    ( gk_call_i64 cl `outer` outer ) ( gk_call_i64 cl `sz` sz ) ( gk_call_i64 cl `inner` inner ) ( gk_call_i64 cl `src_ax` src_ax ) ( gk_call_i64 cl `soff` soff )
    ^ ( __gkd_run_t kit cl kname ( string_new ) \ → String {
        : String body ( string_from `if (gid < outer * sz * inner) {
    long long ii = gid % inner; long long t = gid / inner;
    long long a = t % sz; long long o = t / sz;
    ST(D, gid, LD(S, (o * src_ax + (soff + a)) * inner + ii));
}` )
        ^ body
    } * * outer sz inner )
}

// General N-D (≤6) transpose: output axis k reads input axis perm[k].
// `dims` are the INPUT dims; both vecs hold ndim (≤6) entries and perm
// must be a permutation of 0..ndim−1.
@ gkd_perm GpuKit kit GkBuf y GkBuf x ( Vec i ) dims ( Vec i ) perm → b {
    ? & ( gk_buf_ok y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    : i nd ( vec_len [i] dims )
    ? & & > nd 0 <= nd 6 == ( vec_len [i] perm ) nd {} { ^ F }
    : ~ i total 1
    : ~ b good T
    : ~ i k 0
    ~ < k nd {
        ? > ( _gk_vi dims k ) 0 {} { = good F }
        = total * total ( _gk_vi dims k )
        = k + k 1
    }
    // perm must hit each input axis exactly once
    = k 0
    ~ < k nd {
        : i want k
        : ~ i hits 0
        : ~ i j 0
        ~ < j nd { ? == ( _gk_vi perm j ) want { = hits + hits 1 } {} = j + j 1 }
        ? == hits 1 {} { = good F }
        = k + k 1
    }
    ? good {} { ^ F }
    ? & == . x n total == . y n total {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    // Shape-specialised body. The generic one decomposes the output
    // index with six 64-bit divisions and modulos per element and holds
    // D/P/O/oc/in in dynamically indexed local arrays, which live in
    // LOCAL memory — a permute of 9 MB was running at a fourteenth of
    // the bandwidth it should. The source is generated per call anyway,
    // so the dims and the permutation go in as literals: the divisions
    // become multiply-shifts, the loops unroll, and every intermediate
    // is a register. Only for tensors big enough to be worth a compile;
    // the kernel name carries the shape, so each distinct one is
    // compiled and cached once (and the on-disk kernel cache makes that
    // once per machine, not once per process).
    // A static / WebGPU build links a fixed kernel set by name, which a
    // per-shape name can never be in: specialise only where kernels are
    // compiled at run time (gk_jit).
    : b lit & ( gk_jit kit ) >= total 65536
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `perm6` )
    ? lit {
        : ~ i q 0
        ~ < q 6 {
            ( string_push_char kname 95 )
            ( string_push_int kname ? < q nd { ( _gk_vi dims q ) } { 1 } )
            = q + q 1
        }
        = q 0
        ~ < q 6 {
            ( string_push_char kname 95 )
            ( string_push_int kname ? < q nd { ( _gk_vi perm q ) } { q } )
            = q + q 1
        }
    } {}
    : ~ String body ( string_new )
    ? lit {
        // the dims and the permutation as literals: the divisions become
        // multiply-shifts and every intermediate a register
        : ~ i q 0
        ~ < q 6 {
            ( string_push_str body `long long O` ) ( string_push_int body q ) ( string_push_str body ` = ` )
            ( string_push_int body ? < q nd { ( _gk_vi dims ( _gk_vi perm q ) ) } { 1 } )
            ( string_push_str body `; ` )
            = q + q 1
        }
        ( string_push_str body `
if (gid < O0 * O1 * O2 * O3 * O4 * O5) {
    long long t = gid;
    long long c5 = t % O5; t /= O5; long long c4 = t % O4; t /= O4;
    long long c3 = t % O3; t /= O3; long long c2 = t % O2; t /= O2;
    long long c1 = t % O1; long long c0 = t / O1;
    long long si = ` )
        // ((((c_a0*D1+c_a1)*D2+c_a2)*D3+c_a3)*D4+c_a4)*D5+c_a5, c_aq the
        // output coordinate of the axis that permutes to input axis q
        ( string_push_str body `((((` )
        = q 0
        ~ < q 6 {
            : ~ i which 0
            : ~ i j2 0
            ~ < j2 6 {
                : i pv ? < j2 nd { ( _gk_vi perm j2 ) } { j2 }
                ? == pv q { = which j2 } {}
                = j2 + j2 1
            }
            ? > q 0 {
                ( string_push_str body ` * ` ) ( string_push_int body ? < q nd { ( _gk_vi dims q ) } { 1 } ) ( string_push_str body ` + ` )
            } {}
            ( string_push_str body `c` ) ( string_push_int body which )
            ? & > q 0 < q 5 { ( string_push_char body 41 ) } {}
            = q + q 1
        }
        ( string_push_str body `;
    ST(Y, gid, LD(X, si));
}` )
    } {
        ( string_push_str body `LOCAL_L(D, 6);
LOCAL_L(P, 6);
LOCAL_L(O, 6);
LOCAL_L(oc, 6);
LOCAL_L(inn, 6);
ST(D, 0, d0); ST(D, 1, d1); ST(D, 2, d2); ST(D, 3, d3); ST(D, 4, d4); ST(D, 5, d5);
ST(P, 0, p0); ST(P, 1, p1); ST(P, 2, p2); ST(P, 3, p3); ST(P, 4, p4); ST(P, 5, p5);
for (int i = 0; i < 6; i++) { ST(O, i, LD(D, LD(P, i))); }
long long tot = LD(O, 0) * LD(O, 1) * LD(O, 2) * LD(O, 3) * LD(O, 4) * LD(O, 5);
if (gid < tot) {
    long long t = gid;
    for (int i = 5; i >= 0; i--) { ST(oc, i, t % LD(O, i)); t /= LD(O, i); }
    for (int i = 0; i < 6; i++) { ST(inn, LD(P, i), LD(oc, i)); }
    long long si = ((((LD(inn, 0) * d1 + LD(inn, 1)) * d2 + LD(inn, 2)) * d3 + LD(inn, 3)) * d4 + LD(inn, 4)) * d5 + LD(inn, 5);
    ST(Y, gid, LD(X, si));
}` )
    }
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( gk_call_dev cl `Y` y )
    ? lit {} {
        // input dims padded to 6 with trailing 1s, perm with the identity
        = k 0
        ~ < k 6 {
            ( _gkd_dim_arg cl `d` k ? < k nd { ( _gk_vi dims k ) } { 1 } )
            ( _gkd_dim_arg cl `p` k ? < k nd { ( _gk_vi perm k ) } { k } )
            = k + k 1
        }
        // (the generic body is one text: launched by tag, not rebuilt)
        ^ ( __gkd_run_t kit cl kname ( string_new ) \ → String { ^ ( string_from ( string_data body ) ) } total )
    }
    ^ ( __gkd_run kit cl kname body total )
}

// Nearest-neighbour upsample by integer factors (NCHW):
// Y[c,oy,ox] = X[c, oy/sh, ox/sw].
// ── Bilinear resize, NCHW (batch folded into C) ──────────────────────
//
// The resampler every decoder upsamples with, and the one
// `gkd_resize_nn` is not. `align` picks the coordinate convention, and
// the two are NOT interchangeable:
//
//   align_corners=1 : src = dst · (in−1)/(out−1)   endpoints pinned
//   align_corners=0 : src = (dst + 0.5)·in/out − 0.5, clamped
//
// A single output pixel (out == 1) maps to src 0 under align_corners,
// which is what torch does rather than dividing by zero.
//
// Edge taps are clamped, so a coordinate that lands on the last row or
// column interpolates with itself rather than reading past the end.
@ gkd_resize_bilinear GpuKit kit GkBuf y GkBuf x i c i h i wd i oh i ow i align → b {
    ? & ( gk_buf_ok y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? ( __gkd_isfloat y ) {} { ^ F }
    ? & & & > c 0 > h 0 > wd 0 & > oh 0 > ow 0 {} { ^ F }
    ? & == . x n ( _gk_p3 c h wd ) == . y n ( _gk_p3 c oh ow ) {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname ? != align 0 `ac` `` )
    ( string_push_str kname `resizebilin` )
    : i dty . y dtype
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( gk_call_dev cl `Y` y )
    ( gk_call_i64 cl `C` c ) ( gk_call_i64 cl `H` h ) ( gk_call_i64 cl `W` wd ) ( gk_call_i64 cl `OH` oh ) ( gk_call_i64 cl `OW` ow ) ( gk_call_i64 cl `align` align )
    ^ ( __gkd_run_t kit cl kname ( string_new ) \ → String {
        : ~ String body ( string_from `if (gid < C * OH * OW) {
    long long ox = gid % OW, oy = (gid / OW) % OH, c = gid / (OW * OH);
    double fy, fx;
    if (align) { fy = (OH > 1) ? ((double)oy * (double)(H - 1) / (double)(OH - 1)) : 0.0;
        fx = (OW > 1) ? ((double)ox * (double)(W - 1) / (double)(OW - 1)) : 0.0; }
    else { fy = ((double)oy + 0.5) * (double)H / (double)OH - 0.5; if (fy < 0) { fy = 0; }
        fx = ((double)ox + 0.5) * (double)W / (double)OW - 0.5; if (fx < 0) { fx = 0; } }
    long long y0 = (long long)fy; if (y0 > H - 1) { y0 = H - 1; } long long y1 = (y0 + 1 < H) ? (y0 + 1) : (H - 1);
    long long x0 = (long long)fx; if (x0 > W - 1) { x0 = W - 1; } long long x1 = (x0 + 1 < W) ? (x0 + 1) : (W - 1);
    double wy = fy - (double)y0, wx = fx - (double)x0;
    long long p = c * H * W;
    double v00 = (double)LD(X, p + y0 * W + x0), v01 = (double)LD(X, p + y0 * W + x1);
    double v10 = (double)LD(X, p + y1 * W + x0), v11 = (double)LD(X, p + y1 * W + x1);
    double top = v00 + (v01 - v00) * wx, bot = v10 + (v11 - v10) * wx;
    ST(Y, gid, (` )
        ( string_push_str body tn ) ( string_push_str body `)(top + (bot - top) * wy));
}` )
        ^ body
    } * * c oh ow )
}

@ gkd_resize_nn GpuKit kit GkBuf y GkBuf x i c i h i wd i oh i ow i sh i sw → b {
    ? & ( gk_buf_ok y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? & & & > c 0 > h 0 > wd 0 & > oh 0 > ow 0 {} { ^ F }
    ? & > sh 0 > sw 0 {} { ^ F }
    ? & <= oh ( _gk_p2 h sh ) <= ow ( _gk_p2 wd sw ) {} { ^ F }
    ? & == . x n ( _gk_p3 c h wd ) == . y n ( _gk_p3 c oh ow ) {} { ^ F }
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `resizenn` )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( gk_call_dev cl `Y` y )
    ( gk_call_i64 cl `C` c ) ( gk_call_i64 cl `H` h ) ( gk_call_i64 cl `W` wd ) ( gk_call_i64 cl `OH` oh ) ( gk_call_i64 cl `OW` ow ) ( gk_call_i64 cl `sh` sh ) ( gk_call_i64 cl `sw` sw )
    ^ ( __gkd_run_t kit cl kname ( string_new ) \ → String {
        : String body ( string_from `if (gid < C * OH * OW) {
    long long ox = gid % OW, oy = (gid / OW) % OH, c = gid / (OW * OH);
    ST(Y, gid, LD(X, (c * H + oy / sh) * W + ox / sw));
}` )
        ^ body
    } * * c oh ow )
}

// Expand the last axis: input (outer,1) → (outer,rep), Y[o,r] = X[o].
@ gkd_expandlast GpuKit kit GkBuf y GkBuf x i outer i rep → b {
    ? & ( gk_buf_ok y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? & > outer 0 > rep 0 {} { ^ F }
    ? & == . x n outer == . y n ( _gk_p2 outer rep ) {} { ^ F }
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `expandl` )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( gk_call_dev cl `Y` y ) ( gk_call_i64 cl `outer` outer ) ( gk_call_i64 cl `rep` rep )
    ^ ( __gkd_run_t kit cl kname ( string_new ) \ → String {
        : String body ( string_from `if (gid < outer * rep) { ST(Y, gid, LD(X, gid / rep)); }` )
        ^ body
    } * outer rep )
}

// ── Reductions / index selection ─────────────────────────────────────

// L2 norm along the last axis: input (outer, ax) → output (outer).
@ gkd_reducel2 GpuKit kit GkBuf y GkBuf x i outer i ax → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? & > outer 0 > ax 0 {} { ^ F }
    ? & == . x n ( _gk_p2 outer ax ) == . y n outer {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `rl2` )
    : i dty . y dtype
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( gk_call_dev cl `Y` y ) ( gk_call_i64 cl `outer` outer ) ( gk_call_i64 cl `ax` ax )
    ^ ( __gkd_run_t kit cl kname ( string_from ( __gkd_ctr ax ) ) \ → String {
        : ~ String body ( string_from `if (gid < outer) { WIN(p, X, gid * ax, ax); ` )
        ( string_push_str body tn ) ( string_push_str body ` s = 0; for (` ) ( string_push_str body ( __gkd_ctr ax ) )
        ( string_push_str body ` a = 0; a < LEN(p); a++) { s += LD(p, a) * LD(p, a); } ST(Y, gid, sqrt` )
        ( string_push_str body ( __gkd_sfx dty ) ) ( string_push_str body `(s)); }` )
        ^ body
    } outer )
}

// ArgMax along the last axis: input (outer, ax) in any element type →
// GK_I64 indices (outer). Ties resolve to the first maximum.
@ gkd_argmax GpuKit kit GkBuf y GkBuf x i outer i ax → b {
    ? & & ( gk_buf_ok y ) ( gk_buf_ok x ) == . y dtype GK_I64 {} { ^ F }
    ? & > outer 0 > ax 0 {} { ^ F }
    ? & == . x n ( _gk_p2 outer ax ) == . y n outer {} { ^ F }
    : s tn ( _gk_tname . x dtype )
    : String kname ( __gkd_name . x dtype )
    ( string_push_str kname `argmax` )
    : i dtx . x dtype
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `X` x y ) ( gk_call_dev cl `Y` y ) ( gk_call_i64 cl `outer` outer ) ( gk_call_i64 cl `ax` ax )
    ^ ( __gkd_run_t kit cl kname ( string_from ( __gkd_ctr ax ) ) \ → String {
        : ~ String body ( string_from `if (gid < outer) { WIN(p, X, gid * ax, ax); long long bi = 0; ` )
        ( string_push_str body tn ) ( string_push_str body ` bv = LD(p, 0); for (` ) ( string_push_str body ( __gkd_ctr ax ) )
        ( string_push_str body ` j = 1; j < LEN(p); j++) { if (LD(p, j) > bv) { bv = LD(p, j); bi = j; } } ST(Y, gid, bi); }` )
        ^ body
    } outer )
}

// EOS read-out (CLIP): given per-row token ids `tok` [B,L] (GK_I64) and
// features `data` [B,L,D], select each row's max-id token's features →
// Y [B,D]. One thread per output element.
@ gkd_eos_gather GpuKit kit GkBuf y GkBuf data GkBuf tok i bsz i l i d → b {
    ? & & & ( __gkd_isfloat y ) ( gk_buf_ok data ) ( gk_buf_ok tok ) == . tok dtype GK_I64 {} { ^ F }
    ? == . y dtype . data dtype {} { ^ F }
    ? & & > bsz 0 > l 0 > d 0 {} { ^ F }
    ? & & == . data n ( _gk_p3 bsz l d ) == . y n ( _gk_p2 bsz d ) >= . tok n ( _gk_p2 bsz l ) {} { ^ F }
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `eosg` )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `data` data y ) ( _gkd_in cl `tok` tok y ) ( gk_call_dev cl `Y` y )
    ( gk_call_i64 cl `B` bsz ) ( gk_call_i64 cl `L` l ) ( gk_call_i64 cl `D` d )
    ^ ( __gkd_run_t kit cl kname ( string_from ( __gkd_ctr l ) ) \ → String {
        : ~ String body ( string_from `if (gid < B * D) { long long d = gid % D; long long b = gid / D; WIN(t, tok, b * L, L); long long pos = 0; long long mx = LD(t, 0); for (` )
        ( string_push_str body ( __gkd_ctr l ) )
        ( string_push_str body ` j = 1; j < LEN(t); j++) { if (LD(t, j) > mx) { mx = LD(t, j); pos = j; } } ST(Y, gid, LD(data, (b * L + pos) * D + d)); }` )
        ^ body
    } * bsz d )
}

// ── Rotary position embedding over 2 and 3 axes ───────────────────
//
// `x` is [heads, n, dim] f32, rotated in place by per-token positions
// (i64) into cos/sin tables (f32). gkd_rope2d: the first half of each
// head's vector by position `rows`, the second half by `cols`, each half
// split into (j, j+quarter) pairs. gkd_rope3d: interleaved pairs (x0,x1),
// (x2,x3), …; frequency j < na takes `fr`'s position, j < na+nb `rw`'s,
// the rest `cl`'s. Every buffer's size and dtype is checked against the
// launch, and a position past the tables (or negative) leaves its pair
// untouched. One thread per pair, each owning it: the in-place
// read-then-write needs no barrier.

@ gkd_rope2d GpuKit kit GkBuf x GkBuf rows GkBuf cols GkBuf cosb GkBuf sinb
i heads i n i dim → b {
    ? & & ( gk_buf_ok x ) ( gk_buf_ok rows ) ( gk_buf_ok cols ) {} { ^ F }
    ? & ( gk_buf_ok cosb ) ( gk_buf_ok sinb ) {} { ^ F }
    ? & & > heads 0 > n 0 & > dim 0 == % dim 4 0 {} { ^ F }
    ? == . x n ( _gk_p3 heads n dim ) {} { ^ F }
    // The positions are read per token, and index the tables: both sizes
    // are checked here, and a position past the tables is skipped in the
    // kernel (tl, the shorter table's length).
    ? & & == . x dtype GK_F32 == . rows dtype GK_I64 == . cols dtype GK_I64 {} { ^ F }
    ? & & >= . rows n n >= . cols n n & == . cosb dtype GK_F32 == . sinb dtype GK_F32 {} { ^ F }
    : i tl ? < . cosb n . sinb n . cosb n . sinb n
    : ~ GkCall cl ( gk_call_new )
    ( gk_call_dev cl `X` x ) ( _gkd_in cl `rows` rows x ) ( _gkd_in cl `cols` cols x ) ( _gkd_in cl `cosT` cosb x ) ( _gkd_in cl `sinT` sinb x )
    ( gk_call_i64 cl `heads` heads ) ( gk_call_i64 cl `n` n ) ( gk_call_i64 cl `dim` dim ) ( gk_call_i64 cl `tl` tl )
    : i tot * heads * n / dim 2
    ^ ( __gkd_run_t kit cl ( string_from `gkd_rope2d` ) ( string_new ) \ → String {
        : String body ( string_from `long long half = dim / 2, quarter = half / 2;
long long tot = heads * n * quarter * 2;
if (gid < tot) {
    long long j = gid % quarter; long long r = gid / quarter;
    long long axis = r % 2; r /= 2;
    long long t = r % n; long long h = r / n;
    long long base = h * n * dim + t * dim + axis * half;
    long long pos = (axis == 0) ? LD(rows, t) : LD(cols, t);
    long long tbl = pos * half;
    if (pos >= 0 && tbl + half <= tl) {
        float x1 = LD(X, base + j), x2 = LD(X, base + j + quarter);
        ST(X, base + j, x1 * LD(cosT, tbl + j) - x2 * LD(sinT, tbl + j));
        ST(X, base + j + quarter, x2 * LD(cosT, tbl + j + quarter) + x1 * LD(sinT, tbl + j + quarter));
    }
}` )
        ^ body
    } tot )
}

@ gkd_rope3d GpuKit kit GkBuf x GkBuf fr GkBuf rw GkBuf cl GkBuf cosb GkBuf sinb
i heads i n i dim i nt i nh → b {
    ? & & ( gk_buf_ok x ) ( gk_buf_ok fr ) ( gk_buf_ok rw ) {} { ^ F }
    ? & & ( gk_buf_ok cl ) ( gk_buf_ok cosb ) ( gk_buf_ok sinb ) {} { ^ F }
    ? & & > heads 0 > n 0 & > dim 0 == % dim 2 0 {} { ^ F }
    ? == . x n ( _gk_p3 heads n dim ) {} { ^ F }
    // Positions and tables checked as in gkd_rope2d.
    ? & & == . x dtype GK_F32 == . fr dtype GK_I64 & == . rw dtype GK_I64 == . cl dtype GK_I64 {} { ^ F }
    ? & & >= . fr n n >= . rw n n & >= . cl n n & == . cosb dtype GK_F32 == . sinb dtype GK_F32 {} { ^ F }
    : i tl ? < . cosb n . sinb n . cosb n . sinb n
    : ~ GkCall cl2 ( gk_call_new )
    ( gk_call_dev cl2 `X` x ) ( _gkd_in cl2 `fr` fr x ) ( _gkd_in cl2 `rw` rw x ) ( _gkd_in cl2 `cl` cl x ) ( _gkd_in cl2 `cosT` cosb x ) ( _gkd_in cl2 `sinT` sinb x )
    ( gk_call_i64 cl2 `heads` heads ) ( gk_call_i64 cl2 `n` n ) ( gk_call_i64 cl2 `dim` dim ) ( gk_call_i64 cl2 `nt` nt ) ( gk_call_i64 cl2 `nh` nh ) ( gk_call_i64 cl2 `tl` tl )
    : i tot * heads * n / dim 2
    ^ ( __gkd_run_t kit cl2 ( string_from `gkd_rope3d` ) ( string_new ) \ → String {
        : String body ( string_from `long long width = dim / 2;
long long tot = heads * n * width;
if (gid < tot) {
    long long j = gid % width; long long r = gid / width;
    long long t = r % n; long long h = r / n;
    long long pos = (j < nt) ? LD(fr, t) : ((j < nt + nh) ? LD(rw, t) : LD(cl, t));
    long long tbl = pos * width + j;
    if (pos >= 0 && tbl < tl) {
        long long base = h * n * dim + t * dim + 2 * j;
        float c = LD(cosT, tbl), s = LD(sinT, tbl);
        float x1 = LD(X, base), x2 = LD(X, base + 1);
        ST(X, base, x1 * c - x2 * s); ST(X, base + 1, x1 * s + x2 * c);
    }
}` )
        ^ body
    } tot )
}
