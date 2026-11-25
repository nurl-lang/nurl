// A generic's `sink A` made at `A = s` takes over nothing (AGORA-1028). The
// template takes over an `A`; a raw string `s` is a view, as a `( Vec s )`
// holds views. Before, the caller handed such a parameter a copy of a
// literal or of a String's view (as it does for a declared `sink s`), and
// the value it went into (`( Pair s i )`, `( Box1 s )`, the result of
// `opt_unwrap_or [s]`) never released the copy. A `sink A` made at an
// owning type still takes over (`pair_new [String i]`, `box1_new [String]`).
// A binding of a view handed to such a parameter was refused as "a borrow
// … handed over here as if it owned the value"; it is a borrow it keeps.
$ `stdlib/core/pair.nu`
$ `stdlib/core/option.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Box1 [A] { A v }

@ box1_new [A] sink A x → ( Box1 A ) {
    ^ @ ( Box1 A ) { x }
}

@ main → i {
    // (An earlier instance of each generic, so the call sites below know
    // their callees' summaries, as pair_basic's do.)
    : ( Pair i i ) p0 ( pair_new [i i] 1 2 )
    : ( Box1 i ) b0 ( box1_new [i] 3 )
    ( nurl_print ( nurl_str_int + ( pair_first [i i] p0 ) . b0 v ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] ( vec_get [i] ( vec_new [i] ) 0 ) 5 ) ) ) ( nurl_print `\n` )
    // A literal into a borrowing Pair.
    : ( Pair s i ) p ( pair_new [s i] `key` 42 )
    ( nurl_print ( pair_first [s i] p ) ) ( nurl_print `\n` )
    // A String's view: the String stays its owner.
    : String owned ( string_from `held` )
    : ( Pair s i ) q ( pair_new [s i] ( string_data owned ) 1 )
    ( nurl_print ( pair_first [s i] q ) ) ( nurl_print `\n` )
    ( nurl_print ( string_data owned ) ) ( nurl_print `\n` )
    // A binding of each kind, read after the call: a view of a String, a
    // literal, a string of this function's own. None is handed over.
    : s k ( string_data owned )
    : ( Pair s i ) pk ( pair_new [s i] k 3 )
    : s lit `lit`
    : ( Pair s i ) pl ( pair_new [s i] lit 4 )
    : s made ( nurl_str_cat `ma` `de` )
    : ( Pair s i ) pm ( pair_new [s i] made 5 )
    ( nurl_print k ) ( nurl_print ( pair_first [s i] pk ) ) ( nurl_print lit ) ( nurl_print ( pair_first [s i] pl ) )
    ( nurl_print made ) ( nurl_print ( pair_first [s i] pm ) ) ( nurl_print `\n` )
    // A user generic of the same shape.
    : ( Box1 s ) b ( box1_new [s] `boxed` )
    ( nurl_print . b v ) ( nurl_print `\n` )
    // An option's default.
    : ( Vec s ) vs ( vec_new [s] )
    ( nurl_print ( opt_unwrap_or [s] ( vec_get [s] vs 0 ) `fallback` ) ) ( nurl_print `\n` )
    ( vec_push [s] vs `first` )
    ( nurl_print ( opt_unwrap_or [s] ( vec_get [s] vs 0 ) `unused` ) ) ( nurl_print `\n` )
    // At an owning type the parameter still takes over.
    : ( Pair String i ) r ( pair_new [String i] ( string_from `own` ) 2 )
    ( nurl_print ( string_data ( pair_first [String i] r ) ) ) ( nurl_print `\n` )
    : ( Box1 String ) c ( box1_new [String] ( string_from `own box` ) )
    ( nurl_print ( string_data . c v ) ) ( nurl_print `\n` )
    ( vec_free [s] vs )
    ^ 0
}
