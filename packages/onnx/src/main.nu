// packages/onnx/src/main.nu — run an ONNX model on the GPU.
//
//   onnx <model.onnx> <input.f32> [expected.f32]
//
// Parses the model (pure-NURL protobuf), uploads weights + input to the
// GPU, executes the graph (Gemm/Relu kernels via packages/gpu + NVRTC),
// and prints the output. With an expected.f32 it also checks the result
// against that reference (e.g. an onnxruntime dump) and sets the exit code.
//
// Build:  nurlpkg install onnx   (or, from the package root,
//         NURL_STDLIB=<repo> ../../nurl.sh src/main.nu)

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `pb.nu`
$ `model.nu`
$ `runtime.nu`

& `c` @ nurl_peek_f32 *u base i idx → f

// Load a raw little-endian f32 file: its values as bytes (4 per element),
// empty when the file cannot be read.
@ load_f32 s path → ( Vec u ) {
    ?? ( read_file_bytes path ) {
        T bytes → {
            : i n / ( vec_len [u] bytes ) 4
            : ( Vec u ) host ( vec_with_cap [u] * n 4 )
            ( vec_f32_into bytes # *u ( vec_data [u] host ) n )
            : b _l ( vec_set_len [u] host * n 4 )
            ^ host
        }
        F _ → { ^ ( vec_new [u] ) }
    }
}

@ print_f f x → v { ( nurl_print ( nurl_str_float x ) ) }

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 3 {
        ( nurl_print `usage: onnx <model.onnx> <input.f32> [expected.f32]\n` )
        ^ 2
    } {}
    : String model_path ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : String input_path ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }

    // parse model
    : ~ b have_model F
    : ~ OGraph g ( onnx_empty_graph )
    ?? ( read_file_bytes ( string_data model_path ) ) {
        T mb → { = g ( onnx_parse mb ) = have_model T } F _ → {}
    }
    ? ! have_model { ( nurl_print `cannot read model\n` ) ^ 1 } {}

    // load input
    : ( Vec u ) input ( load_f32 ( string_data input_path ) )
    : i in_n / ( vec_len [u] input ) 4
    ? == in_n 0 { ( nurl_print `cannot read input\n` ) ^ 1 } {}

    // open GPU + run
    : Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( nurl_print `GPU init/kernel compile failed\n` ) ^ 1 } {}
    ( nurl_print `device: ` ) ( nurl_print ( rt_name e ) ) ( nurl_print `\n` )
    ( nurl_print `input elements: ` ) ( nurl_print ( nurl_str_int in_n ) ) ( nurl_print `\n` )

    : RTensor out ( rt_run e g # *u ( vec_data [u] input ) 1 in_n )
    // RTensor carries its full shape now (the 0.5.0 tensor bridge replaced
    // the old rows/cols pair); the element count is a field, not a product.
    : i out_n . out nelem
    : GpuHost host ( rt_download e out )

    ( nurl_print `output [` ) ( nurl_print ( nurl_str_int out_n ) ) ( nurl_print `]: ` )
    : ~ i k 0
    ~ < k out_n {
        ( print_f ( gpu_host_get_f32 host k ) ) ( nurl_print ` ` )
        = k + k 1
    }
    ( nurl_print `\n` )

    // optional verify against expected.f32
    : ~ i rc 0
    ? > ( vec_len [String] av ) 3 {
        : String exp_path ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }
        : ( Vec u ) expb ( load_f32 ( string_data exp_path ) )
        : *u exp # *u ( vec_data [u] expb )
        : i en / ( vec_len [u] expb ) 4
        : ~ i bad 0
        : ~ f maxerr 0.0
        : ~ i j 0
        ~ < j en {
            : ~ f d - ( gpu_host_get_f32 host j ) ( nurl_peek_f32 exp j )
            ? < d 0.0 { = d - 0.0 d } {}
            ? > d maxerr { = maxerr d } {}
            ? > d 0.001 { = bad + bad 1 } {}
            = j + j 1
        }
        ( nurl_print `max abs error vs reference: ` ) ( print_f maxerr ) ( nurl_print `\n` )
        ? == bad 0 { ( nurl_print `MATCH ✓\n` ) } { ( nurl_print `MISMATCH ✗ (` ) ( nurl_print ( nurl_str_int bad ) ) ( nurl_print ` elems)\n` ) = rc 1 }
    } {}

    ^ rc
}
