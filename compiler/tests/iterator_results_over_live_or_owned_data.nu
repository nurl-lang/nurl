// iterator_results_over_live_or_owned_data.nu — the routes Agora #472's
// rule follows, where nothing an iterator's results view ends before them:
// each runs clean. A Vec of literals, a Vec of views of a String that
// outlives the results, numbers, and owned Strings copied out.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/iter.nu`

@ main → i {
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t `a literal` )
        = keep ( iter_collect [s] ( iter_from_vec [s] t ) )
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    : String b ( string_from `a String that outlives the iterator` )
    : ( Vec s ) t2 ( vec_new [s] )
    ( vec_push [s] t2 ( string_data b ) )
    : ( Vec s ) k2 ( iter_collect [s] ( iter_map [s s] ( iter_from_vec [s] t2 ) \ s x → s { ^ x } ) )
    ( nurl_println ( vec_at [s] k2 0 ) )
    ?? ( iter_find [s] ( iter_from_vec [s] t2 ) \ s x → b { ^ T } ) { T x → { ( nurl_println x ) } F → {} }
    : ( Vec i ) ns ( iter_collect [i] ( iter_map [i i] ( iter_range 0 5 ) \ i x → i { ^ * x x } ) )
    ( nurl_println_int ( vec_len [i] ns ) )
    : ~ ( Vec String ) owned ( vec_new [String] )
    {
        : String c ( string_from `copied out before its String goes` )
        : ( Vec s ) t3 ( vec_new [s] )
        ( vec_push [s] t3 ( string_data c ) )
        : ( Vec s ) got ( iter_collect [s] ( iter_from_vec [s] t3 ) )
        ( vec_push [String] owned ( string_from ( vec_at [s] got 0 ) ) )
    }
    ( nurl_println ( string_data ( vec_at [String] owned 0 ) ) )
    ^ 0
}
