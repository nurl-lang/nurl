// borrow_escape_closure.nu — escape analysis for closure-captured
// mutable struct pointers.
//
// docs/GOTCHAS.md item 5: a closure that captures a `: ~`-mutable
// multi-field struct is captured by POINTER into the enclosing
// function's stack frame. Returning it (or storing it somewhere that
// outlives the caller) dangles the pointer — any later invocation is
// use-after-free.
//
// The borrow checker tags such a closure value with a referent depth
// (the scope frame it points into) and rejects `^`-returning it past
// that frame.
//
// Two positive cases (both warn) + two negative controls (no warning).

: Counter { i n i max }

// CASE A — returning a NAMED closure binding that captures byref.
@ make_counter_bind → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) bump \ → v {
        = . c n + . c n 1
    }
    ^ bump
}

// CASE B — returning a CLOSURE LITERAL directly that captures byref.
@ make_counter_lit → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    ^ \ → v { = . c n + . c n 1 }
}

// CONTROL A — closure captures the same struct BY VALUE (no `: ~`).
// The Counter is snapshotted into the env; no dangling pointer.
@ make_safe_value → ( @ v ) {
    : Counter c @ Counter { 0 10 }
    ^ \ → v { = . c n + . c n 1 }
}

// CONTROL B — closure used locally and not returned. No escape.
@ uses_locally → i {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) bump \ → v {
        = . c n + . c n 1
    }
    ( bump )
    ( bump )
    ^ . c n
}

@ main → i {
    : ( @ v ) c1 ( make_counter_bind )
    ( c1 )
    : ( @ v ) c2 ( make_counter_lit )
    ( c2 )
    : ( @ v ) c3 ( make_safe_value )
    ( c3 )
    : i n ( uses_locally )
    ( nurl_print `n=` )
    ( nurl_print ( nurl_str_int n ) )
    ( nurl_print `\n` )
    ^ 0
}
