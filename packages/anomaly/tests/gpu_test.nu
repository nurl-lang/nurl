// gpu_test.nu — M7 GPU-path tests: the accelerated scorer must be
// BIT-IDENTICAL to the pure-NURL loop, element for element — on the CUDA
// backend and on the gpu package's CPU (host C++) backend alike
// (run twice: plain, and with NURL_GPU=cpu).
//
// On a machine with neither a GPU nor a C++ compiler the accelerator
// probe fails; that is a supported configuration, reported as a skip —
// the pure path is the reference and needs no comparison against itself.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `src/score.nu`

: ~ i g_pass 0
: ~ i g_fail 0
: ~ i g_lcg 1

@ pline s x → v {
    ( nurl_print x )
    ( nurl_print `\n` )
}

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` )
        ( pline label )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` )
        ( pline label )
        = g_fail + g_fail 1
    }
}

@ lcg_u01 → f {
    = g_lcg % + * g_lcg 1103515245 12345 2147483648
    ^ / # f g_lcg 2147483648.0
}

// n_rows × n_cols matrix: a mild cluster plus a sprinkle of far outliers.
@ make_matrix i n_rows i n_cols → ( Vec f ) {
    : ( Vec f ) data ( vec_with_cap [f] * n_rows n_cols )
    : ~ i r 0
    ~ < r n_rows {
        : ~ f base 0.0
        ? == % r 97 0 { = base 40.0 } {}
        : ~ i c 0
        ~ < c n_cols {
            ( vec_push [f] data + base * ( lcg_u01 ) 4.0 )
            = c + c 1
        }
        = r + r 1
    }
    ^ data
}

@ main → i {
    : s engine ( anom_gpu_engine )
    ( nurl_print `gpu_test: engine = ` )
    ( pline engine )
    ? == ( nurl_str_eq engine `none` ) 1 {
        ( pline `gpu_test: no accelerator available (no GPU, no C++ compiler) — pure path is authoritative, skipping` )
        ( pline `gpu_test: 0 failed (skipped)` )
        ^ 0
    } {}

    : i ROWS 5000
    : i COLS 8
    : ( Vec f ) data ( make_matrix ROWS COLS )
    : Scaler sc ( scaler_fit data ROWS COLS )
    ( scaler_apply_matrix sc data ROWS COLS )
    : VerCfg cfg @ VerCfg { ( string_from `gpu` ) 0 0 0 0 300 256 -1.0 0.1 T }
    : VerModel vm ( anom_train_version data ROWS COLS cfg )

    // 1. Raw scores: forced accelerator vs the pure loop, every element ==.
    : ( Vec f ) ref ( anom_scores_cpu vm data ROWS COLS )
    : ?( Vec f ) accel ( anom_scores_gpu vm data ROWS COLS )
    ?? accel {
        T got → {
            : ~ b same T
            : ~ i n_diff 0
            : *f a ( vec_data [f] ref )
            : *f b2 ( vec_data [f] got )
            : ~ i r 0
            ~ < r ROWS {
                ? == . a r . b2 r {} {
                    = same F
                    = n_diff + n_diff 1
                }
                = r + r 1
            }
            ( check same `gpu: 5000 scores BIT-IDENTICAL to the pure loop` )
            ? same {} {
                : String msg ( string_from `gpu: differing rows: ` )
                ( string_push_int msg n_diff )
                ( pline ( string_data msg ) )
                ( string_free msg )
            }
            ( vec_free [f] got )
        }
        F _ → { ( check F `gpu: accelerated scoring runs` ) }
    }

    // 2. The auto path (>= threshold rows routes to the accelerator) must
    //    give the same decisions as composing the pure pieces by hand.
    : ( Vec f ) dfs ( anom_decisions vm data ROWS COLS )
    : ~ b dsame T
    : *f dp ( vec_data [f] dfs )
    : *f rp ( vec_data [f] ref )
    : ~ i r 0
    ~ < r ROWS {
        ? == . dp r - - 0.0 . rp r . vm offset {} { = dsame F }
        = r + r 1
    }
    ( check dsame `gpu: auto-path decisions bit-identical` )
    ( vec_free [f] dfs )
    ( vec_free [f] ref )

    // 3. Contamination percentile (trains through the accelerated scorer at
    //    this size) must equal a training run with the accelerator off.
    : VerCfg cfg2 @ VerCfg { ( string_from `gpu2` ) 0 0 0 0 100 256 0.05 0.0 T }
    : VerModel vm_a ( anom_train_version data ROWS COLS cfg2 )
    : ( Vec f ) ref2 ( anom_scores_cpu vm_a data ROWS COLS )
    // offset from the pure path, recomputed by hand:
    : ( Vec f ) ss ( vec_with_cap [f] ROWS )
    : *f r2 ( vec_data [f] ref2 )
    = r 0
    ~ < r ROWS {
        ( vec_push [f] ss - 0.0 . r2 r )
        = r + r 1
    }
    ( sort_by [f] ss \ f a f b → i {
        ? < a b { ^ -1 } {}
        ? > a b { ^ 1 } {}
        ^ 0
    } )
    : f want_off ( _an_percentile ss 0.05 )
    ( check == . vm_a offset want_off `gpu: contamination offset bit-identical` )
    ( vec_free [f] ss )
    ( vec_free [f] ref2 )
    ( anom_vermodel_free vm_a )
    ( _an_vercfg_free cfg2 )

    ( anom_vermodel_free vm )
    ( _an_vercfg_free cfg )
    ( scaler_free sc )
    ( vec_free [f] data )
    ( anom_gpu_close )

    : String summary ( string_from `gpu_test: ` )
    ( string_push_int summary g_pass )
    ( string_push_str summary ` passed, ` )
    ( string_push_int summary g_fail )
    ( string_push_str summary ` failed` )
    ( pline ( string_data summary ) )
    ( string_free summary )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
