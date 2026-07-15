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

// Load a raw little-endian f32 file into a fresh host buffer; returns the
// buffer and writes the element count through `pcount` (an i64 cell).
@ load_f32 s path * u pcount → *u {
    ?? ( read_file_bytes path ) {
        T bytes → {
            : i n / ( vec_len [u] bytes ) 4
            : *u host ( nurl_alloc * n 4 )
            : *PbR r ( pb_new bytes )
            ( pb_read_f32_into r host n )
            ( pb_free r )
            ( nurl_poke pcount 0 n )
            ^ host
        }
        F _ → { ( nurl_poke pcount 0 0 ) ^ # *u 0 }
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
    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes ( string_data model_path ) ) {
        T mb → { = g ( onnx_parse mb ) = have_model T } F _ → {}
    }
    ? ! have_model { ( nurl_print `cannot read model\n` ) ^ 1 } {}

    // load input
    : *u ncell ( nurl_alloc 8 )
    : *u input ( load_f32 ( string_data input_path ) ncell )
    : i in_n ( nurl_peek ncell 0 )
    ? == # i input 0 { ( nurl_print `cannot read input\n` ) ^ 1 } {}

    // open GPU + run
    : *Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( nurl_print `GPU init/kernel compile failed\n` ) ^ 1 } {}
    ( nurl_print `device: ` ) ( nurl_print ( rt_name e ) ) ( nurl_print `\n` )
    ( nurl_print `input elements: ` ) ( nurl_print ( nurl_str_int in_n ) ) ( nurl_print `\n` )

    : RTensor out ( rt_run e g input 1 in_n )
    // RTensor carries its full shape now (the 0.5.0 tensor bridge replaced
    // the old rows/cols pair); the element count is a field, not a product.
    : i out_n . out nelem
    : *u host ( rt_download e out )

    ( nurl_print `output [` ) ( nurl_print ( nurl_str_int out_n ) ) ( nurl_print `]: ` )
    : ~ i k 0
    ~ < k out_n {
        ( print_f ( nurl_peek_f32 host k ) ) ( nurl_print ` ` )
        = k + k 1
    }
    ( nurl_print `\n` )

    // optional verify against expected.f32
    : ~ i rc 0
    ? > ( vec_len [String] av ) 3 {
        : String exp_path ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }
        : *u ecell ( nurl_alloc 8 )
        : *u exp ( load_f32 ( string_data exp_path ) ecell )
        : i en ( nurl_peek ecell 0 )
        : ~ i bad 0
        : ~ f maxerr 0.0
        : ~ i j 0
        ~ < j en {
            : ~ f d - ( nurl_peek_f32 host j ) ( nurl_peek_f32 exp j )
            ? < d 0.0 { = d - 0.0 d } {}
            ? > d maxerr { = maxerr d } {}
            ? > d 0.001 { = bad + bad 1 } {}
            = j + j 1
        }
        ( nurl_print `max abs error vs reference: ` ) ( print_f maxerr ) ( nurl_print `\n` )
        ? == bad 0 { ( nurl_print `MATCH ✓\n` ) } { ( nurl_print `MISMATCH ✗ (` ) ( nurl_print ( nurl_str_int bad ) ) ( nurl_print ` elems)\n` ) = rc 1 }
    } {}

    ( rt_close e )
    ^ rc
}
