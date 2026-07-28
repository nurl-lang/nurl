// packages/map-anything/src/devblock.nu — the transformer block on the
// device, in f32.
//
// MapAnything is built from ONE block shape, used 40 times: prenorm
// LayerNorm (eps 1e-6), biased qkv, SDPA attention, biased proj,
// LayerScale, then a SwiGLU MLP (w12 → chunk 2 → silu(x1)·x2 → w3),
// LayerScale again. The DINOv2-giant encoder's 24 blocks and the
// alternating-attention info_sharing's 16 blocks differ only in their
// weights and in which tokens they are run over — no RoPE, no qk-norm,
// no KV cache anywhere, which is why this file is so much smaller than
// lingbot-map's devblock.nu, its direct ancestor.
//
// Everything is composed from gpukit's `gkd_*` ops — gemm, layernorm,
// bmm, softmax, permute, slice, broadcast-elementwise — so the same
// code runs on CUDA and on the CPU backend.
//
// Weight layouts are torch's, transposed at load time: a Linear weight
// is [out, in] and is uploaded [in, out] (see load.nu), so every
// gkd_gemm here runs transb=0 and the CPU backend takes its
// register-tiled kernel.
//
//   ( ma_ws_new kit n dim heads swh )       → MaWs
//   ( ma_ws_free ws )                       → v
//   ( ma_blk_free w )                       → v
//   ( ma_block_forward kit w ws x n dim heads swh ) → b   x updated

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`

// One block's parameters, resident on the device.
: MaBlk {
    GkBuf n1g GkBuf n1b
    GkBuf qkvw GkBuf qkvb
    GkBuf pw GkBuf pb
    GkBuf ls1
    GkBuf n2g GkBuf n2b
    GkBuf w12w GkBuf w12b  // [dim, 2·swh] on device (transposed)
    GkBuf w3w GkBuf w3b  // [swh, dim] on device (transposed)
    GkBuf ls2
    f eps
}

@ ma_blk_free MaBlk w → v {
    ( gk_dbuf_free . w n1g ) ( gk_dbuf_free . w n1b )
    ( gk_dbuf_free . w qkvw ) ( gk_dbuf_free . w qkvb )
    ( gk_dbuf_free . w pw ) ( gk_dbuf_free . w pb )
    ( gk_dbuf_free . w ls1 )
    ( gk_dbuf_free . w n2g ) ( gk_dbuf_free . w n2b )
    ( gk_dbuf_free . w w12w ) ( gk_dbuf_free . w w12b )
    ( gk_dbuf_free . w w3w ) ( gk_dbuf_free . w w3b )
    ( gk_dbuf_free . w ls2 )
}

// Scratch, sized once for the largest token run the model will see.
: MaWs {
    GkBuf norm
    GkBuf qkv
    GkBuf qkvp
    GkBuf kt
    GkBuf att
    GkBuf ctx
    GkBuf ctxp
    GkBuf branch
    GkBuf hid  // [n, 2·swh]
    GkBuf sw1  // [n, swh]
    GkBuf sw2
    GkBuf scal
    i maxn
}

@ ma_ws_new * GpuKit kit i n i dim i heads i swh → MaWs {
    : i hd / dim heads
    // `att` and `kt` exist only for the composed attention fallback; on
    // a backend where gkd_attention runs, nothing writes a score matrix.
    : b fused ( gkd_attention_ok kit hd )
    : i attn ? fused 1 * heads * n n
    : i ktn ? fused 1 * heads * n hd
    ^ @ MaWs {
        ( gk_dbuf_new kit * n dim GK_F32 )
        ( gk_dbuf_new kit * n * 3 dim GK_F32 )
        ( gk_dbuf_new kit * n * 3 dim GK_F32 )
        ( gk_dbuf_new kit ktn GK_F32 )
        ( gk_dbuf_new kit attn GK_F32 )
        ( gk_dbuf_new kit * n dim GK_F32 )
        ( gk_dbuf_new kit * n dim GK_F32 )
        ( gk_dbuf_new kit * n dim GK_F32 )
        ( gk_dbuf_new kit * n * 2 swh GK_F32 )
        ( gk_dbuf_new kit * n swh GK_F32 )
        ( gk_dbuf_new kit * n swh GK_F32 )
        ( gk_dbuf_new kit 1 GK_F32 )
        n }
}

@ ma_ws_free MaWs ws → v {
    ( gk_dbuf_free . ws norm ) ( gk_dbuf_free . ws qkv )
    ( gk_dbuf_free . ws qkvp ) ( gk_dbuf_free . ws kt )
    ( gk_dbuf_free . ws att ) ( gk_dbuf_free . ws ctx )
    ( gk_dbuf_free . ws ctxp ) ( gk_dbuf_free . ws branch )
    ( gk_dbuf_free . ws hid ) ( gk_dbuf_free . ws sw1 )
    ( gk_dbuf_free . ws sw2 ) ( gk_dbuf_free . ws scal )
}

// ── helpers ─────────────────────────────────────────────────────────

@ _ma_i2 i a i b → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 2 )
    ( vec_push [i] v a ) ( vec_push [i] v b )
    ^ v
}

@ _ma_i3 i a i b i c → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 3 )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c )
    ^ v
}

@ _ma_i4 i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 4 )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d )
    ^ v
}

// A view of `b`'s elements [off, off+len) as its own GkBuf. The device
// pointer is byte-addressed, so a sub-range is just an offset — no copy,
// and nothing to free (the parent owns the allocation).
@ ma_view GkBuf b i off i len → GkBuf {
    ^ @ GkBuf { + . b dptr * off ( gk_buf_esz b ) len . b dtype }
}

// y[rows, cols] += ls[cols] * b[rows, cols], the LayerScale residual.
@ __ma_res * GpuKit kit GkBuf y GkBuf b GkBuf ls GkBuf tmp i rows i cols → b {
    : ( Vec i ) od ( _ma_i2 rows cols )
    : ( Vec i ) as ( _ma_i2 cols 1 )
    : ( Vec i ) bs ( _ma_i2 0 1 )
    : b ok1 ( gkd_ew_bc kit `mul` `*` tmp b ls od as bs )
    ( vec_free [i] od ) ( vec_free [i] as ) ( vec_free [i] bs )
    ? ok1 {} { ^ F }
    ^ ( gkd_add kit y y tmp )
}

// ── the block ───────────────────────────────────────────────────────

// Transformer block over `n` tokens; `x` is [n, dim], updated in place.
// `swh` is the SwiGLU hidden width (4096 for every block in this model;
// w12 produces 2·swh and w3 consumes swh).
@ ma_block_forward * GpuKit kit MaBlk w MaWs ws GkBuf x
i n i dim i heads i swh → b {
    : i hd / dim heads
    : i nd * n dim

    // The workspace is sized once for the LARGEST run; this call may be
    // smaller. Every gkd_* op validates exact element counts, so what
    // goes in is a view cut to this call's n.
    : GkBuf norm ( ma_view . ws norm 0 nd )
    : GkBuf qkv ( ma_view . ws qkv 0 * 3 nd )
    : GkBuf qkvp ( ma_view . ws qkvp 0 * 3 nd )
    : GkBuf ctx ( ma_view . ws ctx 0 nd )
    : GkBuf ctxp ( ma_view . ws ctxp 0 nd )
    : GkBuf branch ( ma_view . ws branch 0 nd )
    : GkBuf hid ( ma_view . ws hid 0 * n * 2 swh )
    : GkBuf sw1 ( ma_view . ws sw1 0 * n swh )
    : GkBuf sw2 ( ma_view . ws sw2 0 * n swh )

    // ── attention branch ──
    ? ( gkd_layernorm kit norm x . w n1g . w n1b n dim . w eps ) {} { ^ F }
    ? ( gkd_gemm kit qkv norm . w qkvw . w qkvb 1 n * 3 dim dim 1.0 1.0 0 ) {} { ^ F }
    // [n, 3, heads, hd] → [3, heads, n, hd]
    : ( Vec i ) qd ( _ma_i4 n 3 heads hd )
    : ( Vec i ) qp ( _ma_i4 1 2 0 3 )
    : b okp ( gkd_perm kit qkvp qkv qd qp )
    ( vec_free [i] qd ) ( vec_free [i] qp )
    ? okp {} { ^ F }
    : GkBuf q ( ma_view qkvp 0 nd )
    : GkBuf k ( ma_view qkvp nd nd )
    : GkBuf v ( ma_view qkvp * 2 nd nd )
    // scores = q · kᵀ / sqrt(hd), softmax, · v. The 1/sqrt(hd) goes on
    // the SCORES, where torch's SDPA puts it.
    : f scale / 1.0 ( float_sqrt # f hd )
    ? ( gkd_attention kit ctx q k v heads n n hd scale ) {} {
        ? >= ( gk_buf_len . ws att ) * heads * n n {} { ^ F }
        ? >= ( gk_buf_len . ws kt ) * heads * n hd {} { ^ F }
        : GkBuf kt ( ma_view . ws kt 0 * heads * n hd )
        : ( Vec i ) kd ( _ma_i3 heads n hd )
        : ( Vec i ) kp ( _ma_i3 0 2 1 )
        : b okk ( gkd_perm kit kt k kd kp )
        ( vec_free [i] kd ) ( vec_free [i] kp )
        ? okk {} { ^ F }
        : GkBuf att ( ma_view . ws att 0 * heads * n n )
        ? ( gkd_bmm kit att q kt heads n hd n 1 1 ) {} { ^ F }
        : ( Vec f ) sv ( vec_with_cap [f] 1 )
        ( vec_push [f] sv scale )
        : b oks ( gk_dbuf_upload kit . ws scal sv )
        ( vec_free [f] sv )
        ? oks {} { ^ F }
        ? ( gkd_ew kit `mul` `*` att att . ws scal ) {} { ^ F }
        ? ( gkd_softmax_ax kit att att * heads n n 1 ) {} { ^ F }
        ? ( gkd_bmm kit ctx att v heads n n hd 1 1 ) {} { ^ F }
    }
    // [heads, n, hd] → [n, heads·hd]
    : ( Vec i ) cd ( _ma_i3 heads n hd )
    : ( Vec i ) cp ( _ma_i3 1 0 2 )
    : b okc ( gkd_perm kit ctxp ctx cd cp )
    ( vec_free [i] cd ) ( vec_free [i] cp )
    ? okc {} { ^ F }
    ? ( gkd_gemm kit branch ctxp . w pw . w pb 1 n dim dim 1.0 1.0 0 ) {} { ^ F }
    ? ( __ma_res kit x branch . w ls1 norm n dim ) {} { ^ F }

    // ── SwiGLU MLP branch ──
    // w12 emits [n, 2·swh]; x1 is each row's first swh columns, x2 the
    // rest (torch's chunk(2, dim=-1)); out = w3(silu(x1) · x2).
    ? ( gkd_layernorm kit norm x . w n2g . w n2b n dim . w eps ) {} { ^ F }
    ? ( gkd_gemm kit hid norm . w w12w . w w12b 1 n * 2 swh dim 1.0 1.0 0 ) {} { ^ F }
    ? ( gkd_slice_ax kit sw1 hid n 1 swh 2 0 ) {} { ^ F }
    ? ( gkd_slice_ax kit sw2 hid n 1 swh 2 1 ) {} { ^ F }
    ? ( gkd_map kit `silu` `x/(1.0f+expf(-x))` sw1 sw1 ) {} { ^ F }
    ? ( gkd_mul kit sw1 sw1 sw2 ) {} { ^ F }
    ? ( gkd_gemm kit branch sw1 . w w3w . w w3b 1 n dim swh 1.0 1.0 0 ) {} { ^ F }
    ? ( __ma_res kit x branch . w ls2 norm n dim ) {} { ^ F }
    ^ T
}
