// packages/mlp/tests/gradfit_test.nu — engine equivalence: the hand-written
// backprop (mlp_fit) vs the grad autograd engine (mlp_fit_grad) on the
// oracle recipe's data. The two are recipe-equal, not bit-equal (batched
// matmuls accumulate in a different order than per-row loops), so the bar is
// the sklearn-oracle bar: both must train to the noise floor, both must
// separate the injected outliers with the p95-threshold rule, and their
// flag decisions must agree.
//
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/gradfit_test.nu /tmp/gf && /tmp/gf

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/time.nu`
$ `src/mlp.nu`
$ `src/gradfit.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label )
    ( nurl_print `\n` )
}

@ row_mse Mlp m ( Vec f ) X i d i r → f {
    : ( Vec f ) x ( vec_new [f] )
    : ~ i k 0
    ~ < k d { ( vec_push [f] x ( _mlp_fget X + * r d k ) ) = k + k 1 }
    : ( Vec f ) y ( mlp_predict m x )
    : ~ f se 0.0
    = k 0
    ~ < k d {
        : f e - ( _mlp_fget y k ) ( _mlp_fget x k )
        = se + se * e e
        = k + k 1
    }
    ( vec_free [f] x ) ( vec_free [f] y )
    ^ / se # f d
}

// p95 (nearest-rank) of per-row MSEs + mean, and outlier flags vs that
// threshold. Returns the flags; writes mean mse + threshold through cells.
@ eval_model Mlp m ( Vec f ) X i n ( Vec f ) O i no i d * u meanb * u thrb → ( Vec i ) {
    : ( Vec f ) mses ( vec_new [f] )
    : ~ f tot 0.0
    : ~ i r 0
    ~ < r n {
        : f e ( row_mse m X d r )
        ( vec_push [f] mses e )
        = tot + tot e
        = r + r 1
    }
    ( nurl_poke meanb 0 ( f64_to_bits / tot # f n ) )
    ( sort_by [f] mses \ f a f b → i { ^ ? < a b -1 ? > a b 1 0 } )
    : i p95i # i * 0.95 # f n
    : f thr ( _mlp_fget mses p95i )
    ( nurl_poke thrb 0 ( f64_to_bits thr ) )
    ( vec_free [f] mses )
    : ( Vec i ) flags ( vec_new [i] )
    = r 0
    ~ < r no {
        ( vec_push [i] flags ? > ( row_mse m O d r ) thr 1 0 )
        = r + r 1
    }
    ^ flags
}

@ main → i {
    // the oracle recipe's data shape: 2-D latent → 6-D + noise, 60 outliers
    : i N 1200
    : i D 6
    : i NO 60
    : Rng g ( rng_seed 42 )
    : ( Vec f ) X ( vec_with_cap [f] * N D )
    : ~ i r 0
    ~ < r N {
        : f t1 - * 2.0 ( rng_u01 g ) 1.0
        : f t2 - * 2.0 ( rng_u01 g ) 1.0
        ( vec_push [f] X + t1 * 0.02 - ( rng_u01 g ) 0.5 )
        ( vec_push [f] X + t2 * 0.02 - ( rng_u01 g ) 0.5 )
        ( vec_push [f] X + * t1 t2 * 0.02 - ( rng_u01 g ) 0.5 )
        ( vec_push [f] X + ( float_sin * 2.0 t1 ) * 0.02 - ( rng_u01 g ) 0.5 )
        ( vec_push [f] X + + t1 t2 * 0.02 - ( rng_u01 g ) 0.5 )
        ( vec_push [f] X + - t1 * 0.5 t2 * 0.02 - ( rng_u01 g ) 0.5 )
        = r + r 1
    }
    : ( Vec f ) O ( vec_with_cap [f] * NO D )
    = r 0
    ~ < r * NO D {
        ( vec_push [f] O - * 4.0 ( rng_u01 g ) 2.0 )
        = r + r 1
    }
    ( rng_free g )
    // minmax on train, applied to both (the recipe)
    : MinMax mm ( minmax_fit X N D )
    ( minmax_apply mm X N )
    ( minmax_apply mm O NO )
    ( minmax_free mm )
    : ( Vec i ) sz ( vec_new [i] )
    ( vec_push [i] sz D ) ( vec_push [i] sz 64 ) ( vec_push [i] sz 32 )
    ( vec_push [i] sz 64 ) ( vec_push [i] sz D )
    : MlpCfg cfg ( mlp_cfg_default )

    : i t0 ( monotonic_ns )
    : MlpFit fh ( mlp_fit sz X N D X D cfg 3 )
    : i t1 ( monotonic_ns )
    : MlpFit fg ( mlp_fit_grad sz X N D X D cfg 3 )
    : i t2 ( monotonic_ns )
    ( nurl_print `  hand engine ` ) ( nurl_print_int / - t1 t0 1000000 )
    ( nurl_print ` ms · grad engine ` ) ( nurl_print_int / - t2 t1 1000000 )
    ( nurl_print ` ms\n` )

    : Mlp mh . fh model
    : Mlp mg . fg model
    : *u mb1 ( nurl_alloc 8 )
    : *u tb1 ( nurl_alloc 8 )
    : *u mb2 ( nurl_alloc 8 )
    : *u tb2 ( nurl_alloc 8 )
    : ( Vec i ) flh ( eval_model mh X N O NO D mb1 tb1 )
    : ( Vec i ) flg ( eval_model mg X N O NO D mb2 tb2 )
    : f mseh ( bits_to_f64 ( nurl_peek mb1 0 ) )
    : f mseg ( bits_to_f64 ( nurl_peek mb2 0 ) )
    ( nurl_print `  hand mse ` ) ( nurl_print ( nurl_str_float mseh ) )
    ( nurl_print ` · grad mse ` ) ( nurl_print ( nurl_str_float mseg ) )
    ( nurl_print `\n` )
    ( check < mseh 0.003 `hand engine trains to the noise floor` )
    ( check < mseg 0.003 `grad engine trains to the noise floor` )
    // both flag nearly all injected outliers; decisions agree
    : ~ i nh 0
    : ~ i ng 0
    : ~ i agree 0
    : ~ i k 0
    ~ < k NO {
        : i a ( _mlp_iget flh k )
        : i b ( _mlp_iget flg k )
        = nh + nh a
        = ng + ng b
        ? == a b { = agree + agree 1 } {}
        = k + k 1
    }
    ( nurl_print `  outliers flagged: hand ` ) ( nurl_print_int nh )
    ( nurl_print ` grad ` ) ( nurl_print_int ng )
    ( nurl_print ` agree ` ) ( nurl_print_int agree )
    ( nurl_print `/` ) ( nurl_println_int NO )
    ( check >= nh 54 `hand engine flags ≥ 90% of outliers` )
    ( check >= ng 54 `grad engine flags ≥ 90% of outliers` )
    ( check >= agree 54 `engines agree on ≥ 90% of outlier decisions` )
    // loss quality parity: neither engine dramatically worse
    : ~ f ratio / mseg mseh
    ? < ratio 1.0 { = ratio / mseh mseg } {}
    ( check < ratio 5.0 `train MSEs within 5× of each other` )
    ( vec_free [i] flh ) ( vec_free [i] flg )
    ( nurl_free mb1 ) ( nurl_free tb1 ) ( nurl_free mb2 ) ( nurl_free tb2 )
    ( mlp_free mh ) ( mlp_free mg )
    ( vec_free [f] X ) ( vec_free [f] O ) ( vec_free [i] sz )

    ( nurl_print `gradfit_test: ` )
    ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` )
    ( nurl_print_int g_fail )
    ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
