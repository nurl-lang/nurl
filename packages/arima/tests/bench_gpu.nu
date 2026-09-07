// bench_gpu.nu — K series at once: the device against the CPU's threads.
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/time.nu`
$ `src/arima.nu`
$ `src/arima_gpu.nu`

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

@ bench i K i n ArimaSpec sp → v {
    : ( Vec ( Vec f ) ) series ( vec_new [( Vec f )] )
    : ~ i k 0
    ~ < k K { ( vec_push [( Vec f )] series ( sim n + 0.3 * 0.002 # f k 0.3 + 100 k ) ) = k + k 1 }
    : i t0 ( now_ms )
    : ( Vec * ArimaModel ) dev ( arima_fit_many_gpu series sp ARIMA_ML )
    : i dt - ( now_ms ) t0
    : i t1 ( now_ms )
    : ( Vec * ArimaModel ) cpu ( arima_fit_many series sp ARIMA_ML )
    : i dc - ( now_ms ) t1
    : i t2 ( now_ms )
    = k 0
    ~ < k K { ?? ( vec_get [( Vec f )] series k ) { T y → { : *ArimaModel m ( arima_fit y sp ) ( arima_free m ) } F _ → {} } = k + k 1 }
    : i ds - ( now_ms ) t2
    ( nurl_print `K=` ) ( nurl_print_int K ) ( nurl_print ` n=` ) ( nurl_print_int n )
    ( nurl_print ` device ms=` ) ( nurl_print_int dt ) ( nurl_print ` cpu-threads ms=` ) ( nurl_print_int dc ) ( nurl_print ` one-by-one ms=` ) ( nurl_print_int ds ) ( nurl_print `\n` )
    ( arima_models_free dev ) ( arima_models_free cpu )
    ( vec_free_with [( Vec f )] series \ ( Vec f ) v → v { ( vec_free [f] v ) } )
}

@ main → i {
    ( bench 64 2000 ( arima_spec 1 0 1 ) )
    ( arima_gpu_trace_report )
    ( bench 64 2000 ( arima_spec_seasonal 1 0 1 1 0 1 24 ) )
    ( arima_gpu_trace_report )
    ^ 0
}
