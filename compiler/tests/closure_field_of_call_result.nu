// A closure field read out of a call's result (`. ( mk_clo 9 ) inner`)
// is a value of its own: the field leaves the temporary, whose rest (its
// String) is dropped where it is read, and the env is the read's —
// taken when the call handed its result over, copied when it lent it
// (`pass`). Whatever takes the read owns it: a binding, a borrowing or a
// `sink` argument, a return, a literal, a reassignment, a closure body's
// binding. The env and the rest of the temporary leaked (h323).
$ `stdlib/core/string.nu`

: Wrap {
    ( @ i i ) inner
    String tag
}

@ mk_clo i x → Wrap {
    ^ @ Wrap { \ i y → i { ^ + x y } ( string_from `t` ) }
}

// Lends its parameter back: the result is borrowed.
@ pass Wrap w → Wrap { ^ w }

@ call_it ( @ i i ) f → i { ^ ( f 1 ) }

@ keep sink ( @ i i ) f → i { ^ ( f 2 ) }

@ give → ( @ i i ) { ^ . ( mk_clo 30 ) inner }

: Box { ( @ i i ) cb }

@ main → i {
    // a binding
    : ( @ i i ) f . ( mk_clo 9 ) inner
    ( nurl_println ( nurl_str_int ( f 0 ) ) )
    // an argument to a borrowing parameter
    ( nurl_println ( nurl_str_int ( call_it . ( mk_clo 10 ) inner ) ) )
    // an argument to a sink parameter
    ( nurl_println ( nurl_str_int ( keep . ( mk_clo 20 ) inner ) ) )
    // a return
    : ( @ i i ) g ( give )
    ( nurl_println ( nurl_str_int ( g 0 ) ) )
    // a literal store
    : Box b @ Box { . ( mk_clo 40 ) inner }
    ( nurl_println ( nurl_str_int ( call_it . b cb ) ) )
    // a lent result: a copy
    : Wrap w ( mk_clo 50 )
    : ( @ i i ) h . ( pass w ) inner
    ( nurl_println ( nurl_str_int ( h 0 ) ) )
    ( nurl_println ( nurl_str_int ( call_it . w inner ) ) )
    // reassigned
    : ~ ( @ i i ) r . ( mk_clo 60 ) inner
    = r . ( mk_clo 70 ) inner
    ( nurl_println ( nurl_str_int ( r 0 ) ) )
    // inside a closure body
    : ( @ i i ) outer \ i z → i {
        : ( @ i i ) q . ( mk_clo 80 ) inner
        ^ ( q z )
    }
    ( nurl_println ( nurl_str_int ( outer 1 ) ) )
    ^ 0
}
