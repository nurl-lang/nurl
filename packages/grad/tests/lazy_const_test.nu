// lazy_const_test.nu — grad_const_lazy: a constant declared by SHAPE and
// filled AFTER the device capture, through gput_set_input.
//
// Why it exists: a frozen base weight is read exactly once, when the
// capture uploads it. Building the graph eagerly still makes every one of
// them resident as f64 host tensors at the same instant, so the host peak
// is the whole model no matter how little of it a training step needs.
// Declared lazily the graph costs a shape, and the caller streams the
// values in one tensor at a time.
//
// The proof is equivalence, not plausibility: the same graph, built both
// ways, must produce the SAME loss and the SAME gradients — not close, the
// same, because the arithmetic is identical and only the moment of upload
// differs.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/lazy_const_test.nu /tmp/lc && /tmp/lc

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `src/grad.nu`
$ `src/gput.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label ) ( nurl_print `\n` )
}

@ gf ( Vec f ) v i k → f { ?? ( vec_get [f] v k ) { T x → x F → 0.0 } }

@ shape2 i r i c → ( Vec i ) {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s r ) ( vec_push [i] s c )
    ^ s
}

// X [3,3] const values, W [3,2] param values — arbitrary but fixed.
@ xvals → ( Vec f ) {
    : ( Vec f ) v ( vec_new [f] )
    : ~ i k 0
    ~ < k 9 { ( vec_push [f] v - * 0.37 # f + k 1 1.1 ) = k + k 1 }
    ^ v
}

@ wvals → ( Vec f ) {
    : ( Vec f ) v ( vec_new [f] )
    : ~ i k 0
    ~ < k 6 { ( vec_push [f] v + 0.2 * 0.11 # f k ) = k + k 1 }
    ^ v
}

// loss = sum((X·W)²) with X a const and W a param. `lazy` picks how X is
// declared; the graph is otherwise identical.
@ run_once b lazy i dtype * u out → b {
    : *GTape tp ( tape_new )
    : ( Vec f ) wv ( wvals )
    : ( Vec i ) ws ( shape2 3 2 )
    : Tensor wt ( tensor_from_data TE_F64 ws wv )
    : GVar W ( grad_param tp wt )
    ( tensor_free wt ) ( vec_free [f] wv )
    : ( Vec f ) xv ( xvals )
    : ~ GVar X @ GVar { -1 }
    ? lazy {
        : ( Vec i ) xs ( shape2 3 3 )
        = X ( grad_const_lazy tp xs TE_F64 )
        ( vec_free [i] xs )
    } {
        : ( Vec i ) xs ( shape2 3 3 )
        : Tensor xt ( tensor_from_data TE_F64 xs xv )
        = X ( grad_const tp xt )
        ( tensor_free xt )
    }
    : GVar y ( g_matmul tp X W )
    : GVar loss ( g_sum tp ( g_mul tp y y ) )
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} {
        ( vec_free [f] xv ) ( tape_free tp ) ( gk_close kit )
        ^ F
    }
    : *GProg pg ( gput_capture_dt kit tp loss dtype )
    : ~ b ok ( gput_ok pg )
    // the lazy const's values arrive AFTER the capture, straight into the
    // buffer the capture sized from its shape
    ? & ok lazy { = ok ( gput_set_input pg X xv ) } {}
    = ok & ok ( gput_forward pg )
    = ok & ok ( gput_backward pg )
    ? ok {
        ( nurl_poke out 0 ( f64_to_bits ( gput_loss pg ) ) )
        : ( Vec f ) gw ( vec_with_cap [f] 6 )
        : ~ i k 0
        ~ < k 6 { ( vec_push [f] gw 0.0 ) = k + k 1 }
        = ok ( gput_grad pg W gw )
        ( nurl_poke out 1 ( f64_to_bits ( gf gw 0 ) ) )
        ( nurl_poke out 2 ( f64_to_bits ( gf gw 5 ) ) )
        ( vec_free [f] gw )
    } {}
    ( gput_free pg )
    ( gk_close kit )
    ( vec_free [f] xv )
    ( tape_free tp )
    ^ ok
}

@ main → i {
    : *u ea ( nurl_alloc 24 )
    : *u la ( nurl_alloc 24 )
    : b oke ( run_once F 0 ea )
    ? oke {} {
        ( nurl_print `lazy_const_test: SKIP (no device)\n` )
        ( nurl_free ea ) ( nurl_free la )
        ^ 0
    }
    : b okl ( run_once T 0 la )
    ( check okl `lazy const: capture, then upload, then forward/backward` )
    ( check == ( nurl_peek ea 0 ) ( nurl_peek la 0 ) `f64 loss is BIT-IDENTICAL to the eager const` )
    ( check == ( nurl_peek ea 1 ) ( nurl_peek la 1 ) `f64 grad[0] bit-identical` )
    ( check == ( nurl_peek ea 2 ) ( nurl_peek la 2 ) `f64 grad[5] bit-identical` )

    // and again on the f32 replay, where the buffer is narrowed on upload
    : *u ea32 ( nurl_alloc 24 )
    : *u la32 ( nurl_alloc 24 )
    : b oke32 ( run_once F 1 ea32 )
    : b okl32 ( run_once T 1 la32 )
    ( check & oke32 okl32 `f32 replay runs both ways` )
    ( check == ( nurl_peek ea32 0 ) ( nurl_peek la32 0 ) `f32 loss bit-identical` )
    ( check == ( nurl_peek ea32 1 ) ( nurl_peek la32 1 ) `f32 grad[0] bit-identical` )

    ( nurl_free ea ) ( nurl_free la ) ( nurl_free ea32 ) ( nurl_free la32 )
    ( nurl_print `lazy_const_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail )
    ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
