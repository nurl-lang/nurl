// tensor/dev.nu — DEVICE-RESIDENT tensors (M3).
//
// A DTensor is a Tensor whose data lives in GPU memory (a gpukit GkBuf):
// ops chain on the device with no host roundtrips, which is what a NN
// forward pass needs (upload the weights once, stream activations through).
// Residency is EXPLICIT — tensor_to_device / dtensor_to_host move data, ops
// never sync behind your back.
//
// Numerics: a TE_F32 DTensor computes IN float32 on the device — true
// float32 semantics (accumulation included), matching numpy float32 and
// onnxruntime. That differs from the HOST TE_F32 Tensor, which computes in
// f64 and rounds each result to the f32 grid: elementwise results agree
// exactly, but reductions/matmul accumulate differently (f32 vs f64 sums).
// TE_F64 DTensors are bit-identical to host ops wherever the kernel
// accumulates sequentially (elementwise, matmul).

$ `stdlib/core/vec.nu`
$ `deps/gpukit/src/dev.nu`
$ `tensor.nu`

: DTensor {
    i dtype
    ( Vec i ) shape
    GkBuf buf
}

@ __dt_gk i dtype → i { ? == dtype TE_F32 { ^ GK_F32 } {} ^ GK_F64 }

@ dtensor_ok DTensor d → b { ^ ( gk_buf_ok . d buf ) }

@ dtensor_free DTensor d → v {
    ( gk_dbuf_free . d buf )
    ( vec_free [i] . d shape )
}

@ dtensor_ndim DTensor d → i { ^ ( vec_len [i] . d shape ) }

@ dtensor_size DTensor d → i { ^ ( gk_buf_len . d buf ) }

@ dtensor_dtype DTensor d → i { ^ . d dtype }

@ dtensor_dim DTensor d i ax → i { ^ ( _ti . d shape ax ) }

// ── Residency moves ───────────────────────────────────────────────────

@ tensor_to_device * GpuKit kit Tensor t → DTensor {
    : i n ( tensor_size t )
    : GkBuf b ( gk_dbuf_new kit n ( __dt_gk . t dtype ) )
    ? ( gk_buf_ok b ) {
        ? ( gk_dbuf_upload kit b . t data ) {} {
            ( gk_dbuf_free b )
            ^ @ DTensor { . t dtype ( _shape_copy . t shape ) @ GkBuf { 0 0 ( __dt_gk . t dtype ) } }
        }
    } {}
    ^ @ DTensor { . t dtype ( _shape_copy . t shape ) b }
}

@ dtensor_to_host * GpuKit kit DTensor d → Tensor {
    : i n ( dtensor_size d )
    : ( Vec f ) out ( _fvec_t n 0.0 )
    ( gk_dbuf_download kit . d buf out )
    ^ @ Tensor { . d dtype ( _shape_copy . d shape ) out }
}

// A fresh uninitialised device tensor with the same dtype as `like`,
// adopting `shape`.
@ __dt_new * GpuKit kit DTensor like ( Vec i ) shape i n → DTensor {
    ^ @ DTensor { . like dtype shape ( gk_dbuf_new kit n ( __dt_gk . like dtype ) ) }
}

// ── Elementwise (same shape) ──────────────────────────────────────────

@ __dt_binop * GpuKit kit s opname s op DTensor a DTensor b → ?DTensor {
    ? & ( dtensor_ok a ) ( dtensor_ok b ) {} { ^ @ ?DTensor { F } }
    ? == . a dtype . b dtype {} { ^ @ ?DTensor { F } }
    : i n ( dtensor_size a )
    ? == n ( dtensor_size b ) {} { ^ @ ?DTensor { F } }
    : DTensor o ( __dt_new kit a ( _shape_copy . a shape ) n )
    ? ( gkd_ew kit opname op . o buf . a buf . b buf ) {} {
        ( dtensor_free o )
        ^ @ ?DTensor { F }
    }
    ^ @ ?DTensor { T o }
}

@ dtensor_add * GpuKit kit DTensor a DTensor b → ?DTensor { ^ ( __dt_binop kit `add` `+` a b ) }

@ dtensor_sub * GpuKit kit DTensor a DTensor b → ?DTensor { ^ ( __dt_binop kit `sub` `-` a b ) }

@ dtensor_mul * GpuKit kit DTensor a DTensor b → ?DTensor { ^ ( __dt_binop kit `mul` `*` a b ) }

@ dtensor_div * GpuKit kit DTensor a DTensor b → ?DTensor { ^ ( __dt_binop kit `div` `/` a b ) }

// ── Scalar forms (broadcast a 1-element device operand) ───────────────

@ __dt_scalar * GpuKit kit s opname s op DTensor a f v → ?DTensor {
    ? ( dtensor_ok a ) {} { ^ @ ?DTensor { F } }
    : GkBuf sc ( gk_dbuf_new kit 1 ( __dt_gk . a dtype ) )
    ? ( gk_buf_ok sc ) {} { ^ @ ?DTensor { F } }
    : ( Vec f ) hv ( _fvec_t 1 v )
    : ~ b ok ( gk_dbuf_upload kit sc hv )
    ( vec_free [f] hv )
    : i n ( dtensor_size a )
    : DTensor o ( __dt_new kit a ( _shape_copy . a shape ) n )
    ? ok { = ok ( gkd_ew kit opname op . o buf . a buf sc ) } {}
    ( gk_dbuf_free sc )
    ? ok { ^ @ ?DTensor { T o } } {}
    ( dtensor_free o )
    ^ @ ?DTensor { F }
}

@ dtensor_adds * GpuKit kit DTensor a f v → ?DTensor { ^ ( __dt_scalar kit `add` `+` a v ) }

@ dtensor_subs * GpuKit kit DTensor a f v → ?DTensor { ^ ( __dt_scalar kit `sub` `-` a v ) }

@ dtensor_muls * GpuKit kit DTensor a f v → ?DTensor { ^ ( __dt_scalar kit `mul` `*` a v ) }

@ dtensor_divs * GpuKit kit DTensor a f v → ?DTensor { ^ ( __dt_scalar kit `div` `/` a v ) }

// ── Unary maps ────────────────────────────────────────────────────────

// kind 0 relu · 1 sigmoid · 2 exp · 3 tanh · 4 sqrt · 5 log
@ __dt_unary * GpuKit kit i kind DTensor a → ?DTensor {
    ? ( dtensor_ok a ) {} { ^ @ ?DTensor { F } }
    : i n ( dtensor_size a )
    : DTensor o ( __dt_new kit a ( _shape_copy . a shape ) n )
    : ~ b ok F
    ? == kind 0 { = ok ( gkd_relu kit . o buf . a buf ) } {}
    ? == kind 1 { = ok ( gkd_sigmoid kit . o buf . a buf ) } {}
    ? == kind 2 { = ok ( gkd_exp kit . o buf . a buf ) } {}
    ? == kind 3 { = ok ( gkd_tanh kit . o buf . a buf ) } {}
    ? == kind 4 { = ok ( gkd_sqrt kit . o buf . a buf ) } {}
    ? == kind 5 { = ok ( gkd_log kit . o buf . a buf ) } {}
    ? ok { ^ @ ?DTensor { T o } } {}
    ( dtensor_free o )
    ^ @ ?DTensor { F }
}

@ dtensor_relu * GpuKit kit DTensor a → ?DTensor { ^ ( __dt_unary kit 0 a ) }

@ dtensor_sigmoid * GpuKit kit DTensor a → ?DTensor { ^ ( __dt_unary kit 1 a ) }

@ dtensor_exp * GpuKit kit DTensor a → ?DTensor { ^ ( __dt_unary kit 2 a ) }

@ dtensor_tanh * GpuKit kit DTensor a → ?DTensor { ^ ( __dt_unary kit 3 a ) }

@ dtensor_sqrt * GpuKit kit DTensor a → ?DTensor { ^ ( __dt_unary kit 4 a ) }

@ dtensor_log * GpuKit kit DTensor a → ?DTensor { ^ ( __dt_unary kit 5 a ) }

// ── Matmul (2-D) ──────────────────────────────────────────────────────

@ dtensor_matmul * GpuKit kit DTensor a DTensor b → ?DTensor {
    ? & ( dtensor_ok a ) ( dtensor_ok b ) {} { ^ @ ?DTensor { F } }
    ? & == ( dtensor_ndim a ) 2 == ( dtensor_ndim b ) 2 {} { ^ @ ?DTensor { F } }
    ? == . a dtype . b dtype {} { ^ @ ?DTensor { F } }
    : i M ( dtensor_dim a 0 )
    : i K ( dtensor_dim a 1 )
    : i N ( dtensor_dim b 1 )
    ? == K ( dtensor_dim b 0 ) {} { ^ @ ?DTensor { F } }
    : ( Vec i ) shp ( vec_with_cap [i] 2 )
    ( vec_push [i] shp M ) ( vec_push [i] shp N )
    : DTensor o ( __dt_new kit a shp * M N )
    ? ( gkd_matmul kit . o buf . a buf . b buf M K N ) {} {
        ( dtensor_free o )
        ^ @ ?DTensor { F }
    }
    ^ @ ?DTensor { T o }
}

// ── Softmax over the LAST axis ────────────────────────────────────────

@ dtensor_softmax * GpuKit kit DTensor a → ?DTensor {
    ? ( dtensor_ok a ) {} { ^ @ ?DTensor { F } }
    : i nd ( dtensor_ndim a )
    ? > nd 0 {} { ^ @ ?DTensor { F } }
    : i cols ( dtensor_dim a - nd 1 )
    ? > cols 0 {} { ^ @ ?DTensor { F } }
    : i n ( dtensor_size a )
    : i rows / n cols
    : DTensor o ( __dt_new kit a ( _shape_copy . a shape ) n )
    ? ( gkd_softmax_rows kit . o buf . a buf rows cols ) {} {
        ( dtensor_free o )
        ^ @ ?DTensor { F }
    }
    ^ @ ?DTensor { T o }
}

// ── Reductions ────────────────────────────────────────────────────────

// Sum of every element (downloads one scalar; accumulates in the buffer's
// element type — true float32 for TE_F32).
@ dtensor_sum * GpuKit kit DTensor a → ?f {
    ? ( dtensor_ok a ) {} { ^ @ ?f { F } }
    ^ ( gkd_sum kit . a buf )
}
