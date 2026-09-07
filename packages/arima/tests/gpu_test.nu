// gpu_test.nu — the device evaluator returns the CPU's numbers, bit for bit.
//
// Three series fitted together through arima_fit_many_gpu (a CUDA device,
// or the gpu package's host C++ backend under NURL_GPU=cpu) must equal
// the same three fitted alone on the CPU: every coefficient, the
// log-likelihood and the evaluation count. Run for both methods.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/time.nu`
$ `src/arima.nu`
$ `src/arima_gpu.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check b cond s label → v {
    ? cond { ( nurl_print `ok ` ) ( nurl_print label ) ( nurl_print `\n` ) = g_pass + g_pass 1 }
    { ( nurl_print `FAIL ` ) ( nurl_print label ) ( nurl_print `\n` ) = g_fail + g_fail 1 }
}

@ sim i n f phi f th i seed0 → ( Vec f ) {
    : ( Vec f ) y ( vec_zeroed [f] n )
    : ~ f prev 0.0
    : ~ f eprev 0.0
    : ~ i seed seed0
    : ~ i t 0
    ~ < t n {
        = seed % + * seed 1103515245 12345 2147483648
        : f u / + # f seed 1.0 2147483649.0
        = seed % + * seed 1103515245 12345 2147483648
        : f u2 / # f seed 2147483648.0
        : f e * ( float_sqrt * -2.0 ( float_log u ) ) ( float_cos * 6.283185307179586 u2 )
        = prev + + * phi prev e * th eprev
        = eprev e
        ( vec_set [f] y t prev )
        = t + t 1
    }
    ^ y
}

@ same_model * ArimaModel a * ArimaModel b → b {
    ? != ( f64_to_bits ( arima_loglik a ) ) ( f64_to_bits ( arima_loglik b ) ) { ^ F } {}
    ? != ( f64_to_bits ( arima_sigma2 a ) ) ( f64_to_bits ( arima_sigma2 b ) ) { ^ F } {}
    ? != . a evals . b evals { ^ F } {}
    : ( Vec f ) pa ( arima_phi a )
    : ( Vec f ) pb ( arima_phi b )
    : ~ i k 0
    ~ < k ( vec_len [f] pa ) { ? != ( f64_to_bits ( _ar_at pa k ) ) ( f64_to_bits ( _ar_at pb k ) ) { ^ F } {} = k + k 1 }
    : ( Vec f ) ta ( arima_theta a )
    : ( Vec f ) tb ( arima_theta b )
    = k 0
    ~ < k ( vec_len [f] ta ) { ? != ( f64_to_bits ( _ar_at ta k ) ) ( f64_to_bits ( _ar_at tb k ) ) { ^ F } {} = k + k 1 }
    = k 0
    ~ < k ( vec_len [f] . a se ) { ? != ( f64_to_bits ( _ar_at . a se k ) ) ( f64_to_bits ( _ar_at . b se k ) ) { ^ F } {} = k + k 1 }
    ^ T
}

@ run_method s label i method → v {
    : ( Vec ( Vec f ) ) series ( vec_new [( Vec f )] )
    ( vec_push [( Vec f )] series ( sim 800 0.6 0.3 21 ) )
    ( vec_push [( Vec f )] series ( sim 600 -0.4 0.5 22 ) )
    ( vec_push [( Vec f )] series ( sim 1200 0.8 -0.2 23 ) )
    : ArimaSpec sp ( arima_spec_with_mean ( arima_spec 1 0 1 ) T )
    : i t0 ( now_ms )
    : ( Vec * ArimaModel ) dev ( arima_fit_many_gpu series sp method )
    : i dt - ( now_ms ) t0
    : i t1 ( now_ms )
    : ( Vec * ArimaModel ) cpu ( arima_fit_many series sp method )
    : i dc - ( now_ms ) t1
    : ~ b same T
    : ~ i i 0
    ~ < i 3 {
        ?? ( vec_get [* ArimaModel] dev i ) {
            T md → { ?? ( vec_get [* ArimaModel] cpu i ) { T mc → { ? ( same_model md mc ) {} { = same F } } F _ → { = same F } } }
            F _ → { = same F }
        }
        = i + i 1
    }
    : String l ( string_from label )
    ( string_push_str l `: device and CPU fits are bit-identical (device ` )
    : String ds ( string_new ) ( string_push_int ds dt ) ( string_push_str l ( string_data ds ) ) ( string_free ds )
    ( string_push_str l ` ms, cpu ` )
    : String cs ( string_new ) ( string_push_int cs dc ) ( string_push_str l ( string_data cs ) ) ( string_free cs )
    ( string_push_str l ` ms)` )
    ( check same ( string_data l ) )
    ( string_free l )
    ?? ( vec_get [* ArimaModel] dev 0 ) { T md → { ( check . md converged `gpu: the device fit converged` ) } F _ → {} }
    ( arima_models_free dev ) ( arima_models_free cpu )
    ( vec_free_with [( Vec f )] series \ ( Vec f ) v → v { ( vec_free [f] v ) } )
}

@ main → i {
    ( nurl_print `gpu: available = ` ) ( nurl_print_int ? ( arima_gpu_available ) 1 0 ) ( nurl_print `\n` )
    ( run_method `gpu ml` ARIMA_ML )
    ( run_method `gpu css` ARIMA_CSS )
    ( nurl_print `gpu_test: ` ) ( nurl_print_int g_pass ) ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
