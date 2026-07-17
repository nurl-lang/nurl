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
$ `deps/gpukit/src/devops.nu`
$ `tensor.nu`
$ `ops.nu`  // _t_bshape / _t_eff_strides / _t_batch_eff (one broadcast impl)

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

// ── Elementwise (full numpy broadcasting, ≤6 dims) ────────────────────
// Same-shape pairs take the plain kernel; anything else goes through the
// stride-broadcast kernel with each input's effective strides (0 on
// broadcast dims), exactly the host tensors' numpy rules.

@ __dt_same_shape DTensor a DTensor b → b {
    : i n ( vec_len [i] . a shape )
    ? == n ( vec_len [i] . b shape ) {} { ^ F }
    : ~ i k 0
    ~ < k n {
        ? == ( _ti . a shape k ) ( _ti . b shape k ) {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ __dt_binop * GpuKit kit s opname s op DTensor a DTensor b → ?DTensor {
    ? & ( dtensor_ok a ) ( dtensor_ok b ) {} { ^ @ ?DTensor { F } }
    ? == . a dtype . b dtype {} { ^ @ ?DTensor { F } }
    ? ( __dt_same_shape a b ) {
        : i n ( dtensor_size a )
        : DTensor o ( __dt_new kit a ( _shape_copy . a shape ) n )
        ? ( gkd_ew kit opname op . o buf . a buf . b buf ) {} {
            ( dtensor_free o )
            ^ @ ?DTensor { F }
        }
        ^ @ ?DTensor { T o }
    } {}
    ?? ( _t_bshape . a shape . b shape ) {
        T oshape → {
            : i nd ( vec_len [i] oshape )
            ? <= nd 6 {} { ( vec_free [i] oshape ) ^ @ ?DTensor { F } }
            : ( Vec i ) ae ( _t_eff_strides . a shape nd )
            : ( Vec i ) be ( _t_eff_strides . b shape nd )
            : i total ( _t_prod oshape )
            : DTensor o ( __dt_new kit a oshape total )  // adopts oshape
            : b r ( gkd_ew_bc kit opname op . o buf . a buf . b buf oshape ae be )
            ( vec_free [i] ae )
            ( vec_free [i] be )
            ? r { ^ @ ?DTensor { T o } } {}
            ( dtensor_free o )
            ^ @ ?DTensor { F }
        }
        F _ → { ^ @ ?DTensor { F } }
    }
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

// ── Batched matmul: [..,M,K] · [..,K,N] → [..,M,N], batch broadcast ──
// Uniform batches (both operands carry the full batch, or one is a single
// matrix broadcast over it) run as ONE kernel launch; a general numpy
// batch broadcast falls back to a per-batch matmul over device-pointer
// views — the same sequential-K kernel math either way.

@ __dt_esz i dtype → i { ? == dtype TE_F32 { ^ 4 } {} ^ 8 }

@ dtensor_bmm * GpuKit kit DTensor a DTensor b → ?DTensor {
    ? & ( dtensor_ok a ) ( dtensor_ok b ) {} { ^ @ ?DTensor { F } }
    ? == . a dtype . b dtype {} { ^ @ ?DTensor { F } }
    : i na ( dtensor_ndim a )
    : i nb ( dtensor_ndim b )
    ? & >= na 2 >= nb 2 {} { ^ @ ?DTensor { F } }
    : i M ( _ti . a shape - na 2 )
    : i K ( _ti . a shape - na 1 )
    : i N ( _ti . b shape - nb 1 )
    ? == K ( _ti . b shape - nb 2 ) {} { ^ @ ?DTensor { F } }
    : ( Vec i ) ba ( _t_take_head . a shape - na 2 )
    : ( Vec i ) bb ( _t_take_head . b shape - nb 2 )
    : ?( Vec i ) bso ( _t_bshape ba bb )
    ( vec_free [i] ba )
    ( vec_free [i] bb )
    ?? bso {
        T bshape → {
            : i ndb ( vec_len [i] bshape )
            : i nbatch ( _t_prod bshape )
            // out shape = bshape ++ [M, N]
            : ( Vec i ) oshape ( vec_with_cap [i] + ndb 2 )
            : ~ i k 0
            ~ < k ndb { ( vec_push [i] oshape ( _ti bshape k ) ) = k + k 1 }
            ( vec_push [i] oshape M )
            ( vec_push [i] oshape N )
            : DTensor o ( __dt_new kit a oshape * nbatch * M N )
            // uniform when each operand is either the full batch or one matrix
            : b afull == ( dtensor_size a ) * nbatch * M K
            : b aone == ( dtensor_size a ) * M K
            : b bfull == ( dtensor_size b ) * nbatch * K N
            : b bone == ( dtensor_size b ) * K N
            : ~ b r F
            ? & | afull aone | bfull bone {
                : i af ? afull { 1 } { 0 }
                : i bf ? bfull { 1 } { 0 }
                = r ( gkd_bmm kit . o buf . a buf . b buf nbatch M K N af bf )
            } {
                // general broadcast: one matmul per output batch over views
                : ( Vec i ) bst ( _t_strides bshape )
                : ( Vec i ) aeff ( _t_batch_eff . a shape ndb )
                : ( Vec i ) beff ( _t_batch_eff . b shape ndb )
                : i esz ( __dt_esz . a dtype )
                : i gdt ( __dt_gk . a dtype )
                = r T
                : ~ i bi 0
                ~ & r < bi nbatch {
                    : ~ i rem bi
                    : ~ i aoff 0
                    : ~ i boff 0
                    : ~ i d 0
                    ~ < d ndb {
                        : i sd ( _ti bst d )
                        : i c ? > sd 0 { / rem sd } { 0 }
                        = rem ? > sd 0 { % rem sd } { rem }
                        = aoff + aoff * c ( _ti aeff d )
                        = boff + boff * c ( _ti beff d )
                        = d + d 1
                    }
                    : GkBuf av @ GkBuf { + . . a buf dptr * aoff esz * M K gdt }
                    : GkBuf bv @ GkBuf { + . . b buf dptr * boff esz * K N gdt }
                    : GkBuf yv @ GkBuf { + . . o buf dptr * * bi * M N esz * M N gdt }
                    ? ( gkd_matmul kit yv av bv M K N ) {} { = r F }
                    = bi + bi 1
                }
                ( vec_free [i] bst )
                ( vec_free [i] aeff )
                ( vec_free [i] beff )
            }
            ( vec_free [i] bshape )
            ? r { ^ @ ?DTensor { T o } } {}
            ( dtensor_free o )
            ^ @ ?DTensor { F }
        }
        F _ → { ^ @ ?DTensor { F } }
    }
}

// ── Gather / Scatter along an axis (host-side index vector) ──────────
// Indices live on the host (`Vec i`), may be negative (wrap once, numpy/
// ONNX style) and are validated BEFORE anything touches the device — the
// ndarray API rejects out-of-range indices instead of zero-filling.

// outer·ax·inner view of `shape` around `axis`.
@ __dt_axview ( Vec i ) shape i axis * u pouter * u pinner → v {
    : i nd ( vec_len [i] shape )
    : ~ i outer 1
    : ~ i inner 1
    : ~ i k 0
    ~ < k nd {
        ? < k axis { = outer * outer ( _ti shape k ) } {}
        ? > k axis { = inner * inner ( _ti shape k ) } {}
        = k + k 1
    }
    ( nurl_poke pouter 0 outer )
    ( nurl_poke pinner 0 inner )
}

@ __dt_idx_ok ( Vec i ) idx i axin → b {
    : i n ( vec_len [i] idx )
    : ~ i k 0
    ~ < k n {
        : i v ( _ti idx k )
        ? & >= v - 0 axin < v axin {} { ^ F }
        = k + k 1
    }
    ^ T
}

@ dtensor_gather * GpuKit kit DTensor a i axis ( Vec i ) idx → ?DTensor {
    ? ( dtensor_ok a ) {} { ^ @ ?DTensor { F } }
    : i nd ( dtensor_ndim a )
    ? & >= axis 0 < axis nd {} { ^ @ ?DTensor { F } }
    : i nidx ( vec_len [i] idx )
    ? > nidx 0 {} { ^ @ ?DTensor { F } }
    : i axin ( _ti . a shape axis )
    ? ( __dt_idx_ok idx axin ) {} { ^ @ ?DTensor { F } }
    : *u cells ( nurl_alloc 16 )
    ( __dt_axview . a shape axis cells # *u + # i cells 8 )
    : i outer ( nurl_peek cells 0 )
    : i inner ( nurl_peek cells 1 )
    ( nurl_free cells )
    : ( Vec i ) oshape ( _shape_copy . a shape )
    ( vec_set [i] oshape axis nidx )
    : DTensor o ( __dt_new kit a oshape * * outer nidx inner )
    : GkBuf ixb ( gk_dbuf_new kit nidx GK_I64 )
    : ~ b r ( gk_dbuf_upload_i kit ixb idx )
    ? r { = r ( gkd_gather kit . o buf . a buf ixb outer axin inner nidx ) } {}
    ( gk_dbuf_free ixb )
    ? r { ^ @ ?DTensor { T o } } {}
    ( dtensor_free o )
    ^ @ ?DTensor { F }
}

// out = a with out[.., idx[g], ..] = upd[.., g, ..] along `axis`; `upd`'s
// shape must equal a's with the axis dim replaced by len(idx). Duplicate
// indices leave which write survives unspecified (ONNX semantics).
@ dtensor_scatter * GpuKit kit DTensor a i axis ( Vec i ) idx DTensor upd → ?DTensor {
    ? & ( dtensor_ok a ) ( dtensor_ok upd ) {} { ^ @ ?DTensor { F } }
    ? == . a dtype . upd dtype {} { ^ @ ?DTensor { F } }
    : i nd ( dtensor_ndim a )
    ? & >= axis 0 < axis nd {} { ^ @ ?DTensor { F } }
    : i nidx ( vec_len [i] idx )
    ? > nidx 0 {} { ^ @ ?DTensor { F } }
    : i axin ( _ti . a shape axis )
    ? ( __dt_idx_ok idx axin ) {} { ^ @ ?DTensor { F } }
    ? == ( dtensor_ndim upd ) nd {} { ^ @ ?DTensor { F } }
    : ~ i k 0
    ~ < k nd {
        : i want ? == k axis { nidx } { ( _ti . a shape k ) }
        ? == ( _ti . upd shape k ) want {} { ^ @ ?DTensor { F } }
        = k + k 1
    }
    : *u cells ( nurl_alloc 16 )
    ( __dt_axview . a shape axis cells # *u + # i cells 8 )
    : i outer ( nurl_peek cells 0 )
    : i inner ( nurl_peek cells 1 )
    ( nurl_free cells )
    : DTensor o ( __dt_new kit a ( _shape_copy . a shape ) ( dtensor_size a ) )
    : GkBuf ixb ( gk_dbuf_new kit nidx GK_I64 )
    : ~ b r ( gk_dbuf_upload_i kit ixb idx )
    ? r { = r ( gkd_scatter kit . o buf . a buf ixb . upd buf outer axin inner nidx ) } {}
    ( gk_dbuf_free ixb )
    ? r { ^ @ ?DTensor { T o } } {}
    ( dtensor_free o )
    ^ @ ?DTensor { F }
}

// ── Convolution / pooling (NCHW without the batch dim) ───────────────
// x is [Cin,H,W]; w is [Cout,Cin,kh,kw]; symmetric zero padding ph/pw;
// output [Cout,OH,OW] with OH = (H + 2·ph − kh)/sh + 1 (floor).

@ __dt_conv * GpuKit kit DTensor x DTensor w DTensor bias i hasb i ph i pw i sh i sw → ?DTensor {
    ? & ( dtensor_ok x ) ( dtensor_ok w ) {} { ^ @ ?DTensor { F } }
    ? == . x dtype . w dtype {} { ^ @ ?DTensor { F } }
    ? & == ( dtensor_ndim x ) 3 == ( dtensor_ndim w ) 4 {} { ^ @ ?DTensor { F } }
    ? & & >= ph 0 >= pw 0 & > sh 0 > sw 0 {} { ^ @ ?DTensor { F } }
    : i cin ( _ti . x shape 0 )
    : i h ( _ti . x shape 1 )
    : i wd ( _ti . x shape 2 )
    : i cout ( _ti . w shape 0 )
    ? == ( _ti . w shape 1 ) cin {} { ^ @ ?DTensor { F } }
    : i kh ( _ti . w shape 2 )
    : i kw ( _ti . w shape 3 )
    : i oh + / - + h * 2 ph kh sh 1
    : i ow + / - + wd * 2 pw kw sw 1
    ? & > oh 0 > ow 0 {} { ^ @ ?DTensor { F } }
    ? != hasb 0 {
        ? & & ( dtensor_ok bias ) == . bias dtype . x dtype == ( dtensor_size bias ) cout {} { ^ @ ?DTensor { F } }
    } {}
    : ( Vec i ) oshape ( vec_with_cap [i] 3 )
    ( vec_push [i] oshape cout )
    ( vec_push [i] oshape oh )
    ( vec_push [i] oshape ow )
    : DTensor o ( __dt_new kit x oshape * * cout oh ow )
    ? ( gkd_conv2d kit . o buf . x buf . w buf . bias buf hasb cin h wd cout kh kw oh ow ph pw sh sw ) {} {
        ( dtensor_free o )
        ^ @ ?DTensor { F }
    }
    ^ @ ?DTensor { T o }
}

@ dtensor_conv2d * GpuKit kit DTensor x DTensor w i ph i pw i sh i sw → ?DTensor {
    ^ ( __dt_conv kit x w x 0 ph pw sh sw )
}

@ dtensor_conv2d_b * GpuKit kit DTensor x DTensor w DTensor bias i ph i pw i sh i sw → ?DTensor {
    ^ ( __dt_conv kit x w bias 1 ph pw sh sw )
}

// Max pool over [C,H,W]: kernel kh×kw, strides sh/sw, symmetric pads.
@ dtensor_maxpool2d * GpuKit kit DTensor x i kh i kw i sh i sw i ph i pw → ?DTensor {
    ? ( dtensor_ok x ) {} { ^ @ ?DTensor { F } }
    ? == ( dtensor_ndim x ) 3 {} { ^ @ ?DTensor { F } }
    ? & & & > kh 0 > kw 0 > sh 0 > sw 0 {} { ^ @ ?DTensor { F } }
    ? & >= ph 0 >= pw 0 {} { ^ @ ?DTensor { F } }
    : i c ( _ti . x shape 0 )
    : i h ( _ti . x shape 1 )
    : i wd ( _ti . x shape 2 )
    : i oh + / - + h * 2 ph kh sh 1
    : i ow + / - + wd * 2 pw kw sw 1
    ? & > oh 0 > ow 0 {} { ^ @ ?DTensor { F } }
    : ( Vec i ) oshape ( vec_with_cap [i] 3 )
    ( vec_push [i] oshape c )
    ( vec_push [i] oshape oh )
    ( vec_push [i] oshape ow )
    : DTensor o ( __dt_new kit x oshape * * c oh ow )
    ? ( gkd_maxpool2d kit . o buf . x buf c h wd kh kw oh ow sh sw ph pw ) {} {
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
