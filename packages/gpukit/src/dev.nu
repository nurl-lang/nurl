// gpukit/dev.nu — device-RESIDENT buffers + dtype-aware kernels.
//
// gk_run marshals host↔device around every call, which is right for one-shot
// compute but wrong for chained pipelines (an ndarray expression, a NN
// forward pass): the data should stay on the device between ops. This layer
// adds exactly that seam:
//
//   GkBuf            an element-typed device allocation
//                    (GK_F32 | GK_F64 | GK_I64)
//   gk_dbuf_new / _free / _upload / _download (f64 host view, converting)
//   gk_dbuf_upload_i / _download_i (exact i64 host view, GK_I64 only)
//   gk_run_dev       cached-compile + launch + sync over RAW device args
//   gkd_*            ready-made dtype-generic kernels over GkBuf:
//                    elementwise (scalar + full N-D stride broadcast),
//                    unary maps, matmul, batched matmul, gather/scatter,
//                    row softmax, sum reduction
//
// Numerics: GK_F64 kernels compute in double exactly like kernels.nu.
// GK_F32 buffers hold real float32 and kernels compute IN float32
// (accumulation included) — true float32 semantics, matching numpy
// float32 / onnxruntime, NOT the host-tensor trick of f64-compute +
// grid-rounding. Uploads convert f64 → f32 via a staging buffer.
// GK_I64 holds long long (index tensors: gather/scatter/argmax); the f64
// host view converts by C truncation, the _i entry points are exact.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/slice.nu`
$ `gpukit.nu`
$ `kernels.nu`  // _gk_partial_threads / _gk_zeros

$ `devbuf.nu`  // GkBuf and its owner
// (After GkBuf: checked.nu binds them. The ops below run as its checked
// kernels — gk_run_checked_dev.)
$ `checked.nu`

@ __gk_nomem → ?GkMem { ^ @ ?GkMem { F } }

// Another owner of the block `m` holds, if it holds one.
@ __gk_mem_share ? GkMem m → ?GkMem {
    ?? m {
        T x → { ^ @ ?GkMem { T ( GkMem_share x ) } }
        F → { ^ @ ?GkMem { F } }
    }
}

// A GkBuf is `raw`: its `dptr` is device memory holding `n` elements of
// `dtype` for as long as the GkBuf lives, and every kernel launched over it
// relies on that. Only this file's functions (and `unsafe` code) build one.

// Products of sizes as a kernel will form them: -1 when a factor is
// negative or the product overflows, which no buffer length equals.
@ _gk_p2 i a i b → i {
    ? | < a 0 < b 0 { ^ -1 } {}
    ? | == a 0 == b 0 { ^ 0 } {}
    ? > a / 9223372036854775807 b { ^ -1 } {}
    ^ * a b
}

@ _gk_p3 i a i b i c → i { ^ ( _gk_p2 ( _gk_p2 a b ) c ) }

@ _gk_p4 i a i b i c i d → i { ^ ( _gk_p2 ( _gk_p3 a b c ) d ) }

// A buffer that is not there: what a failed allocation returns, and the
// placeholder for an absent operand (a missing bias, mask, …).
unsafe @ gk_buf_none i dtype → GkBuf { ^ @ GkBuf { 0 0 dtype ( __gk_nomem ) } }

// `n` elements of `b` starting at element `off`, same dtype — none when
// [off, off + n) is not inside b. The view holds `b`'s block: it stays
// valid however long the view lives.
unsafe @ gk_buf_view GkBuf b i off i n → GkBuf {
    ? | | < off 0 < n 0 > n - . b n off { ^ ( gk_buf_none . b dtype ) } {}
    ^ @ GkBuf { + . b dptr * off ( _gk_esz . b dtype ) n . b dtype ( __gk_mem_share . b mem ) }
}

// `n` elements of type `dtype` at BYTE offset `boff` into `b` — a view
// that reinterprets (an f32 block read as i64 indices, say). Holds `b`'s
// block like gk_buf_view; none when the bytes are not inside b.
unsafe @ gk_buf_view_as GkBuf b i boff i n i dtype → GkBuf {
    : i have ( _gk_p2 . b n ( _gk_esz . b dtype ) )
    : i want ( _gk_p2 n ( _gk_esz dtype ) )
    ? | | | < boff 0 < want 0 < have 0 > want - have boff { ^ ( gk_buf_none dtype ) } {}
    ^ @ GkBuf { + . b dptr boff n dtype ( __gk_mem_share . b mem ) }
}

// ── 16-bit float buffers (GkHBuf) ─────────────────────────────────────

unsafe @ gk_hbuf_none → GkHBuf { ^ @ GkHBuf { 0 0 F ( __gk_nomem ) } }

@ gk_hbuf_ok GkHBuf h → b { ^ != . h dptr 0 }

@ gk_hbuf_len GkHBuf h → i { ^ . h n }

// `n` 16-bit floats at BYTE offset `boff` into `b` (f16, or bf16 when `bf`):
// a view holding `b`'s block, none when the 2n bytes are not inside b or
// boff is odd. How a model carves its half weights out of one allocation.
unsafe @ gk_hbuf_of GkBuf b i boff i n b bf → GkHBuf {
    : i have ( _gk_p2 . b n ( _gk_esz . b dtype ) )
    : i want ( _gk_p2 n 2 )
    ? | | | < boff 0 < want 1 < have 0 > want - have boff { ^ ( gk_hbuf_none ) } {}
    ? | != 0 % boff 2 ! ( gk_buf_ok b ) { ^ ( gk_hbuf_none ) } {}
    ^ @ GkHBuf { + . b dptr boff n bf ( __gk_mem_share . b mem ) }
}

// A new buffer of `n` 16-bit floats (contents undefined until uploaded).
@ gk_hbuf_new GpuKit kit i n b bf → GkHBuf {
    ? < n 1 { ^ ( gk_hbuf_none ) } {}
    : GkBuf b ( gk_dbuf_new kit / + n 1 2 GK_F32 )
    ^ ( gk_hbuf_of b 0 n bf )
}

// Upload `n` halves from a checked view of their bytes (2n of them, little
// endian, as a checkpoint stores them): F unless `src` holds that many.
@ gk_hbuf_upload_bytes GpuKit kit GkHBuf h ( Slice u ) src → b {
    ? ( gk_hbuf_ok h ) {} { ^ F }
    ? < ( slice_len [u] src ) * . h n 2 { ^ F } {}
    ^ ( __gk_hupload_view h src )
}

unsafe @ __gk_hupload_view GkHBuf h ( Slice u ) src → b {
    ^ == ( gpu_upload ( gpu_buffer_view . h dptr * . h n 2 ) ( slice_data [u] src ) ) 0
}

// ── byte buffers (GkBBuf) ───────────────────────────────────────────

// Another owner of the same view (what a call binding holds, so the caller
// keeps its own).
unsafe @ _gk_hbuf_share GkHBuf h → GkHBuf { ^ @ GkHBuf { . h dptr . h n . h bf ( __gk_mem_share . h mem ) } }

unsafe @ _gk_bbuf_share GkBBuf q → GkBBuf { ^ @ GkBBuf { . q dptr . q n ( __gk_mem_share . q mem ) } }

unsafe @ gk_bbuf_none → GkBBuf { ^ @ GkBBuf { 0 0 ( __gk_nomem ) } }

@ gk_bbuf_ok GkBBuf q → b { ^ != . q dptr 0 }

@ gk_bbuf_len GkBBuf q → i { ^ . q n }

// `n` bytes at byte offset `boff` into `b`: a view holding `b`'s block, none
// unless the bytes are inside b, boff is a multiple of 4 and n is at least
// 4 (so every word a kernel can name lies inside the view).
unsafe @ gk_bbuf_of GkBuf b i boff i n → GkBBuf {
    : i have ( _gk_p2 . b n ( _gk_esz . b dtype ) )
    ? | | | < boff 0 < n 4 < have 0 > n - have boff { ^ ( gk_bbuf_none ) } {}
    ? | != 0 % boff 4 ! ( gk_buf_ok b ) { ^ ( gk_bbuf_none ) } {}
    ^ @ GkBBuf { + . b dptr boff n ( __gk_mem_share . b mem ) }
}

// A new buffer of `n` bytes (contents undefined until uploaded).
@ gk_bbuf_new GpuKit kit i n → GkBBuf {
    ? < n 4 { ^ ( gk_bbuf_none ) } {}
    : GkBuf b ( gk_dbuf_new kit / + n 3 4 GK_F32 )
    ^ ( gk_bbuf_of b 0 n )
}

// Upload exactly the buffer's bytes from a checked view of them.
@ gk_bbuf_upload_bytes GpuKit kit GkBBuf q ( Slice u ) src → b {
    ? ( gk_bbuf_ok q ) {} { ^ F }
    ? != ( slice_len [u] src ) . q n { ^ F } {}
    ^ ( __gk_bupload_view q src )
}

unsafe @ __gk_bupload_view GkBBuf q ( Slice u ) src → b {
    ^ == ( gpu_upload ( gpu_buffer_view . q dptr . q n ) ( slice_data [u] src ) ) 0
}

// A buffer over device memory something else owns (another package's
// allocation, a raw pointer out of a C library). It owns nothing: the
// caller vouches (`raw`) that `dptr` holds `n` elements of `dtype` and
// stays alive for as long as the GkBuf is used.
raw @ gk_buf_wrap i dptr i n i dtype → GkBuf { ^ @ GkBuf { dptr n dtype ( __gk_nomem ) } }

@ _gk_esz i dtype → i { ? == dtype GK_F32 { ^ 4 } {} ^ 8 }

@ _gk_tname i dtype → s {
    ? == dtype GK_F32 { ^ `float` } {}
    ? == dtype GK_I64 { ^ `long long` } {}
    ^ `double`
}

// Kernel-name prefix per dtype so the cache never mixes element types.
@ _gk_pfx i dtype → s {
    ? == dtype GK_F32 { ^ `gk32_` } {}
    ? == dtype GK_I64 { ^ `gki_` } {}
    ^ `gk64_`
}

// A scalar kernel argument holding value `v` in the buffer dtype's width:
// f32 bit pattern for GK_F32, f64 bits otherwise (the arg cell is 8 bytes;
// the kernel reads the leading 4 for a float parameter).
@ _gk_scal i dtype f v → i {
    ? == dtype GK_F32 { ^ ( gpu_arg_f32 v ) } {}
    ^ ( f64_to_bits v )
}

@ gk_buf_ok GkBuf b → b { ^ != . b dptr 0 }

@ gk_buf_len GkBuf b → i { ^ . b n }

@ gk_buf_dtype GkBuf b → i { ^ . b dtype }

// Bytes per element. Needed by anyone addressing a sub-range of a buffer
// (the device pointer is byte-addressed), which is why it is public
// rather than the file-private _gk_esz it wraps.
@ gk_buf_esz GkBuf b → i { ^ ( _gk_esz . b dtype ) }

// ── Lifecycle ─────────────────────────────────────────────────────────

@ gk_dbuf_new GpuKit h i n i dtype → GkBuf {
    ? & ( _gk_ok h ) > n 0 {} { ^ ( gk_buf_none dtype ) }
    ? ( _gk_census h ) { ^ ( __gk_census_buf h n dtype ) } {}
    // (The byte count is the checked product: n * 8 wraps for an n near
    // 2^61, and a buffer of 8 bytes would then claim 2^61 elements to
    // every check that trusts its length.)
    : i bytes ( _gk_p2 n ( _gk_esz dtype ) )
    ? < bytes 1 { ^ ( gk_buf_none dtype ) } {}
    : GkInfo kit ( arc_get [GkInfo] . h info )
    ( _gk_pool_default kit )
    : ~ GkState st ( locked_take [GkState] . h st )
    : i dptr ( __gk_alloc_in st kit bytes )
    ( locked_restore [GkState] . h st st )
    ? == dptr 0 { ^ ( gk_buf_none dtype ) } {}
    ^ ( __gk_owned_buf h dptr n dtype )
}

// A census kit launches nothing, so no kernel ever reads its buffers. Each
// is still real memory its owner holds — zeroed host bytes for `n`
// elements — so a census buffer handed to a real kit by mistake points at
// memory that exists (a CPU kernel sees zeros, CUDA reports an invalid
// address), never at a made-up one.
unsafe @ __gk_census_buf GpuKit h i n i dtype → GkBuf {
    : i bytes ( _gk_p2 n ( _gk_esz dtype ) )
    ? < bytes 1 { ^ ( gk_buf_none dtype ) } {}
    : ( Vec u ) host ( vec_zeroed [u] bytes )
    : i dptr # i ( vec_data [u] host )
    ^ @ GkBuf { dptr n dtype @ ?GkMem { T @ GkMem { ( arc_new [GkMemImpl] @ GkMemImpl { dptr ( GpuKit_share h ) host } ) } } }
}

// The GkBuf over the pool block at `dptr`, `n` elements of `dtype`, that
// gk_dbuf_new just took for it: its owner gives the block back to `h`'s
// pool.
unsafe @ __gk_owned_buf GpuKit h i dptr i n i dtype → GkBuf {
    ^ @ GkBuf { dptr n dtype @ ?GkMem { T @ GkMem { ( arc_new [GkMemImpl] @ GkMemImpl { dptr ( GpuKit_share h ) ( vec_new [u] ) } ) } } }
}

// A block of `bytes` for a new buffer — a block this size an earlier
// owner let go of, or a fresh one — in use in the pool; 0 when the device
// has no room even after the pool gave its idle blocks back.
@ __gk_alloc_in inout GkState st GkInfo kit i bytes → i {
    : i dptr ( _gk_pool_take st bytes )
    ? != dptr 0 { ^ dptr } {}
    : ~ GpuBuffer gb ( gpu_alloc . kit gpu bytes )
    // out of memory: the pool is holding blocks nothing is using — give
    // them back and ask once more before reporting failure
    ? == . gb dptr 0 {
        ( _gk_pool_release st )
        = gb ( gpu_alloc . kit gpu bytes )
    } {}
    : i d . gb dptr
    ? == d 0 { ^ 0 } {}
    ( _gk_pool_add st gb )
    ^ d
}

// Let go of `b` now rather than at the end of its owner's scope.
@ gk_dbuf_free sink GkBuf b → v {}

// An f32 buffer `b` filled from (`up`) or read into an f64 Vec through a
// staging f64 buffer and one cast kernel. F when the staging buffer or the
// kernel is not to be had (the caller takes the host path).
@ __gk_f32_dev GpuKit kit GkBuf b ( Vec f ) host b up → b {
    : i n . b n
    : GkBuf stg ( gk_dbuf_new kit n GK_F64 )
    ? ( gk_buf_ok stg ) {} { ^ F }
    // (the store converts: to float rounding to nearest, to double exactly)
    : ~ GkCall c ( gk_call_new )
    ? up {
        ? ( gk_dbuf_upload kit stg host ) {} { ^ F }
        ( gk_call_dev_in c `x` stg )
        ( gk_call_dev c `y` b )
        ^ ( gk_run_checked_dev kit c `gk_d2f` `ST(y, gid, LD(x, gid));` ( gk_grid n 256 ) 256 )
    } {}
    ( gk_call_dev_in c `x` b )
    ( gk_call_dev c `y` stg )
    ? ( gk_run_checked_dev kit c `gk_f2d` `ST(y, gid, LD(x, gid));` ( gk_grid n 256 ) 256 ) {} { ^ F }
    ^ ( gk_dbuf_download kit stg host )
}

// Host f64 vector → device (converted to the buffer's element type: f32
// rounds, i64 truncates like a C cast). Copies min(len(src), b.n) elements;
// missing elements upload as 0. The direct (non-converting) f64 path is
// taken only when src actually holds b.n elements — a short vector goes
// through the padding stage, never out of bounds.
unsafe @ gk_dbuf_upload GpuKit kit GkBuf b ( Vec f ) src → b {
    ? ( gk_buf_ok b ) {} { ^ F }
    : i n . b n
    : i m ( vec_len [f] src )
    : GpuBuffer gb ( gpu_buffer_view . b dptr * n ( _gk_esz . b dtype ) )
    ? & == . b dtype GK_F64 >= m n {
        ^ == ( gpu_upload gb # *u ( vec_data [f] src ) ) 0
    } {}
    // f32 with the whole source in hand: one memcpy into a staging f64
    // buffer and one cast kernel on the device. The host loop below makes
    // one foreign call per element — minutes for a model's weights. (Under
    // 4096 elements the launch costs more than the loop.)
    ? & & & == . b dtype GK_F32 >= m n >= n 4096 ! ( _gk_census kit ) {
        ? ( __gk_f32_dev kit b src T ) { ^ T } {}
    } {}
    // stage-convert on the host, then one upload
    : GpuHost stage ( gpu_host_alloc * n ( _gk_esz . b dtype ) )
    : *u sp ( gpu_host_ptr stage )
    : ~ i k 0
    ~ < k n {
        : f v ? < k m { ?? ( vec_get [f] src k ) { T x → x F _ → 0.0 } } { 0.0 }
        ? == . b dtype GK_F32 { ( nurl_poke_f32 sp k v ) } {
            ? == . b dtype GK_I64 { ( nurl_poke sp k # i v ) } {
                ( nurl_poke sp k ( f64_to_bits v ) ) } }
        = k + k 1
    }
    ^ == ( gpu_upload gb sp ) 0
}

// Device → host f64 vector (converted from the buffer's element type).
// `dst` must already hold at least b.n elements (fails closed otherwise);
// the first b.n are overwritten in place.
unsafe @ gk_dbuf_download GpuKit kit GkBuf b ( Vec f ) dst → b {
    ? ( gk_buf_ok b ) {} { ^ F }
    : i n . b n
    ? >= ( vec_len [f] dst ) n {} { ^ F }
    : GpuBuffer gb ( gpu_buffer_view . b dptr * n ( _gk_esz . b dtype ) )
    ? == . b dtype GK_F64 {
        ^ == ( gpu_download # *u ( vec_data [f] dst ) gb ) 0
    } {}
    // f32: cast to f64 on the device, then one memcpy (see gk_dbuf_upload).
    ? & & == . b dtype GK_F32 >= n 4096 ! ( _gk_census kit ) {
        ? ( __gk_f32_dev kit b dst F ) { ^ T } {}
    } {}
    : GpuHost stage ( gpu_host_alloc * n ( _gk_esz . b dtype ) )
    : *u sp ( gpu_host_ptr stage )
    : i rc ( gpu_download sp gb )
    ? == rc 0 {
        : ~ i k 0
        ~ < k n {
            ? == . b dtype GK_F32 {
                ( vec_set [f] dst k ( nurl_peek_f32 sp k ) )
            } { ( vec_set [f] dst k # f ( nurl_peek sp k ) ) }
            = k + k 1
        }
    } {}
    ^ == rc 0
}

// Upload bytes that are ALREADY in the buffer's element type: no
// conversion, no staging allocation, one memcpy to the device. `src`
// must address b.n elements of that type and stay valid for the call —
// a memory-mapped file is exactly the intended source.
//
// The converting entry point above is the general one, but for a
// checkpoint whose storage dtype already matches the device buffer it
// walks every element through f64 twice (widen on read, narrow on
// upload) and allocates two host buffers the size of the tensor to do
// it. On a 4.6 GB model that is most of the load.
//
// raw: nothing here can check that `src` addresses those bytes; a caller
// that has them as a checked view uploads with gk_dbuf_upload_bytes.
raw @ gk_dbuf_upload_raw GpuKit kit GkBuf b * u src → b {
    ? & ( gk_buf_ok b ) != # i src 0 {} { ^ F }
    ^ == ( gpu_upload ( gpu_buffer_view . b dptr * . b n ( _gk_esz . b dtype ) ) src ) 0
}

// The same from a checked view of the bytes (a tensor's bytes in a mapped
// file, safetensor's st_tensor_bytes): F unless it holds the buffer's
// b.n elements. Safe, and as fast — one memcpy to the device.
@ gk_dbuf_upload_bytes GpuKit kit GkBuf b ( Slice u ) src → b {
    ? ( gk_buf_ok b ) {} { ^ F }
    ? < ( slice_len [u] src ) * . b n ( _gk_esz . b dtype ) { ^ F } {}
    ^ ( __gk_upload_view b src )
}

// Many uploads as ONE batch: srcs[k] into dsts[k], each a checked view
// holding exactly its buffer's bytes. On CUDA the batch streams through a
// pinned double buffer, so a model's hundreds of tensors cost one pass
// instead of a synchronous copy each. F, with nothing sent, when the
// lengths differ, a buffer is none or a source is not its buffer's size.
// `release` gives the staging pair (128 MB of page-locked host memory)
// back afterwards — for a one-off load; a caller sending batch after
// batch keeps it.
unsafe @ gk_dbuf_upload_batch GpuKit kit ( Vec GkBuf ) dsts ( Vec ( Slice u ) ) srcs b release → b {
    ^ ( gk_upload_batch kit dsts srcs ( vec_new [GkHBuf] ) ( vec_new [( Slice u )] ) release )
}

// The same batch with 16-bit float buffers among the destinations — a
// model whose matrices stay half on the device and whose norms do not:
// hsrcs[k] holds exactly hdsts[k]'s 2n bytes. One pass for both.
unsafe @ gk_upload_batch GpuKit kit ( Vec GkBuf ) dsts ( Vec ( Slice u ) ) srcs ( Vec GkHBuf ) hdsts ( Vec ( Slice u ) ) hsrcs b release → b {
    ? ( _gk_ok kit ) {} { ^ F }
    : i n ( vec_len [GkBuf] dsts )
    ? == n ( vec_len [( Slice u )] srcs ) {} { ^ F }
    : i nh ( vec_len [GkHBuf] hdsts )
    ? == nh ( vec_len [( Slice u )] hsrcs ) {} { ^ F }
    : ~ ( Vec GpuCopy ) q ( vec_new [GpuCopy] )
    : ~ i k 0
    ~ < k n {
        : GkBuf d ( vec_at [GkBuf] dsts k )
        : ( Slice u ) sv ( vec_at [( Slice u )] srcs k )
        ? & ( gk_buf_ok d ) == ( slice_len [u] sv ) ( _gk_p2 . d n ( _gk_esz . d dtype ) ) {} { ^ F }
        ( vec_push [GpuCopy] q @ GpuCopy { . d dptr # i ( slice_data [u] sv ) ( slice_len [u] sv ) } )
        = k + k 1
    }
    = k 0
    ~ < k nh {
        : GkHBuf d ( vec_at [GkHBuf] hdsts k )
        : ( Slice u ) sv ( vec_at [( Slice u )] hsrcs k )
        ? & ( gk_hbuf_ok d ) == ( slice_len [u] sv ) ( _gk_p2 . d n 2 ) {} { ^ F }
        ( vec_push [GpuCopy] q @ GpuCopy { . d dptr # i ( slice_data [u] sv ) ( slice_len [u] sv ) } )
        = k + k 1
    }
    ? ( _gk_census kit ) { ^ T } {}
    : b ok == ( gpu_upload_batch q ) 0
    ? release { ( gpu_staging_free ) } {}
    ^ ok
}

// (`src` holds the buffer's bytes: checked by the caller above.)
unsafe @ __gk_upload_view GkBuf b ( Slice u ) src → b {
    ^ == ( gpu_upload ( gpu_buffer_view . b dptr * . b n ( _gk_esz . b dtype ) ) ( slice_data [u] src ) ) 0
}

// Device → a checked view of host bytes: F unless `dst` has room for the
// buffer's b.n elements. The download counterpart of gk_dbuf_upload_bytes.
@ gk_dbuf_download_bytes GpuKit kit GkBuf b ( Slice u ) dst → b {
    ? ( gk_buf_ok b ) {} { ^ F }
    ? < ( slice_len [u] dst ) * . b n ( _gk_esz . b dtype ) { ^ F } {}
    ^ ( __gk_download_view b dst )
}

// (`dst` has room for the buffer's bytes: checked by the caller above.)
unsafe @ __gk_download_view GkBuf b ( Slice u ) dst → b {
    ^ == ( gpu_download ( slice_data [u] dst ) ( gpu_buffer_view . b dptr * . b n ( _gk_esz . b dtype ) ) ) 0
}

// Device → page-locked host memory (a GpuHost from gpu_host_alloc): all of
// the buffer's bytes into the front of `h`. F unless `h` has room for them.
// A view of the buffer downloads part of it.
@ gk_dbuf_download_host GpuKit kit GkBuf b GpuHost h → b {
    ? ( gk_buf_ok b ) {} { ^ F }
    : i bytes ( _gk_p2 . b n ( _gk_esz . b dtype ) )
    ? | < bytes 1 > bytes ( gpu_host_bytes h ) { ^ F } {}
    ^ ( __gk_download_host b h bytes )
}

// (`h` holds at least `bytes`, the buffer's own size: checked above.)
unsafe @ __gk_download_host GkBuf b GpuHost h i bytes → b {
    ^ == ( gpu_download ( gpu_host_ptr h ) ( gpu_buffer_view . b dptr bytes ) ) 0
}

// Device → device: all of `src` into the front of `dst`. F unless both are
// there, share a dtype and `dst` holds at least src.n elements.
@ gk_dbuf_copy GpuKit kit GkBuf dst GkBuf src → b {
    ? & ( gk_buf_ok dst ) ( gk_buf_ok src ) {} { ^ F }
    ? | != . dst dtype . src dtype < . dst n . src n { ^ F } {}
    ^ ( __gk_copy_in dst src )
}

// (Both live, one dtype, `dst` large enough: checked by the caller above.)
unsafe @ __gk_copy_in GkBuf dst GkBuf src → b {
    ^ == ( gpu_dtod ( gpu_buffer_view . dst dptr * . src n ( _gk_esz . src dtype ) ) . src dptr ) 0
}

// Exact i64 host view (GK_I64 buffers only — index tensors must never make
// a round trip through f64). Same length contracts as the f64 view.
unsafe @ gk_dbuf_upload_i GpuKit kit GkBuf b ( Vec i ) src → b {
    ? & ( gk_buf_ok b ) == . b dtype GK_I64 {} { ^ F }
    : i n . b n
    : i m ( vec_len [i] src )
    : GpuBuffer gb ( gpu_buffer_view . b dptr * n 8 )
    ? >= m n { ^ == ( gpu_upload gb # *u ( vec_data [i] src ) ) 0 } {}
    : GpuHost stage ( gpu_host_alloc * n 8 )
    : *u sp ( gpu_host_ptr stage )
    : ~ i k 0
    ~ < k n {
        : i v ? < k m { ?? ( vec_get [i] src k ) { T x → x F _ → 0 } } { 0 }
        ( nurl_poke sp k v )
        = k + k 1
    }
    ^ == ( gpu_upload gb sp ) 0
}

unsafe @ gk_dbuf_download_i GpuKit kit GkBuf b ( Vec i ) dst → b {
    ? & ( gk_buf_ok b ) == . b dtype GK_I64 {} { ^ F }
    : i n . b n
    ? >= ( vec_len [i] dst ) n {} { ^ F }
    ^ == ( gpu_download # *u ( vec_data [i] dst ) ( gpu_buffer_view . b dptr * n 8 ) ) 0
}

// ── Raw device launch (no marshalling) ────────────────────────────────

// Compile-cached launch over pre-built args (device pointers via
// gk_arg_dev, scalars via gpu_arg_i64/_i32/_f32). Syncs before returning
// unless autosync is off (below).
@ gk_arg_dev GkBuf b → i { ^ . b dptr }

// Autosync: gk_run_dev (and every gkd_* kernel on top of it) normally
// syncs the device after each launch. An executor that chains hundreds of
// launches can turn this off, launch away, and gk_sync once at the end —
// the CUDA stream serialises kernels, and downloads synchronise
// implicitly; the CPU backend runs launches synchronously either way.
// gk_autosync switches it for every kit of the process; gk_async for one
// kit, which is what a library holding its own kit wants — it does not
// change how anyone else's launches behave.
: ~ b g_gk_autosync T

@ gk_autosync b on → v { = g_gk_autosync on }

@ gk_async GpuKit h b on → v {
    : ~ GkState kit ( locked_take [GkState] . h st )
    = . kit async on
    ( locked_restore [GkState] . h st kit )
}

@ gk_sync GpuKit kit → b {
    ? ( _gk_census kit ) { ^ T } {}
    ^ == ( gpu_sync . ( arc_get [GkInfo] . kit info ) gpu ) 0
}

// ── Per-kernel profiling ──────────────────────────────────────────────
// "The model is slow" is not actionable; "78% of the frame is in three
// kernels" is. With profiling on, every gk_run_dev launch is bracketed by
// a CUDA event pair (the kit's own, made on first use) and the device
// time is accumulated into the kernel's cache slot, so gk_prof_report
// ranks the kernels by where the time actually went. Events measure the
// GPU, not the launch — a host clock around an async launch measures
// neither.
//
// It is not free: each launch waits for its own end event, which
// serialises the stream. Turn it on to find the hot kernel, off to time
// the program.
: ~ b g_gk_prof F

@ gk_prof GpuKit h b on → v {
    ? & on ( _gk_ok h ) {
        : GkInfo inf ( arc_get [GkInfo] . h info )
        : ~ GkState kit ( locked_take [GkState] . h st )
        ? ( gpu_timer_ok . kit ev0 ) {} {
            = . kit ev0 ( gpu_timer_new . inf gpu )
            = . kit ev1 ( gpu_timer_new . inf gpu )
        }
        = g_gk_prof ( gpu_timer_ok . kit ev0 )
        ( locked_restore [GkState] . h st kit )
    } { = g_gk_prof F }
}

@ gk_prof_on → b { ^ g_gk_prof }

// Drop every accumulated count — e.g. after a warm-up frame, so the
// numbers describe the steady state and not the compiles.
@ gk_prof_reset GpuKit h → v {
    : ~ GkState kit ( locked_take [GkState] . h st )
    : i n ( vec_len [i] . kit kcalls )
    : ~ i k 0
    ~ < k n {
        // counters only — the name and the kernel stay put
        ( vec_put [i] . kit kcalls k 0 )
        ( vec_put [i] . kit kns k 0 )
        = k + k 1
    }
    ( locked_restore [GkState] . h st kit )
}

@ __gk_prof_add inout GkState kit i slot i ns → v {
    ? & >= slot 0 < slot ( vec_len [i] . kit kcalls ) {
        ( vec_put [i] . kit kcalls slot + ( vec_at [i] . kit kcalls slot ) 1 )
        ( vec_put [i] . kit kns slot + ( vec_at [i] . kit kns slot ) ns )
    } {}
}

@ __gk_prof_sum GkState kit → i {
    : ~ i total 0
    : ~ i k 0
    ~ < k ( vec_len [i] . kit kns ) {
        = total + total ( vec_at [i] . kit kns k )
        = k + k 1
    }
    ^ total
}

// Total device time accumulated so far, in nanoseconds.
@ gk_prof_total GpuKit h → i {
    : GkState kit ( locked_take [GkState] . h st )
    : i t ( __gk_prof_sum kit )
    ( locked_restore [GkState] . h st kit )
    ^ t
}

// Kernels by device time, slowest first, with the share of the total.
@ gk_prof_report GpuKit h → v {
    : GkState kit ( locked_take [GkState] . h st )
    ( __gk_prof_report_in kit )
    ( locked_restore [GkState] . h st kit )
}

@ __gk_prof_report_in GkState kit → v {
    : i n ( vec_len [GkKernelEntry] . kit cache )
    : i total ( __gk_prof_sum kit )
    ( nurl_print `gpukit profile: ` )
    ( nurl_print ( nurl_str_int / total 1000000 ) )
    ( nurl_print ` ms of device time over ` )
    ( nurl_print ( nurl_str_int n ) )
    ( nurl_print ` kernels\n` )
    ? == total 0 { ^ } {}
    // selection sort over the slot indices: a dozen entries, printed once
    : ( Vec i ) done ( vec_new [i] )
    : ~ i shown 0
    ~ < shown n {
        : ~ i best - 0 1
        : ~ i bestns - 0 1
        : ~ i j 0
        ~ < j n {
            : ~ b seen F
            : ~ i q 0
            ~ < q ( vec_len [i] done ) {
                ?? ( vec_get [i] done q ) { T d → { ? == d j { = seen T } {} } F → {} }
                = q + q 1
            }
            ? seen {} {
                : i nsj ( vec_at [i] . kit kns j )
                ? > nsj bestns { = bestns nsj = best j } {}
            }
            = j + j 1
        }
        ? < best 0 { = shown n } {
            ( vec_push [i] done best )
            : i calls ( vec_at [i] . kit kcalls best )
            : i ns ( vec_at [i] . kit kns best )
            ?? ( vec_get [GkKernelEntry] . kit cache best ) {
                T e → {
                    ? > calls 0 {
                        ( nurl_print `  ` )
                        ( nurl_print ( nurl_str_int / * ns 100 total ) )
                        ( nurl_print `%  ` )
                        ( nurl_print ( nurl_str_int / ns 1000 ) )
                        ( nurl_print ` us  ` )
                        ( nurl_print ( nurl_str_int calls ) )
                        ( nurl_print ` calls  ` )
                        ( nurl_print ( nurl_str_int / ns calls ) )
                        ( nurl_print ` ns/call  ` )
                        ( nurl_print ( string_data . e name ) )
                        ( nurl_print `\n` )
                    } {}
                }
                F _ → {}
            }
            = shown + shown 1
        }
    }
}

// Launch kernel `name` of `src` over raw argument words. The caller vouches
// that the words fit the kernel. The kit compiles a kernel the first time
// its NAME is launched and keys its cache by that name: one name is one
// kernel, and a second source under a name already launched runs the first.
raw @ gk_run_dev GpuKit h s src s name i grid i block ( Vec i ) args → b {
    ? ( _gk_ok h ) {} { ^ F }
    : GkInfo inf ( arc_get [GkInfo] . h info )
    : ~ GkState kit ( locked_take [GkState] . h st )
    : b ok ( __gk_launch_in kit inf src name grid block args )
    : b wait & g_gk_autosync ! . kit async
    ( locked_restore [GkState] . h st kit )
    ? ok {} { ^ F }
    ? . inf census { ^ T } {}
    ? wait { ^ == ( gpu_sync . inf gpu ) 0 } {}
    ^ T
}

// The cache slot of kernel `name` (compiled from `src` on first use), -1
// when it does not compile. A kit's cache only grows, so the slot stays
// this kernel's for as long as the kit lives.
unsafe @ _gk_slot_of GpuKit h s src s name → i {
    ? ( _gk_ok h ) {} { ^ -1 }
    : GkInfo inf ( arc_get [GkInfo] . h info )
    : ~ GkState kit ( locked_take [GkState] . h st )
    : i slot ( _gk_kernel_slot kit inf src name )
    ( locked_restore [GkState] . h st kit )
    ^ slot
}

// gk_run_dev with the kernel's slot already known (gk_replay): no name
// lookup. The caller vouches that `slot` is a slot of this kit's cache and
// `args` fit the kernel in it.
raw @ _gk_run_slot GpuKit h i slot i grid i block ( Vec i ) args → b {
    ? ( _gk_ok h ) {} { ^ F }
    : GkInfo inf ( arc_get [GkInfo] . h info )
    ? . inf census { ^ T } {}
    : ~ GkState kit ( locked_take [GkState] . h st )
    ? g_gk_prof { ( gpu_timer_mark . inf gpu . kit ev0 ) } {}
    : i rc ( _gk_slot_launch kit slot grid block args )
    ? & g_gk_prof == rc 0 {
        ( gpu_timer_mark . inf gpu . kit ev1 )
        ( __gk_prof_add kit slot ( gpu_timer_ns . inf gpu . kit ev0 . kit ev1 ) )
    } {}
    : b wait & g_gk_autosync ! . kit async
    ( locked_restore [GkState] . h st kit )
    ? == rc 0 {} { ^ F }
    ? wait { ^ == ( gpu_sync . inf gpu ) 0 } {}
    ^ T
}

// Compile (cached) and launch, the state held: F when the compile or the
// launch failed. A census kit records the kernel and launches nothing.
raw @ __gk_launch_in inout GkState kit GkInfo inf s src s name i grid i block ( Vec i ) args → b {
    : i slot ( _gk_kernel_slot kit inf src name )
    ? >= slot 0 {} { ^ F }
    ? . inf census { ^ T } {}
    ? g_gk_prof { ( gpu_timer_mark . inf gpu . kit ev0 ) } {}
    ? == ( _gk_slot_launch kit slot grid block args ) 0 {} { ^ F }
    ? g_gk_prof {
        ( gpu_timer_mark . inf gpu . kit ev1 )
        ( __gk_prof_add kit slot ( gpu_timer_ns . inf gpu . kit ev0 . kit ev1 ) )
    } {}
    ^ T
}

// ── Elementwise binary with scalar broadcast ──────────────────────────
// out[i] = a[i] <op> b[i*bs]; bs = 1 for a full vector, 0 broadcasts b[0].

// The kernel, in gpukit's checked subset (gk_run_checked_dev): every
// element read and written is checked against its buffer.
@ __gkd_ew_body s op → String {
    : ~ String s ( string_from `if (gid < n) { ST(o, gid, LD(a, gid) ` )
    ( string_push_str s op )
    ( string_push_str s ` LD(b, gid * bs)); }` )
    ^ s
}

// `op` is one of + - * / and `opname` an identifier (gk_op_ok,
// gk_name_ok); F otherwise.
@ gkd_ew GpuKit kit s opname s op GkBuf o GkBuf a GkBuf b → b {
    ? & ( gk_name_ok opname ) ( gk_op_ok op ) {} { ^ F }
    ? & & ( gk_buf_ok o ) ( gk_buf_ok a ) ( gk_buf_ok b ) {} { ^ F }
    ? & == . o dtype . a dtype == . a dtype . b dtype {} { ^ F }
    : i n . o n
    : i bs ? == . b n 1 { 0 } { 1 }
    ? | == . b n 1 == . b n n {} { ^ F }
    ? == . a n n {} { ^ F }
    : ~ String kname ( string_from ( _gk_pfx . o dtype ) )
    ( string_push_str kname opname )
    : String body ( __gkd_ew_body op )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `a` a ) ( gk_call_dev c `b` b ) ( gk_call_dev c `o` o )
    ( gk_call_i64 c `bs` bs ) ( gk_call_i64 c `n` n )
    ^ ( gk_run_checked_dev kit c ( string_data kname ) ( string_data body ) ( gk_grid n 256 ) 256 )
}

@ gkd_add GpuKit kit GkBuf o GkBuf a GkBuf b → b { ^ ( gkd_ew kit `add` `+` o a b ) }

@ gkd_sub GpuKit kit GkBuf o GkBuf a GkBuf b → b { ^ ( gkd_ew kit `sub` `-` o a b ) }

@ gkd_mul GpuKit kit GkBuf o GkBuf a GkBuf b → b { ^ ( gkd_ew kit `mul` `*` o a b ) }

@ gkd_div GpuKit kit GkBuf o GkBuf a GkBuf b → b { ^ ( gkd_ew kit `div` `/` o a b ) }

// ── Elementwise binary with full N-D stride broadcast ─────────────────
// The output is dense row-major over `odims` (≤6 dims); each input is read
// at Σ coord[k]·str[k], so a 0 stride broadcasts that dim and general
// numpy broadcasting is one stride table away. The wrapper proves the
// largest reachable offset fits inside each input buffer before launching,
// so a bad stride table fails closed instead of reading out of bounds.

@ _gk_vi ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 } }

// Largest linear offset the kernel can form over `nd` dims: Σ (d−1)·stride.
@ __gk_maxoff ( Vec i ) dims ( Vec i ) str i nd → i {
    : ~ i off 0
    : ~ i k 0
    ~ < k nd {
        : i d ( _gk_vi dims k )
        : i st ( _gk_vi str k )
        ? & > d 1 > st 0 { = off + off * - d 1 st } {}
        = k + k 1
    }
    ^ off
}

// The checked kernel: output element i's coordinates over the six
// (left-padded) dims give each input's offset through its stride table.
@ __gkd_ewbc_body s op → String {
    : ~ String s ( string_from `if (gid < n) {
    long long t = gid, ai = 0, bi = 0, c = 0;
    c = t % d5; t /= d5; ai += c * A5; bi += c * B5;
    c = t % d4; t /= d4; ai += c * A4; bi += c * B4;
    c = t % d3; t /= d3; ai += c * A3; bi += c * B3;
    c = t % d2; t /= d2; ai += c * A2; bi += c * B2;
    c = t % d1; t /= d1; ai += c * A1; bi += c * B1;
    c = t; ai += c * A0; bi += c * B0;
    ST(o, gid, LD(a, ai) ` )
    ( string_push_str s op )
    ( string_push_str s ` LD(b, bi));
}` )
    ^ s
}

// out over `odims`; a and b read through their stride tables (entries ≥ 0,
// 0 = broadcast). Float dtypes only.
@ gkd_ew_bc GpuKit kit s opname s op GkBuf o GkBuf a GkBuf b ( Vec i ) odims ( Vec i ) astr ( Vec i ) bstr → b {
    ? & ( gk_name_ok opname ) ( gk_op_ok op ) {} { ^ F }
    ? & & ( gk_buf_ok o ) ( gk_buf_ok a ) ( gk_buf_ok b ) {} { ^ F }
    ? & == . o dtype . a dtype == . a dtype . b dtype {} { ^ F }
    ? != . o dtype GK_I64 {} { ^ F }
    : i nd ( vec_len [i] odims )
    ? & & > nd 0 <= nd 6 & == ( vec_len [i] astr ) nd == ( vec_len [i] bstr ) nd {} { ^ F }
    : ~ i total 1
    : ~ b good T
    : ~ i k 0
    ~ < k nd {
        ? > ( _gk_vi odims k ) 0 {} { = good F }
        ? & >= ( _gk_vi astr k ) 0 >= ( _gk_vi bstr k ) 0 {} { = good F }
        = total * total ( _gk_vi odims k )
        = k + k 1
    }
    ? good {} { ^ F }
    ? == total . o n {} { ^ F }
    ? & < ( __gk_maxoff odims astr nd ) . a n < ( __gk_maxoff odims bstr nd ) . b n {} { ^ F }
    : ~ String kname ( string_from ( _gk_pfx . o dtype ) )
    ( string_push_str kname `bc` )
    ( string_push_str kname opname )
    : String body ( __gkd_ewbc_body op )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `a` a ) ( gk_call_dev c `b` b ) ( gk_call_dev c `o` o )
    ( gk_call_i64 c `n` total )
    : i pad - 6 nd
    // dims, then a-strides, then b-strides — each left-padded to 6 entries
    : String dn ( string_from `d0 d1 d2 d3 d4 d5 A0 A1 A2 A3 A4 A5 B0 B1 B2 B3 B4 B5` )
    = k 0
    ~ < k 6 {
        : i dv ? < k pad { 1 } { ( _gk_vi odims - k pad ) }
        : i av ? < k pad { 0 } { ( _gk_vi astr - k pad ) }
        : i bv ? < k pad { 0 } { ( _gk_vi bstr - k pad ) }
        ( _gkd_dim_arg c `d` k dv ) ( _gkd_dim_arg c `A` k av ) ( _gkd_dim_arg c `B` k bv )
        = k + k 1
    }
    ^ ( gk_run_checked_dev kit c ( string_data kname ) ( string_data body ) ( gk_grid total 256 ) 256 )
}

// Bind scalar `<p><k>` (d0, A3, …) to `v`.
@ _gkd_dim_arg inout GkCall c s p i k i v → v {
    : ~ String nm ( string_from p )
    ( string_push_int nm k )
    ( gk_call_i64 c ( string_data nm ) v )
}

// ── Unary map: out[i] = expr(x) with x = in[i] ────────────────────────
// `expr` is C over the local `T x`; use the dtype-suffixed math calls via
// the helpers below (they pick expf vs exp, …).

// `expr` is checked like gk_map_f's (gk_expr_ok); F otherwise.
@ gkd_map GpuKit kit s mapname s expr GkBuf o GkBuf a → b {
    ? & ( gk_name_ok mapname ) ( gk_expr_ok expr ) {} { ^ F }
    ? & ( gk_buf_ok o ) ( gk_buf_ok a ) {} { ^ F }
    ? & == . o dtype . a dtype == . o n . a n {} { ^ F }
    : i n . o n
    : ~ String kname ( string_from ( _gk_pfx . o dtype ) )
    ( string_push_str kname mapname )
    : ~ String body ( string_from `if (gid < n) { ` )
    ( string_push_str body ( _gk_tname . o dtype ) )
    ( string_push_str body ` x = LD(a, gid); ST(o, gid, (` )
    ( string_push_str body expr )
    ( string_push_str body `)); }` )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `a` a ) ( gk_call_dev c `o` o ) ( gk_call_i64 c `n` n )
    ^ ( gk_run_checked_dev kit c ( string_data kname ) ( string_data body ) ( gk_grid n 256 ) 256 )
}

@ gkd_relu GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `relu` `x>0.0f?x:0.0f` o a ) } {}
    ^ ( gkd_map kit `relu` `x>0.0?x:0.0` o a )
}

@ gkd_sigmoid GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `sigmoid` `1.0f/(1.0f+expf(-x))` o a ) } {}
    ^ ( gkd_map kit `sigmoid` `1.0/(1.0+exp(-x))` o a )
}

@ gkd_exp GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `exp` `expf(x)` o a ) } {}
    ^ ( gkd_map kit `exp` `exp(x)` o a )
}

@ gkd_tanh GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `tanh` `tanhf(x)` o a ) } {}
    ^ ( gkd_map kit `tanh` `tanh(x)` o a )
}

@ gkd_sqrt GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `sqrt` `sqrtf(x)` o a ) } {}
    ^ ( gkd_map kit `sqrt` `sqrt(x)` o a )
}

@ gkd_log GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `log` `logf(x)` o a ) } {}
    ^ ( gkd_map kit `log` `log(x)` o a )
}

// ── Matmul: C[M×N] = A[M×K]·B[K×N], row-major, sequential-k accumulate ─

// Rows / columns of C one CPU-backend thread owns. See _gk_tile_body.
: i GKD_RT 8
: i GKD_CT 32

@ _gkd_ceil i x i q → i { ^ / + x - q 1 q }

// The multiply-accumulate step, spelled the way each element type's
// contract requires: F64 with explicit round-to-nearest intrinsics
// (NVRTC's fmad contraction would otherwise fuse and change the bits),
// F32 plain (its contract is true-float32 semantics, which the verified
// model goldens pin). `dst` and the product operands are C expressions.
@ _gkd_mac i dtype s dst s x s y → String {
    : String s ( string_from dst )
    ? == dtype GK_F64 {
        ( string_push_str s `=__dadd_rn(` )
        ( string_push_str s dst )
        ( string_push_str s `,__dmul_rn(` )
        ( string_push_str s x ) ( string_push_char s 44 ) ( string_push_str s y )
        ( string_push_str s `));` )
    } {
        ( string_push_str s `+=` )
        ( string_push_str s x ) ( string_push_char s 42 ) ( string_push_str s y )
        ( string_push_char s 59 )
    }
    ^ s
}

// The CPU backend's register-tiled body (8x32 per thread, B read along
// a row) is kernels.nu's _gk_tile_body, shared with gk_matmul_f.

// The shared-memory tiled matmul for the CUDA backend — the body behind
// gkd_gemm and gkd_bmm both (_gkd_smem_cbody).
//
// One thread per output element (the shape this file shipped with) is
// bandwidth-bound: every MAC costs a fresh global load of B, so a 4090
// runs it at ~3 TFLOP/s, about 4% of what its FP32 units can do. Here a
// 256-thread block owns a 64x64 tile of Y, stages 64x16 of A and 16x64
// of B into shared memory, and each thread keeps a 4x4 register tile. B
// is read once per tile instead of once per output row, and the
// arithmetic intensity goes from 1 MAC per load to 32. Measured on a
// 4090 at 783x1024x1024 f32: 3.1 -> 11.5 TFLOP/s, and 0.6 -> 11.1 with
// B transposed (the per-element kernel reads a transposed B along the
// wrong axis entirely).
//
// **The accumulation order is unchanged**: each output still sums
// t = 0..K-1 ascending, only blocked. Out-of-range staging slots hold a
// zero, so a ragged tail adds exact 0.0 terms — the value is
// bit-identical to the per-element kernel, which is what the verified
// model goldens pin. Nothing here reassociates.
//
// transb is baked into the body (and into the kernel name) rather than
// branched on per k: with B as [N,K] the staging loop walks k contiguously
// per column, so transb=1 loads coalesced too — which is why, unlike the
// CPU path, this one does not care which layout the weight arrives in.
//
// `batched` picks the bmm signature (per-batch A/B strides `as`/`bs`, a
// bare store) over the gemm one (alpha/beta and a per-column bias).
// The tile: a block owns GKD_BM x GKD_BN of Y and each of its 256
// threads a GKD_TM x GKD_TN register block, stepping K in GKD_BK.
//
// Why 128x64x16 with an 8x4 register tile and not the obvious 64x64 with
// 4x4: at 4x4 a thread reads 8 floats from shared per k step to do 16
// MACs, and Ada's 128 B/clk of shared bandwidth cannot keep 128 FMA
// lanes fed at that ratio — the kernel stalls on shared, not on math.
// 8x4 halves the ratio to 12 reads per 32 MACs. Going the whole way to
// 128x128/8x8 halves it again, but M here is ~800 rows and N is often
// 1024, which is 56 blocks — under half of a 4090's 128 SMs, so the
// wider tile loses more to idle SMs than it gains per SM.
: i GKD_BM 64
: i GKD_BN 64
: i GKD_BK 16
: i GKD_TM 4
: i GKD_TN 4

// `big` swaps the 64x64/4x4 tile for 128x64 with an 8x4 register tile —
// the shape the comment above argues for and gkd_gemm now picks when M
// is deep enough to keep every SM busy at it: 8x4 halves the
// shared-reads-per-MAC ratio (12 per 32 against 8 per 16), which is the
// bound the 64x64 tile runs into on Ada. Same staging, same ascending-k
// accumulation, so the value is still bit-identical to the per-element
// kernel — only the blocking changes. (On f32 the shared rows are read
// as 16-byte groups, LD4: one conflict-free load instead of four
// bank-conflicting ones, which needs the rows 16-byte aligned — hence
// a pad of 4 rather than the 1 that only separates banks.)

// Bind `b` as an input of `c`: read-only (restrict, and the read-only
// cache) unless it overlaps `out`, the buffer the kernel writes — an op
// called in place reads through a writable binding, as before.
@ _gkd_in inout GkCall c s name GkBuf b GkBuf out → v {
    : i e1 * . b n ( _gk_esz . b dtype )
    : i e2 * . out n ( _gk_esz . out dtype )
    ? & < . b dptr + . out dptr e2 < . out dptr + . b dptr e1 { ( gk_call_dev c name b ) } { ( gk_call_dev_in c name b ) }
}

// ── Checked matmul bodies (device buffers) ───────────────────────────

// alpha / beta as the element type: a checked scalar is a double, and an
// f32 GEMM's epilogue rounds in float.
@ _gkd_ab i dtype s nm → String {
    : ~ String s ( string_from ? == dtype GK_F32 `((float)` `(` )
    ( string_push_str s nm ) ( string_push_char s 41 )
    ^ s
}

// The CUDA shared-memory tile, checked (see the notes above for the
// design and the measurements: a block owns a 64x64 or 128x64 tile of Y,
// stages 16-wide slices of A and B into shared memory, each thread keeps
// a 4x4 or 8x4 register block). The tiles are SHARED arrays — an f32 one
// read four at a time with LD4, a 16-byte shared load — and every index
// into them and into the register block is made of `tid`, loop counters
// and constants, so its check folds. The staging loads are checked
// against their buffers. Each output still sums t = 0..K-1 ascending,
// out-of-range slots adding exact zeros: bit-identical to the raw tile.
//
// Bindings A, B, Y (and Cb, the bias, for the GEMM); scalars M, N, K,
// and alpha, beta, hasB (GEMM) or as, bs (batched: per-batch strides,
// 0 broadcasting).
@ _gkd_smem_cbody s tn i dtype b transb b batched b big → String {
    : b vec4 == dtype GK_F32
    : i bm ? big 128 64
    : i tm ? big 8 4
    : i pad ? vec4 4 1
    : ~ String s ( string_new )
    ( string_push_str s ? vec4 `SHARED_F(As, ` `SHARED_D(As, ` ) ( string_push_int s * 16 + bm pad ) ( string_push_str s `);
` )
    ( string_push_str s ? vec4 `SHARED_F(Bs, ` `SHARED_D(Bs, ` ) ( string_push_int s * 16 + 64 pad ) ( string_push_str s `);
` )
    ( string_push_str s ? vec4 `LOCAL_F(acc, ` `LOCAL_D(acc, ` ) ( string_push_int s * tm 4 ) ( string_push_str s `);
` )
    : ~ String sb ( string_new )
    ( string_push_str sb `const int BM = ` ) ( string_push_int sb bm ) ( string_push_str sb `, BN = 64, BK = 16, TM = ` ) ( string_push_int sb tm )
    ( string_push_str sb `, TN = 4, NT = 256, PA = ` ) ( string_push_int sb + bm pad ) ( string_push_str sb `, PB = ` ) ( string_push_int sb + 64 pad ) ( string_push_str sb `;
long long nbx = (N + BN - 1) / BN;
` )
    ? batched {
        ( string_push_str sb `long long nby = (M + BM - 1) / BM, tpb = nbx * nby;
long long bi = bid / tpb, tile = bid % tpb;
long long rb = (tile / nbx) * BM, cb = (tile % nbx) * BN;
long long ao = bi * as, bo = bi * bs;
` )
    } {
        ( string_push_str sb `long long rb = (bid / nbx) * BM, cb = (bid % nbx) * BN;
long long ao = 0, bo = 0;
` )
    }
    ( string_push_str sb `int tr = tid / (BN / TN), tc = tid % (BN / TN);
for (long long k0 = 0; k0 < K; k0 += BK) {
    for (int l = 0; l < BM * BK / NT; l++) {
        int id = l * NT + tid; int ar = id / BK, ak = id % BK; long long gr = rb + ar, gk = k0 + ak;
        ST(As, ak * PA + ar, (gr < M && gk < K) ? LD(A, ao + gr * K + gk) : 0);
    }
    for (int l = 0; l < BK * BN / NT; l++) {
        int id = l * NT + tid;
` )
    ? transb {
        ( string_push_str sb `        int bn = id / BK, bk = id % BK; long long gk = k0 + bk, gc = cb + bn;
        ST(Bs, bk * PB + bn, (gk < K && gc < N) ? LD(B, bo + gc * K + gk) : 0);
` )
    } {
        ( string_push_str sb `        int bk = id / BN, bn = id % BN; long long gk = k0 + bk, gc = cb + bn;
        ST(Bs, bk * PB + bn, (gk < K && gc < N) ? LD(B, bo + gk * N + gc) : 0);
` )
    }
    ( string_push_str sb `    }
    SYNC();
    for (int kk = 0; kk < BK; kk++) {
` )
    ? vec4 {
        ( string_push_str sb `        float a0, a1, a2, a3, b0, b1, b2, b3;
        LD4(As, kk * PA + tr * TM, a0, a1, a2, a3);
` )
        ? big {
            ( string_push_str sb `        float a4, a5, a6, a7;
        LD4(As, kk * PA + tr * TM + 4, a4, a5, a6, a7);
` )
        } {}
        ( string_push_str sb `        LD4(Bs, kk * PB + tc * TN, b0, b1, b2, b3);
` )
    } {
        : ~ i q 0
        ~ < q tm {
            ( string_push_str sb `        double a` ) ( string_push_int sb q ) ( string_push_str sb ` = LD(As, kk * PA + tr * TM + ` ) ( string_push_int sb q ) ( string_push_str sb `);
` )
            = q + q 1
        }
        ( string_push_str sb `        double b0 = LD(Bs, kk * PB + tc * TN), b1 = LD(Bs, kk * PB + tc * TN + 1), b2 = LD(Bs, kk * PB + tc * TN + 2), b3 = LD(Bs, kk * PB + tc * TN + 3);
` )
    }
    // (the register block's multiply-adds written out, i then j, as the
    // raw tile's loops ran them)
    : ~ i i 0
    ~ < i tm {
        : ~ i j 0
        ~ < j 4 {
            : ~ String ix ( string_new ) ( string_push_int ix + * i 4 j )
            : ~ String av ( string_from `a` ) ( string_push_int av i )
            : ~ String bv ( string_from `b` ) ( string_push_int bv j )
            ( string_push_str sb `        ` )
            ( string_push_str sb ( string_data ( _gk_cmac dtype ( string_data ix ) ( string_data av ) ( string_data bv ) ) ) )
            ( string_push_str sb `
` )
            = j + j 1
        }
        = i + i 1
    }
    // (a row of the block's tile of Y as a window, past N outside it: a
    // store's own check is the edge test, and the row's stores are at
    // constant offsets from one base)
    ( string_push_str sb `    }
    SYNC();
}
long long cols = N - cb < BN ? N - cb : BN;
for (int i = 0; i < TM; i++) {
    long long gr = rb + tr * TM + i;
    if (gr < M) {
` )
    ( string_push_str sb ? batched `        WIN(yr, Y, (bi * M + gr) * N + cb, cols);
` `        WIN(yr, Y, gr * N + cb, cols);
` )
    ( string_push_str sb `        for (int j = 0; j < TN; j++) {
` )
    ? batched {
        ( string_push_str sb `            ST(yr, tc * TN + j, LD(acc, i * TN + j));
` )
    } {
        // (alpha·acc rounded on its own, beta·bias fused into the add —
        // the raw kernel's compile chose that, and naming it keeps the
        // code around it from changing which product fuses)
        ( string_push_str sb `            long long gc = cb + tc * TN + j;
            ` ) ( string_push_str sb tn ) ( string_push_str sb ` bias = hasB != 0 ? LD(Cb, gc) : 0;
            ST(yr, tc * TN + j, ` ) ( string_push_str sb ? == dtype GK_F32 `__fmul_rn(` `__dmul_rn(` ) ( string_push_str sb ( string_data ( _gkd_ab dtype `alpha` ) ) )
        ( string_push_str sb `, LD(acc, i * TN + j)) + ` ) ( string_push_str sb ( string_data ( _gkd_ab dtype `beta` ) ) ) ( string_push_str sb ` * bias);
` )
    }
    ( string_push_str sb `        }
    }
}` )
    ( string_push_str s ( string_data sb ) )
    ^ s
}

// The GEMV on CUDA, checked: a block per output, its threads staging
// the two operand chunks coalesced into shared memory, and one thread's
// single ascending sum over them (see gkd_gemm).
@ _gkd_gemv_cbody s tn i dtype b transb → String {
    : ~ String s ( string_from ? == dtype GK_F32 `SHARED_F(sa, 1024);
SHARED_F(sb, 1024);
` `SHARED_D(sa, 1024);
SHARED_D(sb, 1024);
` )
    ( string_push_str s `if (bid < M * N) {
    long long r = bid / N, c = bid % N;
    ` ) ( string_push_str s tn ) ( string_push_str s ` acc = 0;
    for (long long k0 = 0; k0 < K; k0 += 1024) {
        long long cnt = K - k0 < 1024 ? K - k0 : 1024;
        for (long long j = tid; j < cnt; j += bdim) {
            ST(sa, j, LD(A, r * K + k0 + j));
            ST(sb, j, ` ) ( string_push_str s ? transb `LD(B, c * K + k0 + j)` `LD(B, (k0 + j) * N + c)` ) ( string_push_str s `);
        }
        SYNC();
        // (a whole chunk to a constant bound: its shared reads' checks fold)
        if (tid == 0) {
            if (cnt == 1024) {
                for (int j = 0; j < 1024; j++) { ` ) ( string_push_str s ( string_data ( _gkd_mac dtype `acc` `LD(sa, j)` `LD(sb, j)` ) ) ) ( string_push_str s ` }
            } else {
                for (long long j = 0; j < cnt; j++) { ` ) ( string_push_str s ( string_data ( _gkd_mac dtype `acc` `LD(sa, j)` `LD(sb, j)` ) ) ) ( string_push_str s ` }
            }
        }
        SYNC();
    }
    if (tid == 0) {
        ` ) ( string_push_str s tn ) ( string_push_str s ` bias = hasB != 0 ? LD(Cb, c) : 0;
        ST(Y, bid, ` ) ( string_push_str s ( string_data ( _gkd_ab dtype `alpha` ) ) ) ( string_push_str s ` * acc + ` ) ( string_push_str s ( string_data ( _gkd_ab dtype `beta` ) ) ) ( string_push_str s ` * bias);
    }
}` )
    ^ s
}

// One thread per output, checked: A's row and B's column as windows (a
// column of B is strided unless B is transposed). `mac` T: the sum is
// spelled as _gkd_mac spells it (gkd_matmul, gkd_bmm); F: a plain
// `acc += a * b`, which CUDA may fuse — the GEMM's per-element kernel
// always did. `gemm`: the alpha/beta/bias epilogue; `batched`: offsets
// per batch (as, bs), `nb` batches.
@ _gkd_elem_cbody s tn i dtype b transb b gemm b batched b mac → String {
    : ~ String s ( string_new )
    ( string_push_str s ? batched `if (gid < nb * M * N) {
    long long c = gid % N, t = gid / N, r = t % M, bi = t / M;
    long long ao = bi * as, bo = bi * bs;
` `if (gid < M * N) {
    long long r = gid / N, c = gid % N;
    long long ao = 0, bo = 0;
` )
    ( string_push_str s `    WIN(ar, A, ao + r * K, K);
    ` ) ( string_push_str s ? transb `WIN(bc, B, bo + c * K, K);` `WINS(bc, B, bo + c, K, N);` )
    ( string_push_str s `
    ` ) ( string_push_str s tn ) ( string_push_str s ` acc = 0;
    if (LEN(ar) == K && LEN(bc) == K) {
        for (long long k = 0; k < K; k++) { ` )
    ? mac { ( string_push_str s ( string_data ( _gkd_mac dtype `acc` `LD(ar, k)` `LD(bc, k)` ) ) ) } { ( string_push_str s `acc += LD(ar, k) * LD(bc, k);` ) }
    ( string_push_str s ` }
    }
` )
    ? gemm {
        ( string_push_str s `    ` ) ( string_push_str s tn ) ( string_push_str s ` bias = hasB != 0 ? LD(Cb, c) : 0;
    ST(Y, gid, ` ) ( string_push_str s ( string_data ( _gkd_ab dtype `alpha` ) ) ) ( string_push_str s ` * acc + ` ) ( string_push_str s ( string_data ( _gkd_ab dtype `beta` ) ) ) ( string_push_str s ` * bias);
}` )
    } {
        ( string_push_str s `    ST(Y, gid, acc);
}` )
    }
    ^ s
}

@ gkd_matmul GpuKit kit GkBuf c GkBuf a GkBuf b i m i k i n → b {
    ? & & ( gk_buf_ok c ) ( gk_buf_ok a ) ( gk_buf_ok b ) {} { ^ F }
    ? & == . c dtype . a dtype == . a dtype . b dtype {} { ^ F }
    ? & & == . a n ( _gk_p2 m k ) == . b n ( _gk_p2 k n ) == . c n ( _gk_p2 m n ) {} { ^ F }
    : b on_cpu ( nurl_str_eq ( gk_backend kit ) `cpu` )
    : s tn ( _gk_tname . c dtype )
    : i dt . c dtype
    : String kname ( string_from ( _gk_pfx dt ) )
    ( string_push_str kname ? on_cpu `matmul_tiled` `matmul` )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `A` a c ) ( _gkd_in cl `B` b c ) ( gk_call_dev cl `Y` c )
    ( gk_call_i64 cl `M` m ) ( gk_call_i64 cl `K` k ) ( gk_call_i64 cl `N` n )
    : i total ? on_cpu
    * ( _gkd_ceil m GKD_RT ) ( _gkd_ceil n GKD_CT )
    * m n
    ^ ( gk_run_checked_dev_tagged kit cl ( string_data kname ) `` \ → String { ^ ? on_cpu ( _gk_tile_body tn dt F F ) ( _gkd_elem_cbody tn dt F F F T ) } ( gk_grid total 256 ) 256 )
}

// ── Batched matmul: Y[b,M,N] = A[b,M,K]·B[b,K,N] ──────────────────────
// `abatch` / `bbatch` say whether that operand carries the batch dim;
// 0 broadcasts its single matrix across the whole batch. Accumulation is
// sequential over K in the element type, exactly like gkd_matmul.

@ gkd_bmm GpuKit kit GkBuf y GkBuf a GkBuf b i batch i m i kk i n i abatch i bbatch → b {
    ? & & ( gk_buf_ok y ) ( gk_buf_ok a ) ( gk_buf_ok b ) {} { ^ F }
    ? & == . y dtype . a dtype == . a dtype . b dtype {} { ^ F }
    ? != . y dtype GK_I64 {} { ^ F }
    ? & & & > batch 0 > m 0 > kk 0 > n 0 {} { ^ F }
    : i asz ? != abatch 0 { ( _gk_p3 batch m kk ) } { ( _gk_p2 m kk ) }
    : i bsz ? != bbatch 0 { ( _gk_p3 batch kk n ) } { ( _gk_p2 kk n ) }
    ? & & == . a n asz == . b n bsz == . y n ( _gk_p3 batch m n ) {} { ^ F }
    : i astep ? != abatch 0 { * m kk } { 0 }
    : i bstep ? != bbatch 0 { * kk n } { 0 }
    : b on_cpu ( nurl_str_eq ( gk_backend kit ) `cpu` )
    // The attention matmuls a transformer runs are exactly the shapes the
    // shared-memory tile exists for; see _gkd_smem_cbody. Same threshold as
    // gkd_gemm: a 64x64 tile has to be worth filling.
    : b on_cuda ( nurl_str_eq ( gk_backend kit ) `cuda` )
    : b smem & & & on_cuda >= m 16 >= n 32 >= kk 16
    : s tn ( _gk_tname . y dtype )
    : i dt . y dtype
    : String kname ( string_from ( _gk_pfx dt ) )
    ( string_push_str kname ? smem `bmm_smem` ? on_cpu `bmm_tiled` `bmm` )
    : ~ GkCall cl ( gk_call_new )
    ( _gkd_in cl `A` a y ) ( _gkd_in cl `B` b y ) ( gk_call_dev cl `Y` y )
    ( gk_call_i64 cl `M` m ) ( gk_call_i64 cl `N` n ) ( gk_call_i64 cl `K` kk )
    ( gk_call_i64 cl `as` astep ) ( gk_call_i64 cl `bs` bstep ) ( gk_call_i64 cl `nb` batch )
    // the smem body maps ONE BLOCK to a 64x64 tile of one batch item, so
    // its launch is a block count, not a thread count
    ? smem {
        ^ ( gk_run_checked_dev_tagged kit cl ( string_data kname ) `` \ → String { ^ ( _gkd_smem_cbody tn dt F T F ) } * batch * ( _gkd_ceil m GKD_BM ) ( _gkd_ceil n GKD_BN ) 256 )
    } {}
    : i total ? on_cpu
    * batch * ( _gkd_ceil m GKD_RT ) ( _gkd_ceil n GKD_CT )
    * * batch m n
    ^ ( gk_run_checked_dev_tagged kit cl ( string_data kname ) `` \ → String { ^ ? on_cpu ( _gk_tile_body tn dt T F ) ( _gkd_elem_cbody tn dt F F T T ) } ( gk_grid total 256 ) 256 )
}

// ── Gather / Scatter along an axis ────────────────────────────────────
// The data is viewed as (outer, ax, inner); `ix` is a GK_I64 buffer of
// `nidx` indices into the axis, shared across every (outer, inner) pair.
// Negative indices wrap once (ONNX semantics). Out-of-range indices read
// 0 / skip the write — never out of bounds. Any element type.

@ gkd_gather GpuKit kit GkBuf y GkBuf d GkBuf ix i outer i axin i inner i nidx → b {
    ? & & & ( gk_buf_ok y ) ( gk_buf_ok d ) ( gk_buf_ok ix ) == . ix dtype GK_I64 {} { ^ F }
    ? == . y dtype . d dtype {} { ^ F }
    ? & & & > outer 0 > axin 0 > inner 0 > nidx 0 {} { ^ F }
    ? & & == . d n ( _gk_p3 outer axin inner ) == . y n ( _gk_p3 outer nidx inner ) >= . ix n nidx {} { ^ F }
    : ~ String kname ( string_from ( _gk_pfx . y dtype ) )
    ( string_push_str kname `gather` )
    : i total * * outer nidx inner
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `D` d ) ( gk_call_dev c `ix` ix ) ( gk_call_dev c `Y` y )
    ( gk_call_i64 c `axin` axin ) ( gk_call_i64 c `inner` inner ) ( gk_call_i64 c `nidx` nidx ) ( gk_call_i64 c `total` total )
    ^ ( gk_run_checked_dev kit c ( string_data kname ) `if (gid < total) {
    long long ii = gid % inner;
    long long t = gid / inner;
    long long g = t % nidx;
    long long o = t / nidx;
    long long x = LD(ix, g);
    if (x < 0) { x += axin; }
    if (x >= 0 && x < axin) { ST(Y, gid, LD(D, (o * axin + x) * inner + ii)); } else { ST(Y, gid, 0); }
}` ( gk_grid total 256 ) 256 )
}

// y = d with y[outer, ix[g], inner] = u[outer, g, inner]. When several
// indices collide the surviving write is unspecified (ONNX leaves this
// undefined too). `y` may be `d` itself for in-place update.
@ gkd_scatter GpuKit kit GkBuf y GkBuf d GkBuf ix GkBuf u i outer i ax i inner i nidx → b {
    ? & & & ( gk_buf_ok y ) ( gk_buf_ok d ) ( gk_buf_ok ix ) ( gk_buf_ok u ) {} { ^ F }
    ? & & == . y dtype . d dtype == . d dtype . u dtype == . ix dtype GK_I64 {} { ^ F }
    ? & & & > outer 0 > ax 0 > inner 0 > nidx 0 {} { ^ F }
    ? & == . y n . d n == . y n ( _gk_p3 outer ax inner ) {} { ^ F }
    ? & == . u n ( _gk_p3 outer nidx inner ) >= . ix n nidx {} { ^ F }
    : ~ String kname ( string_from ( _gk_pfx . y dtype ) )
    ? != . y dptr . d dptr {
        : ~ String cname ( string_from ( _gk_pfx . y dtype ) )
        ( string_push_str cname `copy` )
        : ~ GkCall cc ( gk_call_new )
        ( gk_call_dev cc `D` d ) ( gk_call_dev cc `Y` y ) ( gk_call_i64 cc `n` . y n )
        ? ( gk_run_checked_dev kit cc ( string_data cname ) `if (gid < n) { ST(Y, gid, LD(D, gid)); }` ( gk_grid . y n 256 ) 256 ) {} { ^ F }
    } {}
    ( string_push_str kname `scatter` )
    : i total * * outer nidx inner
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `Y` y ) ( gk_call_dev c `ix` ix ) ( gk_call_dev c `U` u )
    ( gk_call_i64 c `ax` ax ) ( gk_call_i64 c `inner` inner ) ( gk_call_i64 c `nidx` nidx ) ( gk_call_i64 c `total` total )
    ^ ( gk_run_checked_dev kit c ( string_data kname ) `if (gid < total) {
    long long ii = gid % inner;
    long long t = gid / inner;
    long long g = t % nidx;
    long long o = t / nidx;
    long long x = LD(ix, g);
    if (x < 0) { x += ax; }
    if (x >= 0 && x < ax) { ST(Y, (o * ax + x) * inner + ii, LD(U, gid)); }
}` ( gk_grid total 256 ) 256 )
}

// ── Row softmax: numerically stable, one thread per row ───────────────

@ gkd_softmax_rows GpuKit kit GkBuf o GkBuf a i rows i cols → b {
    ? & ( gk_buf_ok o ) ( gk_buf_ok a ) {} { ^ F }
    ? & == . o dtype . a dtype == . o n ( _gk_p2 rows cols ) {} { ^ F }
    ? > cols 0 {} { ^ F }  // each row reads its x[0]
    ? == . a n ( _gk_p2 rows cols ) {} { ^ F }
    : s tn ( _gk_tname . o dtype )
    : s ex ? == . o dtype GK_F32 { `expf` } { `exp` }
    : ~ String kname ( string_from ( _gk_pfx . o dtype ) )
    ( string_push_str kname `softmax` )
    : ~ String body ( string_from `if (gid < rows) {
    long long r0 = gid * cols;
    ` )
    ( string_push_str body tn ) ( string_push_str body ` m = LD(a, r0);
    for (long long k = 1; k < cols; k++) { if (LD(a, r0 + k) > m) { m = LD(a, r0 + k); } }
    ` )
    ( string_push_str body tn ) ( string_push_str body ` s = 0;
    for (long long k = 0; k < cols; k++) { ST(o, r0 + k, ` )
    ( string_push_str body ex ) ( string_push_str body `(LD(a, r0 + k) - m)); s += LD(o, r0 + k); }
    for (long long k = 0; k < cols; k++) { ST(o, r0 + k, LD(o, r0 + k) / s); }
}` )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `a` a ) ( gk_call_dev c `o` o ) ( gk_call_i64 c `rows` rows ) ( gk_call_i64 c `cols` cols )
    ^ ( gk_run_checked_dev kit c ( string_data kname ) ( string_data body ) ( gk_grid rows 256 ) 256 )
}

// ── Sum reduction (device partials + single-thread combine) ───────────
// Returns the sum as f64 regardless of the buffer dtype (partials
// accumulate in the buffer's element type).

@ gkd_sum GpuKit kit GkBuf a → ?f {
    ? ( gk_buf_ok a ) {} { ^ @ ?f { F } }
    : i n . a n
    ? <= n 0 { ^ @ ?f { T 0.0 } } {}
    : i threads ( _gk_partial_threads n )
    : GkBuf part ( gk_dbuf_new kit threads . a dtype )
    ? ( gk_buf_ok part ) {} { ^ @ ?f { F } }
    : s tn ( _gk_tname . a dtype )
    : ~ String kname ( string_from ( _gk_pfx . a dtype ) )
    ( string_push_str kname `rsum` )
    : ~ String body ( string_from tn )
    ( string_push_str body ` s = 0;
for (long long i = gid; i < n; i += nthreads) { s += LD(in, i); }
ST(partial, gid, s);` )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_dev c `in` a ) ( gk_call_dev c `partial` part ) ( gk_call_i64 c `n` n )
    : i blocks / threads 256
    : ~ b ok ( gk_run_checked_dev kit c ( string_data kname ) ( string_data body ) blocks 256 )
    : ~ f acc 0.0
    ? ok {
        : ( Vec f ) host ( _gk_zeros threads )
        ? ( gk_dbuf_download kit part host ) {
            : ~ i k 0
            ~ < k threads {
                ?? ( vec_get [f] host k ) { T v → { = acc + acc v } F _ → {} }
                = k + k 1
            }
        } { = ok F }
    } {}
    ? ok { ^ @ ?f { T acc } } { ^ @ ?f { F } }
}
