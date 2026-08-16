// Borrow checker — return escape through a FORWARD call (docs/MEMORY.md
// §2.8). Identical to borrow_ret_escape.nu except that `id` is defined
// BELOW its call site, so `g_fn_ret_param[id]` does not exist when
// `^ ( id f )` compiles. Nothing can be decided there; the check is
// parked and replayed by resolve_pending_ret_escapes() once every body
// has compiled. Definition order must not decide whether returning a
// dangling closure is an error.
: Counter { i n i max }

@ caller → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ( id f )
}

@ id ( @ v ) cb → ( @ v ) {
    ^ cb
}

@ main → i {
    : ( @ v ) g ( caller )
    ( g )
    ^ 0
}
