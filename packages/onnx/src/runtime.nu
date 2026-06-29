// packages/onnx/src/runtime.nu — the graph executor.
//
// Walks the ONNX graph in node order (ONNX guarantees topological order),
// keeping every intermediate tensor resident on the GPU. Initializers and
// the input are uploaded once; each node dispatches to a GPU kernel in
// ops.nu; the named output is downloaded at the end. A value map (name →
// device tensor) threads activations between nodes.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/gpu/src/gpu.nu`
$ `model.nu`
$ `ops.nu`

// A device-resident tensor: name, CUdeviceptr (i64), and 2-D shape
// (vectors are 1×N). Element count is rows*cols.
: RTensor { String name  i dptr  i rows  i cols }

: Engine { Gpu g  Kernels ks  ( Vec RTensor ) vals  b ok }

@ streq2 s a s b → b { ^ != ( nurl_str_eq a b ) 0 }

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

@ rt_put *Engine e s name i dptr i rows i cols → v {
    ( vec_push [RTensor] . e vals @ RTensor { ( string_from name ) dptr rows cols } )
}

// Find a value-map index by name (-1 if absent).
@ rt_find *Engine e s name → i {
    : ( Vec RTensor ) vs . e vals
    : ~ i k 0
    ~ < k ( vec_len [RTensor] vs ) {
        ?? ( vec_get [RTensor] vs k ) {
            T t → ? ( streq2 ( string_data . t name ) name ) { ^ k } {} F _ → {}
        }
        = k + k 1
    }
    ^ - 0 1
}

@ rt_at *Engine e i idx → RTensor {
    ?? ( vec_get [RTensor] . e vals idx ) { T t → ^ t F _ → ^ @ RTensor { ( string_new ) 0 0 0 } }
}

// Upload all graph initializers to the device as RTensors.
@ rt_load_inits *Engine e OGraph g → v {
    : ( Vec OTensor ) inits . g inits
    : ~ i k 0
    ~ < k ( vec_len [OTensor] inits ) {
        ?? ( vec_get [OTensor] inits k ) {
            T t → {
                : i n . t nelem
                : GpuBuffer buf ( gpu_alloc . e g * n 4 )
                ( gpu_upload buf # *u . t host )
                : ( Vec i ) dims . t dims
                : i nd ( vec_len [i] dims )
                : ~ i rows 1
                : ~ i cols n
                ? == nd 2 {
                    ?? ( vec_get [i] dims 0 ) { T d → = rows d F _ → {} }
                    ?? ( vec_get [i] dims 1 ) { T d → = cols d F _ → {} }
                } {}
                ( rt_put e ( string_data . t name ) . buf dptr rows cols )
            } F _ → {}
        }
        = k + k 1
    }
}

// Allocate a fresh device tensor, register it under `name`, return its dptr.
@ rt_alloc_out *Engine e s name i rows i cols → i {
    : GpuBuffer buf ( gpu_alloc . e g * * rows cols 4 )
    ( rt_put e name . buf dptr rows cols )
    ^ . buf dptr
}

// Execute one Gemm node.
@ rt_gemm *Engine e ONode n → v {
    : ( Vec String ) ins . n inputs
    : i ai ( rt_find e ( string_data ?? ( vec_get [String] ins 0 ) { T x → x F _ → ( string_new ) } ) )
    : i bi ( rt_find e ( string_data ?? ( vec_get [String] ins 1 ) { T x → x F _ → ( string_new ) } ) )
    : RTensor A ( rt_at e ai )
    : RTensor B ( rt_at e bi )
    : i transB ( node_attr_i n `transB` 0 )
    : f alpha ( node_attr_f n `alpha` 1.0 )
    : f beta ( node_attr_f n `beta` 1.0 )
    : i M . A rows
    : i K . A cols
    : i N ? != transB 0 . B rows . B cols
    : ~ i cdptr 0
    ? > ( vec_len [String] ins ) 2 {
        : i ci ( rt_find e ( string_data ?? ( vec_get [String] ins 2 ) { T x → x F _ → ( string_new ) } ) )
        ? >= ci 0 { : RTensor ct ( rt_at e ci ) = cdptr . ct dptr } {}
    } {}
    : String oname ?? ( vec_get [String] . n outputs 0 ) { T x → x F _ → ( string_new ) }
    : i ydptr ( rt_alloc_out e ( string_data oname ) M N )
    ( op_gemm . e g . e ks . A dptr . B dptr cdptr ydptr M N K alpha beta transB )
}

// Execute one Relu node.
@ rt_relu *Engine e ONode n → v {
    : ( Vec String ) ins . n inputs
    : i xi ( rt_find e ( string_data ?? ( vec_get [String] ins 0 ) { T x → x F _ → ( string_new ) } ) )
    : RTensor X ( rt_at e xi )
    : i rows . X rows
    : i cols . X cols
    : String oname ?? ( vec_get [String] . n outputs 0 ) { T x → x F _ → ( string_new ) }
    : i ydptr ( rt_alloc_out e ( string_data oname ) rows cols )
    ( op_relu . e g . e ks . X dptr ydptr * rows cols )
}

// Run the graph on a host input buffer (raw f32, rows×cols). Returns the
// output's device tensor; download it with rt_download.
@ rt_run *Engine e OGraph g *u input_host i in_rows i in_cols → RTensor {
    ( rt_load_inits e g )
    : GpuBuffer ib ( gpu_alloc . e g * * in_rows in_cols 4 )
    ( gpu_upload ib input_host )
    ( rt_put e ( string_data . g input_name ) . ib dptr in_rows in_cols )

    : ( Vec ONode ) nodes . g nodes
    : ~ i k 0
    ~ < k ( vec_len [ONode] nodes ) {
        ?? ( vec_get [ONode] nodes k ) {
            T n → {
                : s op ( string_data . n op_type )
                ? ( streq2 op `Gemm` ) { ( rt_gemm e n ) }
                ? ( streq2 op `Relu` ) { ( rt_relu e n ) }
                { ( nurl_eprint `[onnx] unsupported op: ` ) ( nurl_eprint op ) ( nurl_eprint `\n` ) }
            } F _ → {}
        }
        = k + k 1
    }
    ( gpu_sync . e g )
    : i oi ( rt_find e ( string_data . g output_name ) )
    ^ ( rt_at e oi )
}

// Download a device tensor into a fresh host f32 buffer (caller frees).
@ rt_download *Engine e RTensor t → *u {
    : i n * . t rows . t cols
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
