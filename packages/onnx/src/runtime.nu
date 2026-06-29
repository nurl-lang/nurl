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

: Engine { Gpu g  Kernels ks  ( Vec RTensor ) vals  b ok }

@ streq2 s a s b → b { ^ != ( nurl_str_eq a b ) 0 }
@ ceil_div i a i b → i { ^ / + a - b 1 b }

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
                : i n . t nelem
                : GpuBuffer buf ( gpu_alloc . e g * n 4 )
                ( gpu_upload buf # *u . t host )
                ( rt_put e ( string_data . t name ) . buf dptr . t dims )
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
    : i OH ( ceil_div H sh )
    : i OW ( ceil_div Wd sw )
    // SAME_UPPER pad begin (extra goes to the end, so begin = total/2).
    : i pht - + * - OH 1 sh kh H
    : i pwt - + * - OW 1 sw kw Wd
    : i ph ? > pht 0 / pht 2 0
    : i pw ? > pwt 0 / pwt 2 0
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

// Mul (op=0) / Add (op=1) with a broadcast operand. ONNX lets the two
// inputs appear in either order, so the larger tensor is the data (X) and
// the smaller is the broadcast operand (B).
@ rt_eltwise *Engine e ONode n i op → v {
    : RTensor a ( __in e n 0 )
    : RTensor b ( __in e n 1 )
    : RTensor X ? >= . a nelem . b nelem a b
    : RTensor B ? >= . a nelem . b nelem b a
    : i C ( rt_dim X 1 )
    : i HW / . X nelem C
    : ~ i bmode 2
    ? == . B nelem 1 { = bmode 0 } { ? == . B nelem C { = bmode 1 } { = bmode 2 } }
    : i yd ( rt_alloc_out e ( __out_name n ) . X shape )
    ( op_eltwise . e g . e ks . X dptr . B dptr yd . X nelem HW op bmode )
}

// Run the graph on a host input buffer (raw f32). `shape` is the input
// tensor shape (e.g. [1,3,416,416]). Returns the output device tensor.
@ rt_run_shaped *Engine e OGraph g *u input_host ( Vec i ) shape → RTensor {
    ( rt_load_inits e g )
    : i n ( __prod shape )
    : GpuBuffer ib ( gpu_alloc . e g * n 4 )
    ( gpu_upload ib input_host )
    ( rt_put e ( string_data . g input_name ) . ib dptr shape )

    : ( Vec ONode ) nodes . g nodes
    : ~ i k 0
    ~ < k ( vec_len [ONode] nodes ) {
        ?? ( vec_get [ONode] nodes k ) {
            T nd → {
                : s op ( string_data . nd op_type )
                ? ( streq2 op `Gemm` ) { ( rt_gemm e nd ) }
                ? ( streq2 op `Relu` ) { ( rt_relu e nd ) }
                ? ( streq2 op `Conv` ) { ( rt_conv e nd ) }
                ? ( streq2 op `MaxPool` ) { ( rt_maxpool e nd ) }
                ? ( streq2 op `BatchNormalization` ) { ( rt_batchnorm e nd ) }
                ? ( streq2 op `LeakyRelu` ) { ( rt_leakyrelu e nd ) }
                ? ( streq2 op `Mul` ) { ( rt_eltwise e nd 0 ) }
                ? ( streq2 op `Add` ) { ( rt_eltwise e nd 1 ) }
                { ( nurl_eprint `[onnx] unsupported op: ` ) ( nurl_eprint op ) ( nurl_eprint `\n` ) }
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
