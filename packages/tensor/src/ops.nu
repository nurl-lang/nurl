// tensor/ops.nu — broadcasting elementwise, unary maps, matmul and reductions.
//
// Elementwise binary ops broadcast with numpy rules (align trailing dims,
// size-1 stretches). matmul runs on the GPU via gpukit for large f64 problems
// and on a plain triple loop otherwise — identical results either way. F32
// tensors keep their outputs on the f32 grid.

$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/gpukit/src/kernels.nu`
$ `tensor.nu`

// ── GPU singleton (probed lazily; matmul only) ────────────────────────
: ~ i g_t_gpu 0  // 0 unprobed, 1 ready, -1 unavailable
: ~ i g_t_kit 0  // *GpuKit as an int

@ __t_gpu_ready → b {
    ? != g_t_gpu 0 { ^ == g_t_gpu 1 } {}
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) { = g_t_kit # i kit = g_t_gpu 1 ^ T } {}
    ( gk_close kit )
    = g_t_gpu -1
    ^ F
}

@ __t_kit → *GpuKit { ^ # *GpuKit g_t_kit }

// Release the tensor GPU singleton (tests call this so leak checkers are happy).
@ tensor_gpu_close → v {
    ? == g_t_gpu 1 { ( gk_close ( __t_kit ) ) } {}
    = g_t_gpu 0
    = g_t_kit 0
}

@ __round_vec ( Vec f ) v i dtype → v {
    ? == dtype TE_F32 {} { ^ }
    : i n ( vec_len [f] v )
    : ~ i k 0
    ~ < k n { ( vec_set [f] v k ( __t_round32 ( __tf v k ) ) ) = k + k 1 }
}

@ __t_result_dtype Tensor a Tensor b → i {
    ? || == . a dtype TE_F64 == . b dtype TE_F64 { ^ TE_F64 } {}
    ^ TE_F32
}

// ── Broadcasting ──────────────────────────────────────────────────────

@ __t_bshape ( Vec i ) a ( Vec i ) b → ?( Vec i ) {
    : i na ( vec_len [i] a )
    : i nb ( vec_len [i] b )
    : i nd ? > na nb { na } { nb }
    : ( Vec i ) out ( __ivec_t nd 1 )
    : ~ i d 0
    ~ < d nd {
        : i ia - - na 1 d
        : i ib - - nb 1 d
        : i da ? >= ia 0 { ( __ti a ia ) } { 1 }
        : i db ? >= ib 0 { ( __ti b ib ) } { 1 }
        : i od - - nd 1 d
        ? | == da db | == da 1 == db 1 {
            ( vec_set [i] out od ? > da db { da } { db } )
        } {
            ( vec_free [i] out )
            ^ @ ?( Vec i ) { F }
        }
        = d + d 1
    }
    ^ @ ?( Vec i ) { T out }
}

// Effective strides of `shape` aligned into `nd` output dims (0 where broadcast).
@ __t_eff_strides ( Vec i ) shape i nd → ( Vec i ) {
    : i n ( vec_len [i] shape )
    : ( Vec i ) base ( __t_strides shape )
    : ( Vec i ) eff ( __ivec_t nd 0 )
    : ~ i d 0
    ~ < d nd {
        : i j - d - nd n
        ? & >= j 0 > ( __ti shape j ) 1 { ( vec_set [i] eff d ( __ti base j ) ) } {}
        = d + d 1
    }
    ( vec_free [i] base )
    ^ eff
}

@ __apply i op f x f y → f {
    ? == op 0 { ^ + x y } {}
    ? == op 1 { ^ - x y } {}
    ? == op 2 { ^ * x y } {}
    ? == op 3 { ^ / x y } {}
    ? == op 4 { ^ ? > x y { x } { y } } {}
    ? == op 5 { ^ ? < x y { x } { y } } {}
    ^ ( float_pow x y )
}

@ __t_binop Tensor a Tensor b i op → ?Tensor {
    ?? ( __t_bshape . a shape . b shape ) {
        T oshape → {
            : i nd ( vec_len [i] oshape )
            : ( Vec i ) ost ( __t_strides oshape )
            : ( Vec i ) ae ( __t_eff_strides . a shape nd )
            : ( Vec i ) be ( __t_eff_strides . b shape nd )
            : i total ( __t_prod oshape )
            : i rdt ( __t_result_dtype a b )
            : ( Vec f ) out ( vec_with_cap [f] ? > total 0 { total } { 1 } )
            : ~ i i 0
            ~ < i total {
                : ~ i rem i
                : ~ i ao 0
                : ~ i bo 0
                : ~ i d 0
                ~ < d nd {
                    : i sdim ( __ti ost d )
                    : i coord ? > sdim 0 { / rem sdim } { 0 }
                    = rem ? > sdim 0 { % rem sdim } { rem }
                    = ao + ao * coord ( __ti ae d )
                    = bo + bo * coord ( __ti be d )
                    = d + d 1
                }
                : f r ( __apply op ( __tf . a data ao ) ( __tf . b data bo ) )
                ( vec_push [f] out ? == rdt TE_F32 { ( __t_round32 r ) } { r } )
                = i + i 1
            }
            ( vec_free [i] ost ) ( vec_free [i] ae ) ( vec_free [i] be )
            ^ @ ?Tensor { T @ Tensor { rdt oshape out } }
        }
        F _ → { ^ @ ?Tensor { F } }
    }
}

@ tensor_add Tensor a Tensor b → ?Tensor { ^ ( __t_binop a b 0 ) }

@ tensor_sub Tensor a Tensor b → ?Tensor { ^ ( __t_binop a b 1 ) }

@ tensor_mul Tensor a Tensor b → ?Tensor { ^ ( __t_binop a b 2 ) }

@ tensor_div Tensor a Tensor b → ?Tensor { ^ ( __t_binop a b 3 ) }

@ tensor_maximum Tensor a Tensor b → ?Tensor { ^ ( __t_binop a b 4 ) }

@ tensor_minimum Tensor a Tensor b → ?Tensor { ^ ( __t_binop a b 5 ) }

@ tensor_pow Tensor a Tensor b → ?Tensor { ^ ( __t_binop a b 6 ) }

// ── Scalar ops (tensor <op> scalar) ───────────────────────────────────

@ __t_scalar Tensor t f s i op → Tensor {
    : i n ( tensor_size t )
    : ( Vec f ) out ( vec_with_cap [f] ? > n 0 { n } { 1 } )
    : ~ i k 0
    ~ < k n {
        : f r ( __apply op ( __tf . t data k ) s )
        ( vec_push [f] out ? == . t dtype TE_F32 { ( __t_round32 r ) } { r } )
        = k + k 1
    }
    ^ @ Tensor { . t dtype ( __shape_copy . t shape ) out }
}

@ tensor_adds Tensor t f s → Tensor { ^ ( __t_scalar t s 0 ) }

@ tensor_muls Tensor t f s → Tensor { ^ ( __t_scalar t s 2 ) }

@ tensor_subs Tensor t f s → Tensor { ^ ( __t_scalar t s 1 ) }

@ tensor_divs Tensor t f s → Tensor { ^ ( __t_scalar t s 3 ) }

// ── Unary maps ────────────────────────────────────────────────────────

@ __umap i op f x → f {
    ? == op 0 { ^ - 0.0 x } {}
    ? == op 1 { ^ ( float_abs x ) } {}
    ? == op 2 { ^ ( float_exp x ) } {}
    ? == op 3 { ^ ( float_log x ) } {}
    ? == op 4 { ^ ( float_sqrt x ) } {}
    ? == op 5 { ^ ? > x 0.0 { x } { 0.0 } } {}  // relu
    ? == op 6 { ^ / 1.0 + 1.0 ( float_exp - 0.0 x ) } {}  // sigmoid
    : f e2 ( float_exp * 2.0 x )  // tanh
    ^ / - e2 1.0 + e2 1.0
}

@ __t_unary Tensor t i op → Tensor {
    : i n ( tensor_size t )
    : ( Vec f ) out ( vec_with_cap [f] ? > n 0 { n } { 1 } )
    : ~ i k 0
    ~ < k n {
        : f r ( __umap op ( __tf . t data k ) )
        ( vec_push [f] out ? == . t dtype TE_F32 { ( __t_round32 r ) } { r } )
        = k + k 1
    }
    ^ @ Tensor { . t dtype ( __shape_copy . t shape ) out }
}

@ tensor_neg Tensor t → Tensor { ^ ( __t_unary t 0 ) }

@ tensor_abs Tensor t → Tensor { ^ ( __t_unary t 1 ) }

@ tensor_exp Tensor t → Tensor { ^ ( __t_unary t 2 ) }

@ tensor_log Tensor t → Tensor { ^ ( __t_unary t 3 ) }

@ tensor_sqrt Tensor t → Tensor { ^ ( __t_unary t 4 ) }

@ tensor_relu Tensor t → Tensor { ^ ( __t_unary t 5 ) }

@ tensor_sigmoid Tensor t → Tensor { ^ ( __t_unary t 6 ) }

@ tensor_tanh Tensor t → Tensor { ^ ( __t_unary t 7 ) }

// ── Matmul (2-D) ──────────────────────────────────────────────────────

@ tensor_matmul Tensor a Tensor b → ?Tensor {
    ? & == ( tensor_ndim a ) 2 == ( tensor_ndim b ) 2 {} { ^ @ ?Tensor { F } }
    : i M ( tensor_dim a 0 )
    : i K ( tensor_dim a 1 )
    : i N ( tensor_dim b 1 )
    ? == K ( tensor_dim b 0 ) {} { ^ @ ?Tensor { F } }
    : i rdt ( __t_result_dtype a b )
    : ( Vec f ) c ( __fvec_t * M N 0.0 )
    : ~ b done F
    ? >= * * M N K 100000 {
        ? ( __t_gpu_ready ) {
            ? ( gk_matmul_f ( __t_kit ) c . a data . b data M K N ) { = done T } {}
        } {}
    } {}
    ? done {} {
        : ~ i i 0
        ~ < i M {
            : ~ i j 0
            ~ < j N {
                : ~ f s 0.0
                : ~ i p 0
                ~ < p K { = s + s * ( __tf . a data + * i K p ) ( __tf . b data + * p N j ) = p + p 1 }
                ( vec_set [f] c + * i N j s )
                = j + j 1
            }
            = i + i 1
        }
    }
    ( __round_vec c rdt )
    : ( Vec i ) shp ( __ivec_t 2 0 )
    ( vec_set [i] shp 0 M ) ( vec_set [i] shp 1 N )
    ^ @ ?Tensor { T @ Tensor { rdt shp c } }
}

// ── Transpose / permute ───────────────────────────────────────────────

@ tensor_transpose Tensor t → ?Tensor {
    ? == ( tensor_ndim t ) 2 {} { ^ @ ?Tensor { F } }
    : i M ( tensor_dim t 0 )
    : i N ( tensor_dim t 1 )
    : ( Vec f ) d ( __fvec_t * M N 0.0 )
    : ~ i i 0
    ~ < i M {
        : ~ i j 0
        ~ < j N { ( vec_set [f] d + * j M i ( __tf . t data + * i N j ) ) = j + j 1 }
        = i + i 1
    }
    : ( Vec i ) shp ( __ivec_t 2 0 )
    ( vec_set [i] shp 0 N ) ( vec_set [i] shp 1 M )
    ^ @ ?Tensor { T @ Tensor { . t dtype shp d } }
}

// General axis permutation. `perm` is a length-ndim ordering of the axes.
@ tensor_permute Tensor t ( Vec i ) perm → ?Tensor {
    : i nd ( tensor_ndim t )
    ? == ( vec_len [i] perm ) nd {} { ^ @ ?Tensor { F } }
    : ( Vec i ) ist ( __t_strides . t shape )
    : ( Vec i ) oshape ( __ivec_t nd 0 )
    : ( Vec i ) ostr_in ( __ivec_t nd 0 )  // input stride for each output axis
    : ~ i d 0
    ~ < d nd {
        : i src ( __ti perm d )
        ( vec_set [i] oshape d ( __ti . t shape src ) )
        ( vec_set [i] ostr_in d ( __ti ist src ) )
        = d + d 1
    }
    : ( Vec i ) ost ( __t_strides oshape )
    : i total ( tensor_size t )
    : ( Vec f ) out ( vec_with_cap [f] ? > total 0 { total } { 1 } )
    : ~ i i 0
    ~ < i total {
        : ~ i rem i
        : ~ i ino 0
        : ~ i d2 0
        ~ < d2 nd {
            : i sd ( __ti ost d2 )
            : i coord ? > sd 0 { / rem sd } { 0 }
            = rem ? > sd 0 { % rem sd } { rem }
            = ino + ino * coord ( __ti ostr_in d2 )
            = d2 + d2 1
        }
        ( vec_push [f] out ( __tf . t data ino ) )
        = i + i 1
    }
    ( vec_free [i] ist ) ( vec_free [i] ostr_in ) ( vec_free [i] ost )
    ^ @ ?Tensor { T @ Tensor { . t dtype oshape out } }
}

// ── Reductions ────────────────────────────────────────────────────────
//   op: 0 sum · 1 max · 2 min · 3 prod

@ __rinit i op → f {
    ? == op 0 { ^ 0.0 } {}
    ? == op 1 { ^ -1.0e308 } {}
    ? == op 2 { ^ 1.0e308 } {}
    ^ 1.0
}

@ __rstep i op f acc f x → f {
    ? == op 0 { ^ + acc x } {}
    ? == op 1 { ^ ? > x acc { x } { acc } } {}
    ? == op 2 { ^ ? < x acc { x } { acc } } {}
    ^ * acc x
}

// Reduce every element to a scalar tensor (shape []).
@ __reduce_all Tensor t i op → Tensor {
    : i n ( tensor_size t )
    : ~ f acc ( __rinit op )
    : ~ i k 0
    ~ < k n { = acc ( __rstep op acc ( __tf . t data k ) ) = k + k 1 }
    : ( Vec f ) d ( __fvec_t 1 acc )
    ^ @ Tensor { . t dtype ( __ivec_t 0 0 ) d }
}

@ __reduce_axis Tensor t i axis i op b keepdim → Tensor {
    : i nd ( tensor_ndim t )
    : ( Vec i ) ist ( __t_strides . t shape )
    // output shape
    : ( Vec i ) oshape ( vec_new [i] )
    : ~ i d 0
    ~ < d nd {
        ? == d axis { ? keepdim { ( vec_push [i] oshape 1 ) } {} } { ( vec_push [i] oshape ( __ti . t shape d ) ) }
        = d + d 1
    }
    : i outn ( __t_prod oshape )
    : ( Vec f ) out ( __fvec_t outn ( __rinit op ) )
    : ( Vec i ) ost ( __t_strides oshape )
    : i total ( tensor_size t )
    : ~ i i 0
    ~ < i total {
        // unravel over input shape, drop the reduced axis for the output offset
        : ~ i rem i
        : ~ i oo 0
        : ~ i od 0
        : ~ i d2 0
        ~ < d2 nd {
            : i sd ( __ti ist d2 )
            : i coord ? > sd 0 { / rem sd } { 0 }
            = rem ? > sd 0 { % rem sd } { rem }
            ? == d2 axis {
                ? keepdim { = od + od 1 } {}
            } {
                = oo + oo * coord ( __ti ost od )
                = od + od 1
            }
            = d2 + d2 1
        }
        ( vec_set [f] out oo ( __rstep op ( __tf out oo ) ( __tf . t data i ) ) )
        = i + i 1
    }
    ( vec_free [i] ist ) ( vec_free [i] ost )
    ^ @ Tensor { . t dtype oshape out }
}

// axis < 0 → reduce over everything (scalar result).
@ tensor_sum Tensor t i axis b keepdim → Tensor {
    ? < axis 0 { ^ ( __reduce_all t 0 ) } {}
    ^ ( __reduce_axis t axis 0 keepdim )
}

@ tensor_max Tensor t i axis b keepdim → Tensor {
    ? < axis 0 { ^ ( __reduce_all t 1 ) } {}
    ^ ( __reduce_axis t axis 1 keepdim )
}

@ tensor_min Tensor t i axis b keepdim → Tensor {
    ? < axis 0 { ^ ( __reduce_all t 2 ) } {}
    ^ ( __reduce_axis t axis 2 keepdim )
}

@ tensor_prod Tensor t i axis b keepdim → Tensor {
    ? < axis 0 { ^ ( __reduce_all t 3 ) } {}
    ^ ( __reduce_axis t axis 3 keepdim )
}

@ tensor_mean Tensor t i axis b keepdim → Tensor {
    : Tensor s ( tensor_sum t axis keepdim )
    : i cnt ? < axis 0 { ( tensor_size t ) } { ( tensor_dim t axis ) }
    : Tensor r ( tensor_divs s # f cnt )
    ( tensor_free s )
    ^ r
}
