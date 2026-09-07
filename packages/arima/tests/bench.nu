// bench.nu — fit times on synthetic series of the shapes that matter.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `src/arima.nu`

@ gauss * i seed → f {
    = . seed 0 % + * . seed 0 1103515245 12345 2147483648
    : f u / + # f . seed 0 1.0 2147483649.0
    = . seed 0 % + * . seed 0 1103515245 12345 2147483648
    : f u2 / # f . seed 0 2147483648.0
    ^ * ( float_sqrt * -2.0 ( float_log u ) ) ( float_cos * 6.283185307179586 u2 )
}

// SARMA(1,0,1)(1,0,1)_s by simulation from the expanded polynomials.
@ sim i n i s f phi f th f sphi f sth i seed0 → ( Vec f ) {
    : ( Vec f ) y ( vec_zeroed [f] n )
    : ( Vec f ) e ( vec_zeroed [f] n )
    : ( Vec i ) seedv ( vec_zeroed [i] 1 )
    ( vec_set [i] seedv 0 seed0 )
    : *i seed ( vec_data [i] seedv )
    : ~ i t 0
    ~ < t n {
        : f et ( gauss seed )
        ( vec_set [f] e t et )
        : ~ f v et
        ? >= t 1 { = v + v * phi ( _ar_at y - t 1 ) } {}
        ? >= t 1 { = v + v * th ( _ar_at e - t 1 ) } {}
        ? >= t s { = v + v * sphi ( _ar_at y - t s ) } {}
        ? >= t + s 1 { = v - v * * phi sphi ( _ar_at y - t + s 1 ) } {}
        ? >= t s { = v + v * sth ( _ar_at e - t s ) } {}
        ? >= t + s 1 { = v + v * * th sth ( _ar_at e - t + s 1 ) } {}
        ( vec_set [f] y t v )
        = t + t 1
    }
    ( vec_free [f] e ) ( vec_free [i] seedv )
    ^ y
}

@ run s label ( Vec f ) y ArimaSpec sp → v {
    : i t0 ( now_ms )
    : *ArimaModel m ( arima_fit y sp )
    : i dt - ( now_ms ) t0
    ( nurl_print label ) ( nurl_print `: n=` ) ( nurl_print_int ( vec_len [f] y ) ) ( nurl_print ` ms=` ) ( nurl_print_int dt )
    ( nurl_print ` evals=` ) ( nurl_print_int . m evals ) ( nurl_print ` conv=` ) ( nurl_print_int ? . m converged 1 0 )
    ( nurl_print ` phi0=` ) : String s1 ( string_new ) ( string_push_float s1 ( _ar_at ( arima_phi m ) 0 ) ) ( nurl_print ( string_data s1 ) ) ( string_free s1 )
    ( nurl_print ` sphi0=` ) : String s2 ( string_new ) ( string_push_float s2 ( _ar_at ( arima_sphi m ) 0 ) ) ( nurl_print ( string_data s2 ) ) ( string_free s2 )
    ( nurl_print ` llf=` ) : String s3 ( string_new ) ( string_push_float s3 ( arima_loglik m ) ) ( nurl_print ( string_data s3 ) ) ( string_free s3 )
    ( nurl_print `\n` )
    ( arima_free m )
}

@ main → i {
    : ( Vec f ) a ( sim 10000 1 0.5 0.4 0.0 0.0 3 )
    ( run `arma(1,1) n=10k` a ( arima_spec 1 0 1 ) )
    : ( Vec f ) b ( sim 5000 24 0.5 0.3 0.6 -0.4 4 )
    ( run `sarma(1,0,1)(1,0,1)_24 n=5k` b ( arima_spec_seasonal 1 0 1 1 0 1 24 ) )
    : ( Vec f ) c ( sim 3000 168 0.4 0.2 0.5 -0.3 5 )
    ( run `sarma(1,0,1)(1,0,1)_168 n=3k` c ( arima_spec_seasonal 1 0 1 1 0 1 168 ) )
    ( vec_free [f] a ) ( vec_free [f] b ) ( vec_free [f] c )
    ^ 0
}
