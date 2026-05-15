// should_warn_closure_escape.nu — exercises the docs/GOTCHAS.md item 8
// foot-gun: a closure that captures a `: ~`-mutable multi-field struct
// is captured by POINTER into the enclosing function's stack frame. If
// the closure is returned (or stored elsewhere that outlives the
// caller's scope), the pointer dangles and any subsequent invocation
// is use-after-free.
//
// Post-fix (compiler v2.1+): gen_closure_expr tags the closure value
// with `__last_closure_byref__` whenever any capture takes the byref
// path; gen_let_or_struct copies the flag onto the binding
// (`<name>__captures_byref`); gen_ret reads either form and emits a
// `warning:` line. Compile + link + run still succeed (this is a SOFT
// diagnostic) — the actual behaviour the warning describes is what
// the code does anyway. The point is to alert at compile time.
//
// Two positive cases (both warn) + two negative controls (no warning).

: Counter { i n  i max }

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
