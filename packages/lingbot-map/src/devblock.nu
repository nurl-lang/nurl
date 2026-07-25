// packages/lingbot-map/src/devblock.nu — the transformer block on the
// device, in f32.
//
// `src/block.nu` is the same block in host f64 and is verified against the
// reference to 4.4e-15; this is the one that actually runs the model, and
// the host version is what it is checked against. Keeping both is the
// point: a device pipeline of ~15 kernel launches per block has a lot of
// places for a stride to be wrong, and "compare against a slow version
// that is known correct" catches all of them at once.
//
// Everything is composed from gpukit's `gkd_*` ops — gemm, layernorm,
// bmm, softmax, permute, broadcast-elementwise — so the same code runs on
// CUDA and on the CPU backend. The one kernel that had to be written here
// is 2-D RoPE, which is specific to how this model indexes a patch grid.
//
// Weight layouts are torch's, unchanged: a Linear weight is [out, in] and
// goes into `gkd_gemm` with transb=1, so nothing is transposed at load.
//
//   ( lm_ws_new kit n dim heads hidden maxkv maxpos )  → LmWs
//   ( lm_ws_free ws )                                  → v
//   ( lm_blk_free w )                                  → v
//   ( lm_block_forward kit w ws x n dim heads hidden )  → b   x updated

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`

// One block's parameters, resident on the device. A norm gain/bias pair
// with dptr 0 means "absent": DINOv2's own blocks have no qk-norm, the
// aggregator's frame and global blocks do.
: LmBlk {
    GkBuf n1g GkBuf n1b
    GkBuf qkvw GkBuf qkvb
    GkBuf qng GkBuf qnb
    GkBuf kng GkBuf knb
    GkBuf pw GkBuf pb
    GkBuf ls1
    GkBuf n2g GkBuf n2b
    GkBuf f1w GkBuf f1b
    GkBuf f2w GkBuf f2b
    GkBuf ls2
}

@ lm_blk_free LmBlk w → v {
    ( gk_dbuf_free . w n1g ) ( gk_dbuf_free . w n1b )
    ( gk_dbuf_free . w qkvw ) ( gk_dbuf_free . w qkvb )
    ( gk_dbuf_free . w qng ) ( gk_dbuf_free . w qnb )
    ( gk_dbuf_free . w kng ) ( gk_dbuf_free . w knb )
    ( gk_dbuf_free . w pw ) ( gk_dbuf_free . w pb )
    ( gk_dbuf_free . w ls1 )
    ( gk_dbuf_free . w n2g ) ( gk_dbuf_free . w n2b )
    ( gk_dbuf_free . w f1w ) ( gk_dbuf_free . w f1b )
    ( gk_dbuf_free . w f2w ) ( gk_dbuf_free . w f2b )
    ( gk_dbuf_free . w ls2 )
}

// Scratch, sized once for the largest frame the model will see. `maxkv`
// is the widest key/value run attention will face — the token count for
// self-attention, the whole cache for the streaming global blocks.
: LmWs {
    GkBuf norm
    GkBuf qkv
    GkBuf qkvp
    GkBuf kt
    GkBuf att
    GkBuf ctx
    GkBuf ctxp
    GkBuf branch
    GkBuf hid
    GkBuf scal
    GkBuf rows
    GkBuf cols
    GkBuf cosb
    GkBuf sinb
    i maxkv
}

@ lm_ws_new * GpuKit kit i n i dim i heads i hidden i maxkv i maxpos → LmWs {
    : i hd / dim heads
    ^ @ LmWs {
        ( gk_dbuf_new kit * n dim GK_F32 )
        ( gk_dbuf_new kit * n * 3 dim GK_F32 )
        ( gk_dbuf_new kit * n * 3 dim GK_F32 )
        ( gk_dbuf_new kit * heads * hd maxkv GK_F32 )
        ( gk_dbuf_new kit * heads * n maxkv GK_F32 )
        ( gk_dbuf_new kit * n dim GK_F32 )
        ( gk_dbuf_new kit * n dim GK_F32 )
        ( gk_dbuf_new kit * n dim GK_F32 )
        ( gk_dbuf_new kit * n hidden GK_F32 )
        ( gk_dbuf_new kit 1 GK_F32 )
        ( gk_dbuf_new kit n GK_I64 )
        ( gk_dbuf_new kit n GK_I64 )
        ( gk_dbuf_new kit * maxpos / hd 2 GK_F32 )
        ( gk_dbuf_new kit * maxpos / hd 2 GK_F32 )
        maxkv }
}

@ lm_ws_free LmWs ws → v {
    ( gk_dbuf_free . ws norm ) ( gk_dbuf_free . ws qkv )
    ( gk_dbuf_free . ws qkvp ) ( gk_dbuf_free . ws kt )
    ( gk_dbuf_free . ws att ) ( gk_dbuf_free . ws ctx )
    ( gk_dbuf_free . ws ctxp ) ( gk_dbuf_free . ws branch )
    ( gk_dbuf_free . ws hid ) ( gk_dbuf_free . ws scal )
    ( gk_dbuf_free . ws rows ) ( gk_dbuf_free . ws cols )
    ( gk_dbuf_free . ws cosb ) ( gk_dbuf_free . ws sinb )
}

// ── 2-D RoPE, on device ─────────────────────────────────────────────
//
// The one kernel this file adds. `x` is [heads, n, dim] and is rotated in
// place: the first half of each head's feature vector by the token's ROW
// coordinate, the second by its column. One thread per
// (head, token, axis, frequency) — each owns a disjoint pair of elements,
// so the in-place read-then-write is safe without a barrier.
@ lm_rope2d * GpuKit kit GkBuf x GkBuf rows GkBuf cols GkBuf cosb GkBuf sinb
i heads i n i dim → b {
    ? & & ( gk_buf_ok x ) ( gk_buf_ok rows ) ( gk_buf_ok cols ) {} { ^ F }
    ? & ( gk_buf_ok cosb ) ( gk_buf_ok sinb ) {} { ^ F }
    ? & & > heads 0 > n 0 == % dim 4 0 {} { ^ F }
    ? == . x n * heads * n dim {} { ^ F }
    : String src ( string_from `extern "C" __global__ void lm_rope2d(float* X, const long long* rows, const long long* cols, const float* cosT, const float* sinT, long long heads, long long n, long long dim){` )
    ( string_push_str src `long long half=dim/2, quarter=half/2;` )
    ( string_push_str src `long long tot=heads*n*quarter*2;` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;if(idx>=tot)return;` )
    ( string_push_str src `long long j=idx%quarter; long long r=idx/quarter;` )
    ( string_push_str src `long long axis=r%2; r/=2;` )
    ( string_push_str src `long long t=r%n; long long h=r/n;` )
    ( string_push_str src `long long base=h*n*dim+t*dim+axis*half;` )
    ( string_push_str src `long long pos=(axis==0)?rows[t]:cols[t];` )
    ( string_push_str src `long long tbl=pos*half;` )
    ( string_push_str src `float x1=X[base+j], x2=X[base+j+quarter];` )
    ( string_push_str src `X[base+j]=x1*cosT[tbl+j]-x2*sinT[tbl+j];` )
    ( string_push_str src `X[base+j+quarter]=x2*cosT[tbl+j+quarter]+x1*sinT[tbl+j+quarter];}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev rows ) )
    ( vec_push [i] args ( gk_arg_dev cols ) )
    ( vec_push [i] args ( gk_arg_dev cosb ) )
    ( vec_push [i] args ( gk_arg_dev sinb ) )
    ( vec_push [i] args ( gpu_arg_i64 heads ) )
    ( vec_push [i] args ( gpu_arg_i64 n ) )
    ( vec_push [i] args ( gpu_arg_i64 dim ) )
    : i tot * heads * n / dim 2
    : b r ( gk_run_dev kit ( string_data src ) `lm_rope2d` ( gk_grid tot 256 ) 256 args )
    ( vec_free [i] args )
    ( string_free src )
    ^ r
}

// ── helpers ─────────────────────────────────────────────────────────

@ __lm_i2 i a i b → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 2 )
    ( vec_push [i] v a ) ( vec_push [i] v b )
    ^ v
}

@ __lm_i3 i a i b i c → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 3 )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c )
    ^ v
}

@ __lm_i4 i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 4 )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d )
    ^ v
}

// A view of `b`'s elements [off, off+len) as its own GkBuf. The device
// pointer is byte-addressed, so a sub-range is just an offset — no copy,
// and nothing to free (the parent owns the allocation).
@ lm_view GkBuf b i off i len → GkBuf {
    ^ @ GkBuf { + . b dptr * off ( gk_buf_esz b ) len . b dtype }
}

// y[rows, cols] += ls[cols] * b[rows, cols], the LayerScale residual.
@ __lm_res * GpuKit kit GkBuf y GkBuf b GkBuf ls GkBuf tmp i rows i cols → b {
    : ( Vec i ) od ( __lm_i2 rows cols )
    : ( Vec i ) as ( __lm_i2 cols 1 )
    : ( Vec i ) bs ( __lm_i2 0 1 )
    : b ok1 ( gkd_ew_bc kit `mul` `*` tmp b ls od as bs )
    ( vec_free [i] od ) ( vec_free [i] as ) ( vec_free [i] bs )
    ? ok1 {} { ^ F }
    ^ ( gkd_add kit y y tmp )
}

// ── the block ───────────────────────────────────────────────────────

// Self-attention block over `n` tokens. `x` is [n, dim] and is updated in
// place. `rope` selects whether the grid rotation is applied — DINOv2's
// own blocks add a position embedding instead and pass F.
@ lm_block_forward * GpuKit kit LmBlk w LmWs ws GkBuf x
i n i dim i heads i hidden b rope → b {
    : i hd / dim heads
    : i nd * n dim

    // ── attention branch ──
    ? ( gkd_layernorm kit . ws norm x . w n1g . w n1b n dim 0.000001 ) {} { ^ F }
    ? ( gkd_gemm kit . ws qkv . ws norm . w qkvw . w qkvb 1 n * 3 dim dim 1.0 1.0 1 ) {} { ^ F }
    // [n, 3, heads, hd] → [3, heads, n, hd]
    : ( Vec i ) qd ( __lm_i4 n 3 heads hd )
    : ( Vec i ) qp ( __lm_i4 1 2 0 3 )
    : b okp ( gkd_perm kit . ws qkvp . ws qkv qd qp )
    ( vec_free [i] qd ) ( vec_free [i] qp )
    ? okp {} { ^ F }
    : GkBuf q ( lm_view . ws qkvp 0 nd )
    : GkBuf k ( lm_view . ws qkvp nd nd )
    : GkBuf v ( lm_view . ws qkvp * 2 nd nd )
    // qk LayerNorm is per HEAD over head_dim, and uses nn.LayerNorm's own
    // default eps (1e-5) — not the 1e-6 norm1/norm2 get. See src/block.nu.
    ? ( gk_buf_ok . w qng ) {
        ? ( gkd_layernorm kit q q . w qng . w qnb * heads n hd 0.00001 ) {} { ^ F }
        ? ( gkd_layernorm kit k k . w kng . w knb * heads n hd 0.00001 ) {} { ^ F }
    } {}
    ? rope {
        ? ( lm_rope2d kit q . ws rows . ws cols . ws cosb . ws sinb heads n hd ) {} { ^ F }
        ? ( lm_rope2d kit k . ws rows . ws cols . ws cosb . ws sinb heads n hd ) {} { ^ F }
    } {}
    // scores = q · kᵀ / sqrt(hd)
    : GkBuf kt ( lm_view . ws kt 0 * heads * n hd )
    : ( Vec i ) kd ( __lm_i3 heads n hd )
    : ( Vec i ) kp ( __lm_i3 0 2 1 )
    : b okk ( gkd_perm kit kt k kd kp )
    ( vec_free [i] kd ) ( vec_free [i] kp )
    ? okk {} { ^ F }
    : GkBuf att ( lm_view . ws att 0 * heads * n n )
    ? ( gkd_bmm kit att q kt heads n hd n 1 1 ) {} { ^ F }
    // 1/sqrt(head_dim), applied to the SCORES rather than folded into q —
    // algebraically the same, but it is where torch's SDPA puts it, and
    // the host reference this is checked against does the same.
    : ( Vec f ) sv ( vec_with_cap [f] 1 )
    ( vec_push [f] sv / 1.0 ( float_sqrt # f hd ) )
    : b oks ( gk_dbuf_upload kit . ws scal sv )
    ( vec_free [f] sv )
    ? oks {} { ^ F }
    ? ( gkd_ew kit `mul` `*` att att . ws scal ) {} { ^ F }
    ? ( gkd_softmax_ax kit att att * heads n n 1 ) {} { ^ F }
    ? ( gkd_bmm kit . ws ctx att v heads n n hd 1 1 ) {} { ^ F }
    // [heads, n, hd] → [n, heads·hd]
    : ( Vec i ) cd ( __lm_i3 heads n hd )
    : ( Vec i ) cp ( __lm_i3 1 0 2 )
    : b okc ( gkd_perm kit . ws ctxp . ws ctx cd cp )
    ( vec_free [i] cd ) ( vec_free [i] cp )
    ? okc {} { ^ F }
    ? ( gkd_gemm kit . ws branch . ws ctxp . w pw . w pb 1 n dim dim 1.0 1.0 1 ) {} { ^ F }
    ? ( __lm_res kit x . ws branch . w ls1 . ws norm n dim ) {} { ^ F }

    // ── MLP branch ──
    ? ( gkd_layernorm kit . ws norm x . w n2g . w n2b n dim 0.000001 ) {} { ^ F }
    ? ( gkd_gemm kit . ws hid . ws norm . w f1w . w f1b 1 n hidden dim 1.0 1.0 1 ) {} { ^ F }
    // exact GELU, x·Φ(x) — torch's nn.GELU default, not the tanh form
    ? ( gkd_map kit `gelu` `0.5f*x*(1.0f+erff(x*0.70710678118654752f))` . ws hid . ws hid ) {} { ^ F }
    ? ( gkd_gemm kit . ws branch . ws hid . w f2w . w f2b 1 n dim hidden 1.0 1.0 1 ) {} { ^ F }
    ? ( __lm_res kit x . ws branch . w ls2 . ws norm n dim ) {} { ^ F }
    ^ T
}
