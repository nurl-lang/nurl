// packages/map-anything/src/load.nu — checkpoint → device buffers.
//
// `src/weights.nu` finds a tensor and checks its shape; this puts it on
// the device. The four Linear weights of every block are uploaded
// TRANSPOSED — torch stores [out, in], the device gets [in, out] — so
// ma_block_forward runs every gkd_gemm with transb=0 and the CPU
// backend takes its register-tiled kernel.
//
// f32 the whole way: the checkpoint is f32 and contiguous, so the fast
// path is a straight copy out of the mapping plus (for the Linears) one
// permute kernel on the device.
//
//   ( maw_upload w kit name )                → GkBuf   empty on failure
//   ( maw_upload_t w kit name rows cols )    → GkBuf   transposed
//   ( maw_block w kit prefix eps dim swh )   → MaBlk
//   ( maw_prefix base idx )                  → String  "<base>.<idx>."
//
// A missing tensor is recorded in the Lw error list rather than thrown,
// so a whole model's worth of loading reports the first thing wrong
// instead of the first thing touched.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`

@ __maw_none → GkBuf { ^ @ GkBuf { 0 0 GK_F32 } }

// One tensor onto the device, layout unchanged.
@ maw_upload * Lw w * GpuKit kit s name → GkBuf {
    : i n ( lw_nelems w name )
    ? <= n 0 {
        : b _r ( lw_require w name -1 -1 -1 -1 )
        ^ ( __maw_none )
    } {}
    : *u raw ( lw_f32_ptr w name n )
    ? != # i raw 0 {
        : GkBuf rb ( gk_dbuf_new kit n GK_F32 )
        ? ( gk_dbuf_upload_raw kit rb raw ) { ^ rb } {}
        ( gk_dbuf_free rb )
    } {}
    : ( Vec f ) host ( vec_with_cap [f] n )
    : b _sl ( vec_set_len [f] host n )
    ? ! ( lw_read w name ( vec_data [f] host ) n ) {
        ( vec_free [f] host )
        ^ ( __maw_none )
    } {}
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    : b _up ( gk_dbuf_upload kit b host )
    ( vec_free [f] host )
    ^ b
}

// Upload a [rows, cols] tensor TRANSPOSED, as [cols, rows] — straight
// out of the mapping, permuted on the device.
@ maw_upload_t * Lw w * GpuKit kit s name i rows i cols → GkBuf {
    : i n ( lw_nelems w name )
    ? | <= n 0 != n * rows cols {
        : b _r ( lw_require w name rows cols -1 -1 )
        ^ ( __maw_none )
    } {}
    : *u raw ( lw_f32_ptr w name n )
    ? != # i raw 0 {
        : GkBuf src ( gk_dbuf_new kit n GK_F32 )
        ? ( gk_dbuf_upload_raw kit src raw ) {
            : GkBuf dst ( gk_dbuf_new kit n GK_F32 )
            : ( Vec i ) dims ( vec_new [i] )
            ( vec_push [i] dims rows ) ( vec_push [i] dims cols )
            : ( Vec i ) perm ( vec_new [i] )
            ( vec_push [i] perm 1 ) ( vec_push [i] perm 0 )
            : b okp ( gkd_perm kit dst src dims perm )
            ( vec_free [i] dims ) ( vec_free [i] perm )
            ( gk_dbuf_free src )
            ? okp { ^ dst } {}
            ( gk_dbuf_free dst )
        } { ( gk_dbuf_free src ) }
    } {}
    // Host fallback: widen, transpose, upload.
    : ( Vec f ) host ( vec_with_cap [f] n )
    : b _sl ( vec_set_len [f] host n )
    ? ! ( lw_read w name ( vec_data [f] host ) n ) {
        ( vec_free [f] host )
        ^ ( __maw_none )
    } {}
    : ( Vec f ) tp ( vec_with_cap [f] n )
    : b _tl ( vec_set_len [f] tp n )
    : *f src ( vec_data [f] host )
    : *f dst ( vec_data [f] tp )
    : ~ i r 0
    ~ < r rows {
        : ~ i c 0
        ~ < c cols {
            = . dst + * c rows r . src + * r cols c
            = c + c 1
        }
        = r + r 1
    }
    ( vec_free [f] host )
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    : b _up ( gk_dbuf_upload kit b tp )
    ( vec_free [f] tp )
    ^ b
}

@ __maw_at * Lw w * GpuKit kit s prefix s leaf → GkBuf {
    : String nm ( string_from prefix )
    ( string_push_str nm leaf )
    : GkBuf b ( maw_upload w kit ( string_data nm ) )
    ( string_free nm )
    ^ b
}

@ __maw_at_t * Lw w * GpuKit kit s prefix s leaf i rows i cols → GkBuf {
    : String nm ( string_from prefix )
    ( string_push_str nm leaf )
    : GkBuf b ( maw_upload_t w kit ( string_data nm ) rows cols )
    ( string_free nm )
    ^ b
}

// Every parameter of one transformer block: the fourteen tensors under
// `<prefix>` (norm1, qkv, proj, ls1, norm2, w12, w3, ls2). Both stacks
// in this model share this exact layout; only `eps` could ever differ,
// and in this checkpoint both use 1e-6 (encoder blocks are built with
// partial(LayerNorm, eps=1e-6), the info_sharing blocks likewise).
@ maw_block * Lw w * GpuKit kit s prefix f eps i dim i swh → MaBlk {
    ^ @ MaBlk {
        ( __maw_at w kit prefix `norm1.weight` )
        ( __maw_at w kit prefix `norm1.bias` )
        ( __maw_at_t w kit prefix `attn.qkv.weight` * 3 dim dim )
        ( __maw_at w kit prefix `attn.qkv.bias` )
        ( __maw_at_t w kit prefix `attn.proj.weight` dim dim )
        ( __maw_at w kit prefix `attn.proj.bias` )
        ( __maw_at w kit prefix `ls1.gamma` )
        ( __maw_at w kit prefix `norm2.weight` )
        ( __maw_at w kit prefix `norm2.bias` )
        ( __maw_at_t w kit prefix `mlp.w12.weight` * 2 swh dim )
        ( __maw_at w kit prefix `mlp.w12.bias` )
        ( __maw_at_t w kit prefix `mlp.w3.weight` dim swh )
        ( __maw_at w kit prefix `mlp.w3.bias` )
        ( __maw_at w kit prefix `ls2.gamma` ) eps }
}

// `<base>.<idx>.` — the prefix of an indexed block.
@ maw_prefix s base i idx → String {
    : String nm ( string_from base )
    ( string_push_char nm 46 )
    ( string_push_int nm idx )
    ( string_push_char nm 46 )
    ^ nm
}
