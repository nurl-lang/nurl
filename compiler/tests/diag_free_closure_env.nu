// diag_free_closure_env.nu — a closure binding drops its own env at
// scope exit, so the old hand-written 'nurl_free' of the env is a
// double free.

@ main → i {
    : i k 3
    : ( @ i i ) f \ i x → i { ^ + x k }
    ( nurl_free # s # *u f 1 )
    ^ ( f 1 )
}
