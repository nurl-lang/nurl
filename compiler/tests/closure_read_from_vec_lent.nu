// closure_read_from_vec_lent.nu — a closure read out of a Vec is lent
// (Agora #552): `( vec_at [( @ i i )] fs k )` hands back the element
// itself, no copy of its environment. Every way the result is taken over
// copies it where it was lent, so each owner below frees its own env and
// the Vec frees its own: returned from a helper, stored into another Vec,
// handed to a sink parameter, copied with mem_dup and kept past the
// source's clear. The captures own heap data, so a double free or a read
// of a freed env shows under the sanitizers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk sink String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ get ( Vec ( @ i i ) ) fs i k → ( @ i i ) { ^ ( vec_at [( @ i i )] fs k ) }

@ run_sink sink ( @ i i ) f i x → i { ^ ( f x ) }

@ main → i {
    : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] )
    ( vec_push [( @ i i )] fs ( mk ( string_from `four` ) ) )
    ( vec_push [( @ i i )] fs ( mk ( string_from `seven chars` ) ) )

    // A lent read, called in a loop: no allocation per read.
    : ~ i acc 0
    : ~ i n 0
    ~ < n 1000 {
        : ( @ i i ) f ( vec_at [( @ i i )] fs % n 2 )
        = acc + acc ( f 1 )
        = n + n 1
    }
    ( nurl_println_int acc )

    // Returned from a helper: the helper's caller owns a copy.
    : ( @ i i ) g ( get fs 1 )
    // Stored into another Vec: the Vec owns a copy.
    : ( Vec ( @ i i ) ) other ( vec_new [( @ i i )] )
    ( vec_push [( @ i i )] other ( vec_at [( @ i i )] fs 0 ) )
    // Handed to a sink parameter: the callee takes a copy over.
    ( nurl_println_int ( run_sink ( vec_at [( @ i i )] fs 1 ) 2 ) )
    // Grown while a read of it is live: the element's env stays where it
    // is, so the read still runs on it.
    : ( @ i i ) h ( vec_at [( @ i i )] fs 0 )
    ( vec_push [( @ i i )] fs ( mk ( string_from `x` ) ) )
    ( vec_push [( @ i i )] fs ( mk ( string_from `y` ) ) )
    ( vec_push [( @ i i )] fs ( mk ( string_from `z` ) ) )
    ( nurl_println_int ( h 40 ) )
    // Copied with mem_dup: the copy outlives the source's clear.
    : ( @ i i ) d ( mem_dup ( vec_at [( @ i i )] fs 0 ) )
    ( vec_clear [( @ i i )] fs )
    ( nurl_println_int ( g 10 ) )
    : ( @ i i ) o ( vec_at [( @ i i )] other 0 )
    ( nurl_println_int ( o 20 ) )
    ( nurl_println_int ( d 30 ) )
    ^ 0
}
