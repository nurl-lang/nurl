// packages/onnx/tests/infer_test.nu — parse + inference tests.
//
// The parse assertions (structure of tests/data/tiny.onnx) always run.
// The inference section runs the model on the GPU and checks the result
// against tests/data/tiny.out.f32 (an onnxruntime reference) — but SKIPS
// cleanly (still exit 0) when no CUDA device is present, so the suite
// passes on a GPU-less CI box. Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/infer_test.nu /tmp/it && /tmp/it

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `src/pb.nu`
$ `src/model.nu`
$ `src/runtime.nu`

& `c` @ nurl_peek_f32 *u base i idx → f

: ~ i g_fail 0
@ check b cond s name → v {
    ? cond { ( nurl_print `  ok  ` ) } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}
@ streqt s a s b → b { ^ != ( nurl_str_eq a b ) 0 }

// Load a raw little-endian f32 file into a host buffer (count via pcell).
@ load_f32t s path *u pcell → *u {
    ?? ( read_file_bytes path ) {
        T bytes → {
            : i n / ( vec_len [u] bytes ) 4
            : *u host ( nurl_alloc * n 4 )
            : *PbR r ( pb_new bytes )
            ( pb_read_f32_into r host n )
            ( pb_free r )
            ( nurl_poke pcell 0 n )
            ^ host
        }
        F _ → { ( nurl_poke pcell 0 0 ) ^ # *u 0 }
    }
}

@ main → i {
    : ~ b have_model F
    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes `tests/data/tiny.onnx` ) {
        T mb → { = g ( onnx_parse mb ) = have_model T } F _ → {}
    }
    ? ! have_model { ( nurl_print `cannot read tests/data/tiny.onnx (run from package root)\n` ) ^ 1 } {}

    ( nurl_print `[parse]\n` )
    ( check == ( vec_len [ONode] . g nodes ) 3 `3 nodes` )
    ( check == ( vec_len [OTensor] . g inits ) 4 `4 initializers` )
    ( check ( streqt ( string_data . g input_name ) `X` ) `input named X` )
    ( check ( streqt ( string_data . g output_name ) `Y` ) `output named Y` )
    : i w1i ( graph_find_init g `W1` )
    ( check >= w1i 0 `W1 present` )
    ?? ( vec_get [OTensor] . g inits w1i ) {
        T w1 → ( check == . w1 nelem 32 `W1 has 32 elements (4x8)` ) F _ → ( check F `W1 fetch` )
    }

    ( nurl_print `[infer]\n` )
    : *Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( nurl_print `  skip (no CUDA device / kernel compile)\n` )
        ? == g_fail 0 { ( nurl_print `\nALL PASS\n` ) ^ 0 } { ( nurl_print `\nFAIL\n` ) ^ 1 } } {}

    : *u ncell ( nurl_alloc 8 )
    : *u input ( load_f32t `tests/data/tiny.in.f32` ncell )
    : i in_n ( nurl_peek ncell 0 )
    : RTensor out ( rt_run e g input 1 in_n )
    : *u host ( rt_download e out )
    : i out_n . out nelem
    ( check == out_n 3 `output is length 3` )

    : *u ecell ( nurl_alloc 8 )
    : *u exp ( load_f32t `tests/data/tiny.out.f32` ecell )
    : ~ i bad 0
    : ~ i j 0
    ~ < j 3 {
        : ~ f d - ( nurl_peek_f32 host j ) ( nurl_peek_f32 exp j )
        ? < d 0.0 { = d - 0.0 d } {}
        ? > d 0.001 { = bad + bad 1 } {}
        = j + j 1
    }
    ( check == bad 0 `GPU output matches onnxruntime reference` )
    ( rt_close e )

    ? == g_fail 0 { ( nurl_print `\nALL PASS\n` ) ^ 0 }
    { ( nurl_print `\n` ) ( nurl_print ( nurl_str_int g_fail ) ) ( nurl_print ` FAILED\n` ) ^ 1 }
}
