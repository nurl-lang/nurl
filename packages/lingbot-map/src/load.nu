// packages/lingbot-map/src/load.nu — checkpoint → device buffers.
//
// `src/weights.nu` finds a tensor and checks its shape; this puts it on
// the device. Nothing is transposed: torch stores a Linear weight as
// [out, in] and `gkd_gemm` reads it with transb=1, so the bytes go
// across unchanged.
//
// f32 the whole way. The checkpoint is f32, the device buffers are f32,
// and the only f64 in between is the host staging vector — one tensor at
// a time, so peak extra memory is the largest single weight (an MLP's
// 4096x1024, 32 MB) rather than the model.
//
//   ( lmw_upload w kit name )              → GkBuf   empty on failure
//   ( lmw_block w kit prefix qk eps )      → LmBlk
//   ( lmw_ok w )                           → b       nothing failed yet
//
// A missing tensor is recorded in the Lw error list rather than thrown,
// so a whole model's worth of loading reports the first thing wrong
// instead of the first thing touched.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `src/weights.nu`
$ `src/devblock.nu`

@ __lmw_none → GkBuf { ^ @ GkBuf { 0 0 GK_F32 } }

// One tensor onto the device. The staging vector is written through its
// own data pointer — pt_read_f64 fills a raw span — so the elements are
// copied once, not twice.
@ lmw_upload * Lw w * GpuKit kit s name → GkBuf {
    : i n ( lw_nelems w name )
    ? <= n 0 {
        : b _r ( lw_require w name -1 -1 -1 -1 )
        ^ ( __lmw_none )
    } {}
    : ( Vec f ) host ( vec_with_cap [f] n )
    : b _sl ( vec_set_len [f] host n )
    ? ! ( lw_read w name ( vec_data [f] host ) n ) {
        ( vec_free [f] host )
        ^ ( __lmw_none )
    } {}
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    : b _up ( gk_dbuf_upload kit b host )
    ( vec_free [f] host )
    ^ b
}

// `<prefix><leaf>` — the checkpoint's names are dotted paths and a block
// is one prefix away from all eighteen of its tensors.
@ __lmw_at * Lw w * GpuKit kit s prefix s leaf → GkBuf {
    : String nm ( string_from prefix )
    ( string_push_str nm leaf )
    : GkBuf b ( lmw_upload w kit ( string_data nm ) )
    ( string_free nm )
    ^ b
}

// Every parameter of one transformer block. `qk` selects whether the
// attention has q_norm/k_norm — DINOv2's own 24 blocks do not, the
// aggregator's 48 do — and `eps` is norm1/norm2's, which is 1e-6 for
// DINOv2's blocks and 1e-5 for the aggregator's.
@ lmw_block * Lw w * GpuKit kit s prefix b qk f eps → LmBlk {
    ^ @ LmBlk {
        ( __lmw_at w kit prefix `norm1.weight` )
        ( __lmw_at w kit prefix `norm1.bias` )
        ( __lmw_at w kit prefix `attn.qkv.weight` )
        ( __lmw_at w kit prefix `attn.qkv.bias` )
        ? qk ( __lmw_at w kit prefix `attn.q_norm.weight` ) ( __lmw_none )
        ? qk ( __lmw_at w kit prefix `attn.q_norm.bias` ) ( __lmw_none )
        ? qk ( __lmw_at w kit prefix `attn.k_norm.weight` ) ( __lmw_none )
        ? qk ( __lmw_at w kit prefix `attn.k_norm.bias` ) ( __lmw_none )
        ( __lmw_at w kit prefix `attn.proj.weight` )
        ( __lmw_at w kit prefix `attn.proj.bias` )
        ( __lmw_at w kit prefix `ls1.gamma` )
        ( __lmw_at w kit prefix `norm2.weight` )
        ( __lmw_at w kit prefix `norm2.bias` )
        ( __lmw_at w kit prefix `mlp.fc1.weight` )
        ( __lmw_at w kit prefix `mlp.fc1.bias` )
        ( __lmw_at w kit prefix `mlp.fc2.weight` )
        ( __lmw_at w kit prefix `mlp.fc2.bias` )
        ( __lmw_at w kit prefix `ls2.gamma` ) eps }
}

// `<base>.<idx>.` — the prefix of an indexed block.
@ lmw_prefix s base i idx → String {
    : String nm ( string_from base )
    ( string_push_char nm 46 )
    ( string_push_int nm idx )
    ( string_push_char nm 46 )
    ^ nm
}
