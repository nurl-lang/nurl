// packages/onnx/src/runtime.nu — the graph executor.
//
// Walks the ONNX graph in node order (ONNX guarantees topological order),
// keeping every intermediate tensor resident on the GPU. Initializers and
// the input are uploaded once; each node dispatches to a GPU kernel in
// ops.nu; the named output is downloaded at the end. A value map (name →
// device tensor) threads activations between nodes.
//
// Tensors are N-D (shape vector); the dense path reads dims 0,1 as M,K and
// the conv path reads NCHW from dims 1,2,3 (batch N is assumed 1).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/gpu/src/gpu.nu`
$ `model.nu`
$ `ops.nu`

// A device-resident tensor: name, CUdeviceptr (i64), shape, element count.
: RTensor { String name  i dptr  ( Vec i ) shape  i nelem }

: Engine { Gpu g  Kernels ks  ( Vec RTensor ) vals  OGraph graph  b ok }

@ streq2 s a s b → b { ^ != ( nurl_str_eq a b ) 0 }
@ ceil_div i a i b → i { ^ / + a - b 1 b }

// ── initializer metadata (int64 shape/size tensors stay host-side) ──
& `c` @ nurl_peek_f32 *u base i idx → f
@ __init_tensor *Engine e s name → OTensor {
    : OGraph g . e graph
    : i idx ( graph_find_init g name )
    ? < idx 0 { ^ @ OTensor { ( string_new ) ( vec_new [i] ) 0 0 0 } } {}
    ?? ( vec_get [OTensor] . g inits idx ) { T t → ^ t F _ → ^ @ OTensor { ( string_new ) ( vec_new [i] ) 0 0 0 } }
}
@ __init_i64 *Engine e s name i k → i {       // k-th value of an INT64 init
    : OTensor t ( __init_tensor e name )
    ? == . t host 0 { ^ 0 } { ^ ( nurl_peek # *u . t host k ) }
}
@ __init_i64_len *Engine e s name → i { : OTensor t ( __init_tensor e name ) ^ . t nelem }
@ __init_f32 *Engine e s name i k → f {        // k-th value of a FLOAT init
    : OTensor t ( __init_tensor e name )
    ? == . t host 0 { ^ 0.0 } { ^ ( nurl_peek_f32 # *u . t host k ) }
}

@ __prod ( Vec i ) v → i {
    : ~ i p 1
    : ~ i k 0
    ~ < k ( vec_len [i] v ) { ?? ( vec_get [i] v k ) { T d → = p * p d F _ → {} } = k + k 1 }
    ^ p
}
@ __dim_at ( Vec i ) v i ax → i { ?? ( vec_get [i] v ax ) { T d → ^ d F _ → ^ 1 } }
@ rt_dim RTensor t i ax → i { ^ ( __dim_at . t shape ax ) }

// Open a device and compile the kernels.
@ rt_open i ordinal → *Engine {
    : *Engine e # *Engine ( nurl_alloc Z Engine )
    : Gpu g ( gpu_open ordinal )
    = . e g g
    : Kernels ks ( ops_compile g )
    = . e ks ks
    = . e vals ( vec_new [RTensor] )
    = . e graph @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) }
    = . e ok & ( gpu_ok g ) . ks ok
    ^ e
}

@ rt_ok *Engine e → b { ^ . e ok }
@ rt_name *Engine e → s { ^ ( gpu_name . e g ) }

// Register a device tensor under `name` with an explicit shape vector.
@ rt_put *Engine e s name i dptr ( Vec i ) shape → v {
    ( vec_push [RTensor] . e vals @ RTensor { ( string_from name ) dptr shape ( __prod shape ) } )
}
@ __shape2 i a i b → ( Vec i ) { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v a ) ( vec_push [i] v b ) ^ v }
@ __shape4 i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d ) ^ v
}

@ rt_find *Engine e s name → i {
    : ( Vec RTensor ) vs . e vals
    : ~ i k 0
    ~ < k ( vec_len [RTensor] vs ) {
        ?? ( vec_get [RTensor] vs k ) { T t → ? ( streq2 ( string_data . t name ) name ) { ^ k } {} F _ → {} }
        = k + k 1
    }
    ^ - 0 1
}
@ rt_at *Engine e i idx → RTensor {
    ?? ( vec_get [RTensor] . e vals idx ) { T t → ^ t F _ → ^ @ RTensor { ( string_new ) 0 ( vec_new [i] ) 0 } }
}
// Input name of a node (k-th), as an `s`.
@ __in *Engine e ONode n i k → RTensor {
    : ( Vec String ) ins . n inputs
    : i idx ( rt_find e ( string_data ?? ( vec_get [String] ins k ) { T x → x F _ → ( string_new ) } ) )
    ^ ( rt_at e idx )
}
@ __out_name ONode n → s {
    ^ ( string_data ?? ( vec_get [String] . n outputs 0 ) { T x → x F _ → ( string_new ) } )
}

// Upload all graph initializers to the device as RTensors (full shape).
@ rt_load_inits *Engine e OGraph g → v {
    : ( Vec OTensor ) inits . g inits
    : ~ i k 0
    ~ < k ( vec_len [OTensor] inits ) {
        ?? ( vec_get [OTensor] inits k ) {
            T t → {
                // INT64 tensors (shapes/sizes/anchor grids) stay host-side as
                // metadata — read via __init_i64; only FLOAT weights go to GPU.
                ? & != . t dtype 7 != . t host 0 {
                    : i n . t nelem
                    : GpuBuffer buf ( gpu_alloc . e g * n 4 )
                    ( gpu_upload buf # *u . t host )
                    ( rt_put e ( string_data . t name ) . buf dptr . t dims )
                } {}
            } F _ → {}
        }
        = k + k 1
    }
}

// Allocate a fresh device tensor with `shape`, register under `name`,
// return its dptr.
@ rt_alloc_out *Engine e s name ( Vec i ) shape → i {
    : GpuBuffer buf ( gpu_alloc . e g * ( __prod shape ) 4 )
    ( rt_put e name . buf dptr shape )
    ^ . buf dptr
}

// ── op handlers ───────────────────────────────────────────────────
@ rt_gemm *Engine e ONode n → v {
    : RTensor A ( __in e n 0 )
    : RTensor B ( __in e n 1 )
    : i transB ( node_attr_i n `transB` 0 )
    : f alpha ( node_attr_f n `alpha` 1.0 )
    : f beta ( node_attr_f n `beta` 1.0 )
    : i M ( rt_dim A 0 )
    : i K ( rt_dim A 1 )
    : i N ? != transB 0 ( rt_dim B 0 ) ( rt_dim B 1 )
    : ~ i cdptr 0
    ? > ( vec_len [String] . n inputs ) 2 { : RTensor C ( __in e n 2 ) = cdptr . C dptr } {}
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape2 M N ) )
    ( op_gemm . e g . e ks . A dptr . B dptr cdptr yd M N K alpha beta transB )
}

@ rt_relu *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i yd ( rt_alloc_out e ( __out_name n ) . X shape )
    ( op_relu . e g . e ks . X dptr yd . X nelem )
}

@ rt_conv *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : RTensor W ( __in e n 1 )
    : i Cin ( rt_dim X 1 )
    : i H ( rt_dim X 2 )
    : i Wd ( rt_dim X 3 )
    : i Cout ( rt_dim W 0 )
    : i kh ( rt_dim W 2 )
    : i kw ( rt_dim W 3 )
    : i sh ( node_attr_int_at n `strides` 0 1 )
    : i sw ( node_attr_int_at n `strides` 1 1 )
    : s ap ( node_attr_s n `auto_pad` `NOTSET` )
    : ~ i OH ( ceil_div H sh )
    : ~ i OW ( ceil_div Wd sw )
    : ~ i ph 0
    : ~ i pw 0
    ? | ( streq2 ap `SAME_UPPER` ) ( streq2 ap `SAME_LOWER` ) {
        : i pht - + * - OH 1 sh kh H
        : i pwt - + * - OW 1 sw kw Wd
        = ph ? > pht 0 / pht 2 0
        = pw ? > pwt 0 / pwt 2 0
    } {
        = OH + / - + H * 2 ( node_attr_int_at n `pads` 0 0 ) kh sh 1
        = OW + / - + Wd * 2 ( node_attr_int_at n `pads` 1 0 ) kw sw 1
        = ph ( node_attr_int_at n `pads` 0 0 )
        = pw ( node_attr_int_at n `pads` 1 0 )
    }
    : ~ i bd 0
    : ~ i hasB 0
    ? > ( vec_len [String] . n inputs ) 2 { : RTensor B ( __in e n 2 ) = bd . B dptr = hasB 1 } {}
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape4 1 Cout OH OW ) )
    ( op_conv . e g . e ks . X dptr . W dptr bd yd Cin H Wd Cout kh kw OH OW ph pw sh sw hasB )
}

@ rt_maxpool *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i C ( rt_dim X 1 )
    : i H ( rt_dim X 2 )
    : i Wd ( rt_dim X 3 )
    : i kh ( node_attr_int_at n `kernel_shape` 0 2 )
    : i kw ( node_attr_int_at n `kernel_shape` 1 2 )
    : i sh ( node_attr_int_at n `strides` 0 1 )
    : i sw ( node_attr_int_at n `strides` 1 1 )
    : s ap ( node_attr_s n `auto_pad` `NOTSET` )
    : ~ i OH 0
    : ~ i OW 0
    : ~ i ph 0
    : ~ i pw 0
    ? | ( streq2 ap `SAME_UPPER` ) ( streq2 ap `SAME_LOWER` ) {
        = OH ( ceil_div H sh ) = OW ( ceil_div Wd sw )
        : i pht - + * - OH 1 sh kh H
        : i pwt - + * - OW 1 sw kw Wd
        = ph ? > pht 0 / pht 2 0
        = pw ? > pwt 0 / pwt 2 0
    } {
        // NOTSET: explicit pads [top,left,bottom,right] (begin = top/left)
        = ph ( node_attr_int_at n `pads` 0 0 )
        = pw ( node_attr_int_at n `pads` 1 0 )
        = OH + / - + H * 2 ph kh sh 1
        = OW + / - + Wd * 2 pw kw sw 1
    }
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape4 1 C OH OW ) )
    ( op_maxpool . e g . e ks . X dptr yd C H Wd kh kw OH OW sh sw ph pw )
}

@ rt_batchnorm *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : RTensor sc ( __in e n 1 )
    : RTensor B ( __in e n 2 )
    : RTensor mn ( __in e n 3 )
    : RTensor vr ( __in e n 4 )
    : i C ( rt_dim X 1 )
    : i HW / . X nelem C
    : f eps ( node_attr_f n `epsilon` 0.00001 )
    : i yd ( rt_alloc_out e ( __out_name n ) . X shape )
    ( op_batchnorm . e g . e ks . X dptr . sc dptr . B dptr . mn dptr . vr dptr yd C HW eps )
}

@ rt_leakyrelu *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : f alpha ( node_attr_f n `alpha` 0.01 )
    : i yd ( rt_alloc_out e ( __out_name n ) . X shape )
    ( op_leakyrelu . e g . e ks . X dptr yd . X nelem alpha )
}

@ rt_ndim RTensor t → i { ^ ( vec_len [i] . t shape ) }
@ rt_last RTensor t → i { ^ ( rt_dim t - ( rt_ndim t ) 1 ) }

// Binary op: 0=Mul 1=Add 2=Sub 3=Div. For commutative ops (Mul/Add) the
// larger input is the data and the smaller broadcasts (ONNX allows either
// order); Sub/Div keep `in0 op in1`. Broadcast mode is inferred from the
// operand element count: scalar, full, per-inner (a per-anchor stride
// vector), or per-channel.
@ rt_binop *Engine e ONode n i op → v {
    : RTensor a ( __in e n 0 )
    : RTensor b ( __in e n 1 )
    : b comm | == op 0 == op 1
    : RTensor X ? & comm < . a nelem . b nelem b a
    : RTensor B ? & comm < . a nelem . b nelem a b
    : i C ( rt_dim X 1 )
    : i inner ( rt_last X )
    : ~ i bmode 2
    : ~ i per 0
    ? == . B nelem 1 { = bmode 0 }
    ? == . B nelem . X nelem { = bmode 2 }
    ? == . B nelem inner { = bmode 3 = per inner }
    ? == . B nelem C { = bmode 1 = per / . X nelem C }
    { = bmode 2 }
    : i yd ( rt_alloc_out e ( __out_name n ) . X shape )
    ( op_eltwise . e g . e ks . X dptr . B dptr yd . X nelem per op bmode )
}

@ rt_sigmoid *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i yd ( rt_alloc_out e ( __out_name n ) . X shape )
    ( op_sigmoid . e g . e ks . X dptr yd . X nelem )
}

// Reshape: pure reinterpret (data is contiguous) → alias the input buffer
// under the output name with the new shape. Shape comes from the INT64
// initializer input[1]; a -1 entry is inferred, 0 copies the input dim.
@ rt_reshape *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : s shp_name ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } )
    : i nd ( __init_i64_len e shp_name )
    : ( Vec i ) ns ( vec_new [i] )
    : ~ i prod 1
    : ~ i negat - 0 1
    : ~ i k 0
    ~ < k nd {
        : ~ i d ( __init_i64 e shp_name k )
        ? == d 0 { = d ( rt_dim X k ) } {}
        ? == d - 0 1 { = negat k ( vec_push [i] ns - 0 1 ) } { = prod * prod d ( vec_push [i] ns d ) }
        = k + k 1
    }
    ? >= negat 0 { ( vec_set [i] ns negat / . X nelem prod ) } {}
    ( rt_put e ( __out_name n ) . X dptr ns )
}

// Resize (nearest, integer upscale). Scales come from the FLOAT init
// input[2] = [1,1,sh,sw].
@ rt_resize *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : s sc_name ( string_data ?? ( vec_get [String] . n inputs 2 ) { T x → x F _ → ( string_new ) } )
    : i sh # i ( __init_f32 e sc_name 2 )
    : i sw # i ( __init_f32 e sc_name 3 )
    : i C ( rt_dim X 1 )
    : i H ( rt_dim X 2 )
    : i W ( rt_dim X 3 )
    : i OH * H sh
    : i OW * W sw
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape4 1 C OH OW ) )
    ( op_resize . e g . e ks . X dptr yd C H W OH OW sh sw )
}

@ rt_transpose *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i p0 ( node_attr_int_at n `perm` 0 0 )
    : i p1 ( node_attr_int_at n `perm` 1 1 )
    : i p2 ( node_attr_int_at n `perm` 2 2 )
    : i p3 ( node_attr_int_at n `perm` 3 3 )
    : i d0 ( rt_dim X 0 )
    : i d1 ( rt_dim X 1 )
    : i d2 ( rt_dim X 2 )
    : i d3 ( rt_dim X 3 )
    : ( Vec i ) os ( vec_new [i] )
    ( vec_push [i] os ( rt_dim X p0 ) ) ( vec_push [i] os ( rt_dim X p1 ) )
    ( vec_push [i] os ( rt_dim X p2 ) ) ( vec_push [i] os ( rt_dim X p3 ) )
    : i yd ( rt_alloc_out e ( __out_name n ) os )
    ( op_perm4 . e g . e ks . X dptr yd d0 d1 d2 d3 p0 p1 p2 p3 )
}

// Softmax over `axis`, viewing the tensor as (outer, axis, inner).
@ rt_softmax *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i ax ( node_attr_i n `axis` - ( rt_ndim X ) 1 )
    : ~ i outer 1
    : ~ i j 0
    ~ < j ax { = outer * outer ( rt_dim X j ) = j + j 1 }
    : i axn ( rt_dim X ax )
    : ~ i inner 1
    : ~ i m + ax 1
    ~ < m ( rt_ndim X ) { = inner * inner ( rt_dim X m ) = m + m 1 }
    : i yd ( rt_alloc_out e ( __out_name n ) . X shape )
    ( op_softmax . e g . e ks . X dptr yd outer axn inner )
}

// Concat along `axis`, viewing each input as (outer, axis_i, inner).
@ rt_concat *Engine e ONode n → v {
    : i axis ( node_attr_i n `axis` 1 )
    : RTensor first ( __in e n 0 )
    : ~ i outer 1
    : ~ i j 0
    ~ < j axis { = outer * outer ( rt_dim first j ) = j + j 1 }
    : ~ i inner 1
    : ~ i m + axis 1
    ~ < m ( rt_ndim first ) { = inner * inner ( rt_dim first m ) = m + m 1 }
    : i nin ( vec_len [String] . n inputs )
    : ~ i sumax 0
    : ~ i a 0
    ~ < a nin { = sumax + sumax ( rt_dim ( __in e n a ) axis ) = a + a 1 }
    // output shape = first's shape with the concat axis replaced by sumax
    : ( Vec i ) os ( vec_new [i] )
    : ~ i d 0
    ~ < d ( rt_ndim first ) { ( vec_push [i] os ? == d axis sumax ( rt_dim first d ) ) = d + d 1 }
    : i yd ( rt_alloc_out e ( __out_name n ) os )
    : ~ i off 0
    : ~ i ai 0
    ~ < ai nin {
        : RTensor src ( __in e n ai )
        : i sa ( rt_dim src axis )
        ( op_copy_ax . e g . e ks . src dptr yd outer sa inner sumax off )
        = off + off sa
        = ai + ai 1
    }
}

// Split along `axis` into contiguous slices — alias each output onto the
// input buffer at its byte offset (no copy). Sizes from the INT64 init
// input[1] when present, else `num_outputs` equal parts.
@ rt_split *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i axis ( node_attr_i n `axis` 1 )
    : ~ i outer 1
    : ~ i j 0
    ~ < j axis { = outer * outer ( rt_dim X j ) = j + j 1 }
    : ~ i inner 1
    : ~ i m + axis 1
    ~ < m ( rt_ndim X ) { = inner * inner ( rt_dim X m ) = m + m 1 }
    : i nout ( vec_len [String] . n outputs )
    : ~ b have_sizes F
    : ~ s sz_name ``
    ? > ( vec_len [String] . n inputs ) 1 {
        = sz_name ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } )
        ? > ( __init_i64_len e sz_name ) 0 { = have_sizes T } {}
    } {}
    : i src_ax ( rt_dim X axis )
    : i eq / src_ax nout
    : ~ i off 0
    : ~ i k 0
    ~ < k nout {
        : i sz ? have_sizes ( __init_i64 e sz_name k ) eq
        : ( Vec i ) os ( vec_new [i] )
        : ~ i d 0
        ~ < d ( rt_ndim X ) { ( vec_push [i] os ? == d axis sz ( rt_dim X d ) ) = d + d 1 }
        : s onm ( string_data ?? ( vec_get [String] . n outputs k ) { T x → x F _ → ( string_new ) } )
        ? == outer 1 {
            // contiguous slice — alias the input buffer at the byte offset
            ( rt_put e onm + . X dptr * * off inner 4 os )
        } {
            // interleaved slice (outer>1) — must copy into a fresh buffer
            : i od ( rt_alloc_out e onm os )
            ( op_slice_ax . e g . e ks . X dptr od outer sz inner src_ax off )
        }
        = off + off sz
        = k + k 1
    }
}

// MatMul. Two cases: A[...,M,K] @ B[K,N] (2-D B) collapses leading dims
// into M and uses Gemm; A[...,M,K] @ B[...,K,N] (matching batch dims, the
// attention case) uses a batched matmul.
@ rt_matmul *Engine e ONode n → v {
    : RTensor A ( __in e n 0 )
    : RTensor B ( __in e n 1 )
    : i Kd ( rt_last A )
    : i N ( rt_last B )
    ? > ( rt_ndim B ) 2 {
        // batched: A[batch,M,K] @ B[batch,K,N] -> [batch,M,N]
        : i M ( rt_dim A - ( rt_ndim A ) 2 )
        : i batch / . A nelem * M Kd
        : ( Vec i ) os ( vec_new [i] )
        : ~ i d 0
        ~ < d - ( rt_ndim A ) 1 { ( vec_push [i] os ( rt_dim A d ) ) = d + d 1 }
        ( vec_push [i] os N )
        : i yd ( rt_alloc_out e ( __out_name n ) os )
        ( op_bmm . e g . e ks . A dptr . B dptr yd batch M N Kd )
    } {
        : i M / . A nelem Kd
        : ( Vec i ) os ( vec_new [i] )
        : ~ i d 0
        ~ < d - ( rt_ndim A ) 1 { ( vec_push [i] os ( rt_dim A d ) ) = d + d 1 }
        ( vec_push [i] os N )
        : i yd ( rt_alloc_out e ( __out_name n ) os )
        ( op_gemm . e g . e ks . A dptr . B dptr 0 yd M N Kd 1.0 0.0 0 )
    }
}

// LayerNormalization over the last axis (scale = in1, bias = in2).
@ rt_layernorm *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : RTensor sc ( __in e n 1 )
    : RTensor bi ( __in e n 2 )
    : i ax ( rt_last X )
    : i outer / . X nelem ax
    : f eps ( node_attr_f n `epsilon` 0.00001 )
    : i yd ( rt_alloc_out e ( __out_name n ) . X shape )
    ( op_layernorm . e g . e ks . X dptr . sc dptr . bi dptr yd outer ax eps )
}

@ rt_erf *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i yd ( rt_alloc_out e ( __out_name n ) . X shape )
    ( op_erf . e g . e ks . X dptr yd . X nelem )
}

// Einsum "bchw,bkc->bkhw": region[1,C,H,W] · text[1,K,C] -> [1,K,H,W].
// = Gemm(text[K,C], region[C,HW]) -> [K,HW].
@ rt_einsum *Engine e ONode n → v {
    : s eq ( node_attr_s n `equation` `` )
    : RTensor region ( __in e n 0 )
    : RTensor text ( __in e n 1 )
    : i C ( rt_dim region 1 )
    : i H ( rt_dim region 2 )
    : i Wd ( rt_dim region 3 )
    : i HW * H Wd
    : i Kk ( rt_dim text 1 )
    : i yd ( rt_alloc_out e ( __out_name n ) ( __shape4 1 Kk H Wd ) )
    ( op_gemm . e g . e ks . text dptr . region dptr 0 yd Kk HW C 1.0 0.0 0 )
}

@ rt_reducel2 *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : i ax ( rt_last X )
    : i outer / . X nelem ax
    : ( Vec i ) os ( vec_new [i] )
    : ~ i d 0
    ~ < d - ( rt_ndim X ) 1 { ( vec_push [i] os ( rt_dim X d ) ) = d + d 1 }
    ( vec_push [i] os 1 )
    : i yd ( rt_alloc_out e ( __out_name n ) os )
    ( op_reducel2 . e g . e ks . X dptr yd outer ax )
}

@ rt_clip *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : ~ f lo - 0.0 1000000000.0
    : ~ f hi 1000000000.0
    ? > ( vec_len [String] . n inputs ) 1 {
        = lo ( __init_f32 e ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } ) 0 )
    } {}
    ? > ( vec_len [String] . n inputs ) 2 {
        = hi ( __init_f32 e ( string_data ?? ( vec_get [String] . n inputs 2 ) { T x → x F _ → ( string_new ) } ) 0 )
    } {}
    : i yd ( rt_alloc_out e ( __out_name n ) . X shape )
    ( op_clip . e g . e ks . X dptr yd . X nelem lo hi )
}

// Expand the last axis (broadcast a (...,1) tensor to the target shape).
@ rt_expand *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : s shp_name ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } )
    : i nd ( __init_i64_len e shp_name )
    : i rep ( __init_i64 e shp_name - nd 1 )
    : i outer . X nelem
    : ( Vec i ) os ( vec_new [i] )
    : ~ i d 0
    ~ < d nd { ( vec_push [i] os ( __init_i64 e shp_name d ) ) = d + d 1 }
    : i yd ( rt_alloc_out e ( __out_name n ) os )
    ( op_expand . e g . e ks . X dptr yd outer rep )
}

// Unsqueeze: insert size-1 axes — pure reshape (alias). New shape from the
// input's shape with 1s inserted at the `axes` positions.
@ rt_unsqueeze *Engine e ONode n → v {
    : RTensor X ( __in e n 0 )
    : s ax_name ( string_data ?? ( vec_get [String] . n inputs 1 ) { T x → x F _ → ( string_new ) } )
    : i a0 ( __init_i64 e ax_name 0 )
    : ( Vec i ) os ( vec_new [i] )
    : i nd ( rt_ndim X )
    : ~ i d 0
    ~ <= d nd {
        ? == d a0 { ( vec_push [i] os 1 ) } {}
        ? < d nd { ( vec_push [i] os ( rt_dim X d ) ) } {}
        = d + d 1
    }
    ( rt_put e ( __out_name n ) . X dptr os )
}

// Run the graph on a host input buffer (raw f32). `shape` is the input
// tensor shape (e.g. [1,3,416,416]). Returns the output device tensor.
@ rt_run_shaped *Engine e OGraph g *u input_host ( Vec i ) shape → RTensor {
    = . e graph g
    ( rt_load_inits e g )
    : i n ( __prod shape )
    : GpuBuffer ib ( gpu_alloc . e g * n 4 )
    ( gpu_upload ib input_host )
    ( rt_put e ( string_data . g input_name ) . ib dptr shape )
    ^ ( __rt_run_nodes e g )
}

// Two-input run (e.g. image + text embeddings for a promptable model).
@ rt_run_two *Engine e OGraph g s n1 *u h1 ( Vec i ) s1 s n2 *u h2 ( Vec i ) s2 → RTensor {
    = . e graph g
    ( rt_load_inits e g )
    : GpuBuffer b1 ( gpu_alloc . e g * ( __prod s1 ) 4 )
    ( gpu_upload b1 h1 ) ( rt_put e n1 . b1 dptr s1 )
    : GpuBuffer b2 ( gpu_alloc . e g * ( __prod s2 ) 4 )
    ( gpu_upload b2 h2 ) ( rt_put e n2 . b2 dptr s2 )
    ^ ( __rt_run_nodes e g )
}

@ __rt_run_nodes *Engine e OGraph g → RTensor {
    : ( Vec ONode ) nodes . g nodes
    : ~ i k 0
    ~ < k ( vec_len [ONode] nodes ) {
        ?? ( vec_get [ONode] nodes k ) {
            T nd → {
                : s op ( string_data . nd op_type )
                // Skip a node whose first input was never produced (e.g. the
                // segmentation branch hanging off the unsupported ConvTranspose):
                // running an op on an empty (dptr 0) tensor would do an illegal
                // device read and corrupt the whole CUDA context. Detection
                // (output0) doesn't depend on that branch.
                : s in0 ( string_data ?? ( vec_get [String] . nd inputs 0 ) { T x → x F _ → ( string_new ) } )
                : b ready | == ( vec_len [String] . nd inputs ) 0 >= ( rt_find e in0 ) 0
                ? ! ready { } {
                ? ( streq2 op `Gemm` ) { ( rt_gemm e nd ) }
                ? ( streq2 op `Relu` ) { ( rt_relu e nd ) }
                ? ( streq2 op `Conv` ) { ( rt_conv e nd ) }
                ? ( streq2 op `MaxPool` ) { ( rt_maxpool e nd ) }
                ? ( streq2 op `BatchNormalization` ) { ( rt_batchnorm e nd ) }
                ? ( streq2 op `LeakyRelu` ) { ( rt_leakyrelu e nd ) }
                ? ( streq2 op `Mul` ) { ( rt_binop e nd 0 ) }
                ? ( streq2 op `Add` ) { ( rt_binop e nd 1 ) }
                ? ( streq2 op `Sub` ) { ( rt_binop e nd 2 ) }
                ? ( streq2 op `Div` ) { ( rt_binop e nd 3 ) }
                ? ( streq2 op `Sigmoid` ) { ( rt_sigmoid e nd ) }
                ? ( streq2 op `Concat` ) { ( rt_concat e nd ) }
                ? ( streq2 op `Split` ) { ( rt_split e nd ) }
                ? ( streq2 op `Reshape` ) { ( rt_reshape e nd ) }
                ? ( streq2 op `Resize` ) { ( rt_resize e nd ) }
                ? ( streq2 op `Transpose` ) { ( rt_transpose e nd ) }
                ? ( streq2 op `Softmax` ) { ( rt_softmax e nd ) }
                ? ( streq2 op `MatMul` ) { ( rt_matmul e nd ) }
                ? ( streq2 op `Einsum` ) { ( rt_einsum e nd ) }
                ? ( streq2 op `ReduceL2` ) { ( rt_reducel2 e nd ) }
                ? ( streq2 op `Clip` ) { ( rt_clip e nd ) }
                ? ( streq2 op `Expand` ) { ( rt_expand e nd ) }
                ? ( streq2 op `Unsqueeze` ) { ( rt_unsqueeze e nd ) }
                ? ( streq2 op `LayerNormalization` ) { ( rt_layernorm e nd ) }
                ? ( streq2 op `Erf` ) { ( rt_erf e nd ) }
                { ( nurl_eprint `[onnx] unsupported op: ` ) ( nurl_eprint op ) ( nurl_eprint `\n` ) }
                }
            } F _ → {}
        }
        = k + k 1
    }
    ( gpu_sync . e g )
    : i oi ( rt_find e ( string_data . g output_name ) )
    ^ ( rt_at e oi )
}

// Convenience for a 2-D (dense) input.
@ rt_run *Engine e OGraph g *u input_host i in_rows i in_cols → RTensor {
    ^ ( rt_run_shaped e g input_host ( __shape2 in_rows in_cols ) )
}

// Download a device tensor into a fresh host f32 buffer (caller frees).
@ rt_download *Engine e RTensor t → *u {
    : i n . t nelem
    : *u host ( gpu_host_alloc * n 4 )
    : GpuBuffer b @ GpuBuffer { . t dptr * n 4 }
    ( gpu_download host b )
    ^ host
}

@ rt_close *Engine e → v {
    ( ops_free . e ks )
    ( gpu_close . e g )
    ( nurl_free # *u e )
}
