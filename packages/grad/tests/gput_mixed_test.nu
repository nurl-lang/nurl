// gput_mixed_test.nu — mixed precision (dtype 2: f32 storage, f64
// accumulation) vs pure f32 (dtype 1) vs the f64 CPU tape reference. Trains
// the SAME wide autoencoder three ways and shows that mixed tracks the f64
// reference markedly closer than pure f32 — because every matmul-K dot, the
// reductions, and the Adam update accumulate in f64 (only STORAGE is f32),
// killing the swamping pure f32 suffers. VRAM is identical (both store f32).
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/gput_mixed_test.nu /tmp/gm && /tmp/gm

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `src/grad.nu`
$ `src/opt.nu`
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

@ relerr f a f b → f {
    : ~ f den ( float_abs a )
    ? > ( float_abs b ) den { = den ( float_abs b ) } {}
    ? < den 0.001 { = den 0.001 } {}
    ^ / ( float_abs - a b ) den
}

@ glorot Rng g i fin i fout ( Vec f ) out → v {
    : f lim ( float_sqrt / 6.0 # f + fin fout )
    : ~ i k 0
    ~ < k * fin fout { ( vec_push [f] out * lim - * 2.0 ( rng_u01 g ) 1.0 ) = k + k 1 }
}

@ param2 * GTape tp ( Vec f ) v i r i c → GVar {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s r ) ( vec_push [i] s c )
    : Tensor t ( tensor_from_data TE_F64 s v )
    : GVar p ( grad_param tp t )
    ( tensor_free t )
    ^ p
}

@ param1 * GTape tp i n → GVar {
    : ( Vec f ) v ( vec_new [f] )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 0.0 ) = k + k 1 }
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s n )
    : Tensor t ( tensor_from_data TE_F64 s v )
    : GVar p ( grad_param tp t )
    ( tensor_free t ) ( vec_free [f] v )
    ^ p
}

@ episode * GTape tp GVar X GVar W1 GVar B1 GVar W2 GVar B2 f alpha i bsz → GVar {
    : GVar h ( g_relu tp ( g_add tp ( g_matmul tp X W1 ) B1 ) )
    : GVar y ( g_add tp ( g_matmul tp h W2 ) B2 )
    : GVar e ( g_sub tp y X )
    : GVar se ( g_sum tp ( g_mul tp e e ) )
    : GVar l2 ( g_add tp ( g_sum tp ( g_mul tp W1 W1 ) ) ( g_sum tp ( g_mul tp W2 W2 ) ) )
    : GVar num ( g_add tp se ( g_muls tp l2 alpha ) )
    ^ ( g_muls tp num / 1.0 * 2.0 # f bsz )
}

// Train the wide AE on the device with the given capture dtype; download the
// 4 final parameters into `outp` (flat, in id order 0..3).
@ train_device * GpuKit kit ( Vec f ) all ( Vec f ) w1v ( Vec f ) w2v i D i H i BSZ i EP f ALPHA f LR i dtype ( Vec f ) outp → b {
    : *GTape tp ( tape_new )
    : GVar W1 ( param2 tp w1v D H )
    : GVar B1 ( param1 tp H )
    : GVar W2 ( param2 tp w2v H D )
    : GVar B2 ( param1 tp D )
    : ( Vec f ) r0 ( vec_with_cap [f] * BSZ D )
    : ~ i q0 0
    ~ < q0 * BSZ D { ( vec_push [f] r0 ( _tf all q0 ) ) = q0 + q0 1 }
    : ( Vec i ) sh0 ( vec_new [i] )
    ( vec_push [i] sh0 BSZ ) ( vec_push [i] sh0 D )
    : Tensor rt0 ( tensor_from_data TE_F64 sh0 r0 )
    : GVar X ( grad_const tp rt0 )
    ( tensor_free rt0 ) ( vec_free [f] r0 )
    : GVar loss ( episode tp X W1 B1 W2 B2 ALPHA BSZ )
    : *GProg pg ( gput_capture_dt kit tp loss dtype )
    : ~ b ok ( gput_ok pg )
    : *GpOpt go ( gpopt_adam_new LR )
    ( gpopt_add go pg W1 ALPHA ) ( gpopt_add go pg B1 0.0 )
    ( gpopt_add go pg W2 ALPHA ) ( gpopt_add go pg B2 0.0 )
    : ~ i ep 0
    ~ & < ep EP ok {
        : ( Vec f ) rows ( vec_with_cap [f] * BSZ D )
        : ~ i q 0
        ~ < q * BSZ D { ( vec_push [f] rows ( _tf all + * * ep BSZ D q ) ) = q + q 1 }
        = ok & ok ( gput_set_input pg X rows )
        ( vec_free [f] rows )
        = ok & ok ( gput_forward pg )
        = ok & ok ( gput_backward pg )
        = ok & ok ( gpopt_step go pg )
        = ep + ep 1
    }
    = ok & ok ( gput_param_sync_host pg tp )
    ? ok {
        : ~ i pid 0
        ~ < pid 4 {
            : Tensor pv ( gvar_value tp @ GVar { pid } )
            : ~ i j 0
            ~ < j ( vec_len [f] . pv data ) { ( vec_push [f] outp ( _tf . pv data j ) ) = j + j 1 }
            = pid + pid 1
        }
    } {}
    ( gpopt_free go ) ( gput_free pg ) ( tape_free tp )
    ^ ok
}

@ main → i {
    : i D 8
    : i H 128
    : i BSZ 64
    : i EP 80
    : f ALPHA 0.0001
    : f LR 0.01
    : Rng dg ( rng_seed 3 )
    : ( Vec f ) all ( vec_with_cap [f] * * EP BSZ D )
    : ~ i k 0
    ~ < k * * EP BSZ D { ( vec_push [f] all - * 2.0 ( rng_u01 dg ) 1.0 ) = k + k 1 }
    ( rng_free dg )
    : Rng ig ( rng_seed 5 )
    : ( Vec f ) w1v ( vec_new [f] )
    ( glorot ig D H w1v )
    : ( Vec f ) w2v ( vec_new [f] )
    ( glorot ig H D w2v )
    ( rng_free ig )

    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} {
        ( nurl_print `gput_mixed: SKIP (no backend)\n` )
        ( gk_close kit )
        ^ 0
    }
    ( nurl_print `backend: ` ) ( nurl_print ( gk_backend kit ) ) ( nurl_print `\n` )

    // f64 reference (device dtype 0 = the bit-exact CPU-tape mirror)
    : ( Vec f ) pref ( vec_new [f] )
    ( check ( train_device kit all w1v w2v D H BSZ EP ALPHA LR 0 pref ) `f64 reference trains` )
    // pure f32
    : ( Vec f ) pf32 ( vec_new [f] )
    ( check ( train_device kit all w1v w2v D H BSZ EP ALPHA LR 1 pf32 ) `pure-f32 trains` )
    // mixed
    : ( Vec f ) pmix ( vec_new [f] )
    ( check ( train_device kit all w1v w2v D H BSZ EP ALPHA LR 2 pmix ) `mixed trains` )

    // worst param rel error vs f64 reference
    : ~ f wf32 0.0
    : ~ f wmix 0.0
    : i np ( vec_len [f] pref )
    = k 0
    ~ < k np {
        : f e1 ( relerr ( _tf pref k ) ( _tf pf32 k ) )
        : f e2 ( relerr ( _tf pref k ) ( _tf pmix k ) )
        ? > e1 wf32 { = wf32 e1 } {}
        ? > e2 wmix { = wmix e2 } {}
        = k + k 1
    }
    ( nurl_print `  worst param rel vs f64:  pure-f32 ` )
    ( nurl_print ( nurl_str_float wf32 ) )
    ( nurl_print `   mixed ` )
    ( nurl_print ( nurl_str_float wmix ) )
    ( nurl_print `\n` )
    ( check < wmix wf32 `mixed tracks the f64 reference CLOSER than pure f32` )
    ( check < wmix * 0.5 wf32 `mixed halves pure-f32 drift (>= 2x closer)` )

    ( vec_free [f] pref ) ( vec_free [f] pf32 ) ( vec_free [f] pmix )
    ( vec_free [f] all ) ( vec_free [f] w1v ) ( vec_free [f] w2v )
    ( gk_close kit )
    ( nurl_print `gput_mixed_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
