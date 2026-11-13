// inout_taken_on_some_paths_leaves_the_caller_its_value.nu — a function
// that hands its `inout` parameter to a `sink` on some paths only (Agora
// #776).
//
// Where it hands the value on, the caller's slot is emptied (#778); where
// it does not, the slot still holds the caller's value. Either way the
// caller drops its binding — the empty value, or its own. Before, the
// function's summary said "consumes", the caller dropped nothing, and on
// the paths that took nothing its value leaked. The caller may read the
// binding after the call: it is empty where it was taken.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ mkv i k → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v @ S { ( string_from `a name long enough to own a heap buffer` ) k } )
    ^ v
}

// A join one arm of which is the parameter: emptied on that path.
@ g inout ( Vec S ) p i c → i { ^ ( eat ? == c 1 p ( mkv 3 ) ) }

// …a block arm: the arm lends it, and the callee gets a copy.
@ g2 inout ( Vec S ) p i c → i { ^ ( eat ? == c 1 { p } ( mkv 3 ) ) }

// Handed on in one arm of a statement `?`.
@ g3 inout ( Vec S ) p i c → i {
    ? == c 1 { ^ ( eat p ) } {}
    ^ 0
}

// Through another function's `inout`.
@ g4 inout ( Vec S ) p i c → i { ^ ( g3 p c ) }

// Given a new value first, then handed on in one arm.
@ g5 inout ( Vec S ) p i c → i {
    = p ( mkv 7 )
    ? == c 1 { ^ ( eat p ) } {}
    ^ # i ( vec_len [S] p )
}

@ run i c → v {
    : ~ ( Vec S ) w ( mkv 1 )
    ( nurl_println_int ( g w c ) )
    ( nurl_println_int # i ( vec_len [S] w ) )
    : ~ ( Vec S ) w2 ( mkv 1 )
    ( nurl_println_int ( g2 w2 c ) )
    ( nurl_println_int # i ( vec_len [S] w2 ) )
    : ~ ( Vec S ) w3 ( mkv 1 )
    ( nurl_println_int ( g3 w3 c ) )
    ( nurl_println_int # i ( vec_len [S] w3 ) )
    : ~ ( Vec S ) w4 ( mkv 1 )
    ( nurl_println_int ( g4 w4 c ) )
    ( nurl_println_int # i ( vec_len [S] w4 ) )
    : ~ ( Vec S ) w5 ( mkv 1 )
    ( nurl_println_int ( g5 w5 c ) )
    ( nurl_println_int # i ( vec_len [S] w5 ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
