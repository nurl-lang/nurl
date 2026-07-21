// packages/grad/tests/gput_bench.nu — CPU tape vs device replay, wall clock.
//
// The train_test end-to-end workload: a d-64-32-64-d relu autoencoder,
// batch 200, 360 episodes of forward + backward + Adam. Both paths compute
// the SAME training (the parity test pins that bit-for-bit); this one just
// measures it honestly. Prints ms per path and the ratio — no gate, numbers
// only (per-op launches cannot fuse like aegpu's four-kernel pipeline, so
// the tape backend's win grows with the net, not with tiny nets).
//
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/gput_bench.nu /tmp/gb && /tmp/gb

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/time.nu`
$ `src/grad.nu`
$ `src/opt.nu`
$ `src/gput.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

@ glorot Rng g i fin i fout ( Vec f ) out → v {
    : f lim ( float_sqrt / 6.0 # f + fin fout )
    : i n * fin fout
    : ~ i k 0
    ~ < k n { ( vec_push [f] out * lim - * 2.0 ( rng_u01 g ) 1.0 ) = k + k 1 }
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

// One AE episode: X const already on the tape as `xid`.
@ episode * GTape tp GVar X GVar W1 GVar B1 GVar W2 GVar B2 GVar W3 GVar B3 f alpha i bsz → GVar {
    : GVar h1 ( g_relu tp ( g_add tp ( g_matmul tp X W1 ) B1 ) )
    : GVar h2 ( g_relu tp ( g_add tp ( g_matmul tp h1 W2 ) B2 ) )
    : GVar y ( g_add tp ( g_matmul tp h2 W3 ) B3 )
    : GVar e ( g_sub tp y X )
    : GVar se ( g_sum tp ( g_mul tp e e ) )
    : GVar l2a ( g_add tp ( g_sum tp ( g_mul tp W1 W1 ) ) ( g_sum tp ( g_mul tp W2 W2 ) ) )
    : GVar l2 ( g_add tp l2a ( g_sum tp ( g_mul tp W3 W3 ) ) )
    : GVar num ( g_add tp se ( g_muls tp l2 alpha ) )
    ^ ( g_muls tp num / 1.0 * 2.0 # f bsz )
}

@ main → i {
    : i D 6
    : i H1 64
    : i H2 32
    : i BSZ 200
    : i EPISODES 360
    : f ALPHA 0.0001
    : f LR 0.001
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} {
        ( nurl_print `gput_bench: SKIP (no compute backend)\n` )
        ( gk_close kit )
        ^ 0
    }
    ( nurl_print `backend: ` ) ( nurl_print ( gk_backend kit ) )
    ( nurl_print ` (` ) ( nurl_print ( gk_device_name kit ) ) ( nurl_print `)\n` )
    // data + init
    : Rng dg ( rng_seed 5 )
    : ( Vec f ) all ( vec_with_cap [f] * * EPISODES BSZ D )
    : ~ i k 0
    ~ < k * * EPISODES BSZ D { ( vec_push [f] all ( rng_u01 dg ) ) = k + k 1 }
    ( rng_free dg )
    : Rng ig ( rng_seed 11 )
    : ( Vec f ) w1v ( vec_new [f] )
    ( glorot ig D H1 w1v )
    : ( Vec f ) w2v ( vec_new [f] )
    ( glorot ig H1 H2 w2v )
    : ( Vec f ) w3v ( vec_new [f] )
    ( glorot ig H2 D w3v )
    ( rng_free ig )

    // — CPU path —
    : *GTape tp ( tape_new )
    : GVar W1 ( param2 tp w1v D H1 )
    : GVar B1 ( param1 tp H1 )
    : GVar W2 ( param2 tp w2v H1 H2 )
    : GVar B2 ( param1 tp H2 )
    : GVar W3 ( param2 tp w3v H2 D )
    : GVar B3 ( param1 tp D )
    : *Opt co ( opt_adam_new LR )
    ( opt_add co tp W1 ALPHA ) ( opt_add co tp B1 0.0 )
    ( opt_add co tp W2 ALPHA ) ( opt_add co tp B2 0.0 )
    ( opt_add co tp W3 ALPHA ) ( opt_add co tp B3 0.0 )
    : i mark ( tape_mark tp )
    : ~ f cfirst 0.0
    : ~ f clast 0.0
    : i t0 ( monotonic_ns )
    : ~ i ep 0
    ~ < ep EPISODES {
        : ( Vec f ) rows ( vec_with_cap [f] * BSZ D )
        : ~ i q 0
        ~ < q * BSZ D { ( vec_push [f] rows ( _tf all + * * ep BSZ D q ) ) = q + q 1 }
        : ( Vec i ) rsh ( vec_new [i] )
        ( vec_push [i] rsh BSZ ) ( vec_push [i] rsh D )
        : Tensor rt ( tensor_from_data TE_F64 rsh rows )
        : GVar X ( grad_const tp rt )
        ( tensor_free rt ) ( vec_free [f] rows )
        : GVar loss ( episode tp X W1 B1 W2 B2 W3 B3 ALPHA BSZ )
        : b bk ( backward tp loss )
        ? bk {} { ( nurl_print `cpu episode failed\n` ) }
        ? == ep 0 { = cfirst ( g_scalar tp loss ) } {}
        ? == ep - EPISODES 1 { = clast ( g_scalar tp loss ) } {}
        ( opt_step co tp )
        ( tape_reset_to tp mark )
        = ep + ep 1
    }
    : i t1 ( monotonic_ns )

    // — device path —
    : *GTape tp2 ( tape_new )
    : GVar W1d ( param2 tp2 w1v D H1 )
    : GVar B1d ( param1 tp2 H1 )
    : GVar W2d ( param2 tp2 w2v H1 H2 )
    : GVar B2d ( param1 tp2 H2 )
    : GVar W3d ( param2 tp2 w3v H2 D )
    : GVar B3d ( param1 tp2 D )
    : ( Vec f ) rows0 ( vec_with_cap [f] * BSZ D )
    : ~ i q0 0
    ~ < q0 * BSZ D { ( vec_push [f] rows0 ( _tf all q0 ) ) = q0 + q0 1 }
    : ( Vec i ) rsh0 ( vec_new [i] )
    ( vec_push [i] rsh0 BSZ ) ( vec_push [i] rsh0 D )
    : Tensor rt0 ( tensor_from_data TE_F64 rsh0 rows0 )
    : GVar Xd ( grad_const tp2 rt0 )
    ( tensor_free rt0 ) ( vec_free [f] rows0 )
    : GVar lossd ( episode tp2 Xd W1d B1d W2d B2d W3d B3d ALPHA BSZ )
    : *GProg pg ( gput_capture kit tp2 lossd )
    ? ( gput_ok pg ) {} {
        ( nurl_print `gput_bench: capture failed\n` )
        ( gput_free pg ) ( gk_close kit )
        ^ 1
    }
    : *GpOpt go ( gpopt_adam_new LR )
    ( gpopt_add go pg W1d ALPHA ) ( gpopt_add go pg B1d 0.0 )
    ( gpopt_add go pg W2d ALPHA ) ( gpopt_add go pg B2d 0.0 )
    ( gpopt_add go pg W3d ALPHA ) ( gpopt_add go pg B3d 0.0 )
    : ~ f dfirst 0.0
    : ~ f dlast 0.0
    : ~ b devok T
    : i t2 ( monotonic_ns )
    : ~ i ep2 0
    ~ & < ep2 EPISODES devok {
        : ( Vec f ) rows ( vec_with_cap [f] * BSZ D )
        : ~ i q 0
        ~ < q * BSZ D { ( vec_push [f] rows ( _tf all + * * ep2 BSZ D q ) ) = q + q 1 }
        = devok & devok ( gput_set_input pg Xd rows )
        ( vec_free [f] rows )
        = devok & devok ( gput_forward pg )
        = devok & devok ( gput_backward pg )
        ? == ep2 0 { = dfirst ( gput_loss pg ) } {}
        ? == ep2 - EPISODES 1 { = dlast ( gput_loss pg ) } {}
        = devok & devok ( gpopt_step go pg )
        = ep2 + ep2 1
    }
    : i t3 ( monotonic_ns )
    ? devok {} { ( nurl_print `gput_bench: device loop failed\n` ) }

    : i cms / - t1 t0 1000000
    : i dms / - t3 t2 1000000
    ( nurl_print `cpu tape:      ` ) ( nurl_print_int cms ) ( nurl_print ` ms\n` )
    ( nurl_print `device replay: ` ) ( nurl_print_int dms ) ( nurl_print ` ms\n` )
    ? > dms 0 {
        ( nurl_print `ratio: ` )
        ( nurl_print ( nurl_str_float / # f cms # f dms ) )
        ( nurl_print `x\n` )
    } {}
    ( nurl_print `loss cpu ` ) ( nurl_print ( nurl_str_float cfirst ) )
    ( nurl_print ` → ` ) ( nurl_print ( nurl_str_float clast ) ) ( nurl_print `\n` )
    ( nurl_print `loss dev ` ) ( nurl_print ( nurl_str_float dfirst ) )
    ( nurl_print ` → ` ) ( nurl_print ( nurl_str_float dlast ) ) ( nurl_print `\n` )
    : b agree & == ( f64_to_bits cfirst ) ( f64_to_bits dfirst ) == ( f64_to_bits clast ) ( f64_to_bits dlast )
    ( nurl_print ? agree `loss endpoints BIT-EQUAL\n` `loss endpoints DIFFER\n` )
    ( gpopt_free go )
    ( gput_free pg )
    ( opt_free co )
    ( tape_free tp ) ( tape_free tp2 )
    ( vec_free [f] w1v ) ( vec_free [f] w2v ) ( vec_free [f] w3v )
    ( vec_free [f] all )
    ( gk_close kit )
    ^ ? agree 0 1
}
