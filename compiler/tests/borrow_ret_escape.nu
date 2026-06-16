// Borrow checker — return-escape regression (docs/MEMORY.md §2.8).
// `id` returns its parameter, so the checker records param 0 in
// g_fn_ret_param[id]. At the call `( id f )` the result therefore
// carries `f`'s referent depth — and `f` is a closure capturing a
// `: ~`-mutable Counter BY POINTER (a stack reference into `caller`).
// Returning that result from `caller` dangles the captured slot the
// moment `caller` returns, exactly as `^ f` would. A per-function pass
// cannot see this; the returned-parameter summary propagates the
// reference out through the call result.
: Counter { i n i max }

@ id ( @ v ) cb → ( @ v ) {
    ^ cb
}

@ caller → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ( id f )
}

@ main → i {
    : ( @ v ) g ( caller )
    ^ 0
}
