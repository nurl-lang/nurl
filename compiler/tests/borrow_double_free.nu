// Borrow checker — alias double-free regression.
// The harness compiles `borrow_*` tests with --borrowck. The copy
// `: (Vec i) b a` moves `a` into `b`, its new owner; freeing `a`
// afterwards uses the moved-from binding — the silent-alias double
// free. Expect one warning, at the vec_free of `a`.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 10 )
    : ( Vec i ) b a
    ( vec_free [i] a )
    ( vec_free [i] b )
    ^ 0
}
