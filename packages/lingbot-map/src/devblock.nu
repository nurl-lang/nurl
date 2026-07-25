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
//   ( lm_block_forward kit w ws rp x n dim heads hidden ) → b  x updated
//
// `rp` says which rotation the attention applies. The three blocks in
// this model each want a different one, so it is a parameter rather
// than a flag: DINOv2's own blocks rotate nothing (they add a position
// embedding at the input), the aggregator's FRAME blocks use the 2-D
// grid rope, and its GLOBAL blocks use the 3-D (frame, row, column)
// rope. See src/rope.nu for why those two are not interchangeable.

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
    // norm1 / norm2 epsilon. NOT a constant across this model: DINOv2's
    // own blocks are built with partial(LayerNorm, eps=1e-6), while the
    // aggregator's frame and global blocks are built without a
    // norm_layer at all and so get nn.LayerNorm's default 1e-5. The
    // difference is invisible until a row's variance is small, and then
    // it is worth ~1e-3 in the output.
    f eps
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

// Which rotation an attention applies, and the tables it needs.
//
//   LM_ROPE_NONE  nothing
//   LM_ROPE_2D    pa = row, pb = column
//   LM_ROPE_3D    pa = frame, pb = row, pc = column
: i LM_ROPE_NONE 0
: i LM_ROPE_2D 1
: i LM_ROPE_3D 2

: LmRope {
    i mode
    GkBuf pa
    GkBuf pb
    GkBuf pc
    GkBuf cosb
    GkBuf sinb
}

@ lm_rope_none → LmRope {
    ^ @ LmRope { LM_ROPE_NONE @ GkBuf { 0 0 GK_F32 } @ GkBuf { 0 0 GK_F32 }
        @ GkBuf { 0 0 GK_F32 } @ GkBuf { 0 0 GK_F32 } @ GkBuf { 0 0 GK_F32 } }
}

// Scratch, sized once for the largest frame the model will see. `maxkv`
// is the widest key/value run attention will face — the token count for
// self-attention, the whole cache for the streaming global blocks.
: LmWs {
    GkBuf norm
    GkBuf qkv
    GkBuf qkvp
    GkBuf kt
    GkBuf kpack
    GkBuf vpack
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
        ( gk_dbuf_new kit * heads * maxkv hd GK_F32 )
        ( gk_dbuf_new kit * heads * maxkv hd GK_F32 )
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
    ( gk_dbuf_free . ws kpack ) ( gk_dbuf_free . ws vpack )
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

// 3-D RoPE on device. Unlike the 2-D one this rotates INTERLEAVED pairs
// — (x0,x1), (x2,x3), … — and the 64-dim head is split 20 / 22 / 22
// across the frame, row and column axes rather than in half. One thread
// per (head, token, frequency); each owns one pair.
@ lm_rope3d * GpuKit kit GkBuf x GkBuf fr GkBuf rw GkBuf cl GkBuf cosb GkBuf sinb
i heads i n i dim i nt i nh → b {
    ? & & ( gk_buf_ok x ) ( gk_buf_ok fr ) ( gk_buf_ok rw ) {} { ^ F }
    ? & & ( gk_buf_ok cl ) ( gk_buf_ok cosb ) ( gk_buf_ok sinb ) {} { ^ F }
    ? & & > heads 0 > n 0 == % dim 2 0 {} { ^ F }
    ? == . x n * heads * n dim {} { ^ F }
    : String src ( string_from `extern "C" __global__ void lm_rope3d(float* X, const long long* fr, const long long* rw, const long long* cl, const float* cosT, const float* sinT, long long heads, long long n, long long dim, long long nt, long long nh){` )
    ( string_push_str src `long long width=dim/2;` )
    ( string_push_str src `long long tot=heads*n*width;` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;if(idx>=tot)return;` )
    ( string_push_str src `long long j=idx%width; long long r=idx/width;` )
    ( string_push_str src `long long t=r%n; long long h=r/n;` )
    ( string_push_str src `long long pos = (j<nt) ? fr[t] : ((j<nt+nh) ? rw[t] : cl[t]);` )
    ( string_push_str src `long long tbl=pos*width+j;` )
    ( string_push_str src `long long base=h*n*dim+t*dim+2*j;` )
    ( string_push_str src `float c=cosT[tbl], s=sinT[tbl];` )
    ( string_push_str src `float x1=X[base], x2=X[base+1];` )
    ( string_push_str src `X[base]=x1*c-x2*s; X[base+1]=x1*s+x2*c;}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev fr ) )
    ( vec_push [i] args ( gk_arg_dev rw ) )
    ( vec_push [i] args ( gk_arg_dev cl ) )
    ( vec_push [i] args ( gk_arg_dev cosb ) )
    ( vec_push [i] args ( gk_arg_dev sinb ) )
    ( vec_push [i] args ( gpu_arg_i64 heads ) )
    ( vec_push [i] args ( gpu_arg_i64 n ) )
    ( vec_push [i] args ( gpu_arg_i64 dim ) )
    ( vec_push [i] args ( gpu_arg_i64 nt ) )
    ( vec_push [i] args ( gpu_arg_i64 nh ) )
    : i tot * heads * n / dim 2
    : b r ( gk_run_dev kit ( string_data src ) `lm_rope3d` ( gk_grid tot 256 ) 256 args )
    ( vec_free [i] args )
    ( string_free src )
    ^ r
}

// Apply whichever rotation `rp` selects to a [heads, n, hd] tensor.
@ lm_rope_apply * GpuKit kit LmRope rp GkBuf x i heads i n i hd → b {
    ? == . rp mode LM_ROPE_NONE { ^ T } {}
    ? == . rp mode LM_ROPE_2D {
        ^ ( lm_rope2d kit x . rp pa . rp pb . rp cosb . rp sinb heads n hd )
    } {}
    // 20 / 22 / 22 over a 64-dim head → 10 frame, 11 row, 11 column
    ^ ( lm_rope3d kit x . rp pa . rp pb . rp pc . rp cosb . rp sinb heads n hd 10 11 )
}

// ── helpers ─────────────────────────────────────────────────────────

@ _lm_i2 i a i b → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 2 )
    ( vec_push [i] v a ) ( vec_push [i] v b )
    ^ v
}

@ _lm_i3 i a i b i c → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 3 )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c )
    ^ v
}

@ _lm_i4 i a i b i c i d → ( Vec i ) {
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
    : ( Vec i ) od ( _lm_i2 rows cols )
    : ( Vec i ) as ( _lm_i2 cols 1 )
    : ( Vec i ) bs ( _lm_i2 0 1 )
    : b ok1 ( gkd_ew_bc kit `mul` `*` tmp b ls od as bs )
    ( vec_free [i] od ) ( vec_free [i] as ) ( vec_free [i] bs )
    ? ok1 {} { ^ F }
    ^ ( gkd_add kit y y tmp )
}

// ── the block ───────────────────────────────────────────────────────

// A KV cache for one global block: k and v as [heads, maxkv, hd], with
// `used` rows already valid. A cache whose buffers are absent means
// plain self-attention — the frame blocks, and the very first frame.
: LmKv {
    GkBuf k
    GkBuf v
    i maxkv
    i used
}

@ lm_kv_none → LmKv { ^ @ LmKv { @ GkBuf { 0 0 GK_F32 } @ GkBuf { 0 0 GK_F32 } 0 0 } }

@ lm_kv_new * GpuKit kit i heads i maxkv i hd → LmKv {
    ^ @ LmKv { ( gk_dbuf_new kit * heads * maxkv hd GK_F32 )
        ( gk_dbuf_new kit * heads * maxkv hd GK_F32 ) maxkv 0 }
}

@ lm_kv_free LmKv c → v { ( gk_dbuf_free . c k ) ( gk_dbuf_free . c v ) }

// Transformer block over `n` tokens; `x` is [n, dim], updated in place.
//
// With a cache, this frame's keys and values are appended at row
// `kv.used` and attention runs over everything stored so far — the
// streaming global blocks. Without one it is plain self-attention.
// APPENDING IS THE CALLER'S BOOKKEEPING: `used` is read here and not
// written, because one frame passes through 24 different caches and the
// count belongs to the frame, not to any one of them.
@ lm_block_forward * GpuKit kit LmBlk w LmWs ws LmRope rp LmKv kv GkBuf x
i n i dim i heads i hidden → b {
    : i hd / dim heads
    : i nd * n dim

    // The workspace is sized once for the LARGEST frame; this block may
    // be running a smaller one (DINOv2 carries 782 tokens where the
    // aggregator carries 783). Every gkd_* op validates its buffers'
    // exact element counts and fails closed on a mismatch, so what goes
    // in is a view cut to this call's n, not the raw allocation.
    : GkBuf norm ( lm_view . ws norm 0 nd )
    : GkBuf qkv ( lm_view . ws qkv 0 * 3 nd )
    : GkBuf qkvp ( lm_view . ws qkvp 0 * 3 nd )
    : GkBuf ctx ( lm_view . ws ctx 0 nd )
    : GkBuf ctxp ( lm_view . ws ctxp 0 nd )
    : GkBuf branch ( lm_view . ws branch 0 nd )
    : GkBuf hid ( lm_view . ws hid 0 * n hidden )

    // ── attention branch ──
    ? ( gkd_layernorm kit norm x . w n1g . w n1b n dim . w eps ) {} { ^ F }
    ? ( gkd_gemm kit qkv norm . w qkvw . w qkvb 1 n * 3 dim dim 1.0 1.0 1 ) {} { ^ F }
    // [n, 3, heads, hd] → [3, heads, n, hd]
    : ( Vec i ) qd ( _lm_i4 n 3 heads hd )
    : ( Vec i ) qp ( _lm_i4 1 2 0 3 )
    : b okp ( gkd_perm kit qkvp qkv qd qp )
    ( vec_free [i] qd ) ( vec_free [i] qp )
    ? okp {} { ^ F }
    : GkBuf q ( lm_view qkvp 0 nd )
    : GkBuf k ( lm_view qkvp nd nd )
    : GkBuf v ( lm_view qkvp * 2 nd nd )
    // qk LayerNorm is per HEAD over head_dim, and uses nn.LayerNorm's own
    // default eps (1e-5) — not the 1e-6 norm1/norm2 get. See src/block.nu.
    ? ( gk_buf_ok . w qng ) {
        ? ( gkd_layernorm kit q q . w qng . w qnb * heads n hd 0.00001 ) {} { ^ F }
        ? ( gkd_layernorm kit k k . w kng . w knb * heads n hd 0.00001 ) {} { ^ F }
    } {}
    ? ( lm_rope_apply kit rp q heads n hd ) {} { ^ F }
    ? ( lm_rope_apply kit rp k heads n hd ) {} { ^ F }
    // With a cache: append this frame's rotated k/v, then attend over
    // everything stored. gkd_copy_ax writes a [heads, n, hd] run into a
    // [heads, maxkv, hd] cache at row offset `used` — one call, no
    // per-head loop.
    : b cached ( gk_buf_ok . kv k )
    : i nkv ? cached + . kv used n n
    ? cached {
        ? ( gkd_copy_ax kit . kv k k heads n hd . kv maxkv . kv used ) {} { ^ F }
        ? ( gkd_copy_ax kit . kv v v heads n hd . kv maxkv . kv used ) {} { ^ F }
    } {}
    // keys and values attention actually reads: the cache prefix, or
    // just this frame's
    : GkBuf kall ? cached ( lm_view . kv k 0 * heads * nkv hd ) k
    : GkBuf vall ? cached ( lm_view . kv v 0 * heads * nkv hd ) v
    // A cache row is [heads, maxkv, hd] but only `nkv` rows are live, so
    // the view above is NOT contiguous per head unless nkv == maxkv.
    // Repack into a tight [heads, nkv, hd] before the permute.
    : GkBuf kpk ( lm_view . ws kpack 0 * heads * nkv hd )
    : GkBuf vpk ( lm_view . ws vpack 0 * heads * nkv hd )
    ? cached {
        ? ( gkd_slice_ax kit kpk . kv k heads nkv hd . kv maxkv 0 ) {} { ^ F }
        ? ( gkd_slice_ax kit vpk . kv v heads nkv hd . kv maxkv 0 ) {} { ^ F }
    } {}
    : GkBuf kuse ? cached kpk kall
    : GkBuf vuse ? cached vpk vall
    // scores = q · kᵀ / sqrt(hd)
    : GkBuf kt ( lm_view . ws kt 0 * heads * nkv hd )
    : ( Vec i ) kd ( _lm_i3 heads nkv hd )
    : ( Vec i ) kp ( _lm_i3 0 2 1 )
    : b okk ( gkd_perm kit kt kuse kd kp )
    ( vec_free [i] kd ) ( vec_free [i] kp )
    ? okk {} { ^ F }
    : GkBuf att ( lm_view . ws att 0 * heads * n nkv )
    ? ( gkd_bmm kit att q kt heads n hd nkv 1 1 ) {} { ^ F }
    // 1/sqrt(head_dim), applied to the SCORES rather than folded into q —
    // algebraically the same, but it is where torch's SDPA puts it, and
    // the host reference this is checked against does the same.
    : ( Vec f ) sv ( vec_with_cap [f] 1 )
    ( vec_push [f] sv / 1.0 ( float_sqrt # f hd ) )
    : b oks ( gk_dbuf_upload kit . ws scal sv )
    ( vec_free [f] sv )
    ? oks {} { ^ F }
    ? ( gkd_ew kit `mul` `*` att att . ws scal ) {} { ^ F }
    ? ( gkd_softmax_ax kit att att * heads n nkv 1 ) {} { ^ F }
    ? ( gkd_bmm kit ctx att vuse heads n nkv hd 1 1 ) {} { ^ F }
    // [heads, n, hd] → [n, heads·hd]
    : ( Vec i ) cd ( _lm_i3 heads n hd )
    : ( Vec i ) cp ( _lm_i3 1 0 2 )
    : b okc ( gkd_perm kit ctxp ctx cd cp )
    ( vec_free [i] cd ) ( vec_free [i] cp )
    ? okc {} { ^ F }
    ? ( gkd_gemm kit branch ctxp . w pw . w pb 1 n dim dim 1.0 1.0 1 ) {} { ^ F }
    ? ( __lm_res kit x branch . w ls1 norm n dim ) {} { ^ F }

    // ── MLP branch ──
    ? ( gkd_layernorm kit norm x . w n2g . w n2b n dim . w eps ) {} { ^ F }
    ? ( gkd_gemm kit hid norm . w f1w . w f1b 1 n hidden dim 1.0 1.0 1 ) {} { ^ F }
    // exact GELU, x·Φ(x) — torch's nn.GELU default, not the tanh form
    ? ( gkd_map kit `gelu` `0.5f*x*(1.0f+erff(x*0.70710678118654752f))` hid hid ) {} { ^ F }
    ? ( gkd_gemm kit branch hid . w f2w . w f2b 1 n dim hidden 1.0 1.0 1 ) {} { ^ F }
    ? ( __lm_res kit x branch . w ls2 norm n dim ) {} { ^ F }
    ^ T
}
