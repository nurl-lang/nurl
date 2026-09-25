// A closure returned straight from the function that built it owns the
// String / Vec locals it captured: they move into its env (the function's
// own drop would otherwise free them on return) and are dropped with the
// closure. Regression: `packages/http`'s Alt-Svc wrapper served garbage
// header bytes once String locals became auto-dropped.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make_label i n → ( @ s ) {
    : String v ( string_from `label=` )
    ( string_push_int v n )
    ^ \ → s { ^ ( string_data v ) }
}

@ make_sum ( Vec i ) extra → ( @ i ) {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 ) ( vec_push [i] xs 2 ) ( vec_push [i] xs 3 )
    ^ \ → i {
        : ~ i t 0
        : ~ i k 0
        ~ < k ( vec_len [i] xs ) { = t + t ?? ( vec_get [i] xs k ) { T x → x F → 0 } = k + k 1 }
        ^ + t ( vec_len [i] extra )
    }
}

@ main → i {
    : ( @ s ) f ( make_label 42 )
    ( nurl_print ( f ) ) ( nurl_print `\n` )
    ( nurl_print ( f ) ) ( nurl_print `\n` )
    : ( Vec i ) e ( vec_new [i] )
    ( vec_push [i] e 9 )
    : ( @ i ) g ( make_sum e )
    ( nurl_println_int ( g ) )
    ( nurl_println_int ( g ) )
    ^ 0
}
