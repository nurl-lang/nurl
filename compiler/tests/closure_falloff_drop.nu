// closure_falloff_drop.nu — a closure body that falls off its end reclaims
// what it bound.
//
// A closure is a separate function, and its two exits used to disagree:
// `gen_ret_term` ran the drop epilogue for a body ending in `^`, while a
// body ending by falling off its end emitted a bare `ret` and dropped
// nothing. Every owned value such a body bound leaked, once per call —
// which is the shape a callback is usually written in.
//
// None of the bindings below is freed by hand. Under LSan the program must
// end with nothing outstanding; without the epilogue it leaked one
// allocation per iteration per closure. The rosters are shadowed to empty
// when the body's scope is pushed, so the drops can only reach the
// closure's own values — a body that ALSO reached the enclosing frame's
// would free a caller-owned pointer, which is why `outer` below holds one
// across every call.
//
// Expected: COMPILE OK, LINK OK, EXIT 0.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ each ( Vec i ) v ( @ v i ) f → v {
    : i n ( vec_len [i] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [i] v k ) { T x → ( f x ) F _ → {} }
        = k + k 1
    }
}

@ fold ( Vec i ) v ( @ i i ) f → i {
    : i n ( vec_len [i] v )
    : ~ i acc 0
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [i] v k ) { T x → { = acc + acc ( f x ) } F _ → {} }
        = k + k 1
    }
    ^ acc
}

@ main → i {
    // An owned string live in the ENCLOSING frame for the whole run: the
    // closure's epilogue must not touch it.
    : s outer ( nurl_str_int 999 )

    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 11 )
    ( vec_push [i] v 22 )
    ( vec_push [i] v 33 )

    // Void body, falls off its end.
    ( each v \ i x → v {
        : s ks ( nurl_str_int x )
        ( nurl_print ks )
        ( nurl_print ` ` )
    } )
    ( nurl_print `\n` )

    // Value body, falls off its end (no `^`) — the tail is the value.
    : i total ( fold v \ i x → i {
        : s ks ( nurl_str_int x )
        ( nurl_str_len ks )
    } )
    ( nurl_print_int total ) ( nurl_print `\n` )

    // Two owned bindings in one body, one of them unused after its read.
    ( each v \ i x → v {
        : s a ( nurl_str_int x )
        : s b ( nurl_str_int + x 1000 )
        ( nurl_print_int + ( nurl_str_len a ) ( nurl_str_len b ) )
    } )
    ( nurl_print `\n` )

    ( nurl_print outer ) ( nurl_print `\n` )
    ( vec_free [i] v )
    ^ 0
}
