// diag_arg_void_value_kwargs.nu — the kwargs twin of
// diag_arg_void_value: the named-argument path evaluates arguments
// through its own loop, so the void-argument law is stated there too.
// A call returning 'v' produces no value to bind to the parameter.

@ nothing → v {
}

@ scale i x = 2 i k = 3 → i {
    ^ * x k
}

@ main → i {
    ( nurl_print_int ( scale x : ( nothing ) k : 2 ) )
    ^ 0
}
