// diag_free_closure_param_env.nu — a function only borrows the
// closures it is passed; freeing a closure parameter's env frees the
// caller's env, which the caller drops again.

@ apply ( @ i i ) f i v → i {
    : i r ( f v )
    ( nurl_free # s # *u f 1 )
    ^ r
}

@ main → i {
    : i k 3
    ^ ( apply \ i x → i { ^ + x k } 1 )
}
