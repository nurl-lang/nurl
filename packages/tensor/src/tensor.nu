// tensor/tensor.nu — an n-dimensional array over gpukit.
//
// The reusable ndarray the ML packages want: onnx keeps its tensors welded to
// the graph runtime, and gpukit is a marshalling floor nobody wants to program
// against. `Tensor` is the shared layer — shape, broadcasting, matmul and
// reductions — that onnx, anomaly and a future training package can all sit on.
//
// Storage is row-major contiguous f64 (NURL's native float). `dtype` records
// the logical type: an F64 tensor is exact f64; an F32 tensor keeps its values
// on the f32 grid (results are rounded to f32 after each op), so it behaves
// like float32 for interop while computing in f64. Bytes in/out (from_f32 /
// to_f32) bridge to onnx weights and files.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`

: i TE_F64 0
: i TE_F32 1

: Tensor {
    i dtype
    ( Vec i ) shape
    ( Vec f ) data
}

// ── Small shape helpers ───────────────────────────────────────────────

@ _t_prod ( Vec i ) shape → i {
    : i n ( vec_len [i] shape )
    : ~ i p 1
    : ~ i k 0
    ~ < k n { ?? ( vec_get [i] shape k ) { T d → { = p * p d } F _ → {} } = k + k 1 }
    ^ p
}

@ _ti ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → { ^ x } F _ → { ^ 0 } } }

@ _tf ( Vec f ) v i k → f { ?? ( vec_get [f] v k ) { T x → { ^ x } F _ → { ^ 0.0 } } }

// Row-major strides for a shape.
@ _t_strides ( Vec i ) shape → ( Vec i ) {
    : i n ( vec_len [i] shape )
    : ( Vec i ) st ( _ivec_t n 0 )
    : ~ i acc 1
    : ~ i k - n 1
    ~ >= k 0 {
        ( vec_set [i] st k acc )
        = acc * acc ( _ti shape k )
        = k - k 1
    }
    ^ st
}

@ _ivec_t i n i fill → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] ? > n 0 { n } { 1 } )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v fill ) = k + k 1 }
    ^ v
}

@ _fvec_t i n f fill → ( Vec f ) {
    : ( Vec f ) v ( vec_with_cap [f] ? > n 0 { n } { 1 } )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v fill ) = k + k 1 }
    ^ v
}

@ _shape_copy ( Vec i ) s → ( Vec i ) {
    : i n ( vec_len [i] s )
    : ( Vec i ) o ( vec_with_cap [i] ? > n 0 { n } { 1 } )
    : ~ i k 0
    ~ < k n { ( vec_push [i] o ( _ti s k ) ) = k + k 1 }
    ^ o
}

// Round an f64 to the nearest float32-representable value.
@ _t_round32 f x → f { ^ # f ( bits_to_f32 ( f32_to_bits # f32 x ) ) }

// ── Construction ──────────────────────────────────────────────────────

// Adopt a data vector (moved in) under a shape. nelem must equal prod(shape).
@ tensor_of i dtype ( Vec i ) shape ( Vec f ) data → Tensor {
    ^ @ Tensor { dtype shape data }
}

@ tensor_free Tensor t → v {
    ( vec_free [i] . t shape )
    ( vec_free [f] . t data )
}

@ tensor_full i dtype ( Vec i ) shape f v → Tensor {
    : f fv ? == dtype TE_F32 { ( _t_round32 v ) } { v }
    : i n ( _t_prod shape )
    ^ @ Tensor { dtype shape ( _fvec_t n fv ) }
}

@ tensor_zeros i dtype ( Vec i ) shape → Tensor { ^ ( tensor_full dtype shape 0.0 ) }

@ tensor_ones i dtype ( Vec i ) shape → Tensor { ^ ( tensor_full dtype shape 1.0 ) }

// From an explicit row-major f64 buffer (`data` is copied and rounded to the
// dtype grid; `shape` is adopted — the tensor takes ownership of it).
@ tensor_from_data i dtype ( Vec i ) shape ( Vec f ) data → Tensor {
    : i n ( _t_prod shape )
    : ( Vec f ) d ( vec_with_cap [f] ? > n 0 { n } { 1 } )
    : ~ i k 0
    ~ < k n {
        : f v ( _tf data k )
        ( vec_push [f] d ? == dtype TE_F32 { ( _t_round32 v ) } { v } )
        = k + k 1
    }
    ^ @ Tensor { dtype shape d }
}

// 1-D [0, 1, …, n-1].
@ tensor_arange i dtype i n → Tensor {
    : ( Vec i ) shp ( _ivec_t 1 n )
    : ( Vec f ) d ( vec_with_cap [f] ? > n 0 { n } { 1 } )
    : ~ i k 0
    ~ < k n { ( vec_push [f] d # f k ) = k + k 1 }
    ^ @ Tensor { dtype shp d }
}

// ── Queries / access ──────────────────────────────────────────────────

@ tensor_ndim Tensor t → i { ^ ( vec_len [i] . t shape ) }

@ tensor_size Tensor t → i { ^ ( vec_len [f] . t data ) }

@ tensor_dtype Tensor t → i { ^ . t dtype }

@ tensor_dim Tensor t i ax → i { ^ ( _ti . t shape ax ) }

@ tensor_shape Tensor t → ( Vec i ) { ^ . t shape }  // borrow
@ tensor_data Tensor t → ( Vec f ) { ^ . t data }  // borrow

// Flat element read/write.
@ tensor_flat Tensor t i k → f { ^ ( _tf . t data k ) }

@ tensor_set_flat Tensor t i k f v → v {
    ( vec_set [f] . t data k ? == . t dtype TE_F32 { ( _t_round32 v ) } { v } )
}

// ── Shape ops ─────────────────────────────────────────────────────────

// The same data under a new shape (must have equal nelem). Data is copied so
// the result is independent; `shape` is adopted (or freed on a size mismatch).
@ tensor_reshape Tensor t ( Vec i ) shape → ?Tensor {
    ? == ( _t_prod shape ) ( tensor_size t ) {} {
        ( vec_free [i] shape )
        ^ @ ?Tensor { F }
    }
    : i n ( tensor_size t )
    : ( Vec f ) d ( vec_with_cap [f] ? > n 0 { n } { 1 } )
    : ~ i k 0
    ~ < k n { ( vec_push [f] d ( _tf . t data k ) ) = k + k 1 }
    ^ @ ?Tensor { T @ Tensor { . t dtype shape d } }
}

// Clone a tensor (independent copy).
@ tensor_clone Tensor t → Tensor {
    : i n ( tensor_size t )
    : ( Vec f ) d ( vec_with_cap [f] ? > n 0 { n } { 1 } )
    : ~ i k 0
    ~ < k n { ( vec_push [f] d ( _tf . t data k ) ) = k + k 1 }
    ^ @ Tensor { . t dtype ( _shape_copy . t shape ) d }
}

// ── dtype ─────────────────────────────────────────────────────────────

@ tensor_astype Tensor t i dtype → Tensor {
    ^ ( tensor_from_data dtype ( _shape_copy . t shape ) . t data )
}
