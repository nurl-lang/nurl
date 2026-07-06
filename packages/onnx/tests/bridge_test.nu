// packages/onnx/tests/bridge_test.nu — tensor↔onnx zero-copy bridge (M4a).
//
// Runs tests/data/tiny.onnx twice: once through the classic host path
// (rt_run_shaped) and once with a DEVICE-RESIDENT input (rt_run_dtensor,
// no host staging). The two outputs must be BIT-IDENTICAL (same kernels,
// same bytes). Then composes on the device — wraps the graph output as an
// owned DTensor, applies dtensor_softmax, and checks against a host
// softmax of the reference output. SKIPs cleanly with no device.
//   NURL_STDLIB=<repo> ../../nurl.sh tests/bridge_test.nu /tmp/bt && /tmp/bt

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `src/pb.nu`
$ `src/model.nu`
$ `src/tensor_bridge.nu`

& `c` @ nurl_peek_f32 *u base i idx → f

: ~ i g_fail 0

@ check b cond s name → v {
    ? cond { ( nurl_print `  ok  ` ) } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}

@ load_f32b s path * u pcell → *u {
    ?? ( read_file_bytes path ) {
        T bytes → {
            : i n / ( vec_len [u] bytes ) 4
            : *u host ( nurl_alloc * n 4 )
            : *PbR r ( pb_new bytes )
            ( pb_read_f32_into r host n )
            ( pb_free r )
            ( nurl_poke pcell 0 n )
            ( vec_free [u] bytes )
            ^ host
        }
        F _ → { ( nurl_poke pcell 0 0 ) ^ # *u 0 }
    }
}

@ sh2b i a i b → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v a ) ( vec_push [i] v b ) ^ v
}

@ main → i {
    // parse the model
    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes `tests/data/tiny.onnx` ) {
        T mb → { : OGraph parsed ( onnx_parse mb ) ( graph_free g ) = g parsed ( vec_free [u] mb ) }
        F _ → { ( nurl_print `cannot read tests/data/tiny.onnx\n` ) ^ 1 }
    }

    : *u nc ( nurl_alloc 8 )
    : *u input ( load_f32b `tests/data/tiny.in.f32` nc )
    : i in_n ( nurl_peek nc 0 )
    : *u refout ( load_f32b `tests/data/tiny.out.f32` nc )
    : i out_n ( nurl_peek nc 0 )
    ? & == in_n 4 == out_n 3 {} { ( nurl_print `bad test data\n` ) ^ 1 }

    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} { ( nurl_print `SKIP no device\n` ) ( gk_close kit ) ^ 0 }
    : *Engine e ( rt_open 0 )
    ? ( rt_ok e ) {} { ( nurl_print `SKIP engine open failed\n` ) ^ 0 }

    // ── host path ─────────────────────────────────────────────────
    : RTensor oh ( rt_run_shaped e g input ( sh2b 1 4 ) )
    : *u hostr ( rt_download e oh )

    // ── device path: DTensor input, no host staging in the run ───
    : ( Vec f ) inv ( vec_with_cap [f] 4 )
    : ~ i k 0
    ~ < k 4 { ( vec_push [f] inv # f ( nurl_peek_f32 input k ) ) = k + k 1 }
    : Tensor tin ( tensor_from_data TE_F32 ( sh2b 1 4 ) inv )
    ( vec_free [f] inv )
    : DTensor din ( tensor_to_device kit tin )
    ( check ( dtensor_ok din ) `input uploaded as DTensor` )

    : RTensor od ( rt_run_dtensor e g din )
    ( check > . od nelem 0 `graph ran with a device-resident input` )
    : *u devr ( rt_download e od )

    : ~ i diffs 0
    = k 0
    ~ < k 3 {
        ? == ( nurl_f32_to_bits # f32 ( nurl_peek_f32 hostr k ) ) ( nurl_f32_to_bits # f32 ( nurl_peek_f32 devr k ) ) {} { = diffs + diffs 1 }
        = k + k 1
    }
    ( check == diffs 0 `device-input output BIT-IDENTICAL to host-input output` )

    // vs the onnxruntime reference
    : ~ f mx 0.0
    = k 0
    ~ < k 3 {
        : f d ( float_abs - ( nurl_peek_f32 devr k ) ( nurl_peek_f32 refout k ) )
        ? > d mx { = mx d } {}
        = k + k 1
    }
    ( check < mx 0.0001 `matches the onnxruntime reference` )

    // ── device-side postprocess: wrap output, softmax, download ──
    : DTensor dout ( dtensor_from_output kit e od )
    ( check ( dtensor_ok dout ) `output wrapped as an owned DTensor` )
    : ~ DTensor dsm @ DTensor { TE_F32 ( vec_new [i] ) @ GkBuf { 0 0 GK_F32 } }
    ?? ( dtensor_softmax kit dout ) { T sm → { ( dtensor_free dsm ) = dsm sm } F _ → {} }
    ( check ( dtensor_ok dsm ) `dtensor_softmax on the wrapped output` )

    // the copy must survive an engine reset (independence proof)
    ( rt_reset e )
    : Tensor hsm ( dtensor_to_host kit dsm )

    // host softmax of the reference
    : ~ f m0 ( nurl_peek_f32 refout 0 )
    = k 1
    ~ < k 3 { : f v ( nurl_peek_f32 refout k ) ? > v m0 { = m0 v } {} = k + k 1 }
    : ~ f se 0.0
    : ( Vec f ) es ( vec_with_cap [f] 3 )
    = k 0
    ~ < k 3 { : f ev ( float_exp - ( nurl_peek_f32 refout k ) m0 ) ( vec_push [f] es ev ) = se + se ev = k + k 1 }
    : ~ f mx2 0.0
    = k 0
    ~ < k 3 {
        : f want / ?? ( vec_get [f] es k ) { T x → x F _ → 0.0 } se
        : f d ( float_abs - ( tensor_flat hsm k ) want )
        ? > d mx2 { = mx2 d } {}
        = k + k 1
    }
    ( check < mx2 0.0001 `device softmax matches host softmax (after rt_reset)` )

    ( vec_free [f] es )
    ( tensor_free hsm )
    ( dtensor_free dsm )
    ( dtensor_free dout )
    ( dtensor_free din )
    ( tensor_free tin )
    ( gpu_host_free hostr ) ( gpu_host_free devr )
    ( nurl_free input ) ( nurl_free refout )
    ( nurl_free nc )
    ( rt_close e )
    ( gk_close kit )
    ( graph_free g )

    ? == g_fail 0 { ( nurl_print `\nALL PASS\n` ) ^ 0 }
    { ( nurl_print `\n` ) ( nurl_print ( nurl_str_int g_fail ) ) ( nurl_print ` FAILED\n` ) ^ 1 }
}
