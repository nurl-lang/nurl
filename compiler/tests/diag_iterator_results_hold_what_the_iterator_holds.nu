// diag_iterator_results_hold_what_the_iterator_holds.nu — what calling a
// closure hands back may be a copy of what the closure holds (Agora #472).
// `iter_from_vec` over a Vec of views of a String yields copies of those
// views. Collected, found, mapped, called directly or drained by a
// function of the program's own, the results were taken to hold nothing,
// and read after the String's block they read freed memory. Each function
// below is refused.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/iter.nu`

@ drain ( @ ?s i ) src → ( Vec s ) {
    : ( Vec s ) out ( vec_new [s] )
    : ~ b done F
    ~ ! done {
        : ?s got ( src 0 )
        ?? got { T x → { ( vec_push [s] out x ) } F → { = done T } }
    }
    ^ out
}

// Collected.
@ collected → v {
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = keep ( iter_collect [s] ( iter_from_vec [s] t ) )
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
}

// Called directly.
@ called → v {
    : ~ ? s keep @ ?s { F }
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        : ( @ ?s i ) it ( iter_from_vec [s] t )
        = keep ( it 0 )
    }
    ?? keep { T x → { ( nurl_println x ) } F → {} }
}

// Found.
@ found → v {
    : ~ ? s keep @ ?s { F }
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = keep ( iter_find [s] ( iter_from_vec [s] t ) \ s x → b { ^ T } )
    }
    ?? keep { T x → { ( nurl_println x ) } F → {} }
}

// Mapped, then collected.
@ mapped → v {
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = keep ( iter_collect [s] ( iter_map [s s] ( iter_from_vec [s] t ) \ s x → s { ^ x } ) )
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
}

// Drained by a function of the program's own.
@ drained → v {
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = keep ( drain ( iter_from_vec [s] t ) )
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
}

@ main → i {
    ^ 0
}
