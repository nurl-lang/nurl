// H373: `= x ? c x ( f )`: the join lends x's own value on the path that chose `x`; the assignment dropped x's old value by its flag, then stored the join's result — the buffer it had just freed — and x owned nothing.
// Closed: where a join that may select the target lends, the value is copied in, so the target owns what it holds on every path (agora #132).
// v0.79.0: accepted; ASan reported heap-use-after-free.
$ `stdlib/core/vec.nu`

@ key i b → ( Vec u ) {
    : ( Vec u ) r ( vec_new [u] )
    ( vec_push [u] r # u b )
    ^ r
}

@ main → i {
    : ~ ( Vec u ) x ( key 1 )
    : i c 7
    = x ? > c 6 x ( key 2 )
    ( nurl_println_int # i ( vec_at [u] x 0 ) )
    ^ 0
}
