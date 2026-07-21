// packages/anomaly/tests/aegpu_parity_test.nu — the autoencoder GPU-training
// parity gate. Trains the SAME data with mlp_fit (CPU) and aegpu_fit (GPU)
// and asserts the results are BIT-IDENTICAL: weights, biases, the full Adam
// state, epoch count, and both loss figures. This is the proof behind the
// package's guarantee that backend choice can never change a result — the
// GPU path is pure speed. Prints both wall times as a bonus.
//
// Needs a CUDA device (aegpu_fit falls back to mlp_fit without one, which
// would make the comparison trivially true) — the .sh wrapper skips cleanly
// on machines without one. Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/aegpu_parity_test.nu /tmp/aep && /tmp/aep
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/floatbits.nu`
$ `src/aegpu.nu`
$ `deps/mlp/src/mlp.nu`

@ veq s label ( Vec f ) a ( Vec f ) b → b {
    : i n ( vec_len [f] a )
    ? != n ( vec_len [f] b ) { ( nurl_print label ) ( nurl_print ` LEN MISMATCH\n` ) ^ F } {}
    : ~ i bad 0
    : ~ i k 0
    ~ < k n {
        ? != ( f64_to_bits ( _mlp_fget a k ) ) ( f64_to_bits ( _mlp_fget b k ) ) { = bad + bad 1 } {}
        = k + k 1
    }
    ( nurl_print label )
    ? == bad 0 { ( nurl_print ` BIT-EXACT (` ) ( nurl_print_int n ) ( nurl_print ` values)\n` ) ^ T } {
        ( nurl_print ` MISMATCH: ` ) ( nurl_print_int bad ) ( nurl_print ` of ` ) ( nurl_print_int n ) ( nurl_print `\n` ) ^ F
    }
}

@ main → i {
    : i n 6000
    : i d 12
    : Rng g ( rng_seed 99 )
    : ( Vec f ) X ( vec_with_cap [f] * n d )
    : ~ i k 0
    ~ < k * n d { ( vec_push [f] X ( rng_u01 g ) ) = k + k 1 }
    ( rng_free g )
    : ( Vec i ) sz ( vec_new [i] )
    ( vec_push [i] sz d ) ( vec_push [i] sz 64 ) ( vec_push [i] sz 32 ) ( vec_push [i] sz 64 ) ( vec_push [i] sz d )
    : MlpCfg cfg ( mlp_cfg_default )
    ( nurl_print `engine: ` ) ( nurl_print ( anom_gpu_engine ) ) ( nurl_print `\n` )
    : i t0 ( monotonic_ns )
    : MlpFit cpu ( mlp_fit sz X n d X d cfg 3 )
    : i t1 ( monotonic_ns )
    : MlpFit gpu ( aegpu_fit sz X n d cfg 3 )
    : i t2 ( monotonic_ns )
    ( nurl_print `cpu mlp_fit:  ` ) ( nurl_print_int / - t1 t0 1000000 ) ( nurl_print ` ms\n` )
    ( nurl_print `gpu aegpu_fit: ` ) ( nurl_print_int / - t2 t1 1000000 ) ( nurl_print ` ms\n` )
    : Mlp cm . cpu model
    : Mlp gm . gpu model
    : MlpTrain cr . cpu report
    : MlpTrain gr . gpu report
    : ~ b ok T
    ? ( veq `weights:` . cm w . gm w ) {} { = ok F }
    ? ( veq `biases: ` . cm b . gm b ) {} { = ok F }
    ? ( veq `adam mw:` . cm mw . gm mw ) {} { = ok F }
    ? ( veq `adam vw:` . cm vw . gm vw ) {} { = ok F }
    ? ( veq `adam mb:` . cm mb . gm mb ) {} { = ok F }
    ? ( veq `adam vb:` . cm vb . gm vb ) {} { = ok F }
    ? == . cr n_iter . gr n_iter { ( nurl_print `n_iter: EQUAL\n` ) } { ( nurl_print `n_iter: MISMATCH\n` ) = ok F }
    ? == ( f64_to_bits . cr best_val ) ( f64_to_bits . gr best_val ) { ( nurl_print `best_val: BIT-EXACT\n` ) } { ( nurl_print `best_val: MISMATCH\n` ) = ok F }
    ? == ( f64_to_bits . cr loss ) ( f64_to_bits . gr loss ) { ( nurl_print `loss: BIT-EXACT\n` ) } { ( nurl_print `loss: MISMATCH\n` ) = ok F }
    ( mlp_free cm ) ( mlp_free gm )
    ( vec_free [f] X ) ( vec_free [i] sz )
    ( anom_gpu_close )
    ? ok { ( nurl_print `PARITY: ALL BIT-EXACT\n` ) ^ 0 } { ( nurl_print `PARITY: FAILED\n` ) ^ 1 }
}
