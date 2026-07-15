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
    ~ < k n { ( vec_set [f] v k ( _t_round32 ( _tf v k ) ) ) = k + k 1 }
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
    : ( Vec i ) out ( _ivec_t nd 1 )
    : ~ i d 0
    ~ < d nd {
        : i ia - - na 1 d
        : i ib - - nb 1 d
        : i da ? >= ia 0 { ( _ti a ia ) } { 1 }
        : i db ? >= ib 0 { ( _ti b ib ) } { 1 }
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
    : ( Vec i ) base ( _t_strides shape )
    : ( Vec i ) eff ( _ivec_t nd 0 )
    : ~ i d 0
    ~ < d nd {
        : i j - d - nd n
        ? & >= j 0 > ( _ti shape j ) 1 { ( vec_set [i] eff d ( _ti base j ) ) } {}
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
            : ( Vec i ) ost ( _t_strides oshape )
            : ( Vec i ) ae ( __t_eff_strides . a shape nd )
            : ( Vec i ) be ( __t_eff_strides . b shape nd )
            : i total ( _t_prod oshape )
            : i rdt ( __t_result_dtype a b )
            : ( Vec f ) out ( vec_with_cap [f] ? > total 0 { total } { 1 } )
            : ~ i i 0
            ~ < i total {
                : ~ i rem i
                : ~ i ao 0
                : ~ i bo 0
                : ~ i d 0
                ~ < d nd {
                    : i sdim ( _ti ost d )
                    : i coord ? > sdim 0 { / rem sdim } { 0 }
                    = rem ? > sdim 0 { % rem sdim } { rem }
                    = ao + ao * coord ( _ti ae d )
                    = bo + bo * coord ( _ti be d )
                    = d + d 1
                }
                : f r ( __apply op ( _tf . a data ao ) ( _tf . b data bo ) )
                ( vec_push [f] out ? == rdt TE_F32 { ( _t_round32 r ) } { r } )
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
        : f r ( __apply op ( _tf . t data k ) s )
        ( vec_push [f] out ? == . t dtype TE_F32 { ( _t_round32 r ) } { r } )
        = k + k 1
    }
    ^ @ Tensor { . t dtype ( _shape_copy . t shape ) out }
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
        : f r ( __umap op ( _tf . t data k ) )
        ( vec_push [f] out ? == . t dtype TE_F32 { ( _t_round32 r ) } { r } )
        = k + k 1
    }
    ^ @ Tensor { . t dtype ( _shape_copy . t shape ) out }
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
    : ( Vec f ) c ( _fvec_t * M N 0.0 )
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
                ~ < p K { = s + s * ( _tf . a data + * i K p ) ( _tf . b data + * p N j ) = p + p 1 }
                ( vec_set [f] c + * i N j s )
                = j + j 1
            }
            = i + i 1
        }
    }
    ( __round_vec c rdt )
    : ( Vec i ) shp ( _ivec_t 2 0 )
    ( vec_set [i] shp 0 M ) ( vec_set [i] shp 1 N )
    ^ @ ?Tensor { T @ Tensor { rdt shp c } }
}

// ── Transpose / permute ───────────────────────────────────────────────

@ tensor_transpose Tensor t → ?Tensor {
    ? == ( tensor_ndim t ) 2 {} { ^ @ ?Tensor { F } }
    : i M ( tensor_dim t 0 )
    : i N ( tensor_dim t 1 )
    : ( Vec f ) d ( _fvec_t * M N 0.0 )
    : ~ i i 0
    ~ < i M {
        : ~ i j 0
        ~ < j N { ( vec_set [f] d + * j M i ( _tf . t data + * i N j ) ) = j + j 1 }
        = i + i 1
    }
    : ( Vec i ) shp ( _ivec_t 2 0 )
    ( vec_set [i] shp 0 N ) ( vec_set [i] shp 1 M )
    ^ @ ?Tensor { T @ Tensor { . t dtype shp d } }
}

// General axis permutation. `perm` is a length-ndim ordering of the axes.
@ tensor_permute Tensor t ( Vec i ) perm → ?Tensor {
    : i nd ( tensor_ndim t )
    ? == ( vec_len [i] perm ) nd {} { ^ @ ?Tensor { F } }
    : ( Vec i ) ist ( _t_strides . t shape )
    : ( Vec i ) oshape ( _ivec_t nd 0 )
    : ( Vec i ) ostr_in ( _ivec_t nd 0 )  // input stride for each output axis
    : ~ i d 0
    ~ < d nd {
        : i src ( _ti perm d )
        ( vec_set [i] oshape d ( _ti . t shape src ) )
        ( vec_set [i] ostr_in d ( _ti ist src ) )
        = d + d 1
    }
    : ( Vec i ) ost ( _t_strides oshape )
    : i total ( tensor_size t )
    : ( Vec f ) out ( vec_with_cap [f] ? > total 0 { total } { 1 } )
    : ~ i i 0
    ~ < i total {
        : ~ i rem i
        : ~ i ino 0
        : ~ i d2 0
        ~ < d2 nd {
            : i sd ( _ti ost d2 )
            : i coord ? > sd 0 { / rem sd } { 0 }
            = rem ? > sd 0 { % rem sd } { rem }
            = ino + ino * coord ( _ti ostr_in d2 )
            = d2 + d2 1
        }
        ( vec_push [f] out ( _tf . t data ino ) )
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
    ~ < k n { = acc ( __rstep op acc ( _tf . t data k ) ) = k + k 1 }
    : ( Vec f ) d ( _fvec_t 1 acc )
    ^ @ Tensor { . t dtype ( _ivec_t 0 0 ) d }
}

@ __reduce_axis Tensor t i axis i op b keepdim → Tensor {
    : i nd ( tensor_ndim t )
    : ( Vec i ) ist ( _t_strides . t shape )
    // output shape
    : ( Vec i ) oshape ( vec_new [i] )
    : ~ i d 0
    ~ < d nd {
        ? == d axis { ? keepdim { ( vec_push [i] oshape 1 ) } {} } { ( vec_push [i] oshape ( _ti . t shape d ) ) }
        = d + d 1
    }
    : i outn ( _t_prod oshape )
    : ( Vec f ) out ( _fvec_t outn ( __rinit op ) )
    : ( Vec i ) ost ( _t_strides oshape )
    : i total ( tensor_size t )
    : ~ i i 0
    ~ < i total {
        // unravel over input shape, drop the reduced axis for the output offset
        : ~ i rem i
        : ~ i oo 0
        : ~ i od 0
        : ~ i d2 0
        ~ < d2 nd {
            : i sd ( _ti ist d2 )
            : i coord ? > sd 0 { / rem sd } { 0 }
            = rem ? > sd 0 { % rem sd } { rem }
            ? == d2 axis {
                ? keepdim { = od + od 1 } {}
            } {
                = oo + oo * coord ( _ti ost od )
                = od + od 1
            }
            = d2 + d2 1
        }
        ( vec_set [f] out oo ( __rstep op ( _tf out oo ) ( _tf . t data i ) ) )
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

// ══ M2: batched matmul, softmax, slicing, concat, argmax/argmin ════════

@ __unwrap ? Tensor o → Tensor {
    ?? o { T t → { ^ t } F _ → { ^ @ Tensor { TE_F64 ( vec_new [i] ) ( vec_new [f] ) } } }
}

// Batch strides of `shape` (its first ndim-2 dims), aligned into `ndb`
// output batch dims with broadcasting (0 where the batch dim is 1 or padded).
@ __t_batch_eff ( Vec i ) shape i ndb → ( Vec i ) {
    : i n ( vec_len [i] shape )
    : i nbatch - n 2
    : ( Vec i ) full ( _t_strides shape )
    : ( Vec i ) eff ( _ivec_t ndb 0 )
    : ~ i d 0
    ~ < d ndb {
        : i j - d - ndb nbatch
        ? & >= j 0 > ( _ti shape j ) 1 { ( vec_set [i] eff d ( _ti full j ) ) } {}
        = d + d 1
    }
    ( vec_free [i] full )
    ^ eff
}

@ __t_take_head ( Vec i ) shape i cnt → ( Vec i ) {
    : ( Vec i ) o ( vec_with_cap [i] ? > cnt 0 { cnt } { 1 } )
    : ~ i k 0
    ~ < k cnt { ( vec_push [i] o ( _ti shape k ) ) = k + k 1 }
    ^ o
}

// Batched matmul: [..,M,K] · [..,K,N] → [..,M,N], batch dims broadcast.
@ tensor_bmm Tensor a Tensor b → ?Tensor {
    : i na ( tensor_ndim a )
    : i nb ( tensor_ndim b )
    ? & >= na 2 >= nb 2 {} { ^ @ ?Tensor { F } }
    : i M ( _ti . a shape - na 2 )
    : i K ( _ti . a shape - na 1 )
    : i N ( _ti . b shape - nb 1 )
    ? == K ( _ti . b shape - nb 2 ) {} { ^ @ ?Tensor { F } }
    : ( Vec i ) ba ( __t_take_head . a shape - na 2 )
    : ( Vec i ) bb ( __t_take_head . b shape - nb 2 )
    : ?( Vec i ) bso ( __t_bshape ba bb )
    ( vec_free [i] ba ) ( vec_free [i] bb )
    ?? bso {
        T bshape → {
            : i ndb ( vec_len [i] bshape )
            : i nbatch ( _t_prod bshape )
            : ( Vec i ) bst ( _t_strides bshape )
            : ( Vec i ) aeff ( __t_batch_eff . a shape ndb )
            : ( Vec i ) beff ( __t_batch_eff . b shape ndb )
            : i mk * M K
            : i kn * K N
            : i mn * M N
            : i rdt ( __t_result_dtype a b )
            : ( Vec f ) out ( _fvec_t * nbatch mn 0.0 )
            : ~ i bi 0
            ~ < bi nbatch {
                // batch offsets into a and b
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
                : i ooff * bi mn
                : ~ i r 0
                ~ < r M {
                    : ~ i cc 0
                    ~ < cc N {
                        : ~ f s 0.0
                        : ~ i p 0
                        ~ < p K { = s + s * ( _tf . a data + aoff + * r K p ) ( _tf . b data + boff + * p N cc ) = p + p 1 }
                        ( vec_set [f] out + ooff + * r N cc ? == rdt TE_F32 { ( _t_round32 s ) } { s } )
                        = cc + cc 1
                    }
                    = r + r 1
                }
                = bi + bi 1
            }
            // out shape = bshape ++ [M, N]
            : ( Vec i ) oshape ( vec_with_cap [i] + ndb 2 )
            : ~ i k 0
            ~ < k ndb { ( vec_push [i] oshape ( _ti bshape k ) ) = k + k 1 }
            ( vec_push [i] oshape M ) ( vec_push [i] oshape N )
            ( vec_free [i] bshape ) ( vec_free [i] bst ) ( vec_free [i] aeff ) ( vec_free [i] beff )
            ^ @ ?Tensor { T @ Tensor { rdt oshape out } }
        }
        F _ → { ^ @ ?Tensor { F } }
    }
}

// Numerically-stable softmax along one axis.
@ tensor_softmax Tensor t i axis → Tensor {
    : Tensor mx ( tensor_max t axis T )
    : Tensor sh ( __unwrap ( tensor_sub t mx ) )
    : Tensor e ( tensor_exp sh )
    : Tensor sm ( tensor_sum e axis T )
    : Tensor r ( __unwrap ( tensor_div e sm ) )
    ( tensor_free mx ) ( tensor_free sh ) ( tensor_free e ) ( tensor_free sm )
    ^ r
}

// Slice: out[d] spans [starts[d], stops[d]) of each dim.
@ tensor_slice Tensor t ( Vec i ) starts ( Vec i ) stops → ?Tensor {
    : i nd ( tensor_ndim t )
    ? & == ( vec_len [i] starts ) nd == ( vec_len [i] stops ) nd {} { ^ @ ?Tensor { F } }
    : ( Vec i ) oshape ( _ivec_t nd 0 )
    : ~ i d 0
    ~ < d nd {
        : i s0 ( _ti starts d )
        : i s1 ( _ti stops d )
        ? & >= s0 0 & <= s1 ( _ti . t shape d ) <= s0 s1 {} { ( vec_free [i] oshape ) ^ @ ?Tensor { F } }
        ( vec_set [i] oshape d - s1 s0 )
        = d + d 1
    }
    : ( Vec i ) ist ( _t_strides . t shape )
    : ( Vec i ) ost ( _t_strides oshape )
    : i total ( _t_prod oshape )
    : ( Vec f ) out ( vec_with_cap [f] ? > total 0 { total } { 1 } )
    : ~ i i 0
    ~ < i total {
        : ~ i rem i
        : ~ i ino 0
        : ~ i d2 0
        ~ < d2 nd {
            : i sd ( _ti ost d2 )
            : i c ? > sd 0 { / rem sd } { 0 }
            = rem ? > sd 0 { % rem sd } { rem }
            = ino + ino * + c ( _ti starts d2 ) ( _ti ist d2 )
            = d2 + d2 1
        }
        ( vec_push [f] out ( _tf . t data ino ) )
        = i + i 1
    }
    ( vec_free [i] ist ) ( vec_free [i] ost )
    ^ @ ?Tensor { T @ Tensor { . t dtype oshape out } }
}

// Concatenate two tensors along `axis` (shapes equal except along axis).
@ tensor_concat2 Tensor a Tensor b i axis → ?Tensor {
    : i nd ( tensor_ndim a )
    ? & == nd ( tensor_ndim b ) & >= axis 0 < axis nd {} { ^ @ ?Tensor { F } }
    : ~ i d 0
    ~ < d nd { ? | == d axis == ( _ti . a shape d ) ( _ti . b shape d ) {} { ^ @ ?Tensor { F } } = d + d 1 }
    : ( Vec i ) oshape ( _shape_copy . a shape )
    ( vec_set [i] oshape axis + ( _ti . a shape axis ) ( _ti . b shape axis ) )
    : i rdt ( __t_result_dtype a b )
    : ( Vec i ) ost ( _t_strides oshape )
    : ( Vec i ) ast ( _t_strides . a shape )
    : ( Vec i ) bst ( _t_strides . b shape )
    : i asz ( _ti . a shape axis )
    : i total ( _t_prod oshape )
    : ( Vec f ) out ( vec_with_cap [f] ? > total 0 { total } { 1 } )
    : ~ i i 0
    ~ < i total {
        : ~ i rem i
        : ~ i coord_ax 0
        : ~ i aoff 0
        : ~ i boff 0
        : ~ i d3 0
        ~ < d3 nd {
            : i sd ( _ti ost d3 )
            : i c ? > sd 0 { / rem sd } { 0 }
            = rem ? > sd 0 { % rem sd } { rem }
            ? == d3 axis { = coord_ax c } {
                = aoff + aoff * c ( _ti ast d3 )
                = boff + boff * c ( _ti bst d3 )
            }
            = d3 + d3 1
        }
        : ~ f v 0.0
        ? < coord_ax asz {
            = v ( _tf . a data + aoff * coord_ax ( _ti ast axis ) )
        } {
            = v ( _tf . b data + boff * - coord_ax asz ( _ti bst axis ) )
        }
        ( vec_push [f] out v )
        = i + i 1
    }
    ( vec_free [i] ost ) ( vec_free [i] ast ) ( vec_free [i] bst )
    ^ @ ?Tensor { T @ Tensor { rdt oshape out } }
}

// argmax / argmin along an axis (indices as f64 in an F64 tensor).
@ __arg_axis Tensor t i axis b want_max b keepdim → Tensor {
    : i nd ( tensor_ndim t )
    : ( Vec i ) ist ( _t_strides . t shape )
    : ( Vec i ) oshape ( vec_new [i] )
    : ~ i d 0
    ~ < d nd { ? == d axis { ? keepdim { ( vec_push [i] oshape 1 ) } {} } { ( vec_push [i] oshape ( _ti . t shape d ) ) } = d + d 1 }
    : i outn ( _t_prod oshape )
    : ( Vec f ) best ( _fvec_t outn ? want_max { -1.0e308 } { 1.0e308 } )
    : ( Vec f ) idx ( _fvec_t outn 0.0 )
    : ( Vec i ) ost ( _t_strides oshape )
    : i total ( tensor_size t )
    : ~ i i 0
    ~ < i total {
        : ~ i rem i
        : ~ i oo 0
        : ~ i od 0
        : ~ i axc 0
        : ~ i d2 0
        ~ < d2 nd {
            : i sd ( _ti ist d2 )
            : i c ? > sd 0 { / rem sd } { 0 }
            = rem ? > sd 0 { % rem sd } { rem }
            ? == d2 axis { = axc c ? keepdim { = od + od 1 } {} } { = oo + oo * c ( _ti ost od ) = od + od 1 }
            = d2 + d2 1
        }
        : f v ( _tf . t data i )
        : f cur ( _tf best oo )
        : b better ? want_max { > v cur } { < v cur }
        ? better { ( vec_set [f] best oo v ) ( vec_set [f] idx oo # f axc ) } {}
        = i + i 1
    }
    ( vec_free [i] ist ) ( vec_free [i] ost ) ( vec_free [f] best )
    ^ @ Tensor { TE_F64 oshape idx }
}

@ tensor_argmax Tensor t i axis b keepdim → Tensor { ^ ( __arg_axis t axis T keepdim ) }

@ tensor_argmin Tensor t i axis b keepdim → Tensor { ^ ( __arg_axis t axis F keepdim ) }
