// packages/mlp/tests/mlp_test.nu — offline unit tests, no oracle needed.
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/mlp_test.nu /tmp/mt && /tmp/mt

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `src/mlp.nu`

: ~ i g_fail 0

@ check b cond s name → v {
    ? cond { ( nurl_print `  ok  ` ) } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}

@ sizes3 i a i b2 i c → ( Vec i ) {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s a ) ( vec_push [i] s b2 ) ( vec_push [i] s c )
    ^ s
}

@ main → i {
    // ── shapes and determinism ────────────────────────────────────────
    : ( Vec i ) sz ( sizes3 3 8 2 )
    : Mlp m1 ( mlp_new sz 7 )
    : Mlp m2 ( mlp_new sz 7 )
    : Mlp m3 ( mlp_new sz 8 )
    ( check == . m1 n_w + * 3 8 * 8 2 `n_w = 3·8 + 8·2` )
    ( check == . m1 n_b + 8 2 `n_b = 8 + 2` )
    ( check == . m1 n_a + + 3 8 2 `n_a = 3 + 8 + 2` )
    : b same == ( f64_to_bits ( _mlp_fget . m1 w 0 ) ) ( f64_to_bits ( _mlp_fget . m2 w 0 ) )
    : b diff != ( f64_to_bits ( _mlp_fget . m1 w 0 ) ) ( f64_to_bits ( _mlp_fget . m3 w 0 ) )
    ( check same `same seed → identical init` )
    ( check diff `different seed → different init` )
    // Glorot bound: |w| ≤ √(6/(3+8))
    : f bound ( sqrt / 6.0 11.0 )
    : ~ b inb T
    : ~ i k 0
    ~ < k * 3 8 { ? > ( fabs ( _mlp_fget . m1 w k ) ) bound { = inb F } {} = k + k 1 }
    ( check inb `init within the Glorot bound` )
    ( mlp_free m2 ) ( mlp_free m3 )

    // ── XOR regression (the classic non-linear sanity check) ──────────
    // 4 points, target 1 output; a 2-8-1 net must drive MSE ~0.
    : ( Vec f ) X ( vec_new [f] )
    ( vec_push [f] X 0.0 ) ( vec_push [f] X 0.0 )
    ( vec_push [f] X 0.0 ) ( vec_push [f] X 1.0 )
    ( vec_push [f] X 1.0 ) ( vec_push [f] X 0.0 )
    ( vec_push [f] X 1.0 ) ( vec_push [f] X 1.0 )
    : ( Vec f ) Y ( vec_new [f] )
    ( vec_push [f] Y 0.0 ) ( vec_push [f] Y 1.0 )
    ( vec_push [f] Y 1.0 ) ( vec_push [f] Y 0.0 )
    : ( Vec i ) xsz ( sizes3 2 8 1 )
    : Mlp xm ( mlp_new xsz 3 )
    : ~ MlpCfg cfg ( mlp_cfg_default )
    = . cfg early_stop F  // 4 points can't spare a validation split
    = . cfg max_iter 4000
    = . cfg n_no_change 200
    = . cfg lr 0.01
    = . cfg batch 4
    : MlpTrain tr ( mlp_train xm X 4 2 Y 1 cfg )
    : f xor_mse ( mlp_mse xm X 4 2 Y )
    ( check < xor_mse 0.01 `XOR fits (mse < 0.01)` )
    ( check > . tr n_iter 0 `training ran epochs` )
    ( vec_free [i] xsz )

    // ── prediction agrees with mlp_mse's forward ──────────────────────
    : ( Vec f ) p1 ( vec_new [f] )
    ( vec_push [f] p1 1.0 ) ( vec_push [f] p1 0.0 )
    : ( Vec f ) o1 ( mlp_predict xm p1 )
    : f v10 ( _mlp_fget o1 0 )
    ( check & > v10 0.8 < v10 1.2 `predict(1,0) ≈ 1` )
    ( vec_free [f] p1 ) ( vec_free [f] o1 )

    // ── save / load: bit-exact round-trip ─────────────────────────────
    : String js ( mlp_save xm )
    ?? ( mlp_load ( string_data js ) ) {
        T lm → {
            : ~ b bits_eq T
            : ~ i q 0
            ~ < q . xm n_w {
                ? != ( f64_to_bits ( _mlp_fget . xm w q ) ) ( f64_to_bits ( _mlp_fget . lm w q ) ) { = bits_eq F } {}
                = q + q 1
            }
            = q 0
            ~ < q . xm n_b {
                ? != ( f64_to_bits ( _mlp_fget . xm b q ) ) ( f64_to_bits ( _mlp_fget . lm b q ) ) { = bits_eq F } {}
                = q + q 1
            }
            ( check bits_eq `save/load: every weight bit-exact` )
            : f lm_mse ( mlp_mse lm X 4 2 Y )
            ( check == ( f64_to_bits lm_mse ) ( f64_to_bits xor_mse ) `save/load: identical predictions` )
            ( mlp_free lm )
        }
        F → { ( check F `save/load: parses back` ) }
    }
    ( string_free js )
    ?? ( mlp_load `{"broken":1}` ) {
        T bm → { ( check F `malformed JSON rejected` ) ( mlp_free bm ) }
        F → { ( check T `malformed JSON rejected` ) }
    }
    ( vec_free [f] X ) ( vec_free [f] Y )
    ( mlp_free xm )

    // ── autoencoder: reconstruct a 1-D manifold in 3-D ────────────────
    // Points (t, 2t, 3t) — a 3-16-2-16-3 AE must compress through the
    // bottleneck and reconstruct well; a random point far OFF the
    // manifold must reconstruct badly (higher error).
    : ( Vec f ) A ( vec_new [f] )
    : Rng g ( rng_seed 11 )
    : ~ i r 0
    ~ < r 300 {
        : f t ( rng_u01 g )
        ( vec_push [f] A t ) ( vec_push [f] A * 2.0 t ) ( vec_push [f] A * 3.0 t )
        = r + r 1
    }
    ( rng_free g )
    : ( Vec i ) asz ( vec_new [i] )
    ( vec_push [i] asz 3 ) ( vec_push [i] asz 16 ) ( vec_push [i] asz 2 )
    ( vec_push [i] asz 16 ) ( vec_push [i] asz 3 )
    : ~ MlpCfg acfg ( mlp_cfg_default )
    = . acfg max_iter 800
    = . acfg lr 0.005
    = . acfg seed 5
    : MlpFit fit ( mlp_fit asz A 300 3 A 3 acfg 3 )
    : Mlp ae . fit model
    : MlpTrain atr . fit report
    : f ae_mse ( mlp_mse ae A 300 3 A )
    ( check < ae_mse 0.005 `AE reconstructs the manifold (mse < 5e-3)` )
    // On-manifold vs off-manifold reconstruction error
    : ( Vec f ) onp ( vec_new [f] )
    ( vec_push [f] onp 0.5 ) ( vec_push [f] onp 1.0 ) ( vec_push [f] onp 1.5 )
    : ( Vec f ) offp ( vec_new [f] )
    ( vec_push [f] offp 0.9 ) ( vec_push [f] offp 0.1 ) ( vec_push [f] offp 2.9 )
    : ( Vec f ) ron ( mlp_predict ae onp )
    : ( Vec f ) roff ( mlp_predict ae offp )
    : ~ f eon 0.0
    : ~ f eoff 0.0
    : ~ i c 0
    ~ < c 3 {
        : f d1 - ( _mlp_fget ron c ) ( _mlp_fget onp c )
        : f d2 - ( _mlp_fget roff c ) ( _mlp_fget offp c )
        = eon + eon * d1 d1
        = eoff + eoff * d2 d2
        = c + c 1
    }
    ( check < eon / eoff 10.0 `off-manifold error ≫ on-manifold (10×)` )
    ( check . atr stopped_early `AE early-stops before max_iter` )
    ( vec_free [f] onp ) ( vec_free [f] offp )
    ( vec_free [f] ron ) ( vec_free [f] roff )
    ( mlp_free ae )

    // ── restarts rescue a dead-bottleneck init ────────────────────────
    // Seed 4 alone collapses this bottleneck (every unit's pre-activation
    // negative → the net predicts the mean; MSE ≈ the data variance
    // 0.389). mlp_fit with 3 restarts (seeds 4, 5, 6) must recover.
    : ~ MlpCfg rcfg ( mlp_cfg_default )
    = . rcfg max_iter 800
    = . rcfg lr 0.005
    = . rcfg seed 4
    : MlpFit solo ( mlp_fit asz A 300 3 A 3 rcfg 1 )
    : f solo_mse ( mlp_mse . solo model A 300 3 A )
    ( check > solo_mse 0.1 `seed 4 alone collapses (dead bottleneck)` )
    ( mlp_free . solo model )
    : MlpFit resc ( mlp_fit asz A 300 3 A 3 rcfg 3 )
    : f resc_mse ( mlp_mse . resc model A 300 3 A )
    ( check < resc_mse 0.01 `3 restarts rescue it (mse < 1e-2)` )
    ( mlp_free . resc model )
    ( vec_free [f] A ) ( vec_free [i] asz )

    // ── MinMax scaler ─────────────────────────────────────────────────
    : ( Vec f ) S ( vec_new [f] )
    ( vec_push [f] S 0.0 ) ( vec_push [f] S 5.0 ) ( vec_push [f] S 7.0 )
    ( vec_push [f] S 10.0 ) ( vec_push [f] S 5.0 ) ( vec_push [f] S 3.0 )
    : MinMax mm ( minmax_fit S 2 3 )
    ( check == ( f64_to_bits ( _mlp_fget . mm lo 0 ) ) ( f64_to_bits 0.0 ) `minmax lo` )
    ( check == ( f64_to_bits ( _mlp_fget . mm hi 0 ) ) ( f64_to_bits 10.0 ) `minmax hi` )
    ( minmax_apply mm S 2 )
    ( check == ( f64_to_bits ( _mlp_fget S 0 ) ) ( f64_to_bits 0.0 ) `scaled row0 col0 = 0` )
    ( check == ( f64_to_bits ( _mlp_fget S 3 ) ) ( f64_to_bits 1.0 ) `scaled row1 col0 = 1` )
    // col1 has zero range (5, 5) → both map to 0, no div-by-zero
    ( check == ( f64_to_bits ( _mlp_fget S 1 ) ) ( f64_to_bits 0.0 ) `zero-range col → 0` )
    : String ms ( minmax_save mm )
    ?? ( minmax_load ( string_data ms ) ) {
        T lmm → {
            ( check == ( f64_to_bits ( _mlp_fget . lmm hi 0 ) ) ( f64_to_bits 10.0 ) `minmax save/load` )
            ( minmax_free lmm )
        }
        F → { ( check F `minmax save/load` ) }
    }
    ( string_free ms )
    ( minmax_free mm )
    ( vec_free [f] S )
    ( vec_free [i] sz )
    ( mlp_free m1 )

    ? == g_fail 0 { ( nurl_print `ALL PASS\n` ) ^ 0 } { ( nurl_print `FAILURES\n` ) ^ 1 }
}
